#include "zq3_runtime.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

static struct {
    int initialized;
    zq3_input input;
    zq3_player_state player;
    zq3_weapon_state weapon;
    float *vertices;
    size_t vertex_count;
    uint32_t *indices;
    size_t index_count;
} g;

static float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
static float dot3(zq3_vec3 a, zq3_vec3 b) { return a.x*b.x + a.y*b.y + a.z*b.z; }
static zq3_vec3 sub3(zq3_vec3 a, zq3_vec3 b) { return (zq3_vec3){a.x-b.x,a.y-b.y,a.z-b.z}; }
static zq3_vec3 cross3(zq3_vec3 a, zq3_vec3 b) { return (zq3_vec3){a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }

static void free_world(void) {
    free(g.vertices); g.vertices = NULL; g.vertex_count = 0;
    free(g.indices); g.indices = NULL; g.index_count = 0;
}

static void reset_weapon(void) {
    memset(&g.weapon, 0, sizeof(g.weapon));
    g.weapon.magazine = 30;
    g.weapon.reserve = 120;
}

static int triangle_walkable(const float *a,const float *b,const float *c) {
    float abx=b[0]-a[0],aby=b[1]-a[1],abz=b[2]-a[2];
    float acx=c[0]-a[0],acy=c[1]-a[1],acz=c[2]-a[2];
    float nx=aby*acz-abz*acy, ny=abz*acx-abx*acz, nz=abx*acy-aby*acx;
    float len=sqrtf(nx*nx+ny*ny+nz*nz);
    return len >= 0.000001f && fabsf(ny)/len >= 0.65f;
}

static int bary_height(float px,float pz,const float*a,const float*b,const float*c,float*out) {
    float v0x=b[0]-a[0],v0z=b[2]-a[2],v1x=c[0]-a[0],v1z=c[2]-a[2],v2x=px-a[0],v2z=pz-a[2];
    float den=v0x*v1z-v1x*v0z; if(fabsf(den)<0.000001f)return 0;
    float u=(v2x*v1z-v1x*v2z)/den,v=(v0x*v2z-v2x*v0z)/den;
    if(u < -0.001f || v < -0.001f || u+v > 1.001f)return 0;
    *out=a[1]+u*(b[1]-a[1])+v*(c[1]-a[1]); return 1;
}

static int world_floor(float x,float z,float max_y,float*out) {
    int found=0; float best=-INFINITY;
    for(size_t i=0; g.vertices && g.indices && i+2<g.index_count; i+=3){
        uint32_t ia=g.indices[i],ib=g.indices[i+1],ic=g.indices[i+2];
        if(ia>=g.vertex_count||ib>=g.vertex_count||ic>=g.vertex_count)continue;
        const float*a=&g.vertices[(size_t)ia*3],*b=&g.vertices[(size_t)ib*3],*c=&g.vertices[(size_t)ic*3];
        float y; if(triangle_walkable(a,b,c)&&bary_height(x,z,a,b,c,&y)&&y<=max_y&&y>best){best=y;found=1;}
    }
    if(found)*out=best; return found;
}

static int ray_triangle(zq3_vec3 o,zq3_vec3 d,const float*av,const float*bv,const float*cv,float*out_t){
    zq3_vec3 a={av[0],av[1],av[2]},b={bv[0],bv[1],bv[2]},c={cv[0],cv[1],cv[2]};
    zq3_vec3 e1=sub3(b,a),e2=sub3(c,a),p=cross3(d,e2); float det=dot3(e1,p);
    if(fabsf(det)<0.000001f)return 0; float inv=1.0f/det; zq3_vec3 tv=sub3(o,a); float u=dot3(tv,p)*inv;
    if(u<0||u>1)return 0; zq3_vec3 q=cross3(tv,e1); float v=dot3(d,q)*inv; if(v<0||u+v>1)return 0;
    float t=dot3(e2,q)*inv; if(t<=0.02f)return 0; *out_t=t; return 1;
}

static int world_blocks(zq3_vec3 o,float dx,float dz){
    float dist=sqrtf(dx*dx+dz*dz); if(dist<0.000001f)return 0; zq3_vec3 d={dx/dist,0,dz/dist};
    const float probes[]={0,-ZQ3_PLAYER_HEIGHT*.45f,-ZQ3_PLAYER_HEIGHT*.88f};
    for(size_t p=0;p<3;p++){ zq3_vec3 ro=o; ro.y+=probes[p];
        for(size_t i=0;g.vertices&&g.indices&&i+2<g.index_count;i+=3){
            uint32_t ia=g.indices[i],ib=g.indices[i+1],ic=g.indices[i+2]; if(ia>=g.vertex_count||ib>=g.vertex_count||ic>=g.vertex_count)continue;
            const float*a=&g.vertices[(size_t)ia*3],*b=&g.vertices[(size_t)ib*3],*c=&g.vertices[(size_t)ic*3]; if(triangle_walkable(a,b,c))continue;
            float t; if(ray_triangle(ro,d,a,b,c,&t)&&t<=dist+ZQ3_PLAYER_RADIUS)return 1;
        }
    } return 0;
}

static void hitscan(void){
    g.weapon.last_shot_hit=0; g.weapon.last_hit_distance=0; g.weapon.last_hit_position=(zq3_vec3){0,0,0};
    float yaw=g.player.yaw*0.01745329252f,pitch=g.player.pitch*0.01745329252f,cp=cosf(pitch);
    zq3_vec3 d={sinf(yaw)*cp,sinf(pitch),cosf(yaw)*cp},o=g.player.origin; float nearest=100000.0f;
    for(size_t i=0;g.vertices&&g.indices&&i+2<g.index_count;i+=3){
        uint32_t ia=g.indices[i],ib=g.indices[i+1],ic=g.indices[i+2]; if(ia>=g.vertex_count||ib>=g.vertex_count||ic>=g.vertex_count)continue;
        float t; if(ray_triangle(o,d,&g.vertices[(size_t)ia*3],&g.vertices[(size_t)ib*3],&g.vertices[(size_t)ic*3],&t)&&t<nearest){nearest=t;g.weapon.last_shot_hit=1;}
    }
    if(g.weapon.last_shot_hit){g.weapon.last_hit_distance=nearest;g.weapon.last_hit_position=(zq3_vec3){o.x+d.x*nearest,o.y+d.y*nearest,o.z+d.z*nearest};}
}

static void step_weapon(float dt){
    const float reload=1.9f, interval=.095f; if(g.weapon.shot_cooldown>0)g.weapon.shot_cooldown=fmaxf(0,g.weapon.shot_cooldown-dt);
    if(!g.weapon.reloading&&g.input.reload&&g.weapon.magazine<30&&g.weapon.reserve>0){g.weapon.reloading=1;g.weapon.reload_remaining=reload;}
    if(g.weapon.reloading){g.weapon.reload_remaining-=dt;if(g.weapon.reload_remaining<=0){int n=30-g.weapon.magazine,t=n<g.weapon.reserve?n:g.weapon.reserve;g.weapon.magazine+=t;g.weapon.reserve-=t;g.weapon.reloading=0;g.weapon.reload_remaining=0;}return;}
    if(g.input.fire&&g.weapon.magazine>0&&g.weapon.shot_cooldown<=0){g.weapon.magazine--;g.weapon.shots_fired++;g.weapon.shot_cooldown=interval;hitscan();}
}

int zq3_init(void){free_world();memset(&g,0,sizeof(g));g.initialized=1;g.player.origin=(zq3_vec3){0,ZQ3_PLAYER_HEIGHT,0};reset_weapon();return 1;}
int zq3_load_world(const float*xyz,size_t vc,const uint32_t*indices,size_t ic,zq3_vec3 spawn){
    if(!g.initialized||!xyz||!indices||vc<3||ic<3)return 0; free_world();
    g.vertices=malloc(vc*3*sizeof(float));g.indices=malloc(ic*sizeof(uint32_t));if(!g.vertices||!g.indices){free_world();return 0;}
    memcpy(g.vertices,xyz,vc*3*sizeof(float));memcpy(g.indices,indices,ic*sizeof(uint32_t));g.vertex_count=vc;g.index_count=ic;g.player.origin=spawn;g.player.velocity=(zq3_vec3){0,0,0};reset_weapon();
    float fy; if(world_floor(spawn.x,spawn.z,spawn.y-ZQ3_PLAYER_HEIGHT+ZQ3_STEP_HEIGHT,&fy)){float sy=fy+ZQ3_PLAYER_HEIGHT;if(spawn.y<=sy+ZQ3_STEP_HEIGHT){g.player.origin.y=sy;g.player.on_ground=1;}}return 1;
}
void zq3_set_input(zq3_input input){if(g.initialized)g.input=input;}
void zq3_step(float seconds){
    if(!g.initialized)return; float dt=clampf(seconds,0,.05f);g.player.yaw+=g.input.yaw_delta;g.player.pitch=clampf(g.player.pitch+g.input.pitch_delta,-89,89);
    float r=g.player.yaw*.01745329252f,sy=sinf(r),cy=cosf(r),wx=g.input.forward*sy+g.input.right*cy,wz=g.input.forward*cy-g.input.right*sy;
    float speed=g.input.aim?ZQ3_ADS_SPEED:ZQ3_RUN_SPEED;g.player.velocity.x=wx*speed;g.player.velocity.z=wz*speed;
    if(g.input.jump&&g.player.on_ground){g.player.velocity.y=ZQ3_JUMP_SPEED;g.player.on_ground=0;}g.player.velocity.y-=ZQ3_GRAVITY*dt;
    float dx=g.player.velocity.x*dt,dz=g.player.velocity.z*dt;if(!world_blocks(g.player.origin,dx,0))g.player.origin.x+=dx;else g.player.velocity.x=0;if(!world_blocks(g.player.origin,0,dz))g.player.origin.z+=dz;else g.player.velocity.z=0;g.player.origin.y+=g.player.velocity.y*dt;
    float fy;if(world_floor(g.player.origin.x,g.player.origin.z,g.player.origin.y-ZQ3_PLAYER_HEIGHT+ZQ3_STEP_HEIGHT,&fy)){float standing=fy+ZQ3_PLAYER_HEIGHT;if(g.player.origin.y<=standing&&g.player.velocity.y<=0){g.player.origin.y=standing;g.player.velocity.y=0;g.player.on_ground=1;}else if(g.player.origin.y>standing+.05f)g.player.on_ground=0;}else g.player.on_ground=0;step_weapon(dt);
}
zq3_player_state zq3_get_player_state(void){return g.player;}
zq3_weapon_state zq3_get_weapon_state(void){return g.weapon;}
void zq3_shutdown(void){free_world();memset(&g,0,sizeof(g));}
