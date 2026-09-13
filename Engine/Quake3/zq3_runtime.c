/*
===========================================================================
Quake III Arena source code foundation:
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of the Zombies-IOS Quake III-derived runtime and is
redistributed under the GNU General Public License version 2 or later.
The vector/view-command conventions are adapted for a small native iOS
runtime facade; this is not the original Quake III Arena source file.
===========================================================================
*/

#include "zq3_runtime.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define ZQ3_PI 3.14159265358979323846f
#define ZQ3_PLAYER_HEIGHT 1.65f
#define ZQ3_MOVE_SPEED 5.5f
#define ZQ3_JUMP_SPEED 5.8f
#define ZQ3_GRAVITY 14.8f
#define ZQ3_LOOK_SCALE 0.0022f
#define ZQ3_GROUND_SNAP 0.35f

typedef struct zq3_world_s {
    float *xyz;
    uint32_t vertex_count;
    uint32_t *indices;
    uint32_t index_count;
} zq3_world_t;

typedef struct zq3_runtime_s {
    int initialized;
    zq3_world_t world;
    zq3_input_t input;
    zq3_player_state_t player;
} zq3_runtime_t;

static zq3_runtime_t g_runtime;

static float zq3_clampf(float value, float lo, float hi) {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
}

static int zq3_point_in_xz_triangle(
    float x, float z,
    const float *a, const float *b, const float *c,
    float *y_out
) {
    const float v0x = c[0] - a[0];
    const float v0z = c[2] - a[2];
    const float v1x = b[0] - a[0];
    const float v1z = b[2] - a[2];
    const float v2x = x - a[0];
    const float v2z = z - a[2];

    const float dot00 = v0x * v0x + v0z * v0z;
    const float dot01 = v0x * v1x + v0z * v1z;
    const float dot02 = v0x * v2x + v0z * v2z;
    const float dot11 = v1x * v1x + v1z * v1z;
    const float dot12 = v1x * v2x + v1z * v2z;
    const float denom = dot00 * dot11 - dot01 * dot01;
    if (fabsf(denom) < 1.0e-8f) return 0;

    const float inv = 1.0f / denom;
    const float u = (dot11 * dot02 - dot01 * dot12) * inv;
    const float v = (dot00 * dot12 - dot01 * dot02) * inv;
    if (u < -0.001f || v < -0.001f || u + v > 1.001f) return 0;

    const float w = 1.0f - u - v;
    *y_out = w * a[1] + v * b[1] + u * c[1];
    return 1;
}

static int zq3_floor_height(float x, float z, float max_y, float *height_out) {
    const zq3_world_t *world = &g_runtime.world;
    int found = 0;
    float best = -INFINITY;

    for (uint32_t i = 0; i + 2 < world->index_count; i += 3) {
        const uint32_t ia = world->indices[i];
        const uint32_t ib = world->indices[i + 1];
        const uint32_t ic = world->indices[i + 2];
        if (ia >= world->vertex_count || ib >= world->vertex_count || ic >= world->vertex_count) continue;

        const float *a = &world->xyz[ia * 3u];
        const float *b = &world->xyz[ib * 3u];
        const float *c = &world->xyz[ic * 3u];

        const float ux = b[0] - a[0];
        const float uy = b[1] - a[1];
        const float uz = b[2] - a[2];
        const float vx = c[0] - a[0];
        const float vy = c[1] - a[1];
        const float vz = c[2] - a[2];
        const float ny = uz * vx - ux * vz;
        if (fabsf(ny) < 0.15f) continue;

        float y = 0.0f;
        if (!zq3_point_in_xz_triangle(x, z, a, b, c, &y)) continue;
        if (y <= max_y && y > best) {
            best = y;
            found = 1;
        }
    }

    if (found && height_out) *height_out = best;
    return found;
}

static void zq3_clear_world(void) {
    free(g_runtime.world.xyz);
    free(g_runtime.world.indices);
    memset(&g_runtime.world, 0, sizeof(g_runtime.world));
}

int zq3_init(void) {
    zq3_shutdown();
    memset(&g_runtime, 0, sizeof(g_runtime));
    g_runtime.initialized = 1;
    g_runtime.player.grounded = 0;
    return ZQ3_OK;
}

int zq3_load_world(
    const float *xyz,
    uint32_t vertex_count,
    const uint32_t *indices,
    uint32_t index_count,
    const float spawn_xyz[3]
) {
    if (!g_runtime.initialized || !xyz || !indices || !spawn_xyz || vertex_count < 3 || index_count < 3 || index_count % 3u != 0u) {
        return ZQ3_ERROR_ARGUMENT;
    }

    float *vertex_copy = (float *)malloc(sizeof(float) * (size_t)vertex_count * 3u);
    uint32_t *index_copy = (uint32_t *)malloc(sizeof(uint32_t) * (size_t)index_count);
    if (!vertex_copy || !index_copy) {
        free(vertex_copy);
        free(index_copy);
        return ZQ3_ERROR_ALLOCATION;
    }

    memcpy(vertex_copy, xyz, sizeof(float) * (size_t)vertex_count * 3u);
    memcpy(index_copy, indices, sizeof(uint32_t) * (size_t)index_count);
    for (uint32_t i = 0; i < index_count; ++i) {
        if (index_copy[i] >= vertex_count) {
            free(vertex_copy);
            free(index_copy);
            return ZQ3_ERROR_WORLD;
        }
    }

    zq3_clear_world();
    g_runtime.world.xyz = vertex_copy;
    g_runtime.world.vertex_count = vertex_count;
    g_runtime.world.indices = index_copy;
    g_runtime.world.index_count = index_count;

    g_runtime.player.position[0] = spawn_xyz[0];
    g_runtime.player.position[1] = spawn_xyz[1];
    g_runtime.player.position[2] = spawn_xyz[2];
    g_runtime.player.yaw = 0.0f;
    g_runtime.player.pitch = 0.0f;
    g_runtime.player.vertical_velocity = 0.0f;
    g_runtime.player.frame_number = 0;

    float floor = 0.0f;
    if (zq3_floor_height(spawn_xyz[0], spawn_xyz[2], spawn_xyz[1] + 8.0f, &floor)) {
        g_runtime.player.position[1] = floor + ZQ3_PLAYER_HEIGHT;
        g_runtime.player.grounded = 1;
    }
    return ZQ3_OK;
}

void zq3_set_input(const zq3_input_t *input) {
    if (!input) {
        memset(&g_runtime.input, 0, sizeof(g_runtime.input));
        return;
    }
    g_runtime.input = *input;
}

void zq3_step(float delta_seconds) {
    if (!g_runtime.initialized || g_runtime.world.vertex_count == 0) return;
    const float dt = zq3_clampf(delta_seconds, 0.0f, 0.05f);
    if (dt <= 0.0f) return;

    g_runtime.player.yaw -= g_runtime.input.look_x * ZQ3_LOOK_SCALE;
    g_runtime.player.pitch -= g_runtime.input.look_y * ZQ3_LOOK_SCALE;
    g_runtime.player.pitch = zq3_clampf(g_runtime.player.pitch, -1.35f, 1.35f);

    const float move_x = zq3_clampf(g_runtime.input.move_x, -1.0f, 1.0f);
    const float move_y = zq3_clampf(g_runtime.input.move_y, -1.0f, 1.0f);
    const float sy = sinf(g_runtime.player.yaw);
    const float cy = cosf(g_runtime.player.yaw);
    const float dx = (cy * move_x - sy * move_y) * ZQ3_MOVE_SPEED * dt;
    const float dz = (-sy * move_x - cy * move_y) * ZQ3_MOVE_SPEED * dt;

    const float old_x = g_runtime.player.position[0];
    const float old_z = g_runtime.player.position[2];
    const float proposed_x = old_x + dx;
    const float proposed_z = old_z + dz;

    float proposed_floor = 0.0f;
    const float feet = g_runtime.player.position[1] - ZQ3_PLAYER_HEIGHT;
    if (zq3_floor_height(proposed_x, proposed_z, feet + ZQ3_GROUND_SNAP + 1.0f, &proposed_floor)) {
        if (proposed_floor <= feet + 0.65f) {
            g_runtime.player.position[0] = proposed_x;
            g_runtime.player.position[2] = proposed_z;
        }
    } else {
        g_runtime.player.position[0] = proposed_x;
        g_runtime.player.position[2] = proposed_z;
    }

    if (g_runtime.input.jump && g_runtime.player.grounded) {
        g_runtime.player.vertical_velocity = ZQ3_JUMP_SPEED;
        g_runtime.player.grounded = 0;
    }

    g_runtime.player.vertical_velocity -= ZQ3_GRAVITY * dt;
    g_runtime.player.position[1] += g_runtime.player.vertical_velocity * dt;

    float floor = 0.0f;
    const float max_floor = g_runtime.player.position[1] - ZQ3_PLAYER_HEIGHT + 1.0f;
    if (zq3_floor_height(g_runtime.player.position[0], g_runtime.player.position[2], max_floor, &floor)) {
        const float target_y = floor + ZQ3_PLAYER_HEIGHT;
        if (g_runtime.player.position[1] <= target_y + ZQ3_GROUND_SNAP && g_runtime.player.vertical_velocity <= 0.0f) {
            g_runtime.player.position[1] = target_y;
            g_runtime.player.vertical_velocity = 0.0f;
            g_runtime.player.grounded = 1;
        } else {
            g_runtime.player.grounded = 0;
        }
    } else {
        g_runtime.player.grounded = 0;
    }

    g_runtime.player.frame_number += 1u;
}

void zq3_get_player_state(zq3_player_state_t *state_out) {
    if (!state_out) return;
    *state_out = g_runtime.player;
}

void zq3_shutdown(void) {
    zq3_clear_world();
    memset(&g_runtime, 0, sizeof(g_runtime));
}
