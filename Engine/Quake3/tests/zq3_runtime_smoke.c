#include "../zq3_runtime.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static int nearf(float a, float b, float eps) { return fabsf(a - b) <= eps; }

int main(void) {
    const float v[] = {
        -8,0,-8,  8,0,-8,  8,0,8,  -8,0,8,
        -8,6,-8,  8,6,-8,  8,6,8,  -8,6,8
    };
    const uint32_t i[] = {
        0,2,1, 0,3,2,
        0,1,5, 0,5,4,
        1,2,6, 1,6,5,
        2,3,7, 2,7,6,
        3,0,4, 3,4,7,
        4,5,6, 4,6,7
    };

    assert(zq3_init() == 1);
    zq3_vec3 spawn = {0,2,0};
    assert(zq3_load_world(v, 8, i, sizeof(i)/sizeof(i[0]), spawn) == 1);

    zq3_player_state s = zq3_get_player_state();
    assert(nearf(s.origin.y, 1.7f, 0.01f));
    assert(s.on_ground == 1);

    zq3_input move = {0};
    move.forward = 1.0f;
    zq3_set_input(move);
    for (int n = 0; n < 10; ++n) zq3_step(1.0f/60.0f);
    s = zq3_get_player_state();
    assert(s.origin.z > 0.1f);
    assert(nearf(s.origin.y, 1.7f, 0.05f));

    for (int n = 0; n < 180; ++n) zq3_step(1.0f/60.0f);
    s = zq3_get_player_state();
    assert(s.origin.z < 7.8f);

    zq3_input jump = {0};
    jump.jump = 1;
    zq3_set_input(jump);
    zq3_step(1.0f/60.0f);
    s = zq3_get_player_state();
    assert(s.origin.y > 1.7f);
    assert(s.velocity.y > 0.0f);

    zq3_shutdown();
    assert(zq3_init() == 1);
    assert(zq3_load_world(v, 8, i, sizeof(i)/sizeof(i[0]), spawn) == 1);

    zq3_weapon_state w = zq3_get_weapon_state();
    assert(w.magazine == 30);
    assert(w.reserve == 120);
    assert(w.shots_fired == 0);

    zq3_input fire = {0};
    fire.fire = 1;
    zq3_set_input(fire);
    zq3_step(1.0f/60.0f);
    w = zq3_get_weapon_state();
    assert(w.magazine == 29);
    assert(w.shots_fired == 1);
    assert(w.last_shot_hit == 1);
    assert(w.last_hit_distance > 7.9f && w.last_hit_distance < 8.1f);
    assert(nearf(w.last_hit_position.z, 8.0f, 0.01f));

    for (int n = 0; n < 30; ++n) zq3_step(1.0f/60.0f);
    w = zq3_get_weapon_state();
    assert(w.magazine < 29);
    assert(w.shots_fired > 1);

    zq3_input reload = {0};
    reload.reload = 1;
    zq3_set_input(reload);
    zq3_step(1.0f/60.0f);
    w = zq3_get_weapon_state();
    assert(w.reloading == 1);
    for (int n = 0; n < 130; ++n) zq3_step(1.0f/60.0f);
    w = zq3_get_weapon_state();
    assert(w.reloading == 0);
    assert(w.magazine == 30);
    assert(w.reserve < 120);

    zq3_shutdown();
    puts("zq3 runtime smoke test passed");
    return 0;
}
