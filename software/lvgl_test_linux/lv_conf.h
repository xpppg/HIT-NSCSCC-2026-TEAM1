#ifndef LV_CONF_H
#define LV_CONF_H

/* LA32R has no hardware floating-point unit. */
#define LV_COLOR_DEPTH 16
#define LV_USE_FLOAT 0
#define LV_USE_OS LV_OS_NONE

/* Draw directly through the Linux framebuffer device. */
#define LV_USE_LINUX_FBDEV 1
#define LV_LINUX_FBDEV_RENDER_MODE LV_DISPLAY_RENDER_MODE_PARTIAL
#define LV_LINUX_FBDEV_BUFFER_SIZE 10

/* Keep the test binary small and self-contained. */
#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_WARN
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_28 1
#define LV_USE_LABEL 1
#define LV_USE_BUTTON 1
#define LV_USE_BAR 1

#endif
