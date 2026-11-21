#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mudclient.h"
#include "game-model.h"
#include "game-data.h"
#include "utility.h"
/* Loads every .ob3 model the client loads and runs it through rsc-c's model
 * pipeline (copy, light, orient, place, apply, project), printing hashes of
 * each stage. RSCClassicTests/GameModelTests.swift does the same in Swift. */
static uint32_t fnv(const void *v, size_t n){const uint8_t*p=v;uint32_t h=2166136261u;if(!v)return 0;for(size_t i=0;i<n;i++){h^=p[i];h*=16777619u;}return h;}
static int8_t *read_jag(const char *path){
  FILE*f=fopen(path,"rb"); if(!f){perror(path);exit(1);} unsigned char hdr[6]; fread(hdr,6,1,f);
  int size=(hdr[0]<<16)|(hdr[1]<<8)|hdr[2], comp=(hdr[3]<<16)|(hdr[4]<<8)|hdr[5];
  int8_t*raw=malloc(comp); fread(raw,comp,1,f); fclose(f);
  if(size==comp) return raw;
  int8_t*body=malloc(size+4096); bzip_decompress(body,raw,comp,0); return body;
}
static uint32_t faces_hash(GameModel *m){ uint32_t h=2166136261u; for(int i=0;i<m->face_count;i++){ for(int j=0;j<m->face_vertex_count[i];j++){ uint16_t v=m->face_vertices[i][j]; h^=v&0xff; h*=16777619u; h^=v>>8; h*=16777619u; } } return h; }
static void dump(const char *tag, int i, GameModel *m){
  int v=m->vertex_count, f=m->face_count;
  printf("%s %d v%d f%d vx%u vy%u vz%u tx%u ty%u tz%u fv%u ff%u fb%u fi%u vi%u va%u nx%u ny%u nz%u ns%u nm%u b%d,%d,%d,%d,%d,%d vis%d",
    tag, i, v, f, fnv(m->vertex_x,v*2), fnv(m->vertex_y,v*2), fnv(m->vertex_z,v*2),
    fnv(m->vertex_transformed_x,v*2), fnv(m->vertex_transformed_y,v*2), fnv(m->vertex_transformed_z,v*2),
    faces_hash(m), fnv(m->face_fill_front,f*2), fnv(m->face_fill_back,f*2), fnv(m->face_intensity,f*2),
    fnv(m->vertex_intensity,v*2), fnv(m->vertex_ambience,v), fnv(m->face_normal_x,f*2), fnv(m->face_normal_y,f*2),
    fnv(m->face_normal_z,f*2), fnv(m->normal_scale,f*2), fnv(m->normal_magnitude,f*4),
    m->min_x,m->max_x,m->min_y,m->max_y,m->min_z,m->max_z, m->visible);
  if(m->project_vertex_x) printf(" px%u py%u pz%u wx%u wy%u", fnv(m->project_vertex_x,v*2), fnv(m->project_vertex_y,v*2),
    fnv(m->project_vertex_z,v*2), fnv(m->vertex_view_x,v*4), fnv(m->vertex_view_y,v*4));
  printf("\n");
}
int main(int argc, char **argv){
  const char *cache=argv[1]; char path[512];
  init_utility_global();
  snprintf(path,sizeof path,"%s/config85.jag",cache); game_data_load_data(read_jag(path),1,85);
  for(int i=0;i<ANIMATED_MODELS_LENGTH;i++) game_data_get_model_index(mud_strdup(animated_models[i]));
  snprintf(path,sizeof path,"%s/models36.jag",cache); int8_t*jag=read_jag(path);
  GameModel **models=calloc(game_data.model_count,sizeof(GameModel*));
  for(int i=0;i<game_data.model_count;i++){
    char fn[64]; sprintf(fn,"%s.ob3",game_data.model_name[i]);
    uint32_t off=get_data_file_offset(fn,jag), len=get_data_file_length(fn,jag);
    models[i]=malloc(sizeof(GameModel));
    if(off) game_model_new_ob3(models[i],jag+off,len); else game_model_new_alloc(models[i],1,1);
    dump("load",i,models[i]);
  }
  for(int i=0;i<game_data.model_count;i++){
    GameModel *c=game_model_copy(models[i]);
    game_model_set_light(c,1,48,48,-50,-10,-50);
    game_model_orient(c,(i*37)&255,0,(i*11)&255); game_model_place(c,1000+i*3,-200,3000-i*5);
    game_model_apply(c); dump("lit",i,c);
    game_model_project_view(c,800,-500,1500,912,0,0,512,5); dump("proj",i,c);
    GameModel *d=game_model_copy_flags(models[i],0,0,0,1);
    game_model_set_light(d,0,60,24,-50,-10,-50); game_model_rotate(d,0,(i*5)&255,0); game_model_commit(d); dump("commit",i,d);
  }
  GameModel *pieces[12]; for(int i=0;i<12;i++) pieces[i]=models[i*7%game_data.model_count];
  GameModel merged; game_model_new_merge(&merged,pieces,12); dump("merge",0,&merged);
  /* a terrain-like grid, split into 4x4 pieces */
  GameModel grid; game_model_new_alloc_flags(&grid,33*33,32*32,1,0,0,0,1);
  for(int x=0;x<33;x++) for(int z=0;z<33;z++) game_model_create_vertex(&grid,x*128,((x*7+z*13)%50)-25,z*128);
  for(int x=0;x<32;x++) for(int z=0;z<32;z++){ uint16_t *v=malloc(8); v[0]=x*33+z; v[1]=(x+1)*33+z; v[2]=(x+1)*33+z+1; v[3]=x*33+z+1;
    int f=game_model_create_face(&grid,4,v,-1-((x*3+z)&0x7fff),COLOUR_TRANSPARENT); grid.face_tag[f]=x*100+z; }
  for(int i=0;i<grid.vertex_count;i++) game_model_set_vertex_ambience(&grid,i,(i*29)&0xff);
  game_model_set_light(&grid,1,40,48,-50,-10,-50); dump("grid",0,&grid);
  GameModel *split[16]; game_model_split(&grid,split,1024,1024,4,16,500,0);
  for(int i=0;i<16;i++){ dump("split",i,split[i]); printf("tag %d %u\n",i,fnv(split[i]->face_tag,split[i]->face_count*4)); }
  GameModel *mk=game_model_copy(models[5]); game_model_mask_faces(mk,mk->face_fill_front,0xff8040); dump("mask",0,mk);
  return 0;
}
