#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct zq3_input_s {
    float move_x;
    float move_y;
    float look_x;
    float look_y;
    uint8_t fire;
    uint8_t aim;
    uint8_t jump;
    uint8_t reload;
} zq3_input_t;

typedef struct zq3_player_state_s {
    float position[3];
    float yaw;
    float pitch;
    float vertical_velocity;
    uint8_t grounded;
    uint64_t frame_number;
} zq3_player_state_t;

typedef enum zq3_status_e {
    ZQ3_OK = 0,
    ZQ3_ERROR_ARGUMENT = -1,
    ZQ3_ERROR_ALLOCATION = -2,
    ZQ3_ERROR_WORLD = -3
} zq3_status_t;

int zq3_init(void);

int zq3_load_world(
    const float *xyz,
    uint32_t vertex_count,
    const uint32_t *indices,
    uint32_t index_count,
    const float spawn_xyz[3]
);

void zq3_set_input(const zq3_input_t *input);
void zq3_step(float delta_seconds);
void zq3_get_player_state(zq3_player_state_t *state_out);
void zq3_shutdown(void);

#ifdef __cplusplus
}
#endif
