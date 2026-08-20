#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <linux/kd.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define BOARD_COLS 10
#define BOARD_ROWS 20
#define CELL_SIZE  28
#define BOARD_X    100
#define BOARD_Y    150

#define COLOR_SCREEN_BG 0x0842
#define COLOR_BOARD_BG  0x0021
#define COLOR_GRID      0x18c3
#define COLOR_FRAME     0x7bef
#define COLOR_TEXT      0xffff
#define COLOR_ACCENT    0x3dff
#define COLOR_WARNING   0xf945

#define UPDATE_BOARD    0x01
#define UPDATE_STATUS   0x02
#define UPDATE_STATS    0x04

struct point {
    int8_t x;
    int8_t y;
};

struct piece {
    int type;
    int rotation;
    int x;
    int y;
};

struct game {
    uint8_t board[BOARD_ROWS][BOARD_COLS];
    uint8_t rendered[BOARD_ROWS][BOARD_COLS];
    struct piece active;
    uint8_t bag[7];
    unsigned int bag_pos;
    uint32_t random_state;
    unsigned int score;
    unsigned int lines;
    unsigned int level;
    int paused;
    int game_over;
};

struct display {
    int fd;
    struct fb_var_screeninfo var;
    struct fb_fix_screeninfo fix;
};

static const struct point shapes[7][4][4] = {
    { /* I */
        {{0,1},{1,1},{2,1},{3,1}}, {{2,0},{2,1},{2,2},{2,3}},
        {{0,2},{1,2},{2,2},{3,2}}, {{1,0},{1,1},{1,2},{1,3}}
    },
    { /* O */
        {{1,0},{2,0},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{2,1}},
        {{1,0},{2,0},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{2,1}}
    },
    { /* T */
        {{1,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{2,1},{1,2}},
        {{0,1},{1,1},{2,1},{1,2}}, {{1,0},{0,1},{1,1},{1,2}}
    },
    { /* S */
        {{1,0},{2,0},{0,1},{1,1}}, {{1,0},{1,1},{2,1},{2,2}},
        {{1,1},{2,1},{0,2},{1,2}}, {{0,0},{0,1},{1,1},{1,2}}
    },
    { /* Z */
        {{0,0},{1,0},{1,1},{2,1}}, {{2,0},{1,1},{2,1},{1,2}},
        {{0,1},{1,1},{1,2},{2,2}}, {{1,0},{0,1},{1,1},{0,2}}
    },
    { /* J */
        {{0,0},{0,1},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{1,2}},
        {{0,1},{1,1},{2,1},{2,2}}, {{1,0},{1,1},{0,2},{1,2}}
    },
    { /* L */
        {{2,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{1,2},{2,2}},
        {{0,1},{1,1},{2,1},{0,2}}, {{0,0},{1,0},{1,1},{1,2}}
    }
};

static const uint16_t colors[8] = {
    COLOR_BOARD_BG, 0x07ff, 0xffe0, 0xf81f,
    0x07e0, 0xf800, 0x001f, 0xfd20
};

struct glyph {
    char c;
    uint8_t rows[7];
};

static const struct glyph font[] = {
    {' ',{0,0,0,0,0,0,0}}, {'-',{0,0,0,31,0,0,0}},
    {':',{0,4,4,0,4,4,0}},
    {'0',{14,17,19,21,25,17,14}}, {'1',{4,12,4,4,4,4,14}},
    {'2',{14,17,1,2,4,8,31}}, {'3',{30,1,1,14,1,1,30}},
    {'4',{2,6,10,18,31,2,2}}, {'5',{31,16,16,30,1,1,30}},
    {'6',{6,8,16,30,17,17,14}}, {'7',{31,1,2,4,8,8,8}},
    {'8',{14,17,17,14,17,17,14}}, {'9',{14,17,17,15,1,2,12}},
    {'A',{14,17,17,31,17,17,17}}, {'B',{30,17,17,30,17,17,30}},
    {'C',{14,17,16,16,16,17,14}}, {'D',{30,17,17,17,17,17,30}},
    {'E',{31,16,16,30,16,16,31}}, {'F',{31,16,16,30,16,16,16}},
    {'G',{14,17,16,23,17,17,15}}, {'H',{17,17,17,31,17,17,17}},
    {'I',{14,4,4,4,4,4,14}}, {'J',{7,2,2,2,2,18,12}},
    {'K',{17,18,20,24,20,18,17}}, {'L',{16,16,16,16,16,16,31}},
    {'M',{17,27,21,21,17,17,17}}, {'N',{17,25,21,19,17,17,17}},
    {'O',{14,17,17,17,17,17,14}}, {'P',{30,17,17,30,16,16,16}},
    {'Q',{14,17,17,17,21,18,13}}, {'R',{30,17,17,30,20,18,17}},
    {'S',{15,16,16,14,1,1,30}}, {'T',{31,4,4,4,4,4,4}},
    {'U',{17,17,17,17,17,17,14}}, {'V',{17,17,17,17,17,10,4}},
    {'W',{17,17,17,21,21,21,10}}, {'X',{17,17,10,4,10,17,17}},
    {'Y',{17,17,10,4,4,4,4}}, {'Z',{31,1,2,4,8,16,31}}
};

static volatile sig_atomic_t stop_requested;

static void signal_handler(int signal_number)
{
    (void)signal_number;
    stop_requested = 1;
}

static uint64_t monotonic_ms(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000U + (uint64_t)ts.tv_nsec / 1000000U;
}

static int write_at(int fd, const void *buffer, size_t length, off_t offset)
{
    const uint8_t *data = buffer;

    while (length) {
        ssize_t written = pwrite(fd, data, length, offset);

        if (written < 0 && errno == EINTR)
            continue;
        if (written <= 0)
            return -1;
        data += written;
        offset += written;
        length -= (size_t)written;
    }
    return 0;
}

static int write_rect(struct display *display, unsigned int x, unsigned int y,
                      unsigned int width, unsigned int height,
                      const uint16_t *pixels, unsigned int source_stride)
{
    unsigned int row;

    if (!width || !height || x + width > display->var.xres ||
        y + height > display->var.yres)
        return -1;

    for (row = 0; row < height; ++row) {
        off_t offset = (off_t)(y + row) * display->fix.line_length +
                       (off_t)x * 2;
        if (write_at(display->fd, pixels + row * source_stride,
                     (size_t)width * 2, offset))
            return -1;
    }
    return 0;
}

static int fill_rect(struct display *display, unsigned int x, unsigned int y,
                     unsigned int width, unsigned int height, uint16_t color)
{
    uint16_t row[480];
    unsigned int index;
    unsigned int py;

    if (width > sizeof(row) / sizeof(row[0]))
        return -1;
    for (index = 0; index < width; ++index)
        row[index] = color;
    for (py = 0; py < height; ++py) {
        if (write_rect(display, x, y + py, width, 1, row, width))
            return -1;
    }
    return 0;
}

static const uint8_t *glyph_rows(char c)
{
    size_t index;

    for (index = 0; index < sizeof(font) / sizeof(font[0]); ++index)
        if (font[index].c == c)
            return font[index].rows;
    return font[0].rows;
}

static int draw_text(struct display *display, unsigned int x, unsigned int y,
                     const char *text, unsigned int scale,
                     uint16_t foreground, uint16_t background)
{
    size_t length = strlen(text);
    unsigned int width = length ? (unsigned int)(length * 6U - 1U) * scale : 0;
    unsigned int height = 7U * scale;
    uint16_t *pixels;
    size_t count;
    size_t character;
    int ret;

    if (!width || x + width > display->var.xres || y + height > display->var.yres)
        return -1;
    count = (size_t)width * height;
    pixels = malloc(count * sizeof(*pixels));
    if (!pixels)
        return -1;
    for (character = 0; character < count; ++character)
        pixels[character] = background;

    for (character = 0; character < length; ++character) {
        const uint8_t *rows = glyph_rows(text[character]);
        unsigned int row;
        unsigned int column;

        for (row = 0; row < 7; ++row) {
            for (column = 0; column < 5; ++column) {
                unsigned int sx;
                unsigned int sy;

                if (!(rows[row] & (1U << (4U - column))))
                    continue;
                for (sy = 0; sy < scale; ++sy)
                    for (sx = 0; sx < scale; ++sx)
                        pixels[(row * scale + sy) * width +
                               ((unsigned int)character * 6U + column) * scale + sx] =
                            foreground;
            }
        }
    }
    ret = write_rect(display, x, y, width, height, pixels, width);
    free(pixels);
    return ret;
}

static int clear_screen(struct display *display)
{
    size_t size = (size_t)display->fix.line_length * display->var.yres;
    uint8_t *memory = calloc(1, size);
    unsigned int y;

    if (!memory)
        return -1;
    for (y = 0; y < display->var.yres; ++y) {
        uint16_t *row = (uint16_t *)(memory + (size_t)y * display->fix.line_length);
        unsigned int x;

        for (x = 0; x < display->var.xres; ++x)
            row[x] = COLOR_SCREEN_BG;
    }
    if (write_at(display->fd, memory, size, 0)) {
        free(memory);
        return -1;
    }
    free(memory);
    return 0;
}

static uint16_t shade(uint16_t color, int lighter)
{
    unsigned int r = (color >> 11) & 31U;
    unsigned int g = (color >> 5) & 63U;
    unsigned int b = color & 31U;

    if (lighter) {
        r = r + (31U - r) / 2U;
        g = g + (63U - g) / 2U;
        b = b + (31U - b) / 2U;
    } else {
        r /= 2U;
        g /= 2U;
        b /= 2U;
    }
    return (uint16_t)((r << 11) | (g << 5) | b);
}

static void render_cell_pixel(uint16_t *pixel, uint8_t cell,
                              unsigned int local_x, unsigned int local_y)
{
    if (!cell) {
        *pixel = (local_x == 0 || local_y == 0) ? COLOR_GRID : COLOR_BOARD_BG;
        return;
    }

    if (local_x == 0 || local_y == 0 || local_x == CELL_SIZE - 1U ||
        local_y == CELL_SIZE - 1U) {
        *pixel = COLOR_BOARD_BG;
    } else if (local_x <= 3U || local_y <= 3U) {
        *pixel = shade(colors[cell], 1);
    } else if (local_x >= CELL_SIZE - 4U || local_y >= CELL_SIZE - 4U) {
        *pixel = shade(colors[cell], 0);
    } else {
        *pixel = colors[cell];
    }
}

static int piece_fits(const struct game *game, const struct piece *piece)
{
    int index;

    for (index = 0; index < 4; ++index) {
        int x = piece->x + shapes[piece->type][piece->rotation][index].x;
        int y = piece->y + shapes[piece->type][piece->rotation][index].y;

        if (x < 0 || x >= BOARD_COLS || y >= BOARD_ROWS)
            return 0;
        if (y >= 0 && game->board[y][x])
            return 0;
    }
    return 1;
}

static uint32_t random_next(struct game *game)
{
    uint32_t value = game->random_state;

    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    game->random_state = value ? value : 0x13579bdfU;
    return game->random_state;
}

static void refill_bag(struct game *game)
{
    int index;

    for (index = 0; index < 7; ++index)
        game->bag[index] = (uint8_t)index;
    for (index = 6; index > 0; --index) {
        unsigned int other = random_next(game) % (unsigned int)(index + 1);
        uint8_t temporary = game->bag[index];

        game->bag[index] = game->bag[other];
        game->bag[other] = temporary;
    }
    game->bag_pos = 0;
}

static int next_piece(struct game *game)
{
    if (game->bag_pos >= 7)
        refill_bag(game);
    return game->bag[game->bag_pos++];
}

static void spawn_piece(struct game *game)
{
    game->active.type = next_piece(game);
    game->active.rotation = 0;
    game->active.x = 3;
    game->active.y = -1;
    if (!piece_fits(game, &game->active))
        game->game_over = 1;
}

static int clear_lines(struct game *game)
{
    int source;
    int destination = BOARD_ROWS - 1;
    int cleared = 0;

    for (source = BOARD_ROWS - 1; source >= 0; --source) {
        int column;
        int full = 1;

        for (column = 0; column < BOARD_COLS; ++column)
            if (!game->board[source][column])
                full = 0;
        if (full) {
            ++cleared;
            continue;
        }
        if (destination != source)
            memcpy(game->board[destination], game->board[source], BOARD_COLS);
        --destination;
    }
    while (destination >= 0) {
        memset(game->board[destination], 0, BOARD_COLS);
        --destination;
    }
    return cleared;
}

static void lock_piece(struct game *game)
{
    static const unsigned int line_score[5] = {0, 100, 300, 500, 800};
    int index;
    int cleared;

    for (index = 0; index < 4; ++index) {
        int x = game->active.x + shapes[game->active.type][game->active.rotation][index].x;
        int y = game->active.y + shapes[game->active.type][game->active.rotation][index].y;

        if (y < 0) {
            game->game_over = 1;
            return;
        }
        game->board[y][x] = (uint8_t)(game->active.type + 1);
    }
    cleared = clear_lines(game);
    game->score += line_score[cleared] * game->level;
    game->lines += (unsigned int)cleared;
    game->level = 1U + game->lines / 10U;
    spawn_piece(game);
}

static int move_piece(struct game *game, int dx, int dy)
{
    struct piece candidate = game->active;

    candidate.x += dx;
    candidate.y += dy;
    if (!piece_fits(game, &candidate))
        return 0;
    game->active = candidate;
    return 1;
}

static int rotate_piece(struct game *game)
{
    static const int kicks[] = {0, -1, 1, -2, 2};
    struct piece candidate = game->active;
    size_t index;

    candidate.rotation = (candidate.rotation + 1) & 3;
    for (index = 0; index < sizeof(kicks) / sizeof(kicks[0]); ++index) {
        candidate.x = game->active.x + kicks[index];
        if (piece_fits(game, &candidate)) {
            game->active = candidate;
            return 1;
        }
    }
    return 0;
}

static uint8_t visible_cell(const struct game *game, int row, int column)
{
    int index;

    if (!game->game_over) {
        for (index = 0; index < 4; ++index) {
            int x = game->active.x + shapes[game->active.type][game->active.rotation][index].x;
            int y = game->active.y + shapes[game->active.type][game->active.rotation][index].y;

            if (x == column && y == row)
                return (uint8_t)(game->active.type + 1);
        }
    }
    return game->board[row][column];
}

static int draw_board_row(struct display *display, const struct game *game,
                          int row, int first_column, int last_column)
{
    uint16_t pixels[BOARD_COLS * CELL_SIZE];
    unsigned int width = (unsigned int)(last_column - first_column + 1) * CELL_SIZE;
    unsigned int py;

    for (py = 0; py < CELL_SIZE; ++py) {
        unsigned int px;

        for (px = 0; px < width; ++px) {
            int column = first_column + (int)(px / CELL_SIZE);
            unsigned int local_x = px % CELL_SIZE;
            uint8_t cell = visible_cell(game, row, column);

            render_cell_pixel(&pixels[px], cell, local_x, py);
        }
        if (write_rect(display, BOARD_X + (unsigned int)first_column * CELL_SIZE,
                       BOARD_Y + (unsigned int)row * CELL_SIZE + py,
                       width, 1, pixels, width))
            return -1;
    }
    return 0;
}

static int refresh_board(struct display *display, struct game *game, int force)
{
    int row;

    for (row = 0; row < BOARD_ROWS; ++row) {
        int first = BOARD_COLS;
        int last = -1;
        int column;

        for (column = 0; column < BOARD_COLS; ++column) {
            uint8_t desired = visible_cell(game, row, column);

            if (force || desired != game->rendered[row][column]) {
                game->rendered[row][column] = desired;
                if (column < first)
                    first = column;
                if (column > last)
                    last = column;
            }
        }
        if (last >= first && draw_board_row(display, game, row, first, last))
            return -1;
    }
    return 0;
}

static int draw_statistics(struct display *display, const struct game *game)
{
    char text[32];

    snprintf(text, sizeof(text), "SCORE %06u", game->score);
    if (draw_text(display, 24, 78, text, 2, COLOR_TEXT, COLOR_SCREEN_BG))
        return -1;
    snprintf(text, sizeof(text), "LINES %04u", game->lines);
    if (draw_text(display, 276, 78, text, 2, COLOR_TEXT, COLOR_SCREEN_BG))
        return -1;
    snprintf(text, sizeof(text), "LEVEL %02u", game->level);
    return draw_text(display, 174, 108, text, 2, COLOR_ACCENT, COLOR_SCREEN_BG);
}

static int draw_status(struct display *display, const struct game *game)
{
    const char *text = game->game_over ? "GAME OVER - ENTER RESTART" :
                       game->paused ? "PAUSED - SPACE RESUME" :
                       "UP ROTATE  DOWN DROP";
    uint16_t color = game->game_over ? COLOR_WARNING : COLOR_ACCENT;
    unsigned int scale = 1;
    unsigned int width = (unsigned int)(strlen(text) * 6U - 1U) * scale;
    unsigned int x = (display->var.xres - width) / 2U;

    if (fill_rect(display, 0, 132, display->var.xres, 8, COLOR_SCREEN_BG))
        return -1;
    return draw_text(display, x, 132, text, scale, color, COLOR_SCREEN_BG);
}

static int draw_static_screen(struct display *display)
{
    const char *title = "TETRIS";
    unsigned int title_width = (unsigned int)(strlen(title) * 6U - 1U) * 4U;

    if (clear_screen(display))
        return -1;
    if (draw_text(display, (display->var.xres - title_width) / 2U, 20,
                  title, 4, COLOR_ACCENT, COLOR_SCREEN_BG))
        return -1;
    if (fill_rect(display, BOARD_X - 4, BOARD_Y - 4,
                  BOARD_COLS * CELL_SIZE + 8, 4, COLOR_FRAME) ||
        fill_rect(display, BOARD_X - 4, BOARD_Y + BOARD_ROWS * CELL_SIZE,
                  BOARD_COLS * CELL_SIZE + 8, 4, COLOR_FRAME) ||
        fill_rect(display, BOARD_X - 4, BOARD_Y, 4,
                  BOARD_ROWS * CELL_SIZE, COLOR_FRAME) ||
        fill_rect(display, BOARD_X + BOARD_COLS * CELL_SIZE, BOARD_Y, 4,
                  BOARD_ROWS * CELL_SIZE, COLOR_FRAME))
        return -1;
    if (draw_text(display, 67, 730, "LEFT RIGHT MOVE", 1,
                  COLOR_TEXT, COLOR_SCREEN_BG) ||
        draw_text(display, 276, 730, "ESC QUIT", 1,
                  COLOR_TEXT, COLOR_SCREEN_BG) ||
        draw_text(display, 139, 750, "SPACE PAUSE", 1,
                  COLOR_TEXT, COLOR_SCREEN_BG))
        return -1;
    return 0;
}

static void reset_game(struct game *game, uint32_t seed)
{
    memset(game, 0, sizeof(*game));
    memset(game->rendered, 0xff, sizeof(game->rendered));
    game->random_state = seed ? seed : 0x2468ace1U;
    game->level = 1;
    game->bag_pos = 7;
    spawn_piece(game);
}

static unsigned int drop_interval(const struct game *game)
{
    unsigned int reduction = (game->level - 1U) * 35U;

    return reduction >= 500U ? 100U : 600U - reduction;
}

static int handle_key(struct game *game, unsigned int code, int value)
{
    if (value == 0)
        return 0;
    if (code == KEY_ESC) {
        stop_requested = 1;
        return 0;
    }
    if (code == KEY_ENTER && game->game_over) {
        uint32_t seed = game->random_state ^ (uint32_t)monotonic_ms();
        reset_game(game, seed);
        return UPDATE_BOARD | UPDATE_STATUS | UPDATE_STATS;
    }
    if (code == KEY_SPACE) {
        game->paused = !game->paused;
        return UPDATE_STATUS;
    }
    if (game->paused || game->game_over)
        return 0;

    switch (code) {
    case KEY_LEFT:
        return move_piece(game, -1, 0) ? UPDATE_BOARD : 0;
    case KEY_RIGHT:
        return move_piece(game, 1, 0) ? UPDATE_BOARD : 0;
    case KEY_UP:
        return value == 1 && rotate_piece(game) ? UPDATE_BOARD : 0;
    case KEY_DOWN:
        if (move_piece(game, 0, 1))
            return UPDATE_BOARD;
        else {
            unsigned int old_score = game->score;
            unsigned int old_lines = game->lines;
            unsigned int old_level = game->level;
            int update = UPDATE_BOARD;

            lock_piece(game);
            if (game->score != old_score || game->lines != old_lines ||
                game->level != old_level)
                update |= UPDATE_STATS;
            if (game->game_over)
                update |= UPDATE_STATUS;
            return update;
        }
    default:
        return 0;
    }
}

static int run_self_test(void)
{
    struct game game;
    int column;

    reset_game(&game, 1);
    if (!piece_fits(&game, &game.active))
        return fprintf(stderr, "self-test: spawn collision\n"), 1;
    game.active.x = -4;
    if (piece_fits(&game, &game.active))
        return fprintf(stderr, "self-test: left boundary failure\n"), 1;
    memset(game.board, 0, sizeof(game.board));
    for (column = 0; column < BOARD_COLS; ++column)
        game.board[BOARD_ROWS - 1][column] = 1;
    if (clear_lines(&game) != 1)
        return fprintf(stderr, "self-test: line clear failure\n"), 1;
    for (column = 0; column < BOARD_COLS; ++column)
        if (game.board[BOARD_ROWS - 1][column])
            return fprintf(stderr, "self-test: compact failure\n"), 1;
    puts("lcd_tetris self-test passed");
    return 0;
}

int main(int argc, char **argv)
{
    const char *fb_path = argc > 1 ? argv[1] : "/dev/fb0";
    const char *input_path = argc > 2 ? argv[2] : "/dev/input/event0";
    struct display display;
    struct game game;
    struct input_event events[16];
    struct pollfd poll_fd;
    char input_name[128] = "unknown";
    uint64_t next_drop;
    int input_fd = -1;
    int tty_fd = -1;
    int old_kd_mode = KD_TEXT;
    int keyboard_grabbed = 0;
    int result = 1;

    if (argc > 1 && !strcmp(argv[1], "--self-test"))
        return run_self_test();

    memset(&display, 0, sizeof(display));
    display.fd = open(fb_path, O_RDWR);
    if (display.fd < 0) {
        fprintf(stderr, "open %s: %s\n", fb_path, strerror(errno));
        goto cleanup;
    }
    if (ioctl(display.fd, FBIOGET_VSCREENINFO, &display.var) ||
        ioctl(display.fd, FBIOGET_FSCREENINFO, &display.fix)) {
        perror("FBIOGET_*SCREENINFO");
        goto cleanup;
    }
    if (display.var.bits_per_pixel != 16 || display.var.xres < 480 ||
        display.var.yres < 760 || display.fix.line_length < display.var.xres * 2U) {
        fprintf(stderr, "unsupported framebuffer %ux%u-%u, stride=%u\n",
                display.var.xres, display.var.yres, display.var.bits_per_pixel,
                display.fix.line_length);
        goto cleanup;
    }

    input_fd = open(input_path, O_RDONLY | O_NONBLOCK);
    if (input_fd < 0) {
        fprintf(stderr, "open %s: %s\n", input_path, strerror(errno));
        goto cleanup;
    }
    ioctl(input_fd, EVIOCGNAME(sizeof(input_name)), input_name);
    if (!ioctl(input_fd, EVIOCGRAB, 1))
        keyboard_grabbed = 1;
    else
        fprintf(stderr, "warning: cannot grab keyboard: %s\n", strerror(errno));

    tty_fd = open("/dev/tty0", O_RDWR | O_CLOEXEC);
    if (tty_fd >= 0) {
        ioctl(tty_fd, KDGETMODE, &old_kd_mode);
        if (ioctl(tty_fd, KDSETMODE, KD_GRAPHICS))
            fprintf(stderr, "warning: KD_GRAPHICS failed: %s\n", strerror(errno));
    }

    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    reset_game(&game, (uint32_t)monotonic_ms());
    if (draw_static_screen(&display) || draw_statistics(&display, &game) ||
        draw_status(&display, &game) || refresh_board(&display, &game, 1)) {
        fprintf(stderr, "initial LCD drawing failed: %s\n", strerror(errno));
        goto cleanup;
    }

    printf("LCD Tetris started: fb=%s input=%s (%s)\n",
           fb_path, input_path, input_name);
    printf("Controls: LEFT/RIGHT move, UP rotate, DOWN drop, SPACE pause, ESC quit\n");
    fflush(stdout);

    poll_fd.fd = input_fd;
    poll_fd.events = POLLIN;
    next_drop = monotonic_ms() + drop_interval(&game);

    while (!stop_requested) {
        uint64_t now = monotonic_ms();
        int timeout = game.paused || game.game_over ? 100 :
                      next_drop <= now ? 0 :
                      (int)(next_drop - now > 100U ? 100U : next_drop - now);
        int poll_result = poll(&poll_fd, 1, timeout);
        int updates = 0;

        if (poll_result < 0 && errno != EINTR) {
            perror("poll");
            goto cleanup;
        }
        if (poll_result > 0 && (poll_fd.revents & POLLIN)) {
            ssize_t bytes;

            while ((bytes = read(input_fd, events, sizeof(events))) > 0) {
                unsigned int count = (unsigned int)bytes / sizeof(events[0]);
                unsigned int index;

                for (index = 0; index < count; ++index) {
                    int action;

                    if (events[index].type != EV_KEY)
                        continue;
                    action = handle_key(&game, events[index].code,
                                        events[index].value);
                    updates |= action;
                }
            }
            if (bytes < 0 && errno != EAGAIN && errno != EINTR) {
                perror("read input");
                goto cleanup;
            }
        }

        now = monotonic_ms();
        if (!game.paused && !game.game_over && now >= next_drop) {
            if (!move_piece(&game, 0, 1)) {
                unsigned int old_score = game.score;
                unsigned int old_lines = game.lines;
                unsigned int old_level = game.level;

                lock_piece(&game);
                if (game.score != old_score || game.lines != old_lines ||
                    game.level != old_level)
                    updates |= UPDATE_STATS;
                if (game.game_over)
                    updates |= UPDATE_STATUS;
            }
            updates |= UPDATE_BOARD;
            next_drop = now + drop_interval(&game);
        }

        if ((updates & UPDATE_BOARD) && refresh_board(&display, &game, 0)) {
            fprintf(stderr, "LCD board update failed: %s\n", strerror(errno));
            goto cleanup;
        }
        if ((updates & UPDATE_STATS) && draw_statistics(&display, &game)) {
            fprintf(stderr, "LCD statistics update failed: %s\n", strerror(errno));
            goto cleanup;
        }
        if ((updates & UPDATE_STATUS) && draw_status(&display, &game)) {
            fprintf(stderr, "LCD status update failed: %s\n", strerror(errno));
            goto cleanup;
        }
        if (updates & UPDATE_STATUS)
            next_drop = monotonic_ms() + drop_interval(&game);
    }
    result = 0;

cleanup:
    if (keyboard_grabbed)
        ioctl(input_fd, EVIOCGRAB, 0);
    if (tty_fd >= 0) {
        ioctl(tty_fd, KDSETMODE, old_kd_mode);
        close(tty_fd);
    }
    if (input_fd >= 0)
        close(input_fd);
    if (display.fd >= 0)
        close(display.fd);
    return result;
}
