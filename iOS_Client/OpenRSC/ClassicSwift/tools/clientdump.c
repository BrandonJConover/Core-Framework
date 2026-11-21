#include "common.h"
#include "ui/login.h"
#include "ui/appearance.h"
#include "ui/additional-options.h"
#include "ui/message-tabs.h"
#include "ui/confirm.h"
#include <unistd.h>
/* Starts the real mudclient the way mudclient_run does (jagex.jag, then
 * mudclient_start_game) without a window, then draws the loading bar, every
 * login screen, the options dialog and the character designer, and clicks
 * through the welcome panel. Prints hashes of each frame and of every loaded
 * sprite. RSCClassicTests/ClientTests.swift does the same.
 *
 *   clientdump <cache_dir> <empty_config_dir> [frame_dir]
 *
 * Linked with -Wl,--wrap=SDL_GetPrefPath so options.ini and worlds.cfg go in
 * the config dir. */
static const char *config_dir, *frame_dir;
char *__wrap_SDL_GetPrefPath(const char *org, const char *app) {
  (void)org; (void)app; char *p = malloc(600); snprintf(p, 600, "%s/", config_dir); return p;
}
static mudclient *M;
#define WX1 150
#define WY1 260
#define WX2 476
#define WY2 313
#define OT 4
static int otabs[][2]={{216,81},{296,81},{376,81},{136,81}};
#define OC 3
static int ochecks[][2]={{173,125},{338,125},{219,105}};
#define OHX 180
#define OHY 274
#define CX 296
#define CY 193
#define OCX 368
#define OCY 274

static void step(const char *name){
  Surface *S = M->surface;
  printf("step %s %u\n", name, fnv(S->pixels, S->width*S->height*4));
  if(frame_dir){char p[600];snprintf(p,sizeof p,"%s/%s.raw",frame_dir,name);FILE*f=fopen(p,"wb");fwrite(S->pixels,4,S->width*S->height,f);fclose(f);}
}
static void psprite(int id){
  Surface *S = M->surface;
  int area=S->sprite_width[id]*S->sprite_height[id];
  uint32_t hc = S->sprite_colours[id] ? fnv(S->sprite_colours[id], area) : 0;
  uint32_t hp = S->surface_pixels[id] ? fnv(S->surface_pixels[id], area*4) : 0;
  printf("sprite %d %d %d %d %d %d %d %d %u %u\n", id, S->sprite_width[id], S->sprite_height[id],
    S->sprite_width_full[id], S->sprite_height_full[id], S->sprite_translate_x[id], S->sprite_translate_y[id],
    S->sprite_translate[id], hc, hp);
}
static void click(int x, int y){
  M->mouse_x=x; M->mouse_y=y; M->last_mouse_button_down=1; M->mouse_button_down=1;
  mudclient_handle_login_screen_input(M);
  M->last_mouse_button_down=0; M->mouse_button_down=0;
  mudclient_handle_login_screen_input(M);
}
int main(int argc, char **argv){
  const char *cache = argv[1]; config_dir = argv[2]; frame_dir = argc > 3 ? argv[3] : NULL;
  if(chdir(cache)!=0){perror(cache);return 1;}
  srand(1234);
  init_utility_global(); init_surface_global(); init_world_global();
  mudclient *mud = malloc(sizeof(mudclient)); M = mud;
  mudclient_new(mud);
  mud->pixel_surface = SDL_CreateRGBSurface(0, W, H, 32, 0xff0000, 0x00ff00, 0x0000ff, 0);
  mud->surface = malloc(sizeof(Surface));
  surface_new(mud->surface, W, H, SPRITE_LIMIT, mud);
  surface_set_bounds(mud->surface, 0, 0, W, H);

  mudclient_load_jagex(mud); step("jagex");
  mudclient_draw_loading_progress(mud, 42, "Loading something - 42%"); step("loading42");
  mudclient_start_game(mud); step("started");

  printf("models %d anims %d", game_data.model_count, game_data.animation_count);
  for(int i=0;i<game_data.animation_count;i++) printf(" %d", game_data.animations[i].file_id);
  printf("\nserver %s %d\n", mud->server, mud->port);
  for(int i=0;i<SPRITE_LIMIT;i++){ Surface *S=mud->surface; if(S->sprite_width[i]||S->sprite_colours[i]||S->surface_pixels[i]) psprite(i); }

  int timers[] = {0, 200, 420, 700, 1100, 1450, 1530};
  char name[64];
  for(int i=0;i<7;i++){ mud->login_timer=timers[i]; mudclient_draw_login_screens(mud); sprintf(name,"welcome_%d",timers[i]); step(name); }
  mud->login_timer=0;

  /* existing user via the panel button */
  click(256, 290); mudclient_draw_login_screens(mud); step("existing");
  panel_update_text(mud->panel_login_existing_user, mud->control_login_username, "Zezima");
  panel_update_text(mud->panel_login_existing_user, mud->control_login_password, "hunter2");
  mudclient_draw_login_screens(mud); step("existing_typed");
  mudclient_show_login_screen_status(mud, "Invalid username or password.", "Try again, or create a new account"); step("existing_status");
  click(410, 280); mudclient_draw_login_screens(mud); step("cancelled");

  click(412, 313); mudclient_draw_login_screens(mud); step("worlds");
  click(WX1, WY1); mudclient_draw_login_screens(mud); step("worlds_pick");
  printf("server %s %d\n", mud->server, mud->port);
  click(WX2, WY2); mudclient_draw_login_screens(mud); step("worlds_back");
  printf("server %s %d\n", mud->server, mud->port);

  click(476, 313); mudclient_draw_login_screens(mud); step("options");
  for(int t=0;t<OT;t++){ click(otabs[t][0], otabs[t][1]); M->mouse_x=0; M->mouse_y=0; mudclient_draw_login_screens(mud); sprintf(name,"options_tab%d",t); step(name); }
  for(int t=0;t<OC;t++){ click(ochecks[t][0], ochecks[t][1]); }
  M->mouse_x=OHX; M->mouse_y=OHY; mudclient_draw_login_screens(mud); step("options_hover");
  printf("options %d %d %d\n", mud->options->idle_logout, mud->options->members, mud->options->zoom_camera);
  click(OHX, OHY); M->mouse_x=0; M->mouse_y=0; mudclient_draw_login_screens(mud); step("confirm");
  click(CX, CY); mudclient_draw_login_screens(mud); step("confirm_ok");
  printf("options %d %d %d\n", mud->options->idle_logout, mud->options->members, mud->options->zoom_camera);
  click(OCX, OCY); mudclient_draw_login_screens(mud); step("options_closed");

  mudclient_draw_appearance_panel(mud); step("appearance");
  mud->mouse_x=0; mud->mouse_y=0;
  int clicks[][2] = {{256-54-40,24+145},{256+54+40,24+145},{256-54-40,24+145+50},{256+54-40,24+145+50},
                     {256-54+40,24+145+100},{256+54+40,24+145+100}};
  for(int i=0;i<6;i++){ M->mouse_x=clicks[i][0]; M->mouse_y=clicks[i][1]; M->last_mouse_button_down=1; M->mouse_button_down=1;
    mudclient_handle_appearance_panel_input(mud); M->last_mouse_button_down=0; M->mouse_button_down=0; mudclient_handle_appearance_panel_input(mud); }
  mudclient_draw_appearance_panel(mud); step("appearance_changed");
  printf("appearance %d %d %d %d %d %d %d\n", mud->appearance_head_type, mud->appearance_head_gender, mud->appearance_body_type,
    mud->appearance_hair_colour, mud->appearance_top_colour, mud->appearance_skin_colour, mud->appearance_bottom_colour);

  /* message tabs */
  surface_black_screen(mud->surface);
  mudclient_show_message(mud, "Welcome to RuneScape!", MESSAGE_TYPE_GAME);
  mudclient_show_message(mud, "@que@You have completed a quest", MESSAGE_TYPE_QUEST);
  mudclient_show_message(mud, "Bob: hello there", MESSAGE_TYPE_CHAT);
  mudclient_show_server_message(mud, "@pri@Alice tells you: hi");
  mudclient_draw_chat_message_tabs(mud); mudclient_draw_chat_message_tabs_panel(mud); step("chat_all");
  mud->message_tab_selected = MESSAGE_TAB_CHAT; surface_black_screen(mud->surface);
  mudclient_draw_chat_message_tabs(mud); mudclient_draw_chat_message_tabs_panel(mud); step("chat_history");
  int n = chat_message_encode("Hello World! this is a TEST of 123 @#%");
  printf("chat %d", n); for(int i=0;i<n;i++) printf(" %d", (uint8_t)chat_message_encoded[i]);
  printf(" %s\n", chat_message_decode(chat_message_encoded, 0, n));
  return 0;
}
