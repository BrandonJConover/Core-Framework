/* Shared setup for the golden dumpers: cache reading, a 512x346 surface with
 * the item sprites, and the scene with textures loaded the way
 * mudclient_load_textures does it. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mudclient.h"
#include "scene.h"
#include "game-model.h"
#include "game-data.h"
#include "surface.h"
#include "utility.h"
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
static Scene *setup_scene(const char *cache, Surface *S, mudclient **mud_out){
  char path[512];
  mudclient *mud = calloc(1,sizeof(mudclient)); mud->options=calloc(1,sizeof(Options));
  mud->options->ran_target_fps=10; mud->sprite_media=2000; mud->sprite_util=2100; mud->sprite_item=2150;
  mud->sprite_texture=3210; mud->sprite_texture_world=3220;
  int limit=SPRITE_LIMIT;
  S->limit=limit; S->width=W; S->height=H; S->bounds_max_x=W; S->bounds_max_y=H; S->mud=mud;
  S->pixels=calloc(W*H,4);
  S->surface_pixels=calloc(limit,sizeof(int32_t*)); S->sprite_colours=calloc(limit,sizeof(int8_t*));
  S->sprite_palette=calloc(limit,sizeof(int32_t*)); S->sprite_width=calloc(limit,2); S->sprite_height=calloc(limit,2);
  S->sprite_width_full=calloc(limit,2); S->sprite_height_full=calloc(limit,2); S->sprite_translate=calloc(limit,1);
  S->sprite_translate_x=calloc(limit,2); S->sprite_translate_y=calloc(limit,2);

  snprintf(path,sizeof path,"%s/media59.jag",cache); int8_t*mj=read_jag(path);
  int8_t*idx=load_data("index.dat",0,mj,NULL);
  int sc=game_data.item_sprite_count;
  for(int i=1;sc>0;i++){char fn[20];sprintf(fn,"objects%d.dat",i);int c=sc>30?30:sc;sc-=30;
    surface_parse_sprite(S,2150+(i-1)*30,load_data(fn,0,mj,NULL),idx,c);}
  for(int i=0;i<game_data.item_sprite_count;i++) surface_load_sprite(S,2150+i);

  Scene *scene=calloc(1,sizeof(Scene));
  scene_new(scene,S,7500,7500,1000); scene_set_bounds(scene,W,H-12);
  scene->clip_far_3d=2400; scene->clip_far_2d=2400; scene->fog_z_distance=2300;

  /* mudclient_load_textures */
  snprintf(path,sizeof path,"%s/textures17.jag",cache); int8_t*tj=read_jag(path);
  int8_t*tidx=load_data("index.dat",0,tj,NULL);
  scene_allocate_textures(scene,game_data.texture_count,7,11);
  for(int i=0;i<game_data.texture_count;i++){
    char fn[300]; sprintf(fn,"%s.dat",game_data.textures[i].name);
    int8_t*td=load_data(fn,0,tj,NULL); if(!td) continue;
    surface_parse_sprite(S,mud->sprite_texture,td,tidx,1);
    surface_draw_box(S,0,0,128,128,MAGENTA); surface_draw_sprite(S,0,0,mud->sprite_texture);
    free(S->sprite_palette[mud->sprite_texture]); S->sprite_palette[mud->sprite_texture]=NULL;
    free(S->sprite_colours[mud->sprite_texture]); S->sprite_colours[mud->sprite_texture]=NULL;
    int size=S->sprite_width_full[mud->sprite_texture];
    char *sub=game_data.textures[i].subtype_name;
    if(sub){ int sl=strlen(sub); if(sl>0&&sl<=250){ sprintf(fn,"%s.dat",sub);
      surface_parse_sprite(S,mud->sprite_texture,load_data(fn,0,tj,NULL),tidx,1); surface_draw_sprite(S,0,0,mud->sprite_texture);
      free(S->sprite_palette[mud->sprite_texture]); S->sprite_palette[mud->sprite_texture]=NULL;
      free(S->sprite_colours[mud->sprite_texture]); S->sprite_colours[mud->sprite_texture]=NULL; } }
    surface_screen_raster_to_sprite(S,mud->sprite_texture_world+i,0,0,size,size);
    for(int j=0;j<size*size;j++) if(S->surface_pixels[mud->sprite_texture_world+i][j]==GREEN) S->surface_pixels[mud->sprite_texture_world+i][j]=MAGENTA;
    surface_screen_raster_to_palette_sprite(S,mud->sprite_texture_world+i);
    scene_define_texture(scene,i,S->sprite_colours[mud->sprite_texture_world+i],S->sprite_palette[mud->sprite_texture_world+i],(size/64)-1);
    free(S->surface_pixels[mud->sprite_texture_world+i]); S->surface_pixels[mud->sprite_texture_world+i]=NULL;
  }
  *mud_out=mud;
  return scene;
}
