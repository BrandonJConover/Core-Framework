#include "common.h"
/* Builds a small 3D scene (client models, a textured terrain grid, a
 * translucent model and 2D item sprites) and renders it from several cameras
 * with rsc-c's software renderer, printing a hash of each frame, the draw
 * order and the mouse picks. RSCClassicTests/SceneTests.swift does the same. */
static Surface *S; static Scene *SC; static GameModel *MODELS[128]; static int NMODELS;
static const char *frame_dir;
static int model_index(GameModel *m){ if(m==SC->view) return -1; for(int i=0;i<NMODELS;i++) if(MODELS[i]==m) return i; return -2; }
static void frame(const char *name){
  scene_render(SC);
  uint32_t order=2166136261u;
  for(int i=0;i<SC->visible_polygons_count;i++){ int v[2]={model_index(SC->visible_polygons[i]->model),SC->visible_polygons[i]->face};
    const uint8_t*p=(const uint8_t*)v; for(int j=0;j<8;j++){order^=p[j];order*=16777619u;} }
  printf("frame %s %u polys %d order %u picks %d", name, fnv(S->pixels,W*H*4), SC->visible_polygons_count, order, SC->mouse_picked_count);
  for(int i=0;i<SC->mouse_picked_count;i++) printf(" %d:%d", model_index(SC->mouse_picked_models[i]), SC->mouse_picked_faces[i]);
  printf("\n");
  if(frame_dir){char p[600];snprintf(p,sizeof p,"%s/%s.raw",frame_dir,name);FILE*f=fopen(p,"wb");fwrite(S->pixels,4,W*H,f);fclose(f);}
}
int main(int argc, char **argv){
  const char *cache = argv[1]; char path[512];
  frame_dir = argc > 2 ? argv[2] : NULL;
  init_utility_global(); init_surface_global();
  snprintf(path,sizeof path,"%s/config85.jag",cache); game_data_load_data(read_jag(path),1,85);
  mudclient *mud; Surface s = {0}; S=&s; Scene *scene=setup_scene(cache,S,&mud); SC=scene;
  for(int i=0;i<scene->texture_count;i++) printf("texture %d dim %d alpha %d px %u fill %d\n", i, scene->texture_dimension[i],
    scene->texture_back_transparent[i], scene->texture_pixels[i]?fnv(scene->texture_pixels[i],(scene->texture_dimension[i]?128*128:64*64)*16):0,
    scene_get_fill_colour(scene,i));
  printf("fill %d %d %d\n", scene_get_fill_colour(scene,-1-0x1234), scene_get_fill_colour(scene,COLOUR_TRANSPARENT), scene_rgb_to_fill(200,100,50));

  /* client models in an 8x5 grid */
  snprintf(path,sizeof path,"%s/models36.jag",cache); int8_t*mjag=read_jag(path);
  int placed=0;
  for(int i=0;i<game_data.model_count && placed<40;i+=3){
    char fn[64]; sprintf(fn,"%s.ob3",game_data.model_name[i]);
    uint32_t off=get_data_file_offset(fn,mjag), len=get_data_file_length(fn,mjag); if(!off) continue;
    GameModel *src=malloc(sizeof(GameModel)); game_model_new_ob3(src,mjag+off,len);
    GameModel *m=game_model_copy(src);
    if(placed%3==2) game_model_set_light(m,0,40,32,-50,-10,-50); else game_model_set_light(m,1,48,48,-50,-10,-50);
    game_model_orient(m,(placed*29)&255,0,0);
    game_model_place(m,3200+(placed%8)*160,0,3200+(placed/8)*160);
    if(placed==7) m->transparent=1;
    m->depth=(placed%5)*3;
    scene_add_model(scene,m); MODELS[NMODELS++]=m; placed++;
  }
  /* textured terrain grid */
  GameModel *grid=malloc(sizeof(GameModel)); game_model_new_alloc_flags(grid,17*17,16*16+8,1,0,0,0,0);
  for(int x=0;x<17;x++) for(int z=0;z<17;z++) game_model_create_vertex(grid,3000+x*128,((x*7+z*13)%60)-30,3000+z*128);
  for(int x=0;x<16;x++) for(int z=0;z<16;z++){
    int fill = ((x+z)%3==0) ? ((x*5+z)%scene->texture_count) : (-1-((x*3+z*7)&0x7fff));
    if((x*z)%11==5){ uint16_t *v=malloc(6); v[0]=x*17+z; v[1]=(x+1)*17+z; v[2]=(x+1)*17+z+1;
      game_model_create_face(grid,3,v,fill,COLOUR_TRANSPARENT); continue; }
    uint16_t *v=malloc(8); v[0]=x*17+z; v[1]=(x+1)*17+z; v[2]=(x+1)*17+z+1; v[3]=x*17+z+1;
    int f=game_model_create_face(grid,4,v,fill,(x&1)?fill:COLOUR_TRANSPARENT); grid->face_tag[f]=x*100+z; }
  for(int i=0;i<6;i++){ uint16_t *v=malloc(10); v[0]=i*17; v[1]=i*17+1; v[2]=i*17+2; v[3]=(i+1)*17+2; v[4]=(i+1)*17;
    game_model_create_face(grid,5,v,-1-(i*1000),-1-(i*1000)); }
  for(int i=0;i<grid->vertex_count;i++) game_model_set_vertex_ambience(grid,i,(i*29)&0x1f);
  game_model_set_light(grid,1,40,48,-50,-10,-50);
  scene_add_model(scene,grid); MODELS[NMODELS++]=grid;

  /* 2D sprites */
  for(int i=0;i<8;i++){
    int id=scene_add_sprite(scene,2150+i*7,3300+i*120,-10,3500+(i%3)*150,90,110,1000+i);
    if(i==3) scene_set_sprite_translate_x(scene,id,20);
  }
  scene_set_local_player(scene,0);

  surface_black_screen(S); scene_set_camera(scene,3800,0,3700,912,0,0,1500); frame("overview");
  surface_black_screen(S); scene_set_mouse_location(scene,256,180); scene_set_camera(scene,3700,-20,3500,900,256,0,1100); frame("rotated_pick");
  surface_black_screen(S); scene_set_mouse_location(scene,300,200); scene_set_camera(scene,3600,-20,3600,880,512,0,700); frame("south_pick");
  surface_black_screen(S); S->interlace=1; scene_set_camera(scene,3800,0,3700,912,640,0,1300); frame("interlace"); S->interlace=0;
  surface_black_screen(S); scene_set_camera(scene,3400,-60,3400,960,128,30,260); frame("closeup_roll");
  surface_black_screen(S); scene_set_mouse_location(scene,200,150); scene_set_camera(scene,3300,-100,3300,800,800,0,120); frame("near_clip");
  for(int i=0;i<scene->texture_count;i++) if(scene->texture_dimension[i]==0 && scene->texture_pixels[i]){ scene_scroll_texture(scene,i); scene_scroll_texture(scene,i); }
  scene_set_light(scene,30,60,-30,-20,-60);
  surface_black_screen(S); scene_set_camera(scene,3800,0,3700,912,0,0,1500); frame("scrolled_relit");
  scene_reduce_sprites(scene,3); scene_remove_model(scene,MODELS[4]); scene_remove_model(scene,MODELS[9]);
  scene_set_light_dir(scene,0,0,0);
  surface_black_screen(S); scene_set_mouse_location(scene,256,170); scene_set_camera(scene,3700,0,3600,912,1000,0,1600); frame("removed");
  scene_clear(scene);
  surface_black_screen(S); scene_set_camera(scene,3800,0,3700,912,0,0,1500); frame("cleared");
  return 0;
}
