/*
 * SDL2-subset shim + rsc_host bridge for the embedded rsc-c engine.
 * See SDL.h and ../include/rsc_host.h.
 */
#include "SDL.h"
#include "../include/rsc_host.h"

#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* rsc-c's main(), renamed with -Dmain=rsc_c_main when compiling mudclient.c */
extern int rsc_c_main(int argc, char **argv);

#define SHIM_PATH_MAX 1024

static pthread_mutex_t shim_lock = PTHREAD_MUTEX_INITIALIZER;

static char shim_cache_dir[SHIM_PATH_MAX];
static char shim_config_dir[SHIM_PATH_MAX];
static int shim_members = 1;

static volatile int shim_running = 0;
static pthread_t shim_thread;

static rsc_host_log_fn shim_log_fn = NULL;

/* ---------------------------------------------------------------- window */

struct SDL_Window {
    int w, h;
};

struct SDL_Cursor {
    int id;
};

static SDL_Window shim_window = {0, 0};
static int shim_window_w = 0;
static int shim_window_h = 0;
static SDL_PixelFormat shim_format = {0, 32, 4};
static SDL_Surface shim_window_surface = {0, &shim_format, 1, 1, 4, NULL, 0};
static uint32_t shim_window_surface_pixel = 0;
static SDL_Surface *shim_present_src = NULL;

static uint32_t *shim_frame = NULL;
static int shim_frame_capacity = 0;
static int shim_frame_w = 0;
static int shim_frame_h = 0;
static uint64_t shim_frame_counter = 0;

/* ---------------------------------------------------------------- events */

#define SHIM_EVENT_QUEUE 512
static SDL_Event shim_events[SHIM_EVENT_QUEUE];
static int shim_event_head = 0;
static int shim_event_count = 0;

static int shim_text_input_active = 0;

#define SHIM_MAX_FINGERS 10
static struct {
    int64_t id;
    int active;
    float x, y;
} shim_fingers[SHIM_MAX_FINGERS];

/* ----------------------------------------------------------------- audio */

#define SHIM_AUDIO_CAPACITY (8000 * 8)
static int16_t shim_audio[SHIM_AUDIO_CAPACITY];
static int shim_audio_read = 0;
static int shim_audio_count = 0;
static int shim_audio_rate = 8000;

/* --------------------------------------------------------------- helpers */

static void shim_logf(int is_error, const char *fmt, ...) {
    char buffer[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);

    if (shim_log_fn != NULL) {
        shim_log_fn(is_error, buffer);
    } else {
        fputs(buffer, stderr);
    }
}

static void shim_push_event(const SDL_Event *event) {
    pthread_mutex_lock(&shim_lock);

    if (shim_event_count < SHIM_EVENT_QUEUE) {
        int tail = (shim_event_head + shim_event_count) % SHIM_EVENT_QUEUE;
        shim_events[tail] = *event;
        shim_event_count++;
    }

    pthread_mutex_unlock(&shim_lock);
}

static uint32_t shim_ticks_ms(void) {
    static struct timespec start = {0, 0};
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);

    if (start.tv_sec == 0 && start.tv_nsec == 0) {
        start = now;
    }

    return (uint32_t)((now.tv_sec - start.tv_sec) * 1000 +
                      (now.tv_nsec - start.tv_nsec) / 1000000);
}

static void shim_copy_path(char *dst, const char *src) {
    if (src == NULL) {
        dst[0] = '\0';
        return;
    }

    snprintf(dst, SHIM_PATH_MAX, "%s", src);
    size_t len = strlen(dst);

    /* strip trailing slashes */
    while (len > 1 && dst[len - 1] == '/') {
        dst[--len] = '\0';
    }
}

/* ============================================================ SDL2 subset */

int SDL_Init(uint32_t flags) {
    (void)flags;
    shim_ticks_ms();
    return 0;
}

const char *SDL_GetError(void) { return strerror(errno); }

SDL_bool SDL_SetHint(const char *name, const char *value) {
    (void)name;
    (void)value;
    return SDL_TRUE;
}

SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h,
                             uint32_t flags) {
    (void)title;
    (void)x;
    (void)y;
    (void)flags;

    pthread_mutex_lock(&shim_lock);
    if (shim_window_w <= 0 || shim_window_h <= 0) {
        shim_window_w = w;
        shim_window_h = h;
    }
    shim_window.w = shim_window_w;
    shim_window.h = shim_window_h;
    pthread_mutex_unlock(&shim_lock);

    return &shim_window;
}

void SDL_SetWindowMinimumSize(SDL_Window *window, int min_w, int min_h) {
    (void)window;
    (void)min_w;
    (void)min_h;
}

void SDL_GetWindowSize(SDL_Window *window, int *w, int *h) {
    (void)window;
    pthread_mutex_lock(&shim_lock);
    if (w != NULL) {
        *w = shim_window_w;
    }
    if (h != NULL) {
        *h = shim_window_h;
    }
    pthread_mutex_unlock(&shim_lock);
}

void SDL_SetWindowSize(SDL_Window *window, int w, int h) {
    /* The host owns the window size (the device screen). rsc-c only calls
     * this when switching to "vanilla" options on desktop; ignore it. */
    (void)window;
    (void)w;
    (void)h;
}

int SDL_SetWindowFullscreen(SDL_Window *window, uint32_t flags) {
    (void)window;
    (void)flags;
    return 0;
}

void SDL_RestoreWindow(SDL_Window *window) { (void)window; }

SDL_Surface *SDL_GetWindowSurface(SDL_Window *window) {
    (void)window;
    /* Presentation copies from the source surface passed to SDL_BlitScaled,
     * so the window surface is a placeholder. */
    shim_window_surface.pixels = &shim_window_surface_pixel;
    return &shim_window_surface;
}

int SDL_UpdateWindowSurface(SDL_Window *window) {
    (void)window;

    SDL_Surface *src = shim_present_src;

    if (src == NULL || src->pixels == NULL || src->w <= 0 || src->h <= 0) {
        return 0;
    }

    int pixel_count = src->w * src->h;

    pthread_mutex_lock(&shim_lock);

    if (shim_frame_capacity < pixel_count) {
        uint32_t *grown = realloc(shim_frame, (size_t)pixel_count * 4);

        if (grown == NULL) {
            pthread_mutex_unlock(&shim_lock);
            return -1;
        }

        shim_frame = grown;
        shim_frame_capacity = pixel_count;
    }

    memcpy(shim_frame, src->pixels, (size_t)pixel_count * 4);
    shim_frame_w = src->w;
    shim_frame_h = src->h;
    shim_frame_counter++;

    pthread_mutex_unlock(&shim_lock);
    return 0;
}

SDL_Surface *SDL_CreateRGBSurface(uint32_t flags, int width, int height,
                                  int depth, uint32_t Rmask, uint32_t Gmask,
                                  uint32_t Bmask, uint32_t Amask) {
    (void)flags;
    (void)depth;
    (void)Rmask;
    (void)Gmask;
    (void)Bmask;
    (void)Amask;

    if (width <= 0 || height <= 0) {
        return NULL;
    }

    SDL_Surface *surface = calloc(1, sizeof(SDL_Surface));

    if (surface == NULL) {
        return NULL;
    }

    surface->format = &shim_format;
    surface->w = width;
    surface->h = height;
    surface->pitch = width * 4;
    surface->pixels = calloc((size_t)width * height, 4);
    surface->owns_pixels = 1;

    if (surface->pixels == NULL) {
        free(surface);
        return NULL;
    }

    return surface;
}

void SDL_FreeSurface(SDL_Surface *surface) {
    if (surface == NULL || surface == &shim_window_surface) {
        return;
    }

    if (surface == shim_present_src) {
        shim_present_src = NULL;
    }

    if (surface->owns_pixels) {
        free(surface->pixels);
    }

    free(surface);
}

int SDL_BlitScaled(SDL_Surface *src, const SDL_Rect *srcrect, SDL_Surface *dst,
                   SDL_Rect *dstrect) {
    (void)srcrect;
    (void)dstrect;

    if (dst == &shim_window_surface) {
        /* Scaling to the screen happens on the GPU in the host. */
        shim_present_src = src;
    }

    return 0;
}

int SDL_BlitSurface(SDL_Surface *src, const SDL_Rect *srcrect,
                    SDL_Surface *dst, SDL_Rect *dstrect) {
    return SDL_BlitScaled(src, srcrect, dst, dstrect);
}

SDL_Cursor *SDL_CreateSystemCursor(SDL_SystemCursor id) {
    SDL_Cursor *cursor = calloc(1, sizeof(SDL_Cursor));

    if (cursor != NULL) {
        cursor->id = (int)id;
    }

    return cursor;
}

void SDL_SetCursor(SDL_Cursor *cursor) { (void)cursor; }

int SDL_PollEvent(SDL_Event *event) {
    int has_event = 0;

    pthread_mutex_lock(&shim_lock);

    if (shim_event_count > 0) {
        if (event != NULL) {
            *event = shim_events[shim_event_head];
        }

        shim_event_head = (shim_event_head + 1) % SHIM_EVENT_QUEUE;
        shim_event_count--;
        has_event = 1;
    }

    if (has_event && event != NULL && event->type == SDL_WINDOWEVENT) {
        /* apply the size the host announced before rsc-c reads it */
        shim_window_w = event->window.data1;
        shim_window_h = event->window.data2;
        shim_window.w = shim_window_w;
        shim_window.h = shim_window_h;
    }

    pthread_mutex_unlock(&shim_lock);

    return has_event;
}

void SDL_StartTextInput(void) {
    pthread_mutex_lock(&shim_lock);
    shim_text_input_active = 1;
    pthread_mutex_unlock(&shim_lock);
}

void SDL_StopTextInput(void) {
    pthread_mutex_lock(&shim_lock);
    shim_text_input_active = 0;
    pthread_mutex_unlock(&shim_lock);
}

SDL_bool SDL_IsTextInputActive(void) {
    pthread_mutex_lock(&shim_lock);
    int active = shim_text_input_active;
    pthread_mutex_unlock(&shim_lock);
    return active ? SDL_TRUE : SDL_FALSE;
}

uint32_t SDL_GetTicks(void) { return shim_ticks_ms(); }

void SDL_Delay(uint32_t ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;

    while (nanosleep(&ts, &ts) == -1 && errno == EINTR) {
    }
}

int SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained) {
    if (desired != NULL && desired->freq > 0) {
        pthread_mutex_lock(&shim_lock);
        shim_audio_rate = desired->freq;
        pthread_mutex_unlock(&shim_lock);
    }

    if (obtained != NULL && desired != NULL) {
        *obtained = *desired;
    }

    return 0;
}

void SDL_PauseAudio(int pause_on) { (void)pause_on; }

int SDL_QueueAudio(SDL_AudioDeviceID dev, const void *data, uint32_t len) {
    (void)dev;

    const int16_t *samples = (const int16_t *)data;
    int count = (int)(len / 2);

    pthread_mutex_lock(&shim_lock);

    for (int i = 0; i < count; i++) {
        if (shim_audio_count >= SHIM_AUDIO_CAPACITY) {
            break;
        }

        int tail = (shim_audio_read + shim_audio_count) % SHIM_AUDIO_CAPACITY;
        shim_audio[tail] = samples[i];
        shim_audio_count++;
    }

    pthread_mutex_unlock(&shim_lock);
    return 0;
}

void SDL_ClearQueuedAudio(SDL_AudioDeviceID dev) {
    (void)dev;
    pthread_mutex_lock(&shim_lock);
    shim_audio_read = 0;
    shim_audio_count = 0;
    pthread_mutex_unlock(&shim_lock);
}

SDL_RWops *SDL_RWFromFile(const char *file, const char *mode) {
    if (file == NULL || mode == NULL) {
        return NULL;
    }

    FILE *fp = NULL;

    if (file[0] == '/') {
        fp = fopen(file, mode);
    } else {
        /* rsc-c's ANDROID path opens cache archives by bare file name */
        char path[SHIM_PATH_MAX * 2];

        if (strchr(mode, 'r') != NULL && shim_cache_dir[0] != '\0') {
            snprintf(path, sizeof(path), "%s/%s", shim_cache_dir, file);
            fp = fopen(path, mode);
        }

        if (fp == NULL && shim_config_dir[0] != '\0') {
            snprintf(path, sizeof(path), "%s/%s", shim_config_dir, file);
            fp = fopen(path, mode);
        }

        if (fp == NULL) {
            fp = fopen(file, mode);
        }
    }

    if (fp == NULL) {
        return NULL;
    }

    SDL_RWops *ops = calloc(1, sizeof(SDL_RWops));

    if (ops == NULL) {
        fclose(fp);
        return NULL;
    }

    ops->fp = fp;
    return ops;
}

size_t SDL_RWread(SDL_RWops *context, void *ptr, size_t size, size_t maxnum) {
    if (context == NULL || context->fp == NULL || size == 0) {
        return 0;
    }

    return fread(ptr, size, maxnum, context->fp);
}

size_t SDL_RWwrite(SDL_RWops *context, const void *ptr, size_t size,
                   size_t num) {
    if (context == NULL || context->fp == NULL || size == 0) {
        return 0;
    }

    return fwrite(ptr, size, num, context->fp);
}

int64_t SDL_RWseek(SDL_RWops *context, int64_t offset, int whence) {
    if (context == NULL || context->fp == NULL) {
        return -1;
    }

    int origin = whence == RW_SEEK_END   ? SEEK_END
                 : whence == RW_SEEK_CUR ? SEEK_CUR
                                         : SEEK_SET;

    if (fseek(context->fp, (long)offset, origin) != 0) {
        return -1;
    }

    return (int64_t)ftell(context->fp);
}

int SDL_RWclose(SDL_RWops *context) {
    if (context == NULL) {
        return -1;
    }

    int result = 0;

    if (context->fp != NULL) {
        result = fclose(context->fp);
    }

    free(context);
    return result;
}

char *SDL_GetPrefPath(const char *org, const char *app) {
    (void)org;
    (void)app;

    char *path = malloc(SHIM_PATH_MAX + 2);

    if (path == NULL) {
        return NULL;
    }

    snprintf(path, SHIM_PATH_MAX + 2, "%s/", shim_config_dir);
    return path;
}

void SDL_free(void *mem) { free(mem); }

void SDL_LogMessageV(int category, SDL_LogPriority priority, const char *fmt,
                     va_list ap) {
    (void)category;

    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), fmt, ap);

    int is_error = priority >= SDL_LOG_PRIORITY_ERROR;

    if (shim_log_fn != NULL) {
        shim_log_fn(is_error, buffer);
    } else {
        fputs(buffer, is_error ? stderr : stdout);
    }
}

/* ============================================================ host bridge */

/* rsc-c's tiny bignum parser reads hex in 8-digit words, so left-pad RSA
 * values to a multiple of 8 digits ("10001" -> "00010001"). */
static void shim_pad_hex(char *dst, size_t dst_size, const char *hex) {
    while (*hex == ' ') {
        hex++;
    }

    if (hex[0] == '0' && (hex[1] == 'x' || hex[1] == 'X')) {
        hex += 2;
    }

    size_t len = strlen(hex);
    size_t padded = (len + 7) / 8 * 8;

    if (padded + 1 > dst_size) {
        snprintf(dst, dst_size, "%s", hex);
        return;
    }

    size_t zeros = padded - len;
    memset(dst, '0', zeros);
    memcpy(dst + zeros, hex, len);
    dst[padded] = '\0';
}

int rsc_host_write_world(const char *config_dir, const char *name,
                         const char *host, int port, const char *rsa_exponent,
                         const char *rsa_modulus) {
    if (config_dir == NULL || name == NULL || host == NULL ||
        rsa_exponent == NULL || rsa_modulus == NULL) {
        return -1;
    }

    mkdir(config_dir, 0700);

    char path[SHIM_PATH_MAX * 2];
    snprintf(path, sizeof(path), "%s/worlds.cfg", config_dir);

    FILE *file = fopen(path, "w");

    if (file == NULL) {
        return -1;
    }

    /* rsc-c reads "%30s %60s %d %500s %500s"; spaces become underscores */
    char safe_name[31];
    snprintf(safe_name, sizeof(safe_name), "%s", name);

    for (char *c = safe_name; *c != '\0'; c++) {
        if (*c == ' ') {
            *c = '_';
        }
    }

    char exponent[512];
    char modulus[512];
    shim_pad_hex(exponent, sizeof(exponent), rsa_exponent);
    shim_pad_hex(modulus, sizeof(modulus), rsa_modulus);

    fprintf(file, "%s %s %d %s %s\n", safe_name, host, port, exponent,
            modulus);
    fclose(file);
    return 0;
}

int rsc_host_set_option(const char *config_dir, const char *key, int value) {
    if (config_dir == NULL || key == NULL || key[0] == '\0') {
        return -1;
    }

    mkdir(config_dir, 0700);

    char path[SHIM_PATH_MAX * 2];
    snprintf(path, sizeof(path), "%s/options.ini", config_dir);

    /* read the existing file, if any */
    char *contents = NULL;
    long length = 0;
    FILE *file = fopen(path, "rb");

    if (file != NULL) {
        fseek(file, 0, SEEK_END);
        length = ftell(file);
        fseek(file, 0, SEEK_SET);

        if (length > 0) {
            contents = malloc((size_t)length + 1);

            if (contents == NULL) {
                fclose(file);
                return -1;
            }

            length = (long)fread(contents, 1, (size_t)length, file);
            contents[length] = '\0';
        }

        fclose(file);
    }

    file = fopen(path, "wb");

    if (file == NULL) {
        free(contents);
        return -1;
    }

    size_t key_len = strlen(key);
    int replaced = 0;
    char *line = contents;

    while (line != NULL && *line != '\0') {
        char *next = strchr(line, '\n');
        size_t line_len = next != NULL ? (size_t)(next - line) : strlen(line);

        const char *p = line;
        while (*p == ' ' || *p == '\t') {
            p++;
        }

        int is_key = strncmp(p, key, key_len) == 0 &&
                     (p[key_len] == ' ' || p[key_len] == '\t' ||
                      p[key_len] == '=');

        if (is_key) {
            if (!replaced) {
                fprintf(file, "%s = %d\n", key, value);
                replaced = 1;
            }
        } else {
            fwrite(line, 1, line_len, file);
            fputc('\n', file);
        }

        line = next != NULL ? next + 1 : NULL;
    }

    if (!replaced) {
        fprintf(file, "%s = %d\n", key, value);
    }

    fclose(file);
    free(contents);
    return 0;
}

static void *shim_engine_thread(void *arg) {
    (void)arg;

    char arg0[] = "rsc-c";
    char arg1_members[] = "members";
    char arg1_free[] = "free";
    char *argv[] = {arg0, shim_members ? arg1_members : arg1_free, NULL};

    shim_logf(0, "[rsc_host] engine thread starting (cache=%s config=%s)\n",
              shim_cache_dir, shim_config_dir);

    rsc_c_main(2, argv);

    shim_logf(0, "[rsc_host] engine thread finished\n");
    shim_running = 0;
    return NULL;
}

int rsc_host_start(const rsc_host_config *config) {
    if (config == NULL || shim_running) {
        return -1;
    }

    shim_copy_path(shim_cache_dir, config->cache_dir);
    shim_copy_path(shim_config_dir, config->config_dir);
    shim_members = config->members;

    if (shim_config_dir[0] != '\0') {
        mkdir(shim_config_dir, 0700);
    }

    pthread_mutex_lock(&shim_lock);
    shim_window_w = config->window_width > 0 ? config->window_width : 512;
    shim_window_h = config->window_height > 0 ? config->window_height : 346;
    pthread_mutex_unlock(&shim_lock);

    shim_running = 1;

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    /* rsc-c keeps large buffers on the stack in a few places */
    pthread_attr_setstacksize(&attr, 16 * 1024 * 1024);

    int result = pthread_create(&shim_thread, &attr, shim_engine_thread, NULL);
    pthread_attr_destroy(&attr);

    if (result != 0) {
        shim_running = 0;
        return -1;
    }

    pthread_detach(shim_thread);

    /* rsc-c applies its touch layout (shorter side = 360 game pixels) when it
     * sees a resize, as SDL does on Android when the window first appears. */
    rsc_host_resize(shim_window_w, shim_window_h);
    return 0;
}

int rsc_host_is_running(void) { return shim_running; }

void rsc_host_resize(int width, int height) {
    if (width <= 0 || height <= 0) {
        return;
    }

    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_RESIZED;
    event.window.data1 = width;
    event.window.data2 = height;
    shim_push_event(&event);
}

void rsc_host_touch(int phase, int64_t finger_id, float x, float y) {
    SDL_Event event;
    memset(&event, 0, sizeof(event));

    float dx = 0, dy = 0;

    pthread_mutex_lock(&shim_lock);

    int slot = -1;

    for (int i = 0; i < SHIM_MAX_FINGERS; i++) {
        if (shim_fingers[i].active && shim_fingers[i].id == finger_id) {
            slot = i;
            break;
        }
    }

    if (slot < 0 && phase == RSC_TOUCH_BEGAN) {
        for (int i = 0; i < SHIM_MAX_FINGERS; i++) {
            if (!shim_fingers[i].active) {
                slot = i;
                shim_fingers[i].active = 1;
                shim_fingers[i].id = finger_id;
                shim_fingers[i].x = x;
                shim_fingers[i].y = y;
                break;
            }
        }
    }

    if (slot >= 0) {
        dx = x - shim_fingers[slot].x;
        dy = y - shim_fingers[slot].y;
        shim_fingers[slot].x = x;
        shim_fingers[slot].y = y;

        if (phase == RSC_TOUCH_ENDED) {
            shim_fingers[slot].active = 0;
        }
    }

    pthread_mutex_unlock(&shim_lock);

    event.type = phase == RSC_TOUCH_BEGAN   ? SDL_FINGERDOWN
                 : phase == RSC_TOUCH_MOVED ? SDL_FINGERMOTION
                                            : SDL_FINGERUP;
    event.tfinger.fingerId = finger_id;
    event.tfinger.x = x;
    event.tfinger.y = y;
    event.tfinger.dx = dx;
    event.tfinger.dy = dy;
    event.tfinger.pressure = phase == RSC_TOUCH_ENDED ? 0.0f : 1.0f;
    event.tfinger.timestamp = shim_ticks_ms();
    shim_push_event(&event);
}

void rsc_host_mouse_wheel(int dx, int dy) {
    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = SDL_MOUSEWHEEL;
    event.wheel.x = dx;
    event.wheel.y = dy;
    shim_push_event(&event);
}

static SDL_Scancode shim_scancode_for_key(int key) {
    switch (key) {
    case RSC_KEY_ENTER:
        return SDL_SCANCODE_RETURN;
    case RSC_KEY_BACKSPACE:
        return SDL_SCANCODE_BACKSPACE;
    case RSC_KEY_ESCAPE:
        return SDL_SCANCODE_ESCAPE;
    case RSC_KEY_TAB:
        return SDL_SCANCODE_TAB;
    case RSC_KEY_LEFT:
        return SDL_SCANCODE_LEFT;
    case RSC_KEY_RIGHT:
        return SDL_SCANCODE_RIGHT;
    case RSC_KEY_UP:
        return SDL_SCANCODE_UP;
    case RSC_KEY_DOWN:
        return SDL_SCANCODE_DOWN;
    case RSC_KEY_PAGE_UP:
        return SDL_SCANCODE_PAGEUP;
    case RSC_KEY_PAGE_DOWN:
        return SDL_SCANCODE_PAGEDOWN;
    case RSC_KEY_HOME:
        return SDL_SCANCODE_HOME;
    case RSC_KEY_F1:
        return SDL_SCANCODE_F1;
    default:
        return SDL_SCANCODE_UNKNOWN;
    }
}

void rsc_host_key(int key, int down) {
    SDL_Scancode scancode = shim_scancode_for_key(key);

    if (scancode == SDL_SCANCODE_UNKNOWN) {
        return;
    }

    SDL_Event event;
    memset(&event, 0, sizeof(event));
    event.type = down ? SDL_KEYDOWN : SDL_KEYUP;
    event.key.state = down ? 1 : 0;
    event.key.keysym.scancode = scancode;
    shim_push_event(&event);
}

void rsc_host_text(const char *utf8) {
    if (utf8 == NULL) {
        return;
    }

    for (const unsigned char *c = (const unsigned char *)utf8; *c != '\0';
         c++) {
        /* rsc-c only accepts single printable ASCII characters */
        if (*c < 0x20 || *c > 0x7e) {
            continue;
        }

        SDL_Event event;
        memset(&event, 0, sizeof(event));
        event.type = SDL_TEXTINPUT;
        event.text.text[0] = (char)*c;
        shim_push_event(&event);
    }
}

int rsc_host_wants_keyboard(void) { return SDL_IsTextInputActive(); }

void rsc_host_keyboard_dismissed(void) { SDL_StopTextInput(); }

uint64_t rsc_host_copy_frame(uint32_t *dst, int capacity, int *width,
                             int *height) {
    pthread_mutex_lock(&shim_lock);

    uint64_t counter = shim_frame_counter;
    int pixel_count = shim_frame_w * shim_frame_h;

    if (width != NULL) {
        *width = shim_frame_w;
    }

    if (height != NULL) {
        *height = shim_frame_h;
    }

    if (dst != NULL && shim_frame != NULL && pixel_count > 0 &&
        capacity >= pixel_count) {
        memcpy(dst, shim_frame, (size_t)pixel_count * 4);
    }

    pthread_mutex_unlock(&shim_lock);
    return counter;
}

int rsc_host_audio_sample_rate(void) {
    pthread_mutex_lock(&shim_lock);
    int rate = shim_audio_rate;
    pthread_mutex_unlock(&shim_lock);
    return rate;
}

int rsc_host_read_audio(int16_t *dst, int max_samples) {
    if (dst == NULL || max_samples <= 0) {
        return 0;
    }

    pthread_mutex_lock(&shim_lock);

    int count = shim_audio_count < max_samples ? shim_audio_count : max_samples;

    for (int i = 0; i < count; i++) {
        dst[i] = shim_audio[shim_audio_read];
        shim_audio_read = (shim_audio_read + 1) % SHIM_AUDIO_CAPACITY;
    }

    shim_audio_count -= count;

    pthread_mutex_unlock(&shim_lock);
    return count;
}

void rsc_host_set_log_handler(rsc_host_log_fn fn) { shim_log_fn = fn; }
