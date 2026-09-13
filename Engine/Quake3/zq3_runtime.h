#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { float x, y, z; } zq3_vec3;
typedef struct { float forward, right, yaw_delta, pitch_delta; int jump, fire, aim, reload; } zq3_input;
typedef struct { zq3_vec3 origin; zq3_vec3 velocity; float yaw, pitch; int on_ground; } zq3_player_state;
typedef struct {
    int magazine;
    int reserve;
    int shots_fired;
    int reloading;
    float reload_remaining;
    float shot_cooldown;
    int last_shot_hit;
    float last_hit_distance;
    zq3_vec3 last_hit_position;
} zq3_weapon_state;

int zq3_init(void);
int zq3_load_world(const float *xyz, size_t vertex_count, const uint32_t *indices, size_t index_count, zq3_vec3 spawn);
void zq3_set_input(zq3_input input);
void zq3_step(float seconds);
zq3_player_state zq3_get_player_state(void);
zq3_weapon_state zq3_get_weapon_state(void);
void zq3_shutdown(void);

#ifdef __cplusplus
}
#endif
