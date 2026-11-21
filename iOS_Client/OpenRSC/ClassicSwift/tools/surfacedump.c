#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mudclient.h"
#include "surface.h"
#include "game-data.h"
#include "utility.h"
#include "panel.h"
/* Runs a fixed list of rsc-c surface draw calls on a 512x346 frame and prints
 * an FNV-1a hash of the frame after each step, plus every loaded sprite's
 * metadata. RSCClassicTests/SurfaceTests.swift replays the same steps. */
#define W 512
#define H 346
static uint32_t fnv(const void *v, size_t n){const uint8_t*p=v;uint32_t h=2166136261u;for(size_t i=0;i<n;i++){h^=p[i];h*=16777619u;}return h;}
static int8_t *read_jag(const char *path){
  FILE*f=fopen(path,"rb"); if(!f){perror(path);exit(1);} unsigned char hdr[6]; fread(hdr,6,1,f);
  int size=(hdr[0]<<16)|(hdr[1]<<8)|hdr[2], comp=(hdr[3]<<16)|(hdr[4]<<8)|hdr[5];
  int8_t*raw=malloc(comp); fread(raw,comp,1,f); fclose(f);
  if(size==comp) return raw;
  int8_t*body=malloc(size+4096); bzip_decompress(body,raw,comp,0); return body;
}
static Surface *S;
static const char *frame_dir;
static void step(const char *name){
  printf("step %s %u\n", name, fnv(S->pixels, W*H*4));
  if(frame_dir){char p[512];snprintf(p,sizeof p,"%s/%s.raw",frame_dir,name);FILE*f=fopen(p,"wb");fwrite(S->pixels,4,W*H,f);fclose(f);}
}
static void psprite(int id){
  int area=S->sprite_width[id]*S->sprite_height[id];
  uint32_t hc = S->sprite_colours[id] ? fnv(S->sprite_colours[id], area) : 0;
  uint32_t hp = S->surface_pixels[id] ? fnv(S->surface_pixels[id], area*4) : 0;
  printf("sprite %d %d %d %d %d %d %d %d %u %u\n", id, S->sprite_width[id], S->sprite_height[id],
    S->sprite_width_full[id], S->sprite_height_full[id], S->sprite_translate_x[id], S->sprite_translate_y[id],
    S->sprite_translate[id], hc, hp);
}
int main(int argc, char **argv){
  const char *cache = argv[1]; char path[512];
  frame_dir = argc > 2 ? argv[2] : NULL;
  init_utility_global(); init_surface_global();
  snprintf(path,sizeof path,"%s/config85.jag",cache); int8_t*config=read_jag(path);
  game_data_load_data(config,1,85);
  mudclient *mud = calloc(1,sizeof(mudclient)); mud->options=calloc(1,sizeof(Options));
  mud->options->ran_target_fps=10; mud->sprite_media=2000; mud->sprite_util=2100; mud->sprite_item=2150;
  Surface s = {0}; S=&s; int limit=SPRITE_LIMIT;
  s.limit=limit; s.width=W; s.height=H; s.bounds_max_x=W; s.bounds_max_y=H; s.mud=mud;
  s.pixels=calloc(W*H,4);
  s.surface_pixels=calloc(limit,sizeof(int32_t*)); s.sprite_colours=calloc(limit,sizeof(int8_t*));
  s.sprite_palette=calloc(limit,sizeof(int32_t*)); s.sprite_width=calloc(limit,2); s.sprite_height=calloc(limit,2);
  s.sprite_width_full=calloc(limit,2); s.sprite_height_full=calloc(limit,2); s.sprite_translate=calloc(limit,1);
  s.sprite_translate_x=calloc(limit,2); s.sprite_translate_y=calloc(limit,2);

  snprintf(path,sizeof path,"%s/jagex.jag",cache); int8_t*jagex=read_jag(path);
  size_t len=0; int8_t*logo=load_data("logo.tga",0,jagex,&len);
  surface_parse_sprite_tga(S,SPRITE_LIMIT-1,logo,len,0,0);
  for(int i=0;i<8;i++) create_font(load_data(font_files[i],0,jagex,NULL),i);

  snprintf(path,sizeof path,"%s/media59.jag",cache); int8_t*mj=read_jag(path);
  int8_t*idx=load_data("index.dat",0,mj,NULL); int m=2000;
#define P(id,f,n) surface_parse_sprite(S,id,load_data(f,0,mj,NULL),idx,n)
  P(m+1,"inv2.dat",6); P(m+9,"bubble.dat",1); P(m+10,"runescape.dat",1); P(m+11,"splat.dat",3);
  P(m+14,"icon.dat",8); P(m+22,"hbar.dat",1); P(m+23,"hbar2.dat",1); P(m+24,"compass.dat",1);
  P(m+25,"buttons.dat",2); P(m+27,"labels.dat",6); P(m+33,"inv3.dat",6); P(m+39,"message.dat",1);
  P(m+40,"keyboard.dat",1); P(2100,"scrollbar.dat",2); P(2102,"corners.dat",4); P(2106,"arrows.dat",2);
  P(3160,"projectile.dat",game_data.projectile_sprite);
  int sc=game_data.item_sprite_count;
  for(int i=1;sc>0;i++){char fn[20];sprintf(fn,"objects%d.dat",i);int c=sc>30?30:sc;sc-=30;P(2150+(i-1)*30,fn,c);}
  for(int i=0;i<6;i++) surface_load_sprite(S,m+33+i);
  surface_load_sprite(S,m+39); surface_load_sprite(S,m+9);
  for(int i=11;i<=26;i++) surface_load_sprite(S,m+i);
  for(int i=0;i<game_data.projectile_sprite;i++) surface_load_sprite(S,3160+i);
  for(int i=0;i<game_data.item_sprite_count;i++) surface_load_sprite(S,2150+i);
  for(int i=0;i<limit;i++) if(S->sprite_width[i]||S->sprite_colours[i]||S->surface_pixels[i]) psprite(i);

  surface_black_screen(S); step("black");
  surface_draw_gradient(S,10,10,200,100,0x7272b0,0x0e0e3e); step("gradient");
  surface_draw_box(S,50,40,120,60,0x336699); step("box");
  surface_draw_box_alpha(S,30,30,200,150,0xff8000,100); step("box_alpha");
  surface_draw_circle(S,256,173,60,0x00ff00,128,0); step("circle");
  surface_draw_line_horizontal(S,0,5,512,RED); surface_draw_line_vertical(S,5,0,346,YELLOW);
  surface_draw_border(S,100,100,300,200,WHITE); surface_set_pixel(S,511,345,CYAN); step("lines");
  surface_draw_sprite(S,20,200,m+10); surface_draw_sprite(S,300,20,m+24);
  surface_draw_sprite(S,-10,-5,m+1); surface_draw_sprite(S,480,320,m+25); step("sprites");
  surface_draw_sprite_alpha(S,100,250,m+10,128); surface_draw_sprite_alpha(S,200,40,m+24,64); step("sprite_alpha");
  surface_draw_sprite_scale(S,10,10,80,60,2150,0); surface_draw_sprite_scale(S,400,250,140,140,2155,0);
  surface_draw_entity_sprite(S,450,-10,60,40,2162,0,0,0,0); step("sprite_scale");
  surface_draw_sprite_scale_alpha(S,150,150,100,80,m+24,160); step("sprite_scale_alpha");
  surface_draw_sprite_scale_mask(S,250,200,64,48,2170,0xff0000); step("sprite_scale_mask");
  surface_draw_minimap_sprite(S,256,173,m+24,37,128); surface_draw_minimap_sprite(S,100,100,2153,200,192); step("minimap");
  surface_draw_sprite_transform_mask(S,20,20,48,32,2157,0x00ff00,0,0,0);
  surface_draw_sprite_transform_mask(S,80,20,48,32,2157,0xff0000,0xeeaa88,10,1);
  surface_draw_sprite_transform_mask(S,150,60,40,40,m+1,0x8080ff,0x33ff33,-5,1);
  surface_draw_sprite_transform_mask(S,-20,300,64,64,2159,0,0,0,0); step("transform");
  for(int i=0;i<8;i++){ S->draw_string_shadow = i>=4;
    surface_draw_string(S,"Hello @red@World ~300~x @yel@123!",5,20+i*30,i,WHITE); }
  S->draw_string_shadow=0; step("strings");
  surface_draw_string_centre(S,"Welcome to RuneScape",256,330,4,WHITE);
  surface_draw_string_right(S,"Right @gre@aligned",507,340,1,ORANGE); step("string_align");
  const char*para="The quick brown fox jumps over the lazy dog. %Line break here and more words to wrap around";
  surface_draw_paragraph(S,para,256,100,1,WHITE,200); step("paragraph");
  printf("paragraph_height %d %d\n", surface_paragraph_height(S,para,1,200,1000), surface_paragraph_height(S,para,1,200,20));
  printf("text_width"); for(int i=0;i<8;i++) printf(" %d", surface_text_width("Hello @red@World ~300~x",i)); printf("\n");
  surface_set_bounds(S,100,50,400,300); surface_draw_box(S,0,0,512,346,0x123456);
  surface_draw_string(S,"Clipped text that runs off the edge",80,60,7,GREEN);
  surface_draw_sprite(S,350,250,m+10); surface_draw_sprite(S,90,40,m+24); surface_reset_bounds(S); step("bounds");
  surface_draw_blur(S,3,50,50,100,60); step("blur");
  const char*tabs[]={"Friends","Ignore","Other"}; surface_draw_tabs(S,10,250,300,24,tabs,3,1); step("tabs");
  surface_draw_scrollbar(S,400,40,100,200,30,40); step("scrollbar");
  surface_draw_status_bar(S,100,37,"Hits",20,300,150,20,RED,GREEN,0);
  surface_draw_status_bar(S,250,123,"Prayer points",200,300,60,20,RED,GREEN,1); step("status_bar");
  S->interlace=1; surface_draw_box(S,0,101,80,40,0x445566); surface_draw_gradient(S,300,101,80,41,RED,BLUE);
  surface_draw_sprite(S,10,111,m+10); surface_draw_sprite_alpha(S,300,121,m+24,100);
  surface_draw_box_alpha(S,200,201,40,40,WHITE,50); S->interlace=0; step("interlace");
  surface_screen_raster_to_sprite(S,3000,50,50,100,80); surface_draw_sprite(S,300,200,3000); step("raster_to_sprite");
  surface_screen_raster_to_palette_sprite(S,3000); psprite(3000); surface_draw_sprite(S,10,10,3000); step("palette_sprite");
  surface_draw_sprite_reversed(S,3001,0,0,30,40); psprite(3001); surface_draw_sprite(S,480,0,3001); step("reversed");
  surface_draw_sprite(S,0,0,SPRITE_LIMIT-1); step("logo");
  surface_fade_to_black(S); step("fade");
  surface_apply_login_filter(S,200); step("login_filter");

  /* panel.c controls */
  surface_black_screen(S); panel_base_sprite_start = 2100;
  Panel *p = calloc(1, sizeof(Panel)); panel_new(p, S, 50);
  panel_add_button_background(p, 256, 60, 200, 40);
  panel_add_text_centre(p, 256, 52, "Existing User", 4, 0);
  int b = panel_add_button(p, 256, 60, 200, 40);
  panel_add_box_rounded(p, 256, 160, 300, 100);
  panel_add_text(p, 120, 130, "Username:", 4, 1);
  int u = panel_add_text_input(p, 256, 150, 200, 40, 4, 12, 0, 0);
  int pw = panel_add_text_input(p, 256, 180, 200, 40, 4, 20, 1, 1);
  int cb = panel_add_checkbox(p, 420, 140, 14, 14);
  int cb2 = panel_add_checkbox(p, 440, 140, 14, 14);
  panel_add_sprite(p, 60, 300, 2000 + 24);
  int list = panel_add_text_list(p, 20, 220, 200, 100, 1, 40, 1);
  for (int i = 0; i < 20; i++) { char line[40]; sprintf(line, "@yel@Line %d of the chat", i); panel_add_list_entry_wrapped(p, list, strdup(line), 1); }
  int il = panel_add_text_list_interactive(p, 280, 220, 200, 100, 1, 30, 0);
  for (int i = 0; i < 12; i++) { char line[40]; sprintf(line, "Quest number %d", i); panel_add_list_entry(p, il, i, line); }
  panel_update_text(p, u, "Zezima"); panel_update_text(p, pw, "hunter2");
  p->focus_control_index = u;
  panel_toggle_checkbox(p, cb2, 1);
  panel_handle_mouse(p, 300, 245, 1, 1, 0);
  panel_handle_mouse(p, 427, 147, 1, 0, 0);
  panel_handle_mouse(p, 256, 60, 1, 0, 0);
  panel_draw_panel(p); step("panel");
  printf("panel %d %d %d %d %d %d\n", panel_is_clicked(p, b), panel_is_activated(p, cb), panel_is_activated(p, cb2),
    p->control_list_position[list], p->control_list_entry_mouse_over[il], p->control_activated[il]);
  panel_key_press(p, 'x'); panel_key_press(p, 8); panel_key_press(p, 8); panel_key_press(p, '!'); panel_key_press(p, 9);
  printf("panel_keys %s %d\n", panel_get_text(p, u), p->focus_control_index);
  return 0;
}
