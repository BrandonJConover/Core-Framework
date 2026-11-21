/*
 * Minimal SDL2-compatible shim for embedding rsc-c in a host application
 * (the native iOS app, or the headless Linux test harness).
 *
 * rsc-c's SDL2 + RENDER_SW + ANDROID code path is the "mobile SDL2" target:
 * touch input, a 360px-tall scaled layout, SDL_GetPrefPath config storage and
 * an on-screen keyboard request. This header provides exactly the subset of
 * SDL2 that path uses, so the vendored rsc-c sources compile unmodified. The
 * implementation (rsc_sdl_shim.c) bridges it to the rsc_host.h API: the host
 * pushes input events in and pulls finished frames and audio out.
 */
#ifndef RSC_SDL_SHIM_H
#define RSC_SDL_SHIM_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SDL_MAJOR_VERSION 2
#define SDL_MINOR_VERSION 0
#define SDL_PATCHLEVEL 20
#define SDL_VERSIONNUM(X, Y, Z) ((X) * 1000 + (Y) * 100 + (Z))
#define SDL_COMPILEDVERSION                                                    \
    SDL_VERSIONNUM(SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_PATCHLEVEL)
#define SDL_VERSION_ATLEAST(X, Y, Z)                                           \
    (SDL_COMPILEDVERSION >= SDL_VERSIONNUM(X, Y, Z))

#define SDL_LIL_ENDIAN 1234
#define SDL_BIG_ENDIAN 4321
#define SDL_BYTEORDER SDL_LIL_ENDIAN

typedef int SDL_bool;
#define SDL_FALSE 0
#define SDL_TRUE 1
#define SDL_ENABLE 1

/* init flags */
#define SDL_INIT_TIMER 0x00000001u
#define SDL_INIT_AUDIO 0x00000010u
#define SDL_INIT_VIDEO 0x00000020u
#define SDL_INIT_JOYSTICK 0x00000200u

/* window flags */
#define SDL_WINDOW_FULLSCREEN 0x00000001u
#define SDL_WINDOW_OPENGL 0x00000002u
#define SDL_WINDOW_SHOWN 0x00000004u
#define SDL_WINDOW_RESIZABLE 0x00000020u
#define SDL_WINDOWPOS_CENTERED 0x2FFF0000u

#define SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH "SDL_MOUSE_FOCUS_CLICKTHROUGH"

/* ---- video ---- */
typedef struct SDL_PixelFormat {
    uint32_t format;
    uint8_t BitsPerPixel;
    uint8_t BytesPerPixel;
} SDL_PixelFormat;

typedef struct SDL_Surface {
    uint32_t flags;
    SDL_PixelFormat *format;
    int w, h;
    int pitch;
    void *pixels;
    int owns_pixels;
} SDL_Surface;

typedef struct SDL_Rect {
    int x, y, w, h;
} SDL_Rect;

typedef struct SDL_Window SDL_Window;
typedef struct SDL_Cursor SDL_Cursor;
typedef void *SDL_GLContext;

typedef enum {
    SDL_SYSTEM_CURSOR_ARROW = 0,
    SDL_SYSTEM_CURSOR_HAND = 11
} SDL_SystemCursor;

/* ---- events ---- */
typedef enum {
    SDL_FIRSTEVENT = 0,
    SDL_QUIT = 0x100,
    SDL_WINDOWEVENT = 0x200,
    SDL_KEYDOWN = 0x300,
    SDL_KEYUP,
    SDL_TEXTEDITING,
    SDL_TEXTINPUT,
    SDL_MOUSEMOTION = 0x400,
    SDL_MOUSEBUTTONDOWN,
    SDL_MOUSEBUTTONUP,
    SDL_MOUSEWHEEL,
    SDL_JOYBUTTONDOWN = 0x603,
    SDL_JOYBUTTONUP,
    SDL_FINGERDOWN = 0x700,
    SDL_FINGERUP,
    SDL_FINGERMOTION
} SDL_EventType;

typedef enum {
    SDL_WINDOWEVENT_NONE = 0,
    SDL_WINDOWEVENT_RESIZED = 5,
    SDL_WINDOWEVENT_SIZE_CHANGED = 6
} SDL_WindowEventID;

typedef enum {
    SDL_SCANCODE_UNKNOWN = 0,
    SDL_SCANCODE_RETURN = 40,
    SDL_SCANCODE_ESCAPE = 41,
    SDL_SCANCODE_BACKSPACE = 42,
    SDL_SCANCODE_TAB = 43,
    SDL_SCANCODE_CAPSLOCK = 57,
    SDL_SCANCODE_F1 = 58,
    SDL_SCANCODE_HOME = 74,
    SDL_SCANCODE_PAGEUP = 75,
    SDL_SCANCODE_PAGEDOWN = 78,
    SDL_SCANCODE_RIGHT = 79,
    SDL_SCANCODE_LEFT = 80,
    SDL_SCANCODE_DOWN = 81,
    SDL_SCANCODE_UP = 82,
    SDL_SCANCODE_NUMLOCKCLEAR = 83,
    SDL_SCANCODE_KP_ENTER = 88
} SDL_Scancode;

typedef int32_t SDL_Keycode;

typedef struct SDL_Keysym {
    SDL_Scancode scancode;
    SDL_Keycode sym;
    uint16_t mod;
} SDL_Keysym;

typedef int64_t SDL_TouchID;
typedef int64_t SDL_FingerID;

typedef struct SDL_KeyboardEvent {
    uint32_t type;
    uint32_t timestamp;
    uint8_t state;
    uint8_t repeat;
    SDL_Keysym keysym;
} SDL_KeyboardEvent;

#define SDL_TEXTINPUTEVENT_TEXT_SIZE 32
typedef struct SDL_TextInputEvent {
    uint32_t type;
    uint32_t timestamp;
    char text[SDL_TEXTINPUTEVENT_TEXT_SIZE];
} SDL_TextInputEvent;

typedef struct SDL_MouseMotionEvent {
    uint32_t type;
    uint32_t timestamp;
    int32_t x, y;
    int32_t xrel, yrel;
} SDL_MouseMotionEvent;

typedef struct SDL_MouseButtonEvent {
    uint32_t type;
    uint32_t timestamp;
    uint8_t button;
    uint8_t state;
    uint8_t clicks;
    int32_t x, y;
} SDL_MouseButtonEvent;

typedef struct SDL_MouseWheelEvent {
    uint32_t type;
    uint32_t timestamp;
    int32_t x, y;
} SDL_MouseWheelEvent;

typedef struct SDL_TouchFingerEvent {
    uint32_t type;
    uint32_t timestamp;
    SDL_TouchID touchId;
    SDL_FingerID fingerId;
    float x, y;   /* normalized 0..1 */
    float dx, dy; /* normalized -1..1 */
    float pressure;
} SDL_TouchFingerEvent;

typedef struct SDL_WindowEvent {
    uint32_t type;
    uint32_t timestamp;
    uint8_t event;
    int32_t data1, data2;
} SDL_WindowEvent;

typedef struct SDL_JoyButtonEvent {
    uint32_t type;
    uint32_t timestamp;
    uint8_t button;
    uint8_t state;
} SDL_JoyButtonEvent;

typedef union SDL_Event {
    uint32_t type;
    SDL_KeyboardEvent key;
    SDL_TextInputEvent text;
    SDL_MouseMotionEvent motion;
    SDL_MouseButtonEvent button;
    SDL_MouseWheelEvent wheel;
    SDL_TouchFingerEvent tfinger;
    SDL_WindowEvent window;
    SDL_JoyButtonEvent jbutton;
    uint8_t padding[56];
} SDL_Event;

/* ---- audio ---- */
typedef uint16_t SDL_AudioFormat;
#define AUDIO_S16LSB 0x8010
#define AUDIO_S16 AUDIO_S16LSB
typedef void (*SDL_AudioCallback)(void *userdata, uint8_t *stream, int len);

typedef struct SDL_AudioSpec {
    int freq;
    SDL_AudioFormat format;
    uint8_t channels;
    uint8_t silence;
    uint16_t samples;
    uint16_t padding;
    uint32_t size;
    SDL_AudioCallback callback;
    void *userdata;
} SDL_AudioSpec;

typedef uint32_t SDL_AudioDeviceID;

/* ---- files ---- */
#define RW_SEEK_SET 0
#define RW_SEEK_CUR 1
#define RW_SEEK_END 2

typedef struct SDL_RWops {
    FILE *fp;
} SDL_RWops;

/* ---- logging ---- */
enum { SDL_LOG_CATEGORY_APPLICATION = 0 };
typedef enum {
    SDL_LOG_PRIORITY_VERBOSE = 1,
    SDL_LOG_PRIORITY_DEBUG,
    SDL_LOG_PRIORITY_INFO,
    SDL_LOG_PRIORITY_WARN,
    SDL_LOG_PRIORITY_ERROR,
    SDL_LOG_PRIORITY_CRITICAL
} SDL_LogPriority;

/* ---- API ---- */
int SDL_Init(uint32_t flags);
const char *SDL_GetError(void);
SDL_bool SDL_SetHint(const char *name, const char *value);

SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h,
                             uint32_t flags);
void SDL_SetWindowMinimumSize(SDL_Window *window, int min_w, int min_h);
void SDL_GetWindowSize(SDL_Window *window, int *w, int *h);
void SDL_SetWindowSize(SDL_Window *window, int w, int h);
int SDL_SetWindowFullscreen(SDL_Window *window, uint32_t flags);
void SDL_RestoreWindow(SDL_Window *window);
SDL_Surface *SDL_GetWindowSurface(SDL_Window *window);
int SDL_UpdateWindowSurface(SDL_Window *window);

SDL_Surface *SDL_CreateRGBSurface(uint32_t flags, int width, int height,
                                  int depth, uint32_t Rmask, uint32_t Gmask,
                                  uint32_t Bmask, uint32_t Amask);
void SDL_FreeSurface(SDL_Surface *surface);
int SDL_BlitScaled(SDL_Surface *src, const SDL_Rect *srcrect, SDL_Surface *dst,
                   SDL_Rect *dstrect);
int SDL_BlitSurface(SDL_Surface *src, const SDL_Rect *srcrect,
                    SDL_Surface *dst, SDL_Rect *dstrect);

SDL_Cursor *SDL_CreateSystemCursor(SDL_SystemCursor id);
void SDL_SetCursor(SDL_Cursor *cursor);

int SDL_PollEvent(SDL_Event *event);

void SDL_StartTextInput(void);
void SDL_StopTextInput(void);
SDL_bool SDL_IsTextInputActive(void);

uint32_t SDL_GetTicks(void);
void SDL_Delay(uint32_t ms);

int SDL_OpenAudio(SDL_AudioSpec *desired, SDL_AudioSpec *obtained);
void SDL_PauseAudio(int pause_on);
int SDL_QueueAudio(SDL_AudioDeviceID dev, const void *data, uint32_t len);
void SDL_ClearQueuedAudio(SDL_AudioDeviceID dev);

SDL_RWops *SDL_RWFromFile(const char *file, const char *mode);
size_t SDL_RWread(SDL_RWops *context, void *ptr, size_t size, size_t maxnum);
size_t SDL_RWwrite(SDL_RWops *context, const void *ptr, size_t size,
                   size_t num);
int64_t SDL_RWseek(SDL_RWops *context, int64_t offset, int whence);
int SDL_RWclose(SDL_RWops *context);

char *SDL_GetPrefPath(const char *org, const char *app);
void SDL_free(void *mem);

void SDL_LogMessageV(int category, SDL_LogPriority priority, const char *fmt,
                     va_list ap);

#ifdef __cplusplus
}
#endif

#endif /* RSC_SDL_SHIM_H */
