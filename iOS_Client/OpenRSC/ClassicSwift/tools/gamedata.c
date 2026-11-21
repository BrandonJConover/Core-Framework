#include <stdio.h>
#include <stdlib.h>
#include "game-data.h"
#include "utility.h"
/* Dumps every field game_data_load_data parses, one per line, for the Swift port's golden test. */
int main(int argc, char **argv) {
  FILE *f = fopen(argv[1], "rb"); unsigned char hdr[6]; fread(hdr, 6, 1, f);
  int size = (hdr[0]<<16)|(hdr[1]<<8)|hdr[2], comp = (hdr[3]<<16)|(hdr[4]<<8)|hdr[5];
  int8_t *raw = malloc(comp); fread(raw, comp, 1, f); fclose(f);
  int8_t *body = raw;
  if (size != comp) { body = malloc(size + 4096); bzip_decompress(body, raw, comp, 0); }
  game_data_load_data(body, atoi(argv[2]), atoi(argv[3]));
  struct MudConfig *g = &game_data;
  printf("items %d\n", g->item_count);
  for (int i = 0; i < g->item_count; i++) { struct ItemConfig *it = &g->items[i];
    printf("item %d|%s|%s|%s|%d|%d|%d|%d|%d|%d|%d\n", i, it->name, it->description, it->command, it->sprite, it->base_price, it->stackable, it->wearable, it->mask, it->special, it->members); }
  printf("npcs %d\n", g->npc_count);
  for (int i = 0; i < g->npc_count; i++) { struct NpcConfig *n = &g->npcs[i];
    printf("npc %d|%s|%s|%d|%d|%d|%d|%d|", i, n->name, n->description, n->attack, n->strength, n->hits, n->defense, n->attackable);
    for (int j = 0; j < 12; j++) printf("%d,", n->sprites[j]);
    printf("|%d|%d|%d|%d|%d|%d|%d|%d|%d|%s\n", n->hair_colour, n->top_colour, n->bottom_colour, n->skin_colour, n->width, n->height, n->walk_speed, n->combat_speed, n->combat_width, n->command); }
  printf("textures %d\n", g->texture_count);
  for (int i = 0; i < g->texture_count; i++) printf("texture %d|%s|%s\n", i, g->textures[i].name, g->textures[i].subtype_name);
  printf("animations %d\n", g->animation_count);
  for (int i = 0; i < g->animation_count; i++) { struct AnimConfig *a = &g->animations[i];
    printf("animation %d|%s|%d|%d|%d|%d|%d\n", i, a->name, a->colour, a->gender, a->has_a, a->has_f, a->file_id); }
  printf("objects %d\n", g->object_count);
  for (int i = 0; i < g->object_count; i++) { struct ObjectConfig *o = &g->objects[i];
    printf("object %d|%s|%s|%s|%s|%d|%d|%d|%d|%d\n", i, o->name, o->description, o->command1, o->command2, o->model_index, o->width, o->height, o->type, o->elevation); }
  printf("models %d\n", g->model_count);
  for (int i = 0; i < g->model_count; i++) printf("model %d|%s\n", i, g->model_name[i]);
  printf("walls %d\n", g->wall_object_count);
  for (int i = 0; i < g->wall_object_count; i++) { struct WallConfig *w = &g->wall_objects[i];
    printf("wall %d|%s|%s|%s|%s|%d|%d|%d|%d|%d\n", i, w->name, w->description, w->command1, w->command2, w->height, w->texture_front, w->texture_back, w->blocking, w->interactive); }
  printf("roofs %d\n", g->roof_count);
  for (int i = 0; i < g->roof_count; i++) printf("roof %d|%d|%d\n", i, g->roofs[i].height, g->roofs[i].fill);
  printf("tiles %d\n", g->tile_count);
  for (int i = 0; i < g->tile_count; i++) printf("tile %d|%d|%d|%d\n", i, g->tiles[i].decoration, g->tiles[i].type, g->tiles[i].blocking);
  printf("projectile %d\n", g->projectile_sprite);
  printf("spells %d\n", g->spell_count);
  for (int i = 0; i < g->spell_count; i++) { struct SpellConfig *s = &g->spells[i];
    printf("spell %d|%s|%s|%d|%d|%d|", i, s->name, s->description, s->level, s->runes_required, s->type);
    for (int j = 0; j < s->runes_required; j++) printf("%d:%d,", s->runes[j].id, s->runes[j].count);
    printf("\n"); }
  printf("prayers %d\n", g->prayer_count);
  for (int i = 0; i < g->prayer_count; i++) printf("prayer %d|%s|%s|%d|%d\n", i, g->prayers[i].name, g->prayers[i].description, g->prayers[i].level, g->prayers[i].drain);
  return 0;
}
