#include "common.h"
#include "packet-handler.h"
#include "chat-message.h"
#include "ui/stats-tab.h"
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
/* Starts the client like clientdump, logs it in to a fake server over a
 * socketpair and sends it a scripted series of server packets in Lumbridge.
 * Each packet is printed as hex ("packet <opcode> <hex>") before the client
 * reads it, followed by a dump of the game state, so
 * RSCClassicTests/GameTests.swift can replay the same bytes.
 *
 *   gamedump <cache_dir> <empty_config_dir> */
static const char *config_dir, *frame_dir;
char *__wrap_SDL_GetPrefPath(const char *org, const char *app) {
  (void)org; (void)app; char *p = malloc(600); snprintf(p, 600, "%s/", config_dir); return p;
}
static mudclient *M; static int peer;

/* ---- packet building ---- */
static uint8_t pk[5000]; static int pn, bitpos;
static void begin(int op){ memset(pk,0,sizeof pk); pk[0]=op; pn=1; bitpos=8; }
static void b8(int v){ pk[pn++]=v; }
static void b16(int v){ b8(v>>8); b8(v); }
static void b32(int v){ b16(v>>16); b16(v); }
static void b64(int64_t v){ b32((int)(v>>32)); b32((int)v); }
static void bstack(int v){ if(v<128) b8(v); else b32(v+0x80000000); }
static void bstr(const char *s){ while(*s) b8(*s++); }
static void bits(int v, int n){ for(int i=n-1;i>=0;i--){ if((v>>i)&1) pk[bitpos>>3] |= 0x80>>(bitpos&7); bitpos++; } pn=(bitpos+7)>>3; }
static void bchat(const char *s){ int n=chat_message_encode((char*)s); b8(n); for(int i=0;i<n;i++) b8(chat_message_encoded[i]); }
static int64_t name(const char *s){ return encode_username((char*)s); }

static void dump(void);
static void send_packet(void){
  printf("packet %d ", pk[0]); for(int i=0;i<pn;i++) printf("%02x", pk[i]); printf("\n");
  uint8_t frame[5010]; int n=0;
  if(pn>=160){ frame[n++]=160+pn/256; frame[n++]=pn&0xff; memcpy(frame+n,pk,pn); n+=pn; }
  else { frame[n++]=pn; if(pn>1){ frame[n++]=pk[pn-1]; memcpy(frame+n,pk,pn-1); n+=pn-1; } else frame[n++]=pk[0]; }
  write(peer, frame, n);
  mudclient_packet_tick(M);
  { uint8_t junk[5000]; while(read(peer, junk, sizeof junk) > 0) {} }
  dump();
}

/* ---- state dump ---- */
static void dchar(const char *tag, int i, GameCharacter *c){
  if(!c){ printf("%s %d null\n", tag, i); return; }
  int w=c->waypoint_current;
  printf("%s %d si %d id %d npc %d at %d %d step %d wc %d wp %d %d anim %d %d name '%s' lvl %d col %d %d %d %d skull %d eq",
    tag, i, c->server_index, c->server_id, c->npc_id, c->current_x, c->current_y, c->moving_step, w, c->waypoints_x[w], c->waypoints_y[w],
    c->current_animation, c->next_animation, c->name, c->level, c->hair_colour, c->top_colour, c->bottom_colour, c->skin_colour, c->skull_visible);
  for(int j=0;j<ANIMATION_COUNT;j++) printf(" %d", c->animations[j]);
  printf(" msg %d '%s' hit %d %d %d %d bubble %d %d proj %d %d %d %d\n", c->message_timeout, c->message, c->damage_taken, c->current_hits,
    c->max_hits, c->combat_timer, c->bubble_timeout, c->bubble_item, c->incoming_projectile_sprite, c->projectile_range,
    c->attacking_player_server_index, c->attacking_npc_server_index);
}
static void dmodel(GameModel *m){
  if(!m){ printf(" nomodel"); return; }
  printf(" key %d base %d %d %d rot %d %d %d", m->key, m->base_x, m->base_y, m->base_z, m->orientation_yaw, m->orientation_pitch, m->orientation_roll);
}
static void dump(void){
  mudclient *m=M;
  printf("region %d %d local %d %d plane %d %d %d %d last %d bounds %d %d %d %d alive %d loading %d models %d adj %u\n",
    m->region_x, m->region_y, m->local_region_x, m->local_region_y, m->plane_width, m->plane_height, m->plane_index, m->plane_multiplier,
    m->last_plane_index, m->local_lower_x, m->local_lower_y, m->local_upper_x, m->local_upper_y, m->world->player_alive,
    m->loading_area, m->scene->model_count, fnv(m->world->object_adjacency, sizeof m->world->object_adjacency));
  printf("players %d known %d local %d\n", m->player_count, m->known_player_count, m->local_player ? m->local_player->server_index : -1);
  for(int i=0;i<m->player_count;i++) dchar("player", i, m->players[i]);
  printf("npcs %d known %d\n", m->npc_count, m->known_npc_count);
  for(int i=0;i<m->npc_count;i++) dchar("npc", i, m->npcs[i]);
  for(int i=0;i<m->object_count;i++){ printf("object %d %d %d %d %d", i, m->objects[i].x, m->objects[i].y, m->objects[i].id, m->objects[i].direction); dmodel(m->objects[i].model); printf("\n"); }
  for(int i=0;i<m->wall_object_count;i++){ printf("wall %d %d %d %d %d", i, m->wall_objects[i].x, m->wall_objects[i].y, m->wall_objects[i].id, m->wall_objects[i].direction); dmodel(m->wall_objects[i].model);
    GameModel *g=m->wall_objects[i].model; if(g) printf(" v %u %u %u ff %d %d", fnv(g->vertex_x,g->vertex_count*2), fnv(g->vertex_y,g->vertex_count*2), fnv(g->vertex_z,g->vertex_count*2), g->face_fill_front[0], g->face_fill_back[0]); printf("\n"); }
  for(int i=0;i<m->ground_item_count;i++) printf("item %d %d %d %d %d\n", i, m->ground_items[i].x, m->ground_items[i].y, m->ground_items[i].id, m->ground_items[i].z);
  printf("inv %d", m->inventory_items_count); for(int i=0;i<m->inventory_items_count;i++) printf(" %d:%d:%d", m->inventory_item_id[i], m->inventory_item_stack_count[i], m->inventory_equipped[i]); printf("\n");
  printf("skills"); for(int i=0;i<PLAYER_SKILL_COUNT;i++) printf(" %d/%d/%d", m->player_skill_current[i], m->player_skill_base[i], m->player_experience[i]);
  printf(" qp %d fatigue %d %d eq", m->player_quest_points, m->stat_fatigue, m->fatigue_sleeping); for(int i=0;i<PLAYER_STAT_EQUIPMENT_COUNT;i++) printf(" %d", m->player_stat_equipment[i]);
  printf(" quests"); for(int i=0;i<quests_length;i++) printf("%d", m->quest_complete[i]); printf("\n");
  printf("friends %d", m->friend_list_count); for(int i=0;i<m->friend_list_count;i++) printf(" %lld:%d", (long long)m->friend_list[i], m->friend_list_online[i]);
  printf(" ignore %d", m->ignore_list_count); for(int i=0;i<m->ignore_list_count;i++) printf(" %lld", (long long)m->ignore_list[i]); printf("\n");
  printf("messages"); for(int i=0;i<MESSAGE_HISTORY_LENGTH;i++) printf(" [%s|%d]", m->message_history[i], m->message_history_timeout[i]); printf("\n");
  printf("dialogs opt %d %d", m->show_option_menu, m->option_menu_count); for(int i=0;i<m->option_menu_count&&i<5;i++) printf(" [%s]", m->option_menu_entry[i]);
  printf(" welcome %d %d %d %d %d server %d %d [%s] appearance %d sleep %d death %d logout %d sysupd %d\n", m->show_dialog_welcome, m->welcome_last_ip,
    m->welcome_days_ago, m->welcome_recovery_set_days, m->welcome_unread_messages, m->show_dialog_server_message, m->server_message_box_top,
    m->server_message, m->show_appearance_change, m->is_sleeping, m->death_screen_timeout, m->logout_timeout, m->system_update);
  printf("bank %d %d max %d", m->show_dialog_bank, m->bank_item_count, m->bank_items_max); for(int i=0;i<m->bank_item_count;i++) printf(" %d:%d", m->bank_items[i], m->bank_items_count[i]);
  printf(" shop %d %d %d", m->show_dialog_shop, m->shop_sell_price_mod, m->shop_buy_price_mod); for(int i=0;i<40;i++) if(m->shop_items[i]!=-1) printf(" %d=%d:%d:%d", i, m->shop_items[i], m->shop_items_count[i], m->shop_items_price[i]); printf("\n");
  printf("trade %d %d duel %d %d offerx %d name '%s' acc %d %d items", m->show_dialog_trade, m->show_dialog_trade_confirm, m->show_dialog_duel, m->show_dialog_duel_confirm,
    m->show_dialog_offer_x, m->transaction_recipient_name, m->transaction_recipient_accepted, m->transaction_accepted);
  for(int i=0;i<m->transaction_recipient_item_count;i++) printf(" %d:%d", m->transaction_recipient_items[i], m->transaction_recipient_items_count[i]);
  printf(" confirm %lld", (long long)m->transaction_recipient_confirm_name); for(int i=0;i<m->transaction_recipient_confirm_item_count;i++) printf(" %d:%d", m->transaction_recipient_confirm_items[i], m->transaction_recipient_confirm_items_count[i]);
  printf(" /"); for(int i=0;i<m->transaction_confirm_item_count;i++) printf(" %d:%d", m->transaction_confirm_items[i], m->transaction_confirm_items_count[i]);
  printf(" duelopt %d %d %d %d\n", m->duel_option_retreat, m->duel_option_magic, m->duel_option_prayer, m->duel_option_weapons);
  printf("misc prayers"); for(int i=0;i<PRAYER_COUNT;i++) printf("%d", m->prayer_on[i]); printf(" bubbles %d", m->magic_bubble_count);
  for(int i=0;i<m->magic_bubble_count;i++) printf(" %d:%d:%d:%d", m->magic_bubbles[i].x, m->magic_bubbles[i].y, m->magic_bubbles[i].type, m->magic_bubbles[i].time);
  printf(" settings %d %d %d %d %d %d %d\n", m->settings_camera_auto, m->settings_mouse_button_one, m->settings_sound_disabled,
    m->settings_block_chat, m->settings_block_private, m->settings_block_trade, m->settings_block_duel);
}


/* The first half of mudclient_draw_game (before draw_ui), copied verbatim so
 * the 3D view can be compared before the in-game UI is ported. */
static void draw_scene(const char *label){
  mudclient *mud=M;
  if (mud->death_screen_timeout != 0) {
    surface_fade_to_black(mud->surface);
    surface_draw_string_centre(mud->surface, "Oh dear! You are dead...", mud->surface->width / 2, (mud->surface->height - 12) / 2, FONT_BOLD_24, RED);
    mudclient_draw_chat_message_tabs(mud);
    goto out;
  }
  if (mud->show_appearance_change) { mudclient_draw_appearance_panel(mud); goto out; }
  if (mud->is_sleeping) { goto out; }
  if (!mud->world->player_alive) { goto out; }
  for (int i = 0; i < TERRAIN_COUNT; i++) {
    scene_remove_model(mud->scene, mud->world->roof_models[mud->last_plane_index][i]);
    if (mud->last_plane_index == 0) {
      scene_remove_model(mud->scene, mud->world->wall_models[1][i]);
      scene_remove_model(mud->scene, mud->world->roof_models[1][i]);
      scene_remove_model(mud->scene, mud->world->wall_models[2][i]);
      scene_remove_model(mud->scene, mud->world->roof_models[2][i]);
    }
    if (mud->options->show_roofs) {
      mud->fog_of_war = 1;
      if (mud->last_plane_index == 0 && !world_is_under_roof(mud->world, mud->local_player->current_x, mud->local_player->current_y)) {
        scene_add_model(mud->scene, mud->world->roof_models[mud->last_plane_index][i]);
        scene_add_model(mud->scene, mud->world->wall_models[1][i]);
        scene_add_model(mud->scene, mud->world->roof_models[1][i]);
        scene_add_model(mud->scene, mud->world->wall_models[2][i]);
        scene_add_model(mud->scene, mud->world->roof_models[2][i]);
        mud->fog_of_war = 0;
      }
    }
  }
  if (!mud->options->lowmem) mudclient_animate_objects(mud);
  mudclient_draw_entity_sprites(mud);
  mud->surface->interlace = 0;
  surface_black_screen(mud->surface);
  mud->surface->interlace = mud->options->interlace;
  if (mud->last_plane_index == 3 && mud->options->flicker) {
    int ambience = 40 + ((float)rand() / (float)RAND_MAX) * 3;
    int diffuse = 40 + ((float)rand() / (float)RAND_MAX) * 7;
    scene_set_light(mud->scene, ambience, diffuse, -50, -10, -50);
  }
  mud->action_bubble_count = 0; mud->received_messages_count = 0; mud->health_bar_count = 0; mud->overworld_text_count = 0;
  if (mud->settings_camera_auto && !mud->fog_of_war) mudclient_auto_rotate_camera(mud);
  if (mud->options->zoom_camera) {
    int clip_far = (int)((2400.0f / ZOOM_OUTDOORS) * (float)mud->camera_zoom);
    mud->scene->clip_far_3d = clip_far; mud->scene->clip_far_2d = clip_far; mud->scene->fog_z_distance = clip_far - 100;
  } else { mud->scene->clip_far_3d = 2400; mud->scene->clip_far_2d = 2400; mud->scene->fog_z_distance = 2300; }
  if (mud->options->interlace) { mud->scene->clip_far_3d -= 200; mud->scene->clip_far_2d -= 200; mud->scene->fog_z_distance -= 200; }
  if (mud->game_height > MUD_VANILLA_HEIGHT) {
    int clip_far = mud->scene->clip_far_3d / (MUD_VANILLA_HEIGHT / (float)mud->game_height);
    mud->scene->clip_far_3d = clip_far; mud->scene->clip_far_2d = clip_far; mud->scene->fog_z_distance = clip_far - 100;
  }
  if (!mud->options->fog_of_war) { mud->scene->clip_far_3d = 20000; mud->scene->clip_far_2d = 20000; mud->scene->fog_z_distance = 20000; }
  int camera_x = mud->camera_auto_rotate_player_x + mud->camera_rotation_x;
  int camera_z = mud->camera_auto_rotate_player_y + mud->camera_rotation_y;
  int offset_y = 0; int is_touch = mudclient_is_touch(mud);
  if (is_touch) offset_y = 100; else if (MUD_IS_COMPACT) offset_y = 75;
  scene_set_camera(mud->scene, camera_x, -world_get_elevation(mud->world, camera_x, camera_z) - offset_y, camera_z, 912, (mud->camera_rotation * 4), 0, (mud->camera_zoom * 2));
  surface_black_screen(mud->surface);
  scene_render(mud->scene);
  mudclient_draw_overhead(mud);
  if (mud->mouse_click_x_step > 0) surface_draw_sprite(mud->surface, mud->mouse_click_x_x - 8, mud->mouse_click_x_y - 8, mud->sprite_media + 14 + ((24 - mud->mouse_click_x_step) / 6));
  else if (mud->mouse_click_x_step < 0) surface_draw_sprite(mud->surface, mud->mouse_click_x_x - 8, mud->mouse_click_x_y - 8, mud->sprite_media + 18 + ((24 + mud->mouse_click_x_step) / 6));
  if (mud->options->display_fps) {
    int offset_x = mud->is_in_wilderness ? 70 : 0; char fps[17] = {0}; sprintf(fps, "Fps: %d", mud->fps);
    surface_draw_string(mud->surface, fps, is_touch ? 9 + offset_x : mud->surface->width - 62 - offset_x, mud->surface->height - 22, FONT_BOLD_12, YELLOW);
  }
  if (mud->system_update != 0) {
    int seconds = mud->system_update / 50; int minutes = seconds / 60; seconds %= 60;
    char formatted_update[41] = {0}; sprintf(formatted_update, "System update in: %d:%02d", minutes, seconds);
    surface_draw_string_centre(mud->surface, formatted_update, 256, mud->game_height - 19, FONT_BOLD_12, YELLOW);
  }
  if (!mud->loading_area) {
    int wilderness_depth = mudclient_get_wilderness_depth(mud);
    mud->is_in_wilderness = wilderness_depth > 0;
    if (mud->is_in_wilderness) {
      int x = is_touch ? 29 : mud->surface->width - 59;
      surface_draw_sprite(mud->surface, x, mud->surface->height - 68, mud->sprite_media + 13);
      surface_draw_string_centre(mud->surface, "Wilderness", x + 12, mud->surface->height - 32, FONT_BOLD_12, YELLOW);
      int wilderness_level = 1 + (wilderness_depth / 6); char formatted_level[19] = {0}; sprintf(formatted_level, "Level: %d", wilderness_level);
      surface_draw_string_centre(mud->surface, formatted_level, x + 12, mud->surface->height - 19, FONT_BOLD_12, YELLOW);
      if (mud->show_wilderness_warning == 0) mud->show_wilderness_warning = 2;
    }
    if (mud->options->wilderness_warning && mud->show_wilderness_warning == 0 && wilderness_depth > -10 && wilderness_depth <= 0) mud->show_wilderness_warning = 1;
  }
out:;
  Surface *S=mud->surface;
  printf("frame %s %u sprites %d models %d cam %d %d %d %d\n", label, fnv(S->pixels,S->width*S->height*4), mud->scene_sprite_count,
    mud->scene->model_count, mud->camera_auto_rotate_player_x, mud->camera_auto_rotate_player_y, mud->camera_rotation, mud->camera_zoom);
  if(frame_dir){char p[600];snprintf(p,sizeof p,"%s/%s.raw",frame_dir,label);FILE*f=fopen(p,"wb");fwrite(S->pixels,4,S->width*S->height,f);fclose(f);}
}
static void ticks(int n){ printf("tick %d\n", n); for(int i=0;i<n;i++) mudclient_handle_inputs(M); }
static void poke(const char *what, int v){
  printf("poke %s %d\n", what, v);
  if(!strcmp(what,"death")) M->death_screen_timeout=v;
  else if(!strcmp(what,"rotation")) M->camera_rotation=v;
  else if(!strcmp(what,"zoom")) M->camera_zoom=v;
  else if(!strcmp(what,"roofs")) M->options->show_roofs=v;
  else if(!strcmp(what,"fog")) M->options->fog_of_war=v;
  else if(!strcmp(what,"appearance")) M->show_appearance_change=v;
}


/* ---- full frames (mudclient_draw_game, with the in-game UI) ---- */
static void mouse(int x, int y, int click){
  printf("mouse %d %d %d\n", x, y, click);
  M->mouse_x=x; M->mouse_y=y; M->mouse_button_click=0; M->mouse_button_down=0; M->last_mouse_button_down=click;
  mudclient_finger_1_x=x; mudclient_finger_1_y=y; mudclient_finger_1_down=0;
  mudclient_handle_inputs(M); /* one game tick: turns the press into a click and sets the scene's pick point */
}
static void ui(const char *label){
  PacketStream *ps=M->packet_stream; ps->packet_start=0; ps->packet_end=3;
  mudclient_draw_game(M);
  Surface *S=M->surface; mudclient *m=M;
  printf("ui %s %u tab %d sub %d %d %d spell %d item %d rc %d menu %d %d %d %d wiki %d social %d pw %d cam %d %d opts %d %d %d %d %d\n", label,
    fnv(S->pixels,S->width*S->height*4), m->show_ui_tab, m->ui_tab_stats_sub_tab, m->ui_tab_magic_sub_tab, m->ui_tab_social_sub_tab,
    m->selected_spell, m->selected_item_inventory_index, m->show_right_click_menu, m->menu_x, m->menu_y, m->menu_width, m->menu_height,
    m->selected_wiki, m->show_dialog_social_input, m->show_change_password_step, m->camera_rotation, m->settings_camera_auto,
    m->settings_mouse_button_one, m->settings_block_chat, m->settings_block_private, m->settings_block_trade, m->settings_block_duel);
  printf("menu %d", m->menu_items_count);
  for(int i=0;i<m->menu_items_count;i++){ struct MenuEntry *e=&m->menu_items[m->menu_indices[i]]; printf(" [%d|%s|%s]", e->type, e->action_text, e->target_text); }
  printf("\nsent "); for(int i=0;i<ps->packet_start;i++) printf("%02x", (uint8_t)ps->packet_data[i]); printf("\n");
  ps->packet_start=0; ps->packet_end=3;
  if(frame_dir){char p[600];snprintf(p,sizeof p,"%s/%s.raw",frame_dir,label);FILE*f=fopen(p,"wb");fwrite(S->pixels,4,S->width*S->height,f);fclose(f);}
}
/* a point on right-click menu entry i (menu.c's hit box) */
static void menu_entry(int i, int click){ mouse(M->menu_x + 10, M->menu_y + 19 + 12 + i * 19 - 4, click); }

/* ---- scripted session ---- */
static void region_players(int x, int y, int sprite, int known, const int (*moves)[2], const int (*adds)[5], int nadds){
  begin(SERVER_REGION_PLAYERS); bits(x,11); bits(y,13); bits(sprite,4); bits(known,8);
  for(int i=0;i<known;i++){ int t=moves[i][0], v=moves[i][1];
    if(t<0){ bits(0,1); } else { bits(1,1); bits(t,1); if(t==0) bits(v,3); else { bits(v,4); } } }
  for(int i=0;i<nadds;i++){ bits(adds[i][0],11); bits(adds[i][1]&31,5); bits(adds[i][2]&31,5); bits(adds[i][3],4); bits(adds[i][4],1); }
  send_packet();
}
static void appearance(int index, const char *who, int lvl, int skull){
  b16(index); b8(5); b16(index*3); b64(name(who)); b8(5); b8(1); b8(2); b8(3); b8(index); b8(0);
  b8(2); b8(8); b8(14); b8(1); b8(lvl); b8(skull);
}
int main(int argc, char **argv){
  const char *cache = argv[1]; config_dir = argv[2]; frame_dir = argc > 3 ? argv[3] : NULL;
  if(chdir(cache)!=0){perror(cache);return 1;}
  srand(1234);
  init_utility_global(); init_surface_global(); init_world_global(); init_stats_tab_global();
  mudclient *mud = malloc(sizeof(mudclient)); M = mud;
  mudclient_new(mud);
  mud->pixel_surface = SDL_CreateRGBSurface(0, W, H, 32, 0xff0000, 0x00ff00, 0x0000ff, 0);
  mud->surface = malloc(sizeof(Surface));
  surface_new(mud->surface, W, H, SPRITE_LIMIT, mud);
  surface_set_bounds(mud->surface, 0, 0, W, H);
  mudclient_load_jagex(mud);
  mudclient_start_game(mud);

  int sv[2]; socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
  fcntl(sv[0], F_SETFL, O_NONBLOCK); fcntl(sv[1], F_SETFL, O_NONBLOCK); peer = sv[1];
  PacketStream *ps = calloc(1, sizeof(PacketStream));
  ps->socket = sv[0]; ps->packet_end = 3; ps->packet_max_length = 5000; ps->max_read_tries = 1000;
  mud->packet_stream = ps;
  mudclient_reset_game(mud);
  dump();

  begin(SERVER_WORLD_INFO); b16(1); b16(2304); b16(1776); b16(0); b16(944); send_packet();
  int adds1[][5] = {{5,2,2,4,0},{6,-1,3,2,1}};
  region_players(120, 648, 2, 0, NULL, adds1, 2);

  begin(SERVER_REGION_PLAYER_UPDATE); b16(6);
  appearance(1, "Zezima", 126, 0); appearance(5, "Bob", 3, 1); appearance(6, "alice b", 50, 0);
  b16(5); b8(1); bchat("hello there lumbridge");
  b16(1); b8(2); b8(3); b8(7); b8(10);
  b16(6); b8(0); b16(546);
  send_packet();
  begin(SERVER_REGION_PLAYER_UPDATE); b16(3);
  b16(1); b8(6); bchat("selling lobbies");
  b16(5); b8(3); b16(3); b16(7);
  b16(6); b8(4); b16(2); b16(5);
  send_packet();

  begin(SERVER_REGION_OBJECTS);
  b16(0); b8(2); b8(3); b16(1); b8(-4); b8(1); b16(5); b8(3); b8(-2); b16(20); b8(-2); b8(-3); b16(74); b8(6); b8(6); b16(97); b8(0); b8(-5);
  send_packet();
  begin(SERVER_REGION_WALL_OBJECTS);
  b16(1); b8(1); b8(-2); b8(0); b16(2); b8(-3); b8(1); b8(1); b16(5); b8(4); b8(4); b8(2); b16(11); b8(-1); b8(-1); b8(3);
  send_packet();
  begin(SERVER_REGION_GROUND_ITEMS);
  b16(10); b8(0); b8(1); b16(20); b8(1); b8(1); b16(10); b8(1); b8(1); b16(546); b8(2); b8(3); b16(1); b8(-1); b8(2);
  send_packet();
  begin(SERVER_REGION_GROUND_ITEMS); b16(20|32768); b8(1); b8(1); b8(255); b8(-1); b8(2); send_packet();

  begin(SERVER_REGION_NPCS); bits(0,8);
  int npcs[][5] = {{100,3,-2,4,11},{101,-4,-1,2,0},{102,5,5,6,3}};
  for(int i=0;i<3;i++){ bits(npcs[i][0],12); bits(npcs[i][1]&31,5); bits(npcs[i][2]&31,5); bits(npcs[i][3],4); bits(npcs[i][4],10); }
  send_packet();
  begin(SERVER_REGION_NPC_UPDATE); b16(2); b16(100); b8(1); b16(1); bchat("welcome to lumbridge"); b16(102); b8(2); b8(4); b8(1); b8(5); send_packet();
  begin(SERVER_REGION_NPCS); bits(3,8); bits(1,1); bits(0,1); bits(3,3); bits(1,1); bits(1,1); bits(6,4); bits(0,1);
  bits(103,12); bits(1,5); bits(30,5); bits(0,4); bits(7,10); send_packet();

  int moves2[][2] = {{0,2},{1,5}};
  region_players(121, 648, 3, 2, moves2, NULL, 0);
  int moves3[][2] = {{-1,0},{0,6}};
  int adds3[][5] = {{9,4,-4,0,0}};
  region_players(121, 649, 4, 2, moves3, adds3, 1);
  ticks(1); draw_scene("lumbridge_1");
  ticks(12); draw_scene("lumbridge_13");
  poke("rotation", 64); poke("zoom", 550); ticks(1); draw_scene("rotated");
  poke("roofs", 0); poke("fog", 0); ticks(40); draw_scene("no_roofs");
  poke("rotation", 200); poke("zoom", 1200); poke("roofs", 1); poke("fog", 1); ticks(3); draw_scene("far");

  begin(SERVER_INVENTORY_ITEMS); b8(4); b16(10); bstack(1500); b16(1|32768); b16(546); b16(20); bstack(3); send_packet();
  begin(SERVER_INVENTORY_ITEM_UPDATE); b8(4); b16(87|32768); b8(1); send_packet();
  begin(SERVER_INVENTORY_ITEM_REMOVE); b8(2); send_packet();
  begin(SERVER_PLAYER_STAT_LIST);
  for(int i=0;i<18;i++) b8(i+1); for(int i=0;i<18;i++) b8(i+3); for(int i=0;i<18;i++) b32(i*1000+7); b8(12); send_packet();
  begin(SERVER_PLAYER_STAT_EQUIPMENT_BONUS); b8(5); b8(6); b8(7); b8(8); b8(9); send_packet();
  begin(SERVER_PLAYER_STAT_EXPERIENCE_UPDATE); b8(2); b32(99999); send_packet();
  begin(SERVER_PLAYER_STAT_UPDATE); b8(4); b8(40); b8(41); b32(123456); send_packet();
  begin(SERVER_PLAYER_STAT_FATIGUE); b16(750); send_packet();
  begin(SERVER_PLAYER_QUEST_LIST); for(int i=0;i<50;i++) b8(i%3==0); send_packet();
  begin(SERVER_FRIEND_LIST); b8(3); b64(name("friend one")); b8(0); b64(name("friend two")); b8(255); b64(name("friend3")); b8(4); send_packet();
  begin(SERVER_FRIEND_STATUS_CHANGE); b64(name("friend one")); b8(255); send_packet();
  begin(SERVER_FRIEND_STATUS_CHANGE); b64(name("newpal")); b8(0); send_packet();
  begin(SERVER_FRIEND_MESSAGE); b64(name("friend two")); b32(77); { int n=chat_message_encode("are you there?"); for(int i=0;i<n;i++) b8(chat_message_encoded[i]); } send_packet();
  begin(SERVER_IGNORE_LIST); b8(2); b64(name("spammer")); b64(name("Bob")); send_packet();

  /* in-game UI: tabs, menus and clicks (touch layout: tab buttons on the
   * right; 196 wide tabs span x 269..465, y 116..314) */
  { int tx = 480, ty = 117 + 16;
  mouse(200, 200, 0); ui("game_ui");
  mouse(tx, ty, 1); ui("inv_open");
  mouse(240, 130, 0); ui("inv_hover");
  mouse(240, 130, 2); ui("inv_menu");
  menu_entry(2, 0); ui("inv_menu_hover");
  menu_entry(2, 1); ui("inv_examine");
  mouse(tx, ty, 1); ui("inv_open2");
  mouse(290, 130, 2); ui("inv_menu2");
  menu_entry(0, 1); ui("inv_menu2_click");
  mouse(tx, ty + 33, 1); ui("map");
  mouse(407, 231, 1); ui("map_walk");
  mouse(319, 155, 2); ui("map_compass");
  menu_entry(1, 1); ui("map_look");
  mouse(tx, ty + 66, 1); ui("stats");
  mouse(290, 150, 0); ui("stats_skill");
  mouse(420, 128, 1); ui("stats_quests");
  mouse(300, 200, 0); ui("stats_quest_hover");
  mouse(360, 128, 1); ui("stats_gear");
  mouse(tx, ty + 99, 1); ui("magic");
  mouse(300, 150, 0); ui("magic_hover");
  mouse(300, 150, 1); ui("magic_select");
  mouse(420, 128, 1); ui("prayers");
  mouse(300, 150, 1); ui("prayer_on");
  mouse(tx, ty + 132, 1); ui("social");
  mouse(300, 150, 0); ui("social_hover");
  mouse(420, 128, 1); ui("ignore");
  mouse(320, 128, 1); ui("friends");
  mouse(300, 306, 1); ui("add_friend");
  mouse(10, 10, 1); ui("add_friend_close");
  mouse(tx, ty + 165, 1); ui("options");
  mouse(300, 137, 1); ui("options_camera");
  mouse(300, 235, 1); ui("options_privacy");
  mouse(tx, ty + 165, 1); ui("closed");
  mouse(217, 225, 0); ui("hover_player");
  mouse(217, 225, 2); ui("player_menu");
  menu_entry(1, 0); ui("player_menu_hover");
  menu_entry(1, 1); ui("player_menu_click");
  mouse(310, 195, 2); ui("menu2");
  menu_entry(0, 1); ui("menu2_click");
  mouse(270, 160, 2); ui("menu3");
  menu_entry(0, 1); ui("menu3_click");
  mouse(150, 250, 1); ui("world_click");
  ticks(5); mouse(150, 250, 0); ui("after_walk");
  }
  begin(SERVER_REGION_PLAYER_UPDATE); b16(1); b16(5); b8(1); bchat("you cannot hear me"); send_packet();
  begin(SERVER_MESSAGE); bstr("@gre@Welcome to the game"); send_packet();
  begin(SERVER_OPTION_LIST); b8(3); b8(3); bstr("Yes"); b8(2); bstr("No"); b8(10); bstr("Maybe later"); send_packet();
  mouse(200, 200, 0); ui("option_menu");
  begin(SERVER_OPTION_LIST_CLOSE); send_packet();
  begin(SERVER_WELCOME); b32(0x7f000001); b16(3); b8(200); b16(2); send_packet();
  ui("welcome"); mouse(256, 205, 1); ui("welcome_closed");
  begin(SERVER_SERVER_MESSAGE_ONTOP); bstr("Server restarting soon%Please log out"); send_packet();
  ui("server_message"); mouse(256, 300, 1); ui("server_message_closed");
  begin(SERVER_BANK_OPEN); b8(3); b8(48); b16(10); bstack(100000); b16(546); bstack(5); b16(20); bstack(1); send_packet();
  mouse(200, 200, 0); ui("bank"); mouse(88, 78, 0); ui("bank_hover"); mouse(88, 78, 1); ui("bank_select");
  begin(SERVER_BANK_UPDATE); b8(1); b16(546); bstack(0); send_packet();
  begin(SERVER_BANK_UPDATE); b8(4); b16(87); bstack(300); send_packet();
  ui("bank_updated");
  begin(SERVER_BANK_CLOSE); send_packet();
  begin(SERVER_SHOP_OPEN); b8(2); b8(1); b8(100); b8(60); b16(20); b16(5); b8(-3); b16(87); b16(0); b8(2); send_packet();
  ui("shop"); mouse(82, 89, 1); ui("shop_select"); mouse(400, 253, 0); ui("shop_hover_buy"); mouse(400, 253, 1); ui("shop_buy");
  begin(SERVER_SHOP_CLOSE); send_packet();
  begin(SERVER_TRADE_OPEN); b16(5); send_packet();
  ui("trade");
  begin(SERVER_TRADE_ITEMS); b8(2); b16(10); b32(50); b16(20); b32(1); send_packet();
  begin(SERVER_TRADE_RECIPIENT_ACCEPTED); b8(1); send_packet();
  mouse(263, 83, 0); ui("trade_hover"); mouse(263, 83, 2); ui("trade_menu"); menu_entry(0, 1); ui("trade_offer");
  mouse(55, 83, 0); ui("trade_offer_hover"); mouse(55, 208, 0); ui("trade_their_hover"); mouse(269, 284, 1); ui("trade_accept");
  begin(SERVER_TRADE_ACCEPTED); b8(1); send_packet();
  begin(SERVER_TRADE_CONFIRM_OPEN); b64(name("Bob")); b8(1); b16(10); b32(50); b8(1); b16(20); b32(3); send_packet();
  mouse(200, 200, 0); ui("trade_confirm"); mouse(122, 281, 1); ui("trade_confirm_accept");
  begin(SERVER_TRADE_CLOSE); send_packet();
  begin(SERVER_DUEL_OPEN); b16(6); send_packet();
  ui("duel"); mouse(120, 262, 1); ui("duel_retreat");
  begin(SERVER_DUEL_SETTINGS); b8(1); b8(0); b8(1); b8(1); send_packet();
  ui("duel_settings");
  begin(SERVER_DUEL_CONFIRM_OPEN); b64(name("Bob")); b8(1); b16(10); b32(50); b8(0); send_packet();
  mouse(200, 200, 0); ui("duel_confirm");
  begin(SERVER_DUEL_CLOSE); send_packet();
  begin(SERVER_PRAYER_STATUS); for(int i=0;i<14;i++) b8(i%4==1); send_packet();
  begin(SERVER_MAGIC_BUBBLE); b8(2); b8(3); b8(-1); send_packet();
  begin(SERVER_GAME_SETTINGS); b8(1); b8(0); b8(1); send_packet();
  begin(SERVER_PRIVACY_SETTINGS); b8(0); b8(1); b8(1); b8(0); send_packet();
  begin(SERVER_SYSTEM_UPDATE); b16(120); send_packet();
  begin(SERVER_LOGOUT_DENY); send_packet();
  begin(SERVER_APPEARANCE); send_packet();
  begin(SERVER_PLAYER_DIED); send_packet();
  int moves4[][2] = {{-1,0},{-1,0},{-1,0}};
  region_players(121, 649, 4, 3, moves4, NULL, 0);
  draw_scene("dead");
  poke("death", 0);

  begin(SERVER_REGION_ENTITY_UPDATE); b16(0); b16(0); send_packet();
  /* walk far enough east to load the next region, shifting everything */
  int moves5[][2] = {{-1,0},{-1,0},{-1,0}};
  region_players(200, 649, 2, 3, moves5, NULL, 0);
  poke("appearance", 0); ticks(30); draw_scene("east");
  begin(SERVER_REGION_OBJECTS); b8(255); b8(-24); b8(0); send_packet();
  begin(SERVER_REGION_WALL_OBJECTS); b16(65535); b8(-25); b8(-2); b8(0); b8(255); b8(-30); b8(4); send_packet();
  begin(SERVER_PLAYER_STAT_FATIGUE_ASLEEP); b16(321); send_packet();
  begin(SERVER_SLEEP_OPEN); b8(100); b8(55); b8(100); for(int y=1;y<40;y++){ b8(50+y); b8(204-y); } send_packet();
  ui("sleep");
  begin(SERVER_SLEEP_INCORRECT); send_packet();
  ui("sleep_incorrect");
  begin(SERVER_SLEEP_CLOSE); send_packet();
  begin(SERVER_CLOSE_CONNECTION); send_packet();
  return 0;
}
