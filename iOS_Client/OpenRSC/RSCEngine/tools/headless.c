/*
 * Headless driver for the embedded rsc-c engine (Linux/macOS).
 *
 * Runs the same rsc_host API the iOS app uses, without a display, so the
 * engine + SDL shim can be tested against a local server and inspected via
 * screenshots. Reads commands from stdin, one per line:
 *
 *   sleep <ms>
 *   tap <x> <y>              (game pixels; quick touch down/up)
 *   press <x> <y> <ms>       (touch held for <ms>: long press = context menu)
 *   drag <x0> <y0> <x1> <y1> <ms>
 *   text <string...>
 *   key <enter|backspace|escape|tab|left|right|up|down|pageup|pagedown|f1>
 *   wheel <dx> <dy>
 *   shot <file.ppm>
 *   resize <w> <h>
 *   quit
 *
 * Usage: headless <cache_dir> <config_dir> <host> <port> <rsa_exp_hex>
 *                 <rsa_mod_hex> [width height]
 */
#include "../include/rsc_host.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int window_w = 780;
static int window_h = 360;

static void sleep_ms(int ms) {
    struct timespec ts = {ms / 1000, (long)(ms % 1000) * 1000000L};
    nanosleep(&ts, NULL);
}

/* rsc-c's ANDROID layout makes the shorter side 360 game pixels; the touch
 * coordinates we push are normalized to the window. */
static void game_to_norm(int gx, int gy, float *nx, float *ny) {
    int fw, fh;
    rsc_host_copy_frame(NULL, 0, &fw, &fh);

    if (fw <= 0 || fh <= 0) {
        fw = window_w;
        fh = window_h;
    }

    *nx = (gx + 0.5f) / (float)fw;
    *ny = (gy + 0.5f) / (float)fh;
}

static int save_ppm(const char *path) {
    int w = 0, h = 0;
    rsc_host_copy_frame(NULL, 0, &w, &h);

    if (w <= 0 || h <= 0) {
        fprintf(stderr, "[headless] no frame yet\n");
        return -1;
    }

    uint32_t *pixels = malloc((size_t)w * h * 4);
    uint64_t counter = rsc_host_copy_frame(pixels, w * h, &w, &h);

    FILE *f = fopen(path, "wb");

    if (f == NULL) {
        free(pixels);
        return -1;
    }

    fprintf(f, "P6\n%d %d\n255\n", w, h);

    for (int i = 0; i < w * h; i++) {
        unsigned char rgb[3] = {(pixels[i] >> 16) & 0xff,
                                (pixels[i] >> 8) & 0xff, pixels[i] & 0xff};
        fwrite(rgb, 3, 1, f);
    }

    fclose(f);
    free(pixels);
    fprintf(stderr, "[headless] saved %s (%dx%d, frame %llu)\n", path, w, h,
            (unsigned long long)counter);
    return 0;
}

static int key_from_name(const char *name) {
    static const struct {
        const char *name;
        int key;
    } keys[] = {{"enter", RSC_KEY_ENTER},       {"backspace", RSC_KEY_BACKSPACE},
                {"escape", RSC_KEY_ESCAPE},     {"tab", RSC_KEY_TAB},
                {"left", RSC_KEY_LEFT},         {"right", RSC_KEY_RIGHT},
                {"up", RSC_KEY_UP},             {"down", RSC_KEY_DOWN},
                {"pageup", RSC_KEY_PAGE_UP},    {"pagedown", RSC_KEY_PAGE_DOWN},
                {"home", RSC_KEY_HOME},         {"f1", RSC_KEY_F1}};

    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        if (strcmp(keys[i].name, name) == 0) {
            return keys[i].key;
        }
    }

    return 0;
}

static int64_t next_finger = 1;

static void touch_at(int phase, int64_t finger, int gx, int gy) {
    float nx, ny;
    game_to_norm(gx, gy, &nx, &ny);
    rsc_host_touch(phase, finger, nx, ny);
}

int main(int argc, char **argv) {
    if (argc < 7) {
        fprintf(stderr,
                "usage: %s cache_dir config_dir host port rsa_exp rsa_mod "
                "[width height]\n",
                argv[0]);
        return 1;
    }

    if (argc >= 9) {
        window_w = atoi(argv[7]);
        window_h = atoi(argv[8]);
    }

    rsc_host_write_world(argv[2], "Local", argv[3], atoi(argv[4]), argv[5],
                         argv[6]);

    rsc_host_config config = {argv[1], argv[2], window_w, window_h, 1};

    if (rsc_host_start(&config) != 0) {
        fprintf(stderr, "[headless] failed to start engine\n");
        return 1;
    }

    char line[1024];

    while (fgets(line, sizeof(line), stdin) != NULL) {
        line[strcspn(line, "\r\n")] = '\0';

        if (line[0] == '\0' || line[0] == '#') {
            continue;
        }

        char cmd[32] = {0};
        sscanf(line, "%31s", cmd);
        const char *rest = line + strlen(cmd);

        while (*rest == ' ') {
            rest++;
        }

        if (strcmp(cmd, "sleep") == 0) {
            sleep_ms(atoi(rest));
        } else if (strcmp(cmd, "tap") == 0) {
            int x, y;
            sscanf(rest, "%d %d", &x, &y);
            int64_t f = next_finger++;
            touch_at(RSC_TOUCH_BEGAN, f, x, y);
            sleep_ms(60);
            touch_at(RSC_TOUCH_ENDED, f, x, y);
        } else if (strcmp(cmd, "press") == 0) {
            int x, y, ms;
            sscanf(rest, "%d %d %d", &x, &y, &ms);
            int64_t f = next_finger++;
            touch_at(RSC_TOUCH_BEGAN, f, x, y);
            sleep_ms(ms);
            touch_at(RSC_TOUCH_ENDED, f, x, y);
        } else if (strcmp(cmd, "drag") == 0) {
            int x0, y0, x1, y1, ms;
            sscanf(rest, "%d %d %d %d %d", &x0, &y0, &x1, &y1, &ms);
            int64_t f = next_finger++;
            touch_at(RSC_TOUCH_BEGAN, f, x0, y0);
            int steps = ms / 16 > 0 ? ms / 16 : 1;

            for (int i = 1; i <= steps; i++) {
                sleep_ms(16);
                touch_at(RSC_TOUCH_MOVED, f, x0 + (x1 - x0) * i / steps,
                         y0 + (y1 - y0) * i / steps);
            }

            touch_at(RSC_TOUCH_ENDED, f, x1, y1);
        } else if (strcmp(cmd, "text") == 0) {
            rsc_host_text(rest);
        } else if (strcmp(cmd, "key") == 0) {
            int key = key_from_name(rest);
            rsc_host_key(key, 1);
            sleep_ms(30);
            rsc_host_key(key, 0);
        } else if (strcmp(cmd, "wheel") == 0) {
            int dx, dy;
            sscanf(rest, "%d %d", &dx, &dy);
            rsc_host_mouse_wheel(dx, dy);
        } else if (strcmp(cmd, "shot") == 0) {
            save_ppm(rest);
        } else if (strcmp(cmd, "resize") == 0) {
            sscanf(rest, "%d %d", &window_w, &window_h);
            rsc_host_resize(window_w, window_h);
        } else if (strcmp(cmd, "quit") == 0) {
            break;
        } else {
            fprintf(stderr, "[headless] unknown command: %s\n", cmd);
        }

        if (!rsc_host_is_running()) {
            fprintf(stderr, "[headless] engine stopped\n");
            break;
        }
    }

    return 0;
}
