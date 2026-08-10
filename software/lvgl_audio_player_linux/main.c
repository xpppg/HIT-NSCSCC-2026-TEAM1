#include "lvgl.h"
#include "src/drivers/display/fb/lv_linux_fbdev.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define TRACK_LENGTH_SECONDS 228U
#define UI_REFRESH_MS        100U

/*
 * This BSP reports a 200 MHz constant counter although the FPGA counter
 * advances at the 33 MHz CPU clock.  Keep the BSP behavior for compatibility
 * and compensate for it locally in this application.
 */
#define BSP_TIMER_HZ         200000000ULL
#define FPGA_TIMER_HZ         33000000ULL

static volatile sig_atomic_t running = 1;

struct player_ui {
    lv_obj_t *progress;
    lv_obj_t *elapsed;
    uint64_t start_ms;
    uint32_t start_position_ms;
};

static const char *const playlist[] = {
    "01  Blue Horizon.wav",
    "02  Morning Light.wav",
    "03  Loongson Dream.wav",
    "04  Network Radio.wav",
    "05  LCD Test Tone.wav",
};

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
                                       int32_t x)
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

    lv_label_set_text(label, text);
    lv_obj_set_style_text_font(label, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(label, lv_color_white(), 0);
    lv_obj_center(label);
    return button;
}

static void create_player_view(struct player_ui *ui)
{
    lv_obj_t *screen = lv_screen_active();
    lv_obj_t *art_card;
    lv_obj_t *disc;
    lv_obj_t *note;
    lv_obj_t *now_playing;
    lv_obj_t *song;
    lv_obj_t *artist;
    lv_obj_t *duration;
    lv_obj_t *footer;

    create_header(screen, "Framebuffer audio player concept");

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

    song = lv_label_create(screen);
    lv_label_set_text(song, "Blue Horizon");
    lv_obj_set_style_text_font(song, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(song, lv_color_white(), 0);
    lv_obj_align(song, LV_ALIGN_TOP_MID, 0, 440);

    artist = lv_label_create(screen);
    lv_label_set_text(artist, "LA32R Demo Collection");
    lv_obj_set_style_text_font(artist, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(artist, lv_color_hex(0xb5e7f7), 0);
    lv_obj_align(artist, LV_ALIGN_TOP_MID, 0, 481);

    ui->progress = lv_bar_create(screen);
    lv_obj_set_size(ui->progress, 390, 12);
    lv_obj_align(ui->progress, LV_ALIGN_TOP_MID, 0, 530);
    lv_bar_set_range(ui->progress, 0, TRACK_LENGTH_SECONDS * 1000U);
    lv_bar_set_value(ui->progress, (int32_t)ui->start_position_ms,
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
    lv_label_set_text(ui->elapsed, "01:24");
    lv_obj_set_style_text_font(ui->elapsed, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(ui->elapsed, lv_color_hex(0xc8efff), 0);
    lv_obj_align(ui->elapsed, LV_ALIGN_TOP_LEFT, 45, 552);

    duration = lv_label_create(screen);
    lv_label_set_text(duration, "03:48");
    lv_obj_set_style_text_font(duration, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(duration, lv_color_hex(0xc8efff), 0);
    lv_obj_align(duration, LV_ALIGN_TOP_RIGHT, -45, 552);

    (void)create_control_button(screen, LV_SYMBOL_PAUSE "  PAUSE", 28);
    (void)create_control_button(screen, LV_SYMBOL_NEXT "  NEXT", 177);
    (void)create_control_button(screen, LV_SYMBOL_LIST "  MENU", 326);

    footer = lv_label_create(screen);
    lv_label_set_text(footer, "I2S output: not connected");
    lv_obj_set_style_text_font(footer, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(footer, lv_color_hex(0x8fc8da), 0);
    lv_obj_align(footer, LV_ALIGN_BOTTOM_MID, 0, -25);
}

static void create_menu_view(void)
{
    lv_obj_t *screen = lv_screen_active();
    lv_obj_t *panel;
    lv_obj_t *heading;
    lv_obj_t *hint;
    lv_obj_t *footer;
    unsigned int i;

    create_header(screen, "Available songs");

    panel = lv_obj_create(screen);
    lv_obj_set_size(panel, 420, 570);
    lv_obj_align(panel, LV_ALIGN_TOP_MID, 0, 112);
    lv_obj_remove_flag(panel, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_all(panel, 18, 0);
    set_panel_style(panel, 0x083f61, LV_OPA_80, 24);

    heading = lv_label_create(panel);
    lv_label_set_text(heading, LV_SYMBOL_LIST "  PLAYLIST");
    lv_obj_set_style_text_font(heading, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(heading, lv_color_white(), 0);
    lv_obj_align(heading, LV_ALIGN_TOP_LEFT, 5, 4);

    hint = lv_label_create(panel);
    lv_label_set_text(hint, "5 songs found");
    lv_obj_set_style_text_font(hint, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(hint, lv_color_hex(0x9edbf1), 0);
    lv_obj_align(hint, LV_ALIGN_TOP_RIGHT, -5, 8);

    for(i = 0; i < sizeof(playlist) / sizeof(playlist[0]); ++i) {
        lv_obj_t *row = lv_obj_create(panel);
        lv_obj_t *name = lv_label_create(row);
        lv_obj_t *length = lv_label_create(row);

        lv_obj_set_size(row, 380, 76);
        lv_obj_align(row, LV_ALIGN_TOP_MID, 0, 55 + (int32_t)i * 91);
        lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_style_radius(row, 15, 0);
        lv_obj_set_style_border_width(row, i == 0U ? 2 : 0, 0);
        lv_obj_set_style_border_color(row, lv_color_hex(0x55dff2), 0);
        lv_obj_set_style_bg_color(row,
                                  lv_color_hex(i == 0U ? 0x0d7999 : 0x0b5778),
                                  0);
        lv_obj_set_style_bg_opa(row, i == 0U ? LV_OPA_90 : LV_OPA_60, 0);

        lv_label_set_text(name, playlist[i]);
        lv_obj_set_style_text_font(name, &lv_font_montserrat_14, 0);
        lv_obj_set_style_text_color(name, lv_color_white(), 0);
        lv_obj_align(name, LV_ALIGN_LEFT_MID, 4, 0);

        lv_label_set_text(length, i == 0U ? LV_SYMBOL_PLAY " 03:48" : "03:30");
        lv_obj_set_style_text_font(length, &lv_font_montserrat_14, 0);
        lv_obj_set_style_text_color(length, lv_color_hex(0xa7e4f3), 0);
        lv_obj_align(length, LV_ALIGN_RIGHT_MID, -3, 0);
    }

    footer = lv_label_create(screen);
    lv_label_set_text(footer, "Display preview - input disabled");
    lv_obj_set_style_text_font(footer, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(footer, lv_color_hex(0x9bd3e6), 0);
    lv_obj_align(footer, LV_ALIGN_BOTTOM_MID, 0, -50);
}

static void create_background(void)
{
    lv_obj_t *screen = lv_screen_active();

    lv_obj_set_style_bg_color(screen, lv_color_hex(0x061f3a), 0);
    lv_obj_set_style_bg_grad_color(screen, lv_color_hex(0x117aa0), 0);
    lv_obj_set_style_bg_grad_dir(screen, LV_GRAD_DIR_VER, 0);
}

static void update_timer_cb(lv_timer_t *timer)
{
    struct player_ui *ui = lv_timer_get_user_data(timer);
    uint64_t elapsed_ms = app_monotonic_ms() - ui->start_ms;
    uint32_t position_ms;
    uint32_t position_seconds;
    char text[16];

    position_ms = (uint32_t)((ui->start_position_ms + elapsed_ms) %
                             (TRACK_LENGTH_SECONDS * 1000U));
    position_seconds = position_ms / 1000U;

    lv_bar_set_value(ui->progress, (int32_t)position_ms, LV_ANIM_OFF);
    snprintf(text, sizeof(text), "%02u:%02u", position_seconds / 60U,
             position_seconds % 60U);
    lv_label_set_text(ui->elapsed, text);
}

int main(int argc, char **argv)
{
    const char *fb_path = "/dev/fb0";
    struct player_ui ui = {
        .start_position_ms = 84U * 1000U,
    };
    lv_display_t *display;
    bool show_menu = false;
    int fd;
    int i;

    for(i = 1; i < argc; ++i) {
        if(strcmp(argv[i], "--menu") == 0)
            show_menu = true;
        else
            fb_path = argv[i];
    }

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

    printf("LVGL audio player started on %s (%ld x %ld), view=%s\n",
           fb_path, (long)lv_display_get_horizontal_resolution(display),
           (long)lv_display_get_vertical_resolution(display),
           show_menu ? "menu" : "player");

    create_background();
    if(show_menu)
        create_menu_view();
    else {
        ui.start_ms = app_monotonic_ms();
        create_player_view(&ui);
        lv_timer_create(update_timer_cb, UI_REFRESH_MS, &ui);
    }

    while(running) {
        uint32_t delay_ms = lv_timer_handler();

        if(delay_ms < 5U) delay_ms = 5U;
        if(delay_ms > 50U) delay_ms = 50U;
        app_sleep_ms(delay_ms);
    }

    printf("LVGL audio player stopped\n");
    return 0;
}
