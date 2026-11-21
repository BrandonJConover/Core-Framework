#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/socket.h>
#include "packet-stream.h"
/* Golden output for the Swift port's ISAAC, RSA and packet framing tests. */
static const char *MOD = "87cef754966ecb19806238d9fecf0f421e816976f74f365c86a584e51049794d41fefbdc5fed3a3ed3b7495ba24262bb7d1dd5d2ff9e306b5bbf5522a2e85b25";
static void hex(const char *tag, const uint8_t *p, int n){ printf("%s", tag); for(int i=0;i<n;i++) printf("%02x", p[i]); printf("\n"); }
static void dump_out(const char *tag, PacketStream *ps){ hex(tag, (uint8_t*)ps->packet_data, ps->packet_start); }
int main(int argc, char **argv){
  uint32_t keys[4] = {0x12345678u, 0x9abcdef0u, 0x0badf00du, 0xdeadbeefu};
  struct isaac is; memset(&is, 0, sizeof is); for(int i=0;i<4;i++) is.randrsl[i]=keys[i];
  isaac_init(&is, 1);
  printf("isaac"); for(int i=0;i<600;i++) printf(" %u", isaac_next(&is)); printf("\n");
  struct isaac z; memset(&z, 0, sizeof z); isaac_init(&z, 0);
  printf("isaac0"); for(int i=0;i<10;i++) printf(" %u", isaac_next(&z)); printf("\n");

  struct rsa r; rsa_init(&r, "00010001", MOD);
  const char *inputs[] = {"\x01", "hello world", "\n\x12\x34\x56\x78 a much longer login-ish block of bytes!!\n", ""};
  for(int k=0;k<3;k++){ uint8_t out[64]={0}; int n=rsa_crypt(&r,(void*)inputs[k],strlen(inputs[k]),out,64); hex("rsa ", out, n); }
  struct rsa r2; rsa_init(&r2, "81f390b2cf8ca7039ee507975951d5a0b15a87bf8b3f99c966834118c50fd94d",
    "88c38748a58228f7261cdc340b5691d7d0975dee0ecdb717609e6bf971eb3fe723ef9d130e4686813739768ad9472eb46d8bfcc042c1a5fcb05e931f632eea5d");
  { uint8_t out[64]={0}; int n=rsa_crypt(&r2,(void*)inputs[2],strlen(inputs[2]),out,64); hex("rsa2 ", out, n); }

  int sv[2]; socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
  fcntl(sv[0], F_SETFL, O_NONBLOCK);
  PacketStream *ps = calloc(1, sizeof(PacketStream));
  rsa_init(&ps->rsa, "00010001", MOD);
  ps->socket = sv[0]; ps->packet_end = 3; ps->packet_max_length = 5000; ps->max_read_tries = 1000;
  packet_stream_new_packet(ps, 67); packet_stream_send_packet(ps); dump_out("out_empty ", ps);
  packet_stream_new_packet(ps, 45); packet_stream_put_byte(ps, 300); packet_stream_put_short(ps, -2);
  packet_stream_put_int(ps, 0x89abcdef); packet_stream_put_long(ps, 0x0123456789abcdefLL);
  packet_stream_put_string(ps, "Zezima"); packet_stream_send_packet(ps); dump_out("out_mixed ", ps);
  packet_stream_new_packet(ps, 216); for(int i=0;i<200;i++) packet_stream_put_byte(ps, i*7);
  packet_stream_send_packet(ps); dump_out("out_long ", ps);
  packet_stream_write_packet(ps, 0);
  { uint8_t buf[2000]; int n=read(sv[1], buf, sizeof buf); hex("wire ", buf, n); }
  packet_stream_new_packet(ps, 0); packet_stream_put_short(ps, 204);
  packet_stream_put_login_block(ps, "tester", "secret123", keys, 0x0a0b0c0d);
  packet_stream_send_packet(ps); dump_out("out_login ", ps);
  for(int i=0;i<5;i++){ packet_stream_new_packet(ps, 67); packet_stream_put_byte(ps, i); packet_stream_send_packet(ps); }
  dump_out("out_isaac ", ps);

  /* incoming: three packets, one long, written to the peer end */
  uint8_t in[600]; int n=0;
  in[n++]=3; in[n++]=0xaa; in[n++]=0x10; in[n++]=0x20;            /* len 3: last byte first */
  in[n++]=1; in[n++]=0x55;                                        /* len 1 */
  in[n++]=160+1; in[n++]=44; for(int i=0;i<300;i++) in[n++]=(uint8_t)(i*3+1); /* len 300 */
  write(sv[1], in, n);
  int8_t buf[5000];
  for(int t=0;t<6;t++){ int len=packet_stream_read_packet(ps, buf); printf("read %d ", len); hex("", (uint8_t*)buf, len); }
  return 0;
}
