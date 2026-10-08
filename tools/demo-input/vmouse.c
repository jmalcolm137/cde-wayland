/* vmouse — pointer actions with tight timing (no blocking roundtrips mid-sequence).
 * usage: vmouse move X Y | click X Y | rclick X Y | dclick X Y | drag X1 Y1 X2 Y2 [steps]
 */
#include <wayland-client.h>
#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include "vptr.h"
static struct zwlr_virtual_pointer_manager_v1 *mgr=NULL; static struct wl_seat *seat=NULL;
static struct wl_display *dpy=NULL; static struct zwlr_virtual_pointer_v1 *vp=NULL;
static void g(void*d,struct wl_registry*r,uint32_t n,const char*i,uint32_t v){(void)d;(void)v;
  if(!strcmp(i,zwlr_virtual_pointer_manager_v1_interface.name)) mgr=wl_registry_bind(r,n,&zwlr_virtual_pointer_manager_v1_interface,2);
  else if(!strcmp(i,wl_seat_interface.name)&&!seat) seat=wl_registry_bind(r,n,&wl_seat_interface,1);}
static void gr(void*d,struct wl_registry*r,uint32_t n){(void)d;(void)r;(void)n;}
static const struct wl_registry_listener L={g,gr};
#define W 1280
#define H 720
static void mv(int x,int y){ zwlr_virtual_pointer_v1_motion_absolute(vp,0,x,y,W,H); zwlr_virtual_pointer_v1_frame(vp); wl_display_flush(dpy); }
static uint32_t now32(void){ struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts); return (uint32_t)(ts.tv_sec*1000 + ts.tv_nsec/1000000); }
static void btn(uint32_t b,int st){ zwlr_virtual_pointer_v1_button(vp,now32(),b,st); zwlr_virtual_pointer_v1_frame(vp); wl_display_flush(dpy); }
static void ms(int m){ usleep(m*1000); }
int main(int argc,char**argv){
  if(argc<4 && !(argc>1&&!strcmp(argv[1],"drag"))){fprintf(stderr,"usage: %s move X Y|click X Y|rclick X Y|dclick X Y|drag X1 Y1 X2 Y2 [steps]\n",argv[0]);return 2;}
  dpy=wl_display_connect(NULL); if(!dpy){fprintf(stderr,"no display\n");return 1;}
  struct wl_registry*r=wl_display_get_registry(dpy); wl_registry_add_listener(r,&L,NULL); wl_display_roundtrip(dpy);
  if(!mgr){fprintf(stderr,"no vp mgr\n");return 1;}
  vp=zwlr_virtual_pointer_manager_v1_create_virtual_pointer(mgr,seat);
  const char*cmd=argv[1];
  if(!strcmp(cmd,"drag")){
    int x1=atoi(argv[2]),y1=atoi(argv[3]),x2=atoi(argv[4]),y2=atoi(argv[5]);
    int steps=argc>6?atoi(argv[6]):10;
    mv(x1,y1); ms(250); btn(BTN_LEFT,WL_POINTER_BUTTON_STATE_PRESSED); ms(250);
    for(int i=1;i<=steps;i++){ mv(x1+(x2-x1)*i/steps, y1+(y2-y1)*i/steps); ms(60); }
    ms(250); btn(BTN_LEFT,WL_POINTER_BUTTON_STATE_RELEASED); ms(200);
  } else {
    int x=atoi(argv[2]),y=atoi(argv[3]);
    uint32_t b = !strcmp(cmd,"rclick")?BTN_RIGHT:BTN_LEFT;
    mv(x,y); ms(150);
    if(!strcmp(cmd,"dclick")){
      btn(b,WL_POINTER_BUTTON_STATE_PRESSED); ms(20); btn(b,WL_POINTER_BUTTON_STATE_RELEASED); ms(80);
      btn(b,WL_POINTER_BUTTON_STATE_PRESSED); ms(20); btn(b,WL_POINTER_BUTTON_STATE_RELEASED); ms(150);
    } else if(!strcmp(cmd,"move")){ /* nothing */ }
    else { btn(b,WL_POINTER_BUTTON_STATE_PRESSED); ms(90); btn(b,WL_POINTER_BUTTON_STATE_RELEASED); ms(150); }
  }
  wl_display_flush(dpy); ms(80);
  return 0;
}
