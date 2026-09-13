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

    zq3_input jump = {0};
    jump.jump = 1;
    zq3_set_input(jump);
    zq3_step(1.0f/60.0f);
    s = zq3_get_player_state();
    assert(s.origin.y > 1.7f);
    assert(s.velocity.y > 0.0f);

    zq3_shutdown();
    puts("zq3 runtime smoke test passed");
    return 0;
}
