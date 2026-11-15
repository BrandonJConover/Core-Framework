/*
 * rsc_host.h — host-facing API for the embedded rsc-c engine.
 *
 * The rsc-c client runs on its own thread with its original blocking game
 * loop. The host (Swift on iOS, or the headless Linux harness) feeds it input
 * events and pulls finished frames and audio out. All functions are safe to
 * call from any thread.
 */
#ifndef RSC_HOST_H
#define RSC_HOST_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rsc_host_config {
    /* Directory holding the game cache (*.jag / *.mem files). */
    const char *cache_dir;
    /* Writable directory for options.ini and worlds.cfg. */
    const char *config_dir;
    /* Logical window size in points. rsc-c scales its UI so the shorter
     * side is 360 game pixels. */
    int window_width;
    int window_height;
    /* Non-zero for a members client (sounds, members content). */
    int members;
} rsc_host_config;

/* Writes worlds.cfg with a single world so rsc-c connects to it. RSA values
 * are hex strings (rsc-c's worlds.cfg format). Call before rsc_host_start. */
int rsc_host_write_world(const char *config_dir, const char *name,
                         const char *host, int port, const char *rsa_exponent,
                         const char *rsa_modulus);

/* Starts the engine thread. Returns 0 on success. Only call once per
 * process: rsc-c keeps global state. */
int rsc_host_start(const rsc_host_config *config);

/* Non-zero while the engine thread is alive. */
int rsc_host_is_running(void);

/* Window size changed (points). */
void rsc_host_resize(int width, int height);

/* Touch input. Coordinates are normalized to the window (0..1). Phase:
 * 0 = began, 1 = moved, 2 = ended/cancelled. finger_id must stay stable for
 * the lifetime of a touch. */
enum { RSC_TOUCH_BEGAN = 0, RSC_TOUCH_MOVED = 1, RSC_TOUCH_ENDED = 2 };
void rsc_host_touch(int phase, int64_t finger_id, float x, float y);

/* Scroll wheel / trackpad scroll: dy zooms the camera, dx rotates it.
 * (rsc-c's touch build ignores mouse button/motion events; taps and long
 * presses arrive through rsc_host_touch.) */
void rsc_host_mouse_wheel(int dx, int dy);

/* Special keys. */
enum {
    RSC_KEY_ENTER = 1,
    RSC_KEY_BACKSPACE,
    RSC_KEY_ESCAPE,
    RSC_KEY_TAB,
    RSC_KEY_LEFT,
    RSC_KEY_RIGHT,
    RSC_KEY_UP,
    RSC_KEY_DOWN,
    RSC_KEY_PAGE_UP,
    RSC_KEY_PAGE_DOWN,
    RSC_KEY_HOME,
    RSC_KEY_F1
};
void rsc_host_key(int key, int down);

/* Typed text (UTF-8). Only printable ASCII reaches the game. */
void rsc_host_text(const char *utf8);

/* Non-zero when the game has asked for the on-screen keyboard (a text
 * field is focused). */
int rsc_host_wants_keyboard(void);
/* Host dismissed the keyboard. */
void rsc_host_keyboard_dismissed(void);

/* Copies the latest finished frame into dst (XRGB8888, little-endian, so
 * bytes are B,G,R,X — Metal .bgra8Unorm with alpha ignored). Returns the
 * frame counter (0 if no frame yet) and fills width/height. If dst is NULL
 * or too small (capacity in pixels), only the size and counter are
 * returned. */
uint64_t rsc_host_copy_frame(uint32_t *dst, int capacity, int *width,
                             int *height);

/* Audio: signed 16-bit mono PCM queued by the game. Returns the number of
 * samples copied into dst (at most max_samples). */
int rsc_host_audio_sample_rate(void);
int rsc_host_read_audio(int16_t *dst, int max_samples);

/* Log sink. Called on the engine thread. Default prints to stderr. */
typedef void (*rsc_host_log_fn)(int is_error, const char *message);
void rsc_host_set_log_handler(rsc_host_log_fn fn);

#ifdef __cplusplus
}
#endif

#endif /* RSC_HOST_H */
