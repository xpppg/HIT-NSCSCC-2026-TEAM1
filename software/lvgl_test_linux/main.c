#include "lvgl.h"
#include "src/drivers/display/fb/lv_linux_fbdev.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

struct ui_state {
    lv_obj_t *counter_label;
    lv_obj_t *bar;
    unsigned int counter;
};

static void stop_handler(int signo)
{
    (void)signo;
    running = 0;
}

static void update_timer_cb(lv_timer_t *timer)
{
    struct ui_state *ui = lv_timer_get_user_data(timer);

    ui->counter++;
    lv_label_set_text_fmt(ui->counter_label, "Linux timer: %u", ui->counter);
    lv_bar_set_value(ui->bar, (int32_t)((ui->counter * 10U) % 101U),
                     LV_ANIM_OFF);
}

static void create_ui(struct ui_state *ui)
{
    lv_obj_t *screen = lv_screen_active();
    lv_obj_t *title;
    lv_obj_t *subtitle;
    lv_obj_t *card;
    lv_obj_t *status;
    lv_obj_t *button;
    lv_obj_t *button_label;

    lv_obj_set_style_bg_color(screen, lv_color_hex(0x082b4c), 0);
    lv_obj_set_style_bg_grad_color(screen, lv_color_hex(0x126a91), 0);
    lv_obj_set_style_bg_grad_dir(screen, LV_GRAD_DIR_VER, 0);

    title = lv_label_create(screen);
    lv_label_set_text(title, "LA32R  LVGL");
    lv_obj_set_style_text_font(title, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(title, lv_color_white(), 0);
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 70);

    subtitle = lv_label_create(screen);
    lv_label_set_text(subtitle, "Linux framebuffer demonstration");
    lv_obj_set_style_text_color(subtitle, lv_color_hex(0xb9e8ff), 0);
    lv_obj_align_to(subtitle, title, LV_ALIGN_OUT_BOTTOM_MID, 0, 12);

    card = lv_obj_create(screen);
    lv_obj_set_size(card, 410, 360);
    lv_obj_align(card, LV_ALIGN_CENTER, 0, 15);
    lv_obj_set_style_radius(card, 18, 0);
    lv_obj_set_style_bg_color(card, lv_color_hex(0xf4f8fb), 0);
    lv_obj_set_style_border_width(card, 0, 0);
    lv_obj_set_style_pad_all(card, 28, 0);

    status = lv_label_create(card);
    lv_label_set_text(status,
                      "Framebuffer: /dev/fb0\n"
                      "Resolution: 480 x 800\n"
                      "Pixel format: RGB565\n"
                      "Floating point: disabled");
    lv_obj_set_style_text_font(status, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(status, lv_color_hex(0x17354d), 0);
    lv_obj_align(status, LV_ALIGN_TOP_LEFT, 0, 0);

    ui->bar = lv_bar_create(card);
    lv_obj_set_size(ui->bar, 350, 22);
    lv_bar_set_range(ui->bar, 0, 100);
    lv_bar_set_value(ui->bar, 0, LV_ANIM_OFF);
    lv_obj_align(ui->bar, LV_ALIGN_CENTER, 0, 30);
    lv_obj_set_style_bg_color(ui->bar, lv_color_hex(0xd4e4ec),
                              LV_PART_MAIN);
    lv_obj_set_style_bg_color(ui->bar, lv_color_hex(0x0084ae),
                              LV_PART_INDICATOR);

    ui->counter_label = lv_label_create(card);
    lv_label_set_text(ui->counter_label, "Linux timer: 0");
    lv_obj_set_style_text_font(ui->counter_label, &lv_font_montserrat_20, 0);
    lv_obj_set_style_text_color(ui->counter_label, lv_color_hex(0x005c7c), 0);
    lv_obj_align(ui->counter_label, LV_ALIGN_CENTER, 0, 80);

    button = lv_button_create(card);
    lv_obj_set_size(button, 220, 58);
    lv_obj_align(button, LV_ALIGN_BOTTOM_MID, 0, -2);
    lv_obj_set_style_bg_color(button, lv_color_hex(0x007da5), 0);

    button_label = lv_label_create(button);
    lv_label_set_text(button_label, "LVGL is running");
    lv_obj_center(button_label);

    status = lv_label_create(screen);
    lv_label_set_text(status, "Ctrl+C to exit");
    lv_obj_set_style_text_color(status, lv_color_hex(0xb9e8ff), 0);
    lv_obj_align(status, LV_ALIGN_BOTTOM_MID, 0, -55);
}

int main(int argc, char **argv)
{
    const char *fb_path = argc > 1 ? argv[1] : "/dev/fb0";
    struct ui_state ui = { 0 };
    lv_display_t *display;
    int fd;

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

    printf("LVGL test started on %s (%ld x %ld)\n", fb_path,
           (long)lv_display_get_horizontal_resolution(display),
           (long)lv_display_get_vertical_resolution(display));

    create_ui(&ui);
    lv_timer_create(update_timer_cb, 3000, &ui);

    while(running) {
        uint32_t delay_ms = lv_timer_handler();

        if(delay_ms < 5U) delay_ms = 5U;
        if(delay_ms > 50U) delay_ms = 50U;
        usleep(delay_ms * 1000U);
    }

    printf("LVGL test stopped\n");
    return 0;
}
