#include <wayland-client.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "vptr.h"
static struct zwlr_virtual_pointer_manager_v1 *mgr=NULL;
static struct wl_seat *seat=NULL;
static void g(void*d,struct wl_registry*r,uint32_t n,const char*i,uint32_t v){(void)d;(void)v;
  if(!strcmp(i,zwlr_virtual_pointer_manager_v1_interface.name)) mgr=wl_registry_bind(r,n,&zwlr_virtual_pointer_manager_v1_interface,2);
  else if(!strcmp(i,wl_seat_interface.name)&&!seat) seat=wl_registry_bind(r,n,&wl_seat_interface,1);}
static void gr(void*d,struct wl_registry*r,uint32_t n){(void)d;(void)r;(void)n;}
static const struct wl_registry_listener L={g,gr};
int main(int argc,char**argv){
  if(argc<3){fprintf(stderr,"usage: vmove X Y [w h]\n");return 2;}
  int x=atoi(argv[1]),y=atoi(argv[2]); int w=argc>4?atoi(argv[4]):1280,h=argc>5?atoi(argv[5]):720;
  struct wl_display*d=wl_display_connect(NULL); if(!d){fprintf(stderr,"no display\n");return 1;}
  struct wl_registry*r=wl_display_get_registry(d); wl_registry_add_listener(r,&L,NULL); wl_display_roundtrip(d);
  if(!mgr){fprintf(stderr,"no virtual pointer manager\n");return 1;}
  struct zwlr_virtual_pointer_v1*vp=zwlr_virtual_pointer_manager_v1_create_virtual_pointer(mgr,seat);
  zwlr_virtual_pointer_v1_motion_absolute(vp,0,x,y,w,h);
  zwlr_virtual_pointer_v1_frame(vp);
  wl_display_roundtrip(d); usleep(150000);
  return 0;
}
