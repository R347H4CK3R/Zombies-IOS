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

static void free_world(void) {
    free(g.vertices); g.vertices = NULL; g.vertex_count = 0;
    free(g.indices); g.indices = NULL; g.index_count = 0;
}

static void reset_weapon(void) {
    g.weapon.magazine = 30;
    g.weapon.reserve = 120;
    g.weapon.shots_fired = 0;
    g.weapon.reloading = 0;
    g.weapon.reload_remaining = 0.0f;
    g.weapon.shot_cooldown = 0.0f;
}

static int barycentric_height(float px, float pz, const float *a, const float *b, const float *c, float *out_y) {
    float v0x = b[0] - a[0], v0z = b[2] - a[2];
    float v1x = c[0] - a[0], v1z = c[2] - a[2];
    float v2x = px - a[0], v2z = pz - a[2];
    float den = v0x * v1z - v1x * v0z;
    if (fabsf(den) < 0.000001f) return 0;
    float u = (v2x * v1z - v1x * v2z) / den;
    float v = (v0x * v2z - v2x * v0z) / den;
    if (u < -0.001f || v < -0.001f || u + v > 1.001f) return 0;
    *out_y = a[1] + u * (b[1] - a[1]) + v * (c[1] - a[1]);
    return 1;
}

static int triangle_is_walkable(const float *a, const float *b, const float *c) {
    float abx = b[0] - a[0], aby = b[1] - a[1], abz = b[2] - a[2];
    float acx = c[0] - a[0], acy = c[1] - a[1], acz = c[2] - a[2];
    float nx = aby * acz - abz * acy;
    float ny = abz * acx - abx * acz;
    float nz = abx * acy - aby * acx;
    float length = sqrtf(nx * nx + ny * ny + nz * nz);
    if (length < 0.000001f) return 0;
    return fabsf(ny) / length >= 0.65f;
}

static int world_floor(float x, float z, float max_y, float *floor_y) {
    if (!g.vertices || !g.indices) return 0;
    int found = 0;
    float best = -INFINITY;
    for (size_t i = 0; i + 2 < g.index_count; i += 3) {
        uint32_t ia = g.indices[i], ib = g.indices[i + 1], ic = g.indices[i + 2];
        if (ia >= g.vertex_count || ib >= g.vertex_count || ic >= g.vertex_count) continue;
        const float *a = &g.vertices[(size_t)ia * 3];
        const float *b = &g.vertices[(size_t)ib * 3];
        const float *c = &g.vertices[(size_t)ic * 3];
        if (!triangle_is_walkable(a, b, c)) continue;
        float y;
        if (barycentric_height(x, z, a, b, c, &y) && y <= max_y && y > best) {
            best = y; found = 1;
        }
    }
    if (found) *floor_y = best;
    return found;
}

static void step_weapon(float dt) {
    const float reload_seconds = 1.9f;
    const float fire_interval = 0.095f;

    if (g.weapon.shot_cooldown > 0.0f) {
        g.weapon.shot_cooldown = fmaxf(0.0f, g.weapon.shot_cooldown - dt);
    }

    if (!g.weapon.reloading && g.input.reload && g.weapon.magazine < 30 && g.weapon.reserve > 0) {
        g.weapon.reloading = 1;
        g.weapon.reload_remaining = reload_seconds;
    }

    if (g.weapon.reloading) {
        g.weapon.reload_remaining -= dt;
        if (g.weapon.reload_remaining <= 0.0f) {
            int needed = 30 - g.weapon.magazine;
            int transferred = needed < g.weapon.reserve ? needed : g.weapon.reserve;
            g.weapon.magazine += transferred;
            g.weapon.reserve -= transferred;
            g.weapon.reloading = 0;
            g.weapon.reload_remaining = 0.0f;
        }
        return;
    }

    if (g.input.fire && g.weapon.magazine > 0 && g.weapon.shot_cooldown <= 0.0f) {
        g.weapon.magazine -= 1;
        g.weapon.shots_fired += 1;
        g.weapon.shot_cooldown = fire_interval;
    }
}

int zq3_init(void) {
    free_world();
    memset(&g, 0, sizeof(g));
    g.initialized = 1;
    g.player.origin = (zq3_vec3){0.0f, 2.0f, 0.0f};
    reset_weapon();
    return 1;
}

int zq3_load_world(const float *xyz, size_t vertex_count, const uint32_t *indices, size_t index_count, zq3_vec3 spawn) {
    if (!g.initialized || !xyz || !indices || vertex_count < 3 || index_count < 3) return 0;
    free_world();
    g.vertices = (float *)malloc(vertex_count * 3 * sizeof(float));
    g.indices = (uint32_t *)malloc(index_count * sizeof(uint32_t));
    if (!g.vertices || !g.indices) { free_world(); return 0; }
    memcpy(g.vertices, xyz, vertex_count * 3 * sizeof(float));
    memcpy(g.indices, indices, index_count * sizeof(uint32_t));
    g.vertex_count = vertex_count;
    g.index_count = index_count;
    g.player.origin = spawn;
    g.player.velocity = (zq3_vec3){0,0,0};
    reset_weapon();

    const float player_height = 1.7f;
    const float step_height = 0.75f;
    float floor_y;
    float floor_query_max = spawn.y - player_height + step_height;
    if (world_floor(spawn.x, spawn.z, floor_query_max, &floor_y)) {
        float standing_y = floor_y + player_height;
        if (spawn.y <= standing_y + step_height) {
            g.player.origin.y = standing_y;
            g.player.on_ground = 1;
        }
    }
    return 1;
}

void zq3_set_input(zq3_input input) { if (g.initialized) g.input = input; }

void zq3_step(float seconds) {
    if (!g.initialized) return;
    float dt = clampf(seconds, 0.0f, 0.05f);
    g.player.yaw += g.input.yaw_delta;
    g.player.pitch = clampf(g.player.pitch + g.input.pitch_delta, -89.0f, 89.0f);
    float radians = g.player.yaw * 0.01745329251994329577f;
    float sy = sinf(radians), cy = cosf(radians);
    float wishx = g.input.forward * sy + g.input.right * cy;
    float wishz = g.input.forward * cy - g.input.right * sy;
    const float speed = g.input.aim ? 3.5f : 6.5f;
    g.player.velocity.x = wishx * speed;
    g.player.velocity.z = wishz * speed;
    if (g.input.jump && g.player.on_ground) {
        g.player.velocity.y = 5.2f;
        g.player.on_ground = 0;
    }
    g.player.velocity.y -= 15.0f * dt;
    g.player.origin.x += g.player.velocity.x * dt;
    g.player.origin.y += g.player.velocity.y * dt;
    g.player.origin.z += g.player.velocity.z * dt;

    const float player_height = 1.7f;
    const float step_height = 0.75f;
    float floor_y;
    float floor_query_max = g.player.origin.y - player_height + step_height;
    if (world_floor(g.player.origin.x, g.player.origin.z, floor_query_max, &floor_y)) {
        float standing_y = floor_y + player_height;
        if (g.player.origin.y <= standing_y && g.player.velocity.y <= 0.0f) {
            g.player.origin.y = standing_y;
            g.player.velocity.y = 0.0f;
            g.player.on_ground = 1;
        } else if (g.player.origin.y > standing_y + 0.05f) {
            g.player.on_ground = 0;
        }
    } else {
        g.player.on_ground = 0;
    }

    step_weapon(dt);
}

zq3_player_state zq3_get_player_state(void) { return g.player; }
zq3_weapon_state zq3_get_weapon_state(void) { return g.weapon; }

void zq3_shutdown(void) {
    free_world();
    memset(&g, 0, sizeof(g));
}
