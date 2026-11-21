#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "bzip.h"
/* Prints: entry_index hash size fnv1a for every entry of a .jag archive, using rsc-c's bzip. */
static uint32_t fnv(const uint8_t *p, int n){uint32_t h=2166136261u;for(int i=0;i<n;i++){h^=p[i];h*=16777619u;}return h;}
int main(int argc,char**argv){
  FILE*f=fopen(argv[1],"rb"); uint8_t hdr[6]; fread(hdr,6,1,f);
  int size=(hdr[0]<<16)|(hdr[1]<<8)|hdr[2], comp=(hdr[3]<<16)|(hdr[4]<<8)|hdr[5];
  int8_t*raw=malloc(comp); fread(raw,comp,1,f); fclose(f);
  uint8_t*body=(uint8_t*)raw;
  if(size!=comp){ body=malloc(size+4096); bzip_decompress((int8_t*)body,raw,comp,0);}
  int n=(body[0]<<8)|body[1]; int off=2+n*10;
  for(int e=0;e<n;e++){ uint8_t*b=body+2+e*10;
    uint32_t h=((uint32_t)b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3];
    int s=(b[4]<<16)|(b[5]<<8)|b[6], st=(b[7]<<16)|(b[8]<<8)|b[9];
    uint8_t*out;
    if(s!=st){out=malloc(s+4096); bzip_decompress((int8_t*)out,(int8_t*)body,st,off);} else out=body+off;
    printf("%d %u %d %u\n",e,h,s,fnv(out,s));
    off+=st;
  }
  return 0;
}
