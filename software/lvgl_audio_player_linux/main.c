#include "lvgl.h"
#include "src/drivers/display/fb/lv_linux_fbdev.h"

#include <alsa/asoundlib.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define UI_REFRESH_MS        100U
#define PLAYLIST_MAX_TRACKS  64U
#define AUDIO_CHUNK_FRAMES   1024U
#define AUDIO_PATH_MAX       256U

/*
 * This BSP reports a 200 MHz constant counter although the FPGA counter
 * advances at the 33 MHz CPU clock.  Keep the BSP behavior for compatibility
 * and compensate for it locally in this application.
 */
#define BSP_TIMER_HZ         200000000ULL
#define FPGA_TIMER_HZ         33000000ULL

static volatile sig_atomic_t running = 1;

enum player_view {
    PLAYER_VIEW_NOW_PLAYING,
    PLAYER_VIEW_MENU,
};

struct wav_file {
    FILE *file;
    uint32_t data_bytes;
    uint32_t data_remaining;
    uint32_t total_frames;
};

struct audio_track {
    char path[AUDIO_PATH_MAX];
    char name[AUDIO_PATH_MAX];
    uint32_t duration_ms;
};

struct playlist {
    struct audio_track tracks[PLAYLIST_MAX_TRACKS];
    unsigned int count;
};

struct audio_engine {
    pthread_t thread;
    pthread_mutex_t lock;
    pthread_cond_t changed;
    char device[AUDIO_PATH_MAX];
    struct audio_track tracks[PLAYLIST_MAX_TRACKS];
    unsigned int track_count;
    unsigned int selected_track;
    unsigned int generation;
    uint64_t frames_written;
    uint32_t duration_ms;
    bool pause_requested;
    bool paused;
    bool active;
    bool terminate;
};

struct player_ui;

struct track_event_data {
    struct player_ui *ui;
    unsigned int index;
};

struct player_ui {
    lv_obj_t *progress;
    lv_obj_t *elapsed;
    lv_obj_t *duration;
    lv_obj_t *song;
    lv_obj_t *pause_label;
    struct audio_engine *audio;
    unsigned int current_track;
    bool paused;
    bool render_pending;
    enum player_view view;
    const char *input_path;
    struct track_event_data track_events[PLAYLIST_MAX_TRACKS];
};

struct touch_input {
    int fd;
    int32_t raw_x;
    int32_t raw_y;
    int32_t min_x;
    int32_t max_x;
    int32_t min_y;
    int32_t max_y;
    int32_t display_width;
    int32_t display_height;
    bool pressed;
};

static const char *audio_track_name(const struct audio_engine *audio,
                                    unsigned int track)
{
    return audio->tracks[track % audio->track_count].name;
}

static uint32_t audio_track_duration(const struct audio_engine *audio,
                                     unsigned int track)
{
    return audio->tracks[track % audio->track_count].duration_ms;
}

static uint16_t wav_read_u16(const unsigned char *data)
{
    return (uint16_t)data[0] | ((uint16_t)data[1] << 8);
}

static uint32_t wav_read_u32(const unsigned char *data)
{
    return (uint32_t)data[0] | ((uint32_t)data[1] << 8) |
           ((uint32_t)data[2] << 16) | ((uint32_t)data[3] << 24);
}

static int wav_open(struct wav_file *wav, const char *path)
{
    unsigned char header[12];
    uint16_t format = 0;
    uint16_t channels = 0;
    uint16_t bits = 0;
    uint16_t block_align = 0;
    uint32_t rate = 0;
    bool have_fmt = false;

    memset(wav, 0, sizeof(*wav));
    wav->file = fopen(path, "rb");
    if(wav->file == NULL) return -errno;
    if(fread(header, 1, sizeof(header), wav->file) != sizeof(header) ||
       memcmp(header, "RIFF", 4) != 0 || memcmp(header + 8, "WAVE", 4) != 0)
        goto invalid;

    for(;;) {
        unsigned char chunk[8];
        uint32_t size;

        if(fread(chunk, 1, sizeof(chunk), wav->file) != sizeof(chunk))
            goto invalid;
        size = wav_read_u32(chunk + 4);
        if(memcmp(chunk, "fmt ", 4) == 0) {
            unsigned char fmt[16];

            if(size < sizeof(fmt) || fread(fmt, 1, sizeof(fmt), wav->file) !=
               sizeof(fmt))
                goto invalid;
            format = wav_read_u16(fmt);
            channels = wav_read_u16(fmt + 2);
            rate = wav_read_u32(fmt + 4);
            block_align = wav_read_u16(fmt + 12);
            bits = wav_read_u16(fmt + 14);
            if(size > sizeof(fmt) &&
               fseek(wav->file, (long)(size - sizeof(fmt)), SEEK_CUR) != 0)
                goto invalid;
            have_fmt = true;
        }
        else if(memcmp(chunk, "data", 4) == 0) {
            if(!have_fmt || format != 1 || channels != 2 || rate != 44100 ||
               bits != 16 || block_align != 4)
                goto invalid;
            wav->data_bytes = size;
            wav->data_remaining = size;
            wav->total_frames = size / 4U;
            return 0;
        }
        else if(fseek(wav->file, (long)size, SEEK_CUR) != 0) {
            goto invalid;
        }
        if((size & 1U) && fseek(wav->file, 1, SEEK_CUR) != 0)
            goto invalid;
    }

invalid:
    fclose(wav->file);
    wav->file = NULL;
    return -EINVAL;
}

static bool has_wav_extension(const char *name)
{
    const char *extension = strrchr(name, '.');

    return extension != NULL && strcasecmp(extension, ".wav") == 0;
}

static int track_compare(const void *left, const void *right)
{
    const struct audio_track *a = left;
    const struct audio_track *b = right;

    return strcasecmp(a->name, b->name);
}

static int playlist_scan(struct playlist *playlist, const char *directory)
{
    struct dirent *entry;
    DIR *dir;

    memset(playlist, 0, sizeof(*playlist));
    dir = opendir(directory);
    if(dir == NULL) return -errno;

    while((entry = readdir(dir)) != NULL) {
        struct audio_track *track;
        struct wav_file wav;
        struct stat status;
        int length;

        if(entry->d_name[0] == '.' || !has_wav_extension(entry->d_name))
            continue;
        if(playlist->count >= PLAYLIST_MAX_TRACKS) {
            fprintf(stderr, "Playlist limited to %u WAV files; remaining files ignored\n",
                    PLAYLIST_MAX_TRACKS);
            break;
        }

        track = &playlist->tracks[playlist->count];
        if(strcmp(directory, "/") == 0)
            length = snprintf(track->path, sizeof(track->path), "/%s",
                              entry->d_name);
        else
            length = snprintf(track->path, sizeof(track->path), "%s/%s",
                              directory, entry->d_name);
        if(length < 0 || (size_t)length >= sizeof(track->path)) {
            fprintf(stderr, "Skipping overlong path: %s/%s\n",
                    directory, entry->d_name);
            continue;
        }
        if(stat(track->path, &status) != 0 || !S_ISREG(status.st_mode))
            continue;
        if(wav_open(&wav, track->path) != 0) {
            fprintf(stderr, "Skipping unsupported WAV: %s\n", track->path);
            continue;
        }

        snprintf(track->name, sizeof(track->name), "%s", entry->d_name);
        track->duration_ms =
            (uint32_t)((uint64_t)wav.total_frames * 1000U / 44100U);
        fclose(wav.file);
        playlist->count++;
    }
    closedir(dir);

    qsort(playlist->tracks, playlist->count, sizeof(playlist->tracks[0]),
          track_compare);
    return playlist->count != 0U ? 0 : -ENOENT;
}

static void path_directory(char *directory, size_t size, const char *path)
{
    const char *slash = strrchr(path, '/');
    size_t length;

    if(slash == NULL) {
        snprintf(directory, size, ".");
        return;
    }
    if(slash == path) {
        snprintf(directory, size, "/");
        return;
    }
    length = (size_t)(slash - path);
    if(length >= size) length = size - 1U;
    memcpy(directory, path, length);
    directory[length] = '\0';
}

static unsigned int playlist_find(const struct playlist *playlist,
                                  const char *path)
{
    const char *name = strrchr(path, '/');
    unsigned int index;

    name = name != NULL ? name + 1 : path;
    for(index = 0; index < playlist->count; ++index)
        if(strcmp(playlist->tracks[index].path, path) == 0 ||
           strcmp(playlist->tracks[index].name, name) == 0)
            return index;
    return 0;
}

static void audio_set_state(struct audio_engine *audio, bool active,
                            bool paused, uint64_t frames, uint32_t duration)
{
    pthread_mutex_lock(&audio->lock);
    audio->active = active;
    audio->paused = paused;
    audio->frames_written = frames;
    audio->duration_ms = duration;
    pthread_mutex_unlock(&audio->lock);
}

static void *audio_thread_main(void *data)
{
    struct audio_engine *audio = data;
    unsigned int handled_generation = 0;
    int16_t samples[AUDIO_CHUNK_FRAMES * 2U];

    for(;;) {
        struct wav_file wav;
        snd_pcm_t *pcm = NULL;
        unsigned int generation;
        unsigned int track;
        uint64_t frames_written = 0;
        uint32_t duration_ms;
        int result;

        pthread_mutex_lock(&audio->lock);
        while(!audio->terminate && audio->generation == handled_generation)
            pthread_cond_wait(&audio->changed, &audio->lock);
        if(audio->terminate) {
            pthread_mutex_unlock(&audio->lock);
            break;
        }
        generation = audio->generation;
        handled_generation = generation;
        track = audio->selected_track;
        pthread_mutex_unlock(&audio->lock);

        result = wav_open(&wav, audio->tracks[track].path);
        if(result < 0) {
            fprintf(stderr, "Cannot play %s: expected 44.1kHz stereo S16_LE WAV\n",
                    audio->tracks[track].path);
            audio_set_state(audio, false, false, 0, 0);
            continue;
        }
        duration_ms = (uint32_t)((uint64_t)wav.total_frames * 1000U / 44100U);
        result = snd_pcm_open(&pcm, audio->device, SND_PCM_STREAM_PLAYBACK, 0);
        if(result < 0) {
            fprintf(stderr, "Cannot open ALSA %s: %s\n", audio->device,
                    snd_strerror(result));
            fclose(wav.file);
            audio_set_state(audio, false, false, 0, duration_ms);
            continue;
        }
        result = snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16_LE,
                                    SND_PCM_ACCESS_RW_INTERLEAVED,
                                    2, 44100, 0, 350000);
        if(result < 0) {
            fprintf(stderr, "Cannot configure ALSA: %s\n", snd_strerror(result));
            snd_pcm_close(pcm);
            fclose(wav.file);
            audio_set_state(audio, false, false, 0, duration_ms);
            continue;
        }
        audio_set_state(audio, true, false, 0, duration_ms);
        printf("Playing track %u/%u: %s (%u ms)\n", track + 1U,
               audio->track_count, audio->tracks[track].path, duration_ms);

        while(wav.data_remaining != 0U) {
            size_t bytes = wav.data_remaining;
            size_t got;
            snd_pcm_sframes_t offset = 0;
            snd_pcm_sframes_t frames;
            bool pause_requested;
            bool changed = false;

            if(bytes > sizeof(samples)) bytes = sizeof(samples);
            got = fread(samples, 1, bytes, wav.file);
            if(got == 0U) break;
            wav.data_remaining -= (uint32_t)got;
            frames = (snd_pcm_sframes_t)(got / 4U);

            while(offset < frames) {
                pthread_mutex_lock(&audio->lock);
                changed = audio->terminate || audio->generation != generation;
                pause_requested = audio->pause_requested;
                pthread_mutex_unlock(&audio->lock);
                if(changed) break;

                if(pause_requested) {
                    bool hardware_paused = false;
                    snd_pcm_state_t state = snd_pcm_state(pcm);

                    if(state == SND_PCM_STATE_RUNNING) {
                        result = snd_pcm_pause(pcm, 1);
                        hardware_paused = result == 0;
                    }
                    else if(state == SND_PCM_STATE_XRUN) {
                        /* Leave the recovered stream prepared while the UI is
                         * paused.  The first write after resume starts it. */
                        snd_pcm_prepare(pcm);
                    }
                    pthread_mutex_lock(&audio->lock);
                    audio->paused = true;
                    while(!audio->terminate && audio->generation == generation &&
                          audio->pause_requested)
                        pthread_cond_wait(&audio->changed, &audio->lock);
                    changed = audio->terminate || audio->generation != generation;
                    audio->paused = false;
                    pthread_mutex_unlock(&audio->lock);
                    if(changed) break;
                    result = hardware_paused ? snd_pcm_pause(pcm, 0) : 0;
                    if(result < 0) {
                        fprintf(stderr, "ALSA resume failed: %s\n",
                                snd_strerror(result));
                        snd_pcm_prepare(pcm);
                    }
                    continue;
                }

                result = (int)snd_pcm_writei(pcm, samples + offset * 2,
                                             (snd_pcm_uframes_t)(frames - offset));
                if(result == -EPIPE) {
                    fprintf(stderr, "ALSA underrun, recovering\n");
                    snd_pcm_prepare(pcm);
                    continue;
                }
                if(result < 0) {
                    fprintf(stderr, "ALSA write failed: %s\n",
                            snd_strerror(result));
                    changed = true;
                    break;
                }
                offset += result;
                frames_written += (uint64_t)result;
                audio_set_state(audio, true, false, frames_written, duration_ms);
            }
            if(changed) break;
        }

        pthread_mutex_lock(&audio->lock);
        result = audio->terminate || audio->generation != generation;
        pthread_mutex_unlock(&audio->lock);
        if(result)
            snd_pcm_drop(pcm);
        else
            snd_pcm_drain(pcm);
        snd_pcm_close(pcm);
        fclose(wav.file);
        audio_set_state(audio, false, false, frames_written, duration_ms);
    }
    return NULL;
}

static int audio_engine_init(struct audio_engine *audio, const char *device,
                             const struct playlist *playlist)
{
    memset(audio, 0, sizeof(*audio));
    pthread_mutex_init(&audio->lock, NULL);
    pthread_cond_init(&audio->changed, NULL);
    snprintf(audio->device, sizeof(audio->device), "%s", device);
    memcpy(audio->tracks, playlist->tracks,
           (size_t)playlist->count * sizeof(playlist->tracks[0]));
    audio->track_count = playlist->count;
    /* The worker initially waits.  main() starts generation 1 only after the
     * expensive first full-screen render has completed. */
    audio->generation = 0;
    return pthread_create(&audio->thread, NULL, audio_thread_main, audio);
}

static void audio_engine_select(struct audio_engine *audio, unsigned int track)
{
    pthread_mutex_lock(&audio->lock);
    audio->selected_track = track % audio->track_count;
    audio->pause_requested = false;
    audio->generation++;
    pthread_cond_broadcast(&audio->changed);
    pthread_mutex_unlock(&audio->lock);
}

static void audio_engine_pause(struct audio_engine *audio, bool paused)
{
    pthread_mutex_lock(&audio->lock);
    audio->pause_requested = paused;
    pthread_cond_broadcast(&audio->changed);
    pthread_mutex_unlock(&audio->lock);
}

static void audio_engine_status(struct audio_engine *audio,
                                uint32_t *position_ms, uint32_t *duration_ms)
{
    pthread_mutex_lock(&audio->lock);
    *position_ms = (uint32_t)(audio->frames_written * 1000U / 44100U);
    *duration_ms = audio->duration_ms;
    pthread_mutex_unlock(&audio->lock);
}

static void audio_engine_shutdown(struct audio_engine *audio)
{
    pthread_mutex_lock(&audio->lock);
    audio->terminate = true;
    audio->generation++;
    pthread_cond_broadcast(&audio->changed);
    pthread_mutex_unlock(&audio->lock);
    pthread_join(audio->thread, NULL);
    pthread_cond_destroy(&audio->changed);
    pthread_mutex_destroy(&audio->lock);
}

static void render_view(struct player_ui *ui);

static void stop_handler(int signo)
{
    (void)signo;
    running = 0;
}

static uint64_t kernel_monotonic_ms(void)
{
    struct timespec now;

    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000U + (uint64_t)now.tv_nsec / 1000000U;
}

static uint64_t app_monotonic_ms(void)
{
    return kernel_monotonic_ms() * BSP_TIMER_HZ / FPGA_TIMER_HZ;
}

static uint32_t app_tick_ms(void)
{
    return (uint32_t)app_monotonic_ms();
}

static void app_sleep_ms(uint32_t real_ms)
{
    uint64_t kernel_us;

    kernel_us = ((uint64_t)real_ms * 1000U * FPGA_TIMER_HZ +
                 BSP_TIMER_HZ - 1U) / BSP_TIMER_HZ;
    if(kernel_us == 0U) kernel_us = 1U;
    usleep((useconds_t)kernel_us);
}

static uint32_t player_position_ms(const struct player_ui *ui)
{
    uint32_t position_ms;
    uint32_t duration_ms;

    audio_engine_status(ui->audio, &position_ms, &duration_ms);
    return position_ms;
}

static uint32_t player_duration_ms(const struct player_ui *ui)
{
    uint32_t position_ms;
    uint32_t duration_ms;

    audio_engine_status(ui->audio, &position_ms, &duration_ms);
    return duration_ms != 0U ? duration_ms :
           audio_track_duration(ui->audio, ui->current_track);
}

static void format_time(char *text, size_t size, uint32_t time_ms)
{
    uint32_t seconds = time_ms / 1000U;

    snprintf(text, size, "%02u:%02u", seconds / 60U, seconds % 60U);
}

static void set_panel_style(lv_obj_t *obj, uint32_t color, lv_opa_t opacity,
                            int32_t radius)
{
    lv_obj_set_style_bg_color(obj, lv_color_hex(color), 0);
    lv_obj_set_style_bg_opa(obj, opacity, 0);
    lv_obj_set_style_border_width(obj, 1, 0);
    lv_obj_set_style_border_color(obj, lv_color_hex(0x70c9ee), 0);
    lv_obj_set_style_border_opa(obj, LV_OPA_30, 0);
    lv_obj_set_style_radius(obj, radius, 0);
    lv_obj_set_style_shadow_color(obj, lv_color_hex(0x001c33), 0);
    lv_obj_set_style_shadow_opa(obj, LV_OPA_30, 0);
    lv_obj_set_style_shadow_width(obj, 18, 0);
    lv_obj_set_style_shadow_offset_y(obj, 7, 0);
}

static void create_header(lv_obj_t *parent, const char *subtitle)
{
    lv_obj_t *title = lv_label_create(parent);
    lv_obj_t *sub = lv_label_create(parent);

    lv_label_set_text(title, LV_SYMBOL_AUDIO "  LA32R MUSIC");
    lv_obj_set_style_text_font(title, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(title, lv_color_white(), 0);
    lv_obj_set_style_text_letter_space(title, 2, 0);
    lv_obj_align(title, LV_ALIGN_TOP_LEFT, 28, 28);

    lv_label_set_text(sub, subtitle);
    lv_obj_set_style_text_font(sub, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(sub, lv_color_hex(0xa9def5), 0);
    lv_obj_align(sub, LV_ALIGN_TOP_LEFT, 31, 67);
}

static lv_obj_t *create_control_button(lv_obj_t *parent, const char *text,
                                       int32_t x, lv_event_cb_t callback,
                                       void *user_data, lv_obj_t **label_out)
{
    lv_obj_t *button = lv_button_create(parent);
    lv_obj_t *label = lv_label_create(button);

    lv_obj_set_size(button, 126, 72);
    lv_obj_align(button, LV_ALIGN_BOTTOM_LEFT, x, -78);
    lv_obj_set_style_radius(button, 18, 0);
    lv_obj_set_style_bg_color(button, lv_color_hex(0x087ca9), 0);
    lv_obj_set_style_bg_grad_color(button, lv_color_hex(0x0ca6cb), 0);
    lv_obj_set_style_bg_grad_dir(button, LV_GRAD_DIR_VER, 0);
    lv_obj_set_style_shadow_color(button, lv_color_hex(0x00182c), 0);
    lv_obj_set_style_shadow_opa(button, LV_OPA_40, 0);
    lv_obj_set_style_shadow_width(button, 12, 0);
    lv_obj_set_style_shadow_offset_y(button, 5, 0);
    lv_obj_add_event_cb(button, callback, LV_EVENT_CLICKED, user_data);

    lv_label_set_text(label, text);
    lv_obj_set_style_text_font(label, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(label, lv_color_white(), 0);
    lv_obj_center(label);
    if(label_out != NULL) *label_out = label;
    return button;
}

static void render_view_async(void *user_data)
{
    struct player_ui *ui = user_data;

    ui->render_pending = false;
    render_view(ui);
}

static void request_view(struct player_ui *ui, enum player_view view)
{
    ui->view = view;
    if(!ui->render_pending) {
        ui->render_pending = true;
        if(lv_async_call(render_view_async, ui) != LV_RESULT_OK)
            ui->render_pending = false;
    }
}

static void pause_button_cb(lv_event_t *event)
{
    struct player_ui *ui = lv_event_get_user_data(event);

    if(ui->paused) {
        ui->paused = false;
        audio_engine_pause(ui->audio, false);
        lv_label_set_text(ui->pause_label, LV_SYMBOL_PAUSE "  PAUSE");
    }
    else {
        ui->paused = true;
        audio_engine_pause(ui->audio, true);
        lv_label_set_text(ui->pause_label, LV_SYMBOL_PLAY "  PLAY");
    }
}

static void next_button_cb(lv_event_t *event)
{
    struct player_ui *ui = lv_event_get_user_data(event);

    ui->current_track = (ui->current_track + 1U) % ui->audio->track_count;
    ui->paused = false;
    audio_engine_select(ui->audio, ui->current_track);
    lv_label_set_text(ui->song, audio_track_name(ui->audio,
                                                ui->current_track));
    lv_label_set_text(ui->pause_label, LV_SYMBOL_PAUSE "  PAUSE");
}

static void menu_button_cb(lv_event_t *event)
{
    struct player_ui *ui = lv_event_get_user_data(event);

    request_view(ui, PLAYER_VIEW_MENU);
}

static void back_button_cb(lv_event_t *event)
{
    struct player_ui *ui = lv_event_get_user_data(event);

    request_view(ui, PLAYER_VIEW_NOW_PLAYING);
}

static void track_button_cb(lv_event_t *event)
{
    struct track_event_data *track = lv_event_get_user_data(event);
    struct player_ui *ui = track->ui;

    ui->current_track = track->index;
    ui->paused = false;
    audio_engine_select(ui->audio, ui->current_track);
    request_view(ui, PLAYER_VIEW_NOW_PLAYING);
}

static void create_player_view(struct player_ui *ui)
{
    lv_obj_t *screen = lv_screen_active();
    lv_obj_t *art_card;
    lv_obj_t *disc;
    lv_obj_t *note;
    lv_obj_t *now_playing;
    lv_obj_t *artist;
    lv_obj_t *footer;
    char duration_text[16];

    create_header(screen, "Touch-enabled framebuffer player");

    art_card = lv_obj_create(screen);
    lv_obj_set_size(art_card, 410, 270);
    lv_obj_align(art_card, LV_ALIGN_TOP_MID, 0, 108);
    lv_obj_remove_flag(art_card, LV_OBJ_FLAG_SCROLLABLE);
    set_panel_style(art_card, 0x0b4c72, LV_OPA_80, 24);

    disc = lv_obj_create(art_card);
    lv_obj_set_size(disc, 180, 180);
    lv_obj_align(disc, LV_ALIGN_CENTER, 0, -2);
    lv_obj_set_style_radius(disc, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(disc, lv_color_hex(0x063552), 0);
    lv_obj_set_style_bg_grad_color(disc, lv_color_hex(0x16b8d4), 0);
    lv_obj_set_style_bg_grad_dir(disc, LV_GRAD_DIR_VER, 0);
    lv_obj_set_style_border_width(disc, 6, 0);
    lv_obj_set_style_border_color(disc, lv_color_hex(0x91ebff), 0);
    lv_obj_set_style_shadow_width(disc, 24, 0);
    lv_obj_set_style_shadow_color(disc, lv_color_hex(0x10b7d5), 0);
    lv_obj_set_style_shadow_opa(disc, LV_OPA_40, 0);
    lv_obj_remove_flag(disc, LV_OBJ_FLAG_SCROLLABLE);

    note = lv_label_create(disc);
    lv_label_set_text(note, LV_SYMBOL_AUDIO);
    lv_obj_set_style_text_font(note, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(note, lv_color_white(), 0);
    lv_obj_center(note);

    now_playing = lv_label_create(screen);
    lv_label_set_text(now_playing, "NOW PLAYING");
    lv_obj_set_style_text_font(now_playing, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(now_playing, lv_color_hex(0x8edcf7), 0);
    lv_obj_set_style_text_letter_space(now_playing, 3, 0);
    lv_obj_align(now_playing, LV_ALIGN_TOP_MID, 0, 410);

    ui->song = lv_label_create(screen);
    lv_label_set_text(ui->song, audio_track_name(ui->audio,
                                                ui->current_track));
    lv_obj_set_style_text_font(ui->song, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(ui->song, lv_color_white(), 0);
    lv_obj_set_width(ui->song, 420);
    lv_label_set_long_mode(ui->song, LV_LABEL_LONG_DOT);
    lv_obj_set_style_text_align(ui->song, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(ui->song, LV_ALIGN_TOP_MID, 0, 440);

    artist = lv_label_create(screen);
    lv_label_set_text(artist, "LA32R Demo Collection");
    lv_obj_set_style_text_font(artist, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(artist, lv_color_hex(0xb5e7f7), 0);
    lv_obj_align(artist, LV_ALIGN_TOP_MID, 0, 481);

    ui->progress = lv_bar_create(screen);
    lv_obj_set_size(ui->progress, 390, 12);
    lv_obj_align(ui->progress, LV_ALIGN_TOP_MID, 0, 530);
    lv_bar_set_range(ui->progress, 0, (int32_t)player_duration_ms(ui));
    lv_bar_set_value(ui->progress, (int32_t)player_position_ms(ui),
                     LV_ANIM_OFF);
    lv_obj_set_style_radius(ui->progress, LV_RADIUS_CIRCLE, LV_PART_MAIN);
    lv_obj_set_style_bg_color(ui->progress, lv_color_hex(0x315f78),
                              LV_PART_MAIN);
    lv_obj_set_style_bg_opa(ui->progress, LV_OPA_70, LV_PART_MAIN);
    lv_obj_set_style_radius(ui->progress, LV_RADIUS_CIRCLE,
                            LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(ui->progress, lv_color_hex(0x48d7ef),
                              LV_PART_INDICATOR);

    ui->elapsed = lv_label_create(screen);
    lv_obj_set_style_text_font(ui->elapsed, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(ui->elapsed, lv_color_hex(0xc8efff), 0);
    lv_obj_align(ui->elapsed, LV_ALIGN_TOP_LEFT, 45, 552);

    ui->duration = lv_label_create(screen);
    format_time(duration_text, sizeof(duration_text), player_duration_ms(ui));
    lv_label_set_text(ui->duration, duration_text);
    lv_obj_set_style_text_font(ui->duration, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(ui->duration, lv_color_hex(0xc8efff), 0);
    lv_obj_align(ui->duration, LV_ALIGN_TOP_RIGHT, -45, 552);

    (void)create_control_button(screen,
        ui->paused ? LV_SYMBOL_PLAY "  PLAY" : LV_SYMBOL_PAUSE "  PAUSE",
        28, pause_button_cb, ui, &ui->pause_label);
    (void)create_control_button(screen, LV_SYMBOL_NEXT "  NEXT", 177,
                                next_button_cb, ui, NULL);
    (void)create_control_button(screen, LV_SYMBOL_LIST "  MENU", 326,
                                menu_button_cb, ui, NULL);

    footer = lv_label_create(screen);
    {
        char footer_text[AUDIO_PATH_MAX + 16U];

        snprintf(footer_text, sizeof(footer_text), "Touch input: %s",
                 ui->input_path);
        lv_label_set_text(footer, footer_text);
    }
    lv_obj_set_style_text_font(footer, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(footer, lv_color_hex(0x8fc8da), 0);
    lv_obj_align(footer, LV_ALIGN_BOTTOM_MID, 0, -25);
}

static void create_menu_view(struct player_ui *ui)
{
    lv_obj_t *screen = lv_screen_active();
    lv_obj_t *panel;
    lv_obj_t *heading;
    lv_obj_t *hint;
    lv_obj_t *footer;
    lv_obj_t *back;
    lv_obj_t *back_label;
    char hint_text[32];
    unsigned int i;

    create_header(screen, "Touch a song to play");

    panel = lv_obj_create(screen);
    lv_obj_set_size(panel, 420, 570);
    lv_obj_align(panel, LV_ALIGN_TOP_MID, 0, 112);
    lv_obj_set_scrollbar_mode(panel, LV_SCROLLBAR_MODE_AUTO);
    lv_obj_set_scroll_dir(panel, LV_DIR_VER);
    lv_obj_set_style_pad_all(panel, 18, 0);
    set_panel_style(panel, 0x083f61, LV_OPA_80, 24);

    heading = lv_label_create(panel);
    lv_label_set_text(heading, LV_SYMBOL_LIST "  PLAYLIST");
    lv_obj_set_style_text_font(heading, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(heading, lv_color_white(), 0);
    lv_obj_align(heading, LV_ALIGN_TOP_LEFT, 5, 4);

    hint = lv_label_create(panel);
    snprintf(hint_text, sizeof(hint_text), "%u song%s found",
             ui->audio->track_count,
             ui->audio->track_count == 1U ? "" : "s");
    lv_label_set_text(hint, hint_text);
    lv_obj_set_style_text_font(hint, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(hint, lv_color_hex(0x9edbf1), 0);
    lv_obj_align(hint, LV_ALIGN_TOP_RIGHT, -5, 8);

    for(i = 0; i < ui->audio->track_count; ++i) {
        lv_obj_t *row = lv_obj_create(panel);
        lv_obj_t *name = lv_label_create(row);
        lv_obj_t *length = lv_label_create(row);
        bool selected = i == ui->current_track;
        char name_text[AUDIO_PATH_MAX + 8U];
        char length_text[24];

        ui->track_events[i].ui = ui;
        ui->track_events[i].index = i;
        lv_obj_set_size(row, 380, 64);
        lv_obj_align(row, LV_ALIGN_TOP_MID, 0, 55 + (int32_t)i * 72);
        lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_add_event_cb(row, track_button_cb, LV_EVENT_CLICKED,
                            &ui->track_events[i]);
        lv_obj_set_style_radius(row, 15, 0);
        lv_obj_set_style_border_width(row, selected ? 2 : 0, 0);
        lv_obj_set_style_border_color(row, lv_color_hex(0x55dff2), 0);
        lv_obj_set_style_bg_color(row,
                                  lv_color_hex(selected ? 0x0d7999 : 0x0b5778),
                                  0);
        lv_obj_set_style_bg_opa(row, selected ? LV_OPA_90 : LV_OPA_60, 0);

        snprintf(name_text, sizeof(name_text), "%02u  %s", i + 1U,
                 audio_track_name(ui->audio, i));
        lv_label_set_text(name, name_text);
        lv_obj_set_style_text_font(name, &lv_font_montserrat_14, 0);
        lv_obj_set_style_text_color(name, lv_color_white(), 0);
        lv_obj_set_width(name, 270);
        lv_label_set_long_mode(name, LV_LABEL_LONG_DOT);
        lv_obj_align(name, LV_ALIGN_LEFT_MID, 4, 0);

        format_time(length_text, sizeof(length_text),
                    audio_track_duration(ui->audio, i));
        if(selected) {
            char selected_text[32];

            snprintf(selected_text, sizeof(selected_text), LV_SYMBOL_PLAY " %s",
                     length_text);
            lv_label_set_text(length, selected_text);
        }
        else {
            lv_label_set_text(length, length_text);
        }
        lv_obj_set_style_text_font(length, &lv_font_montserrat_14, 0);
        lv_obj_set_style_text_color(length, lv_color_hex(0xa7e4f3), 0);
        lv_obj_align(length, LV_ALIGN_RIGHT_MID, -3, 0);
    }

    back = lv_button_create(screen);
    lv_obj_set_size(back, 150, 48);
    lv_obj_align(back, LV_ALIGN_BOTTOM_MID, 0, -18);
    lv_obj_set_style_radius(back, 15, 0);
    lv_obj_set_style_bg_color(back, lv_color_hex(0x087ca9), 0);
    lv_obj_add_event_cb(back, back_button_cb, LV_EVENT_CLICKED, ui);
    back_label = lv_label_create(back);
    lv_label_set_text(back_label, LV_SYMBOL_LEFT "  BACK");
    lv_obj_set_style_text_color(back_label, lv_color_white(), 0);
    lv_obj_center(back_label);

    footer = lv_label_create(screen);
    lv_label_set_text(footer, "Touch-enabled playlist");
    lv_obj_set_style_text_font(footer, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(footer, lv_color_hex(0x9bd3e6), 0);
    lv_obj_align(footer, LV_ALIGN_BOTTOM_MID, 0, -72);
}

static void create_background(void)
{
    lv_obj_t *screen = lv_screen_active();

    lv_obj_set_style_bg_color(screen, lv_color_hex(0x061f3a), 0);
    lv_obj_set_style_bg_grad_color(screen, lv_color_hex(0x117aa0), 0);
    lv_obj_set_style_bg_grad_dir(screen, LV_GRAD_DIR_VER, 0);
}

static void render_view(struct player_ui *ui)
{
    lv_obj_t *screen = lv_screen_active();

    ui->progress = NULL;
    ui->elapsed = NULL;
    ui->duration = NULL;
    ui->song = NULL;
    ui->pause_label = NULL;
    lv_obj_clean(screen);
    create_background();
    if(ui->view == PLAYER_VIEW_MENU)
        create_menu_view(ui);
    else
        create_player_view(ui);
}

static void update_timer_cb(lv_timer_t *timer)
{
    struct player_ui *ui = lv_timer_get_user_data(timer);
    uint32_t position_ms;
    uint32_t duration_ms;
    uint32_t position_seconds;
    char text[16];

    if(ui->view != PLAYER_VIEW_NOW_PLAYING || ui->progress == NULL ||
       ui->elapsed == NULL || ui->duration == NULL)
        return;

    position_ms = player_position_ms(ui);
    duration_ms = player_duration_ms(ui);
    position_seconds = position_ms / 1000U;
    lv_bar_set_range(ui->progress, 0, (int32_t)duration_ms);
    lv_bar_set_value(ui->progress, (int32_t)position_ms, LV_ANIM_OFF);
    snprintf(text, sizeof(text), "%02u:%02u", position_seconds / 60U,
             position_seconds % 60U);
    lv_label_set_text(ui->elapsed, text);
    format_time(text, sizeof(text), duration_ms);
    lv_label_set_text(ui->duration, text);
}

static int32_t map_coordinate(int32_t value, int32_t minimum,
                              int32_t maximum, int32_t output_size)
{
    int64_t mapped;

    if(output_size <= 1) return 0;
    if(maximum <= minimum) {
        if(value < 0) return 0;
        if(value >= output_size) return output_size - 1;
        return value;
    }
    if(value < minimum) value = minimum;
    if(value > maximum) value = maximum;
    mapped = (int64_t)(value - minimum) * (output_size - 1);
    return (int32_t)(mapped / (maximum - minimum));
}

static void touch_read_cb(lv_indev_t *indev, lv_indev_data_t *data)
{
    struct touch_input *touch = lv_indev_get_user_data(indev);
    struct input_event event;
    bool report_ready = false;
    ssize_t bytes;

    /* Submit exactly one evdev report to LVGL at a time.  Draining the whole
     * fd here would merge a quick press and release into RELEASED, making the
     * tap invisible to LVGL. */
    for(;;) {
        bytes = read(touch->fd, &event, sizeof(event));
        if(bytes < 0 && errno == EINTR)
            continue;
        if(bytes != (ssize_t)sizeof(event))
            break;

        if(event.type == EV_ABS) {
            if(event.code == ABS_X || event.code == ABS_MT_POSITION_X)
                touch->raw_x = event.value;
            else if(event.code == ABS_Y || event.code == ABS_MT_POSITION_Y)
                touch->raw_y = event.value;
            else if(event.code == ABS_MT_TRACKING_ID && event.value < 0)
                touch->pressed = false;
        }
        else if(event.type == EV_KEY && event.code == BTN_TOUCH) {
            touch->pressed = event.value != 0;
        }
        else if(event.type == EV_SYN) {
            if(event.code == SYN_DROPPED)
                touch->pressed = false;
            else if(event.code == SYN_REPORT) {
                report_ready = true;
                break;
            }
        }
    }

    data->point.x = map_coordinate(touch->raw_x, touch->min_x,
                                   touch->max_x, touch->display_width);
    data->point.y = map_coordinate(touch->raw_y, touch->min_y,
                                   touch->max_y, touch->display_height);
    data->state = touch->pressed ? LV_INDEV_STATE_PRESSED :
                                  LV_INDEV_STATE_RELEASED;
    /* LVGL processes this report before calling us again.  If more reports
     * are queued, the next invocation preserves their state transitions. */
    data->continue_reading = report_ready;
}

static int touch_input_open(struct touch_input *touch, const char *path,
                            int32_t width, int32_t height)
{
    struct input_absinfo x_info;
    struct input_absinfo y_info;

    memset(touch, 0, sizeof(*touch));
    touch->fd = open(path, O_RDONLY | O_NONBLOCK);
    if(touch->fd < 0)
        return -1;

    touch->display_width = width;
    touch->display_height = height;
    touch->min_x = 0;
    touch->max_x = width - 1;
    touch->min_y = 0;
    touch->max_y = height - 1;

    if(ioctl(touch->fd, EVIOCGABS(ABS_X), &x_info) == 0) {
        touch->min_x = x_info.minimum;
        touch->max_x = x_info.maximum;
    }
    if(ioctl(touch->fd, EVIOCGABS(ABS_Y), &y_info) == 0) {
        touch->min_y = y_info.minimum;
        touch->max_y = y_info.maximum;
    }
    return 0;
}

int main(int argc, char **argv)
{
    const char *fb_path = "/dev/fb0";
    const char *input_path = "/dev/input/event1";
    const char *alsa_device = "hw:0,0";
    const char *music_directory = "/tmp";
    const char *initial_track_path = NULL;
    char derived_directory[AUDIO_PATH_MAX];
    bool music_directory_explicit = false;
    struct playlist playlist;
    struct player_ui ui = {
        .view = PLAYER_VIEW_NOW_PLAYING,
    };
    struct audio_engine audio;
    struct touch_input touch;
    lv_display_t *display;
    lv_indev_t *indev;
    bool show_menu = false;
    unsigned int initial_track = 0;
    int fd;
    int i;

    for(i = 1; i < argc; ++i) {
        if(strcmp(argv[i], "--menu") == 0) {
            show_menu = true;
        }
        else if(strcmp(argv[i], "--input") == 0 && i + 1 < argc) {
            input_path = argv[++i];
        }
        else if(strcmp(argv[i], "--alsa") == 0 && i + 1 < argc) {
            alsa_device = argv[++i];
        }
        else if(strcmp(argv[i], "--music-dir") == 0 && i + 1 < argc) {
            music_directory = argv[++i];
            music_directory_explicit = true;
        }
        else if(strcmp(argv[i], "--track") == 0 && i + 1 < argc) {
            initial_track_path = argv[++i];
        }
        else if(strcmp(argv[i], "--help") == 0) {
            printf("Usage: %s [fbdev] [--input event] [--alsa pcm] "
                   "[--music-dir dir] [--track initial.wav] [--menu]\n",
                   argv[0]);
            return 0;
        }
        else if(argv[i][0] == '-') {
            fprintf(stderr, "Unknown or incomplete option: %s\n", argv[i]);
            return 2;
        }
        else {
            fb_path = argv[i];
        }
    }

    if(initial_track_path != NULL && !music_directory_explicit) {
        path_directory(derived_directory, sizeof(derived_directory),
                       initial_track_path);
        music_directory = derived_directory;
    }
    if(playlist_scan(&playlist, music_directory) != 0) {
        fprintf(stderr,
                "No playable 44.1kHz stereo S16_LE WAV files in %s\n",
                music_directory);
        return 1;
    }
    if(initial_track_path != NULL)
        initial_track = playlist_find(&playlist, initial_track_path);

    fd = open(fb_path, O_RDWR);
    if(fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", fb_path, strerror(errno));
        return 1;
    }
    close(fd);

    signal(SIGINT, stop_handler);
    signal(SIGTERM, stop_handler);

    lv_init();
    display = lv_linux_fbdev_create();
    if(display == NULL) {
        fprintf(stderr, "Cannot create LVGL framebuffer display\n");
        return 1;
    }
    lv_linux_fbdev_set_file(display, fb_path);
    lv_tick_set_cb(app_tick_ms);

    if(touch_input_open(&touch, input_path,
                        lv_display_get_horizontal_resolution(display),
                        lv_display_get_vertical_resolution(display)) < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", input_path, strerror(errno));
        return 1;
    }

    indev = lv_indev_create();
    if(indev == NULL) {
        fprintf(stderr, "Cannot create LVGL touch input device\n");
        close(touch.fd);
        return 1;
    }
    lv_indev_set_type(indev, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(indev, touch_read_cb);
    lv_indev_set_user_data(indev, &touch);
    lv_indev_set_display(indev, display);

    if(audio_engine_init(&audio, alsa_device, &playlist) != 0) {
        fprintf(stderr, "Cannot start ALSA playback thread\n");
        close(touch.fd);
        return 1;
    }
    ui.audio = &audio;
    ui.current_track = initial_track;
    ui.input_path = input_path;
    ui.view = show_menu ? PLAYER_VIEW_MENU : PLAYER_VIEW_NOW_PLAYING;
    render_view(&ui);
    lv_timer_create(update_timer_cb, UI_REFRESH_MS, &ui);

    /* Do not let the initial 480x800 render contend with the I2S DMA's first
     * FIFO fill.  Later progress updates only invalidate small screen areas. */
    lv_refr_now(display);
    audio_engine_select(&audio, initial_track);

    printf("LVGL audio player started: fb=%s, input=%s, %ld x %ld, view=%s\n",
           fb_path, input_path,
           (long)lv_display_get_horizontal_resolution(display),
           (long)lv_display_get_vertical_resolution(display),
           show_menu ? "menu" : "player");
    printf("Touch range: X=%ld..%ld, Y=%ld..%ld\n",
           (long)touch.min_x, (long)touch.max_x,
           (long)touch.min_y, (long)touch.max_y);
    printf("ALSA device: %s\n", alsa_device);
    printf("Music directory: %s (%u playable WAV file%s)\n",
           music_directory, playlist.count, playlist.count == 1U ? "" : "s");
    for(i = 0; i < (int)playlist.count; ++i) {
        char duration_text[16];

        format_time(duration_text, sizeof(duration_text),
                    playlist.tracks[i].duration_ms);
        printf("Track %d: %s [%s]\n", i + 1, playlist.tracks[i].path,
               duration_text);
    }

    while(running) {
        uint32_t delay_ms = lv_timer_handler();

        if(delay_ms < 5U) delay_ms = 5U;
        if(delay_ms > 50U) delay_ms = 50U;
        app_sleep_ms(delay_ms);
    }

    audio_engine_shutdown(&audio);
    close(touch.fd);
    printf("LVGL audio player stopped\n");
    return 0;
}
