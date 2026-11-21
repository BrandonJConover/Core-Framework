#include "common.h"
#include "world.h"
/* Loads map sections the way the client does (login screen background and
 * in-game areas), dumping hashes of the terrain, wall and roof models, the
 * walk adjacency, minimap raster and rendered frames, plus some routes.
 * RSCClassicTests/WorldTests.swift does the same. */
static Surface *S; static Scene *SC; static World *WD; static const char *frame_dir;
static uint32_t faces_hash(GameModel *m){ uint32_t h=2166136261u; for(int i=0;i<m->face_count;i++){ for(int j=0;j<m->face_vertex_count[i];j++){ uint16_t v=m->face_vertices[i][j]; h^=v&0xff; h*=16777619u; h^=v>>8; h*=16777619u; } } return h; }
static void mdump(const char *tag, int p, int i, GameModel *m){
  if(!m){ printf("%s %d %d null\n",tag,p,i); return; }
  int v=m->vertex_count, f=m->face_count;
  printf("%s %d %d v%d f%d vx%u vy%u vz%u va%u vi%u fv%u ff%u fb%u fi%u ft%u\n", tag, p, i, v, f,
    fnv(m->vertex_x,v*2), fnv(m->vertex_y,v*2), fnv(m->vertex_z,v*2), fnv(m->vertex_ambience,v), fnv(m->vertex_intensity,v*2),
    faces_hash(m), fnv(m->face_fill_front,f*2), fnv(m->face_fill_back,f*2), fnv(m->face_intensity,f*2),
    m->face_tag?fnv(m->face_tag,f*4):0);
}
static void wdump(const char *name, int plane){
  for(int i=0;i<TERRAIN_COUNT;i++) mdump("terrain",0,i,WD->terrain_models[i]);
  for(int p=0;p<PLANE_COUNT;p++) for(int i=0;i<TERRAIN_COUNT;i++){ if(WD->wall_models[p][i]) mdump("wall",p,i,WD->wall_models[p][i]); }
  for(int p=0;p<PLANE_COUNT;p++) for(int i=0;i<TERRAIN_COUNT;i++){ if(WD->roof_models[p][i]) mdump("roof",p,i,WD->roof_models[p][i]); }
  int32_t *mm=S->surface_pixels[WD->base_media_sprite-1];
  printf("world %s adj %u thl %u lx %u ly %u models %d minimap %u %dx%d\n", name, fnv(WD->object_adjacency,sizeof WD->object_adjacency),
    fnv(WD->terrain_height_local,sizeof WD->terrain_height_local), fnv(WD->local_x,sizeof WD->local_x), fnv(WD->local_y,sizeof WD->local_y),
    SC->model_count, mm?fnv(mm,MINIMAP_SPRITE_WIDTH*MINIMAP_SPRITE_WIDTH*4):0, S->sprite_width[WD->base_media_sprite-1], S->sprite_height[WD->base_media_sprite-1]);
  printf("planes %s td %u tdir %u wd %u wr %u th %u tc %u\n", name, fnv(WD->tile_decoration,sizeof WD->tile_decoration),
    fnv(WD->tile_direction,sizeof WD->tile_direction), fnv(WD->walls_diagonal,sizeof WD->walls_diagonal), fnv(WD->walls_roof,sizeof WD->walls_roof),
    fnv(WD->terrain_height,sizeof WD->terrain_height), fnv(WD->terrain_colour,sizeof WD->terrain_colour));
  printf("elev %s", name); for(int i=0;i<12;i++){ int x=(i*977)%12288, y=(i*1361+400)%12288; printf(" %d",world_get_elevation(WD,x,y)); }
  printf(" roof"); for(int i=0;i<12;i++) printf(" %d", world_is_under_roof(WD,(i*733)%12288,(i*1201)%12288)?1:0);
  printf("\n");
}
static void frame(const char *name, int x, int y, int rot, int zoom){
  surface_black_screen(S);
  scene_set_camera(SC,x,-world_get_elevation(WD,x,y),y,912,rot,0,zoom);
  scene_render(SC);
  printf("frame %s %u polys %d\n", name, fnv(S->pixels,W*H*4), SC->visible_polygons_count);
  if(frame_dir){char p[600];snprintf(p,sizeof p,"%s/%s.raw",frame_dir,name);FILE*f=fopen(p,"wb");fwrite(S->pixels,4,W*H,f);fclose(f);}
}
static void route(int sx, int sy, int x1, int y1, int x2, int y2, int obj){
  static int rx[PATH_STEPS_MAX], ry[PATH_STEPS_MAX];
  int n=world_route(WD,sx,sy,x1,y1,x2,y2,rx,ry,obj);
  printf("route %d,%d->%d,%d..%d,%d %d %d:", sx,sy,x1,y1,x2,y2,obj,n);
  for(int i=0;i<n;i++) printf(" %d,%d",rx[i],ry[i]);
  printf("\n");
}
int main(int argc, char **argv){
  const char *cache = argv[1]; char path[512];
  frame_dir = argc > 2 ? argv[2] : NULL;
  init_utility_global(); init_surface_global(); init_world_global();
  snprintf(path,sizeof path,"%s/config85.jag",cache); game_data_load_data(read_jag(path),1,85);
  for(int i=0;i<ANIMATED_MODELS_LENGTH;i++) game_data_get_model_index(mud_strdup(animated_models[i]));
  mudclient *mud; Surface s = {0}; S=&s; Scene *scene=setup_scene(cache,S,&mud); SC=scene;

  srand(1); int r1=rand(), r2=rand(), r3=rand(); srand(4321); int r4=rand(); printf("rand %d %d %d %d\n", r1, r2, r3, r4);
  printf("terrain_colours %u\n", fnv(terrain_colours,sizeof terrain_colours));

  snprintf(path,sizeof path,"%s/models36.jag",cache); int8_t*mjag=read_jag(path);
  GameModel **models=calloc(game_data.model_count,sizeof(GameModel*));
  for(int i=0;i<game_data.model_count;i++){
    char fn[64]; sprintf(fn,"%s.ob3",game_data.model_name[i]);
    uint32_t off=get_data_file_offset(fn,mjag), len=get_data_file_length(fn,mjag);
    models[i]=malloc(sizeof(GameModel));
    if(off) game_model_new_ob3(models[i],mjag+off,len); else game_model_new_alloc(models[i],1,1);
  }

  World *world=calloc(1,sizeof(World)); WD=world;
  world_new(world,scene,S,63); world->base_media_sprite=2000; world->thick_walls=0;
  snprintf(path,sizeof path,"%s/maps63.jag",cache); world->map_pack=read_jag(path);
  snprintf(path,sizeof path,"%s/maps63.mem",cache); world->member_map_pack=read_jag(path);
  snprintf(path,sizeof path,"%s/land63.jag",cache); world->landscape_pack=read_jag(path);
  snprintf(path,sizeof path,"%s/land63.mem",cache); world->member_landscape_pack=read_jag(path);

  srand(4321);
  /* mudclient_render_login_scene_sprites */
  world_load_section(world,50*48+23,50*48+23,0);
  world_add_models(world,models);
  scene->clip_far_3d=4100; scene->clip_far_2d=4100; scene->fog_z_distance=4000;
  wdump("login",0);
  frame("login1",9728,6400,888,2200);
  frame("login2",9216,9216,888,2200);

  scene->clip_far_3d=2400; scene->clip_far_2d=2400; scene->fog_z_distance=2300;
  world_load_section(world,2304+120,1776+650,0);
  wdump("lumbridge",0);
  frame("lumbridge1",6144,6144,0,1500);
  frame("lumbridge2",5800,6500,512,1200);
  route(48,48,48,48,48,48,0);
  route(48,48,60,40,60,40,0);
  route(48,48,30,70,31,71,1);
  route(40,50,90,10,90,10,0);
  route(10,10,85,85,85,85,0);
  world_register_object(world,44,44,1); world_register_wall_object(world,46,46,0,1); world_register_wall_object(world,47,47,3,2);
  printf("objects adj %u\n", fnv(world->object_adjacency,sizeof world->object_adjacency));
  for(int i=0;i<TERRAIN_COUNT;i++) if(i%9==4) mdump("shadow",0,i,world->terrain_models[i]);
  route(40,40,52,52,52,52,0);
  world_remove_object(world,44,44,1); world_remove_wall_object(world,46,46,0,1); world_remove_wall_object(world,47,47,3,2);
  printf("removed adj %u\n", fnv(world->object_adjacency,sizeof world->object_adjacency));

  world_load_section(world,2304+120,1776+650,1);
  wdump("upstairs",1);
  frame("upstairs1",6144,6144,256,1500);

  world_load_section(world,2304+130,1776+500,0);
  wdump("varrock",0);
  frame("varrock1",6144,6144,128,1800);
  return 0;
}
