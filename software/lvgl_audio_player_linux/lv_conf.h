#ifndef LV_CONF_H
#define LV_CONF_H

/* LA32R has no hardware floating-point unit. */
#define LV_COLOR_DEPTH 16
#define LV_USE_FLOAT 0
#define LV_USE_OS LV_OS_NONE

/*
 * Keep one complete RGB565 draw buffer.  Rendering the initial screen into a
 * full frame prevents framebuffer deferred-I/O from starting DMA between the
 * small strips used by partial rendering.
 */
#define LV_USE_LINUX_FBDEV 1
#define LV_LINUX_FBDEV_RENDER_MODE LV_DISPLAY_RENDER_MODE_DIRECT

#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_WARN
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_28 1
#define LV_USE_LABEL 1
#define LV_USE_BUTTON 1
#define LV_USE_BAR 1

#endif
