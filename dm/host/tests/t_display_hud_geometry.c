#include "display_hud_geometry.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
int main(void) {
 float sizes[][4]={{0,0,1920,1080},{0,0,1280,720},{12,8,960,540},{0,0,640,360}};
 double ratios[]={76.0/35,4.0/3,16.0/9,1.43,1.0,4.0};
 for(int j=0;j<6;j++)for(int i=0;i<4;i++) {
  float r[4],before[4]; memcpy(before,sizes[i],sizeof before);
  assert(dm_display_hud_rect(sizes[i],ratios[j],r));
  assert(fabs((r[2]/sizes[i][2])/(r[3]/sizes[i][3])*ratios[j]-16.0/9)<1e-6);
  assert(r[0]>=sizes[i][0]&&r[1]>=sizes[i][1]);
  assert(r[0]+r[2]<=sizes[i][0]+sizes[i][2]+.001 && r[1]+r[3]<=sizes[i][1]+sizes[i][3]+.001);
  assert(fabs(r[1]+r[3]/2-(sizes[i][1]+sizes[i][3]/2))<.001);
  assert(fabs(r[0]+r[2]/2-(sizes[i][0]+sizes[i][2]/2))<.001);
  assert(!memcmp(before,sizes[i],sizeof before));
 }
 float panels[][4]={{0,0,200,200},{10,20,300,80},{0,0,0,720},{0,0,NAN,720}};
 for(int i=0;i<4;i++){float r[4]={1,2,3,4},before[4];memcpy(before,r,sizeof r);assert(!dm_display_hud_rect(panels[i],76.0/35,r));assert(!memcmp(r,before,sizeof r));}
 puts("HUD geometry: 24 screen canvases + 4 unrelated/invalid panels passed");
}
