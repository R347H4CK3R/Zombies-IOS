#include "zq3_runtime.h"
#include <math.h>
#include <string.h>

static struct {
    int initialized;
    zq3_input input;
    zq3_player_state player;
    const float *vertices;
    size_t vertex_count;
    const uint32_t *indices;
    size_t index_count;
} g;

static float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

int zq3_init(void) {
    memset(&g, 0, sizeof(g));
    g.initialized = 1;
    g.player.origin = (zq3_vec3){0.0f, 2.0f, 0.0f};
    return 1;
}

int zq3_load_world(const float *xyz, size_t vertex_count, const uint32_t *indices, size_t index_count, zq3_vec3 spawn) {
    if (!g.initialized || !xyz || !indices || vertex_count < 3 || index_count < 3) return 0;
    g.vertices = xyz;
    g.vertex_count = vertex_count;
    g.indices = indices;
    g.index_count = index_count;
    g.player.origin = spawn;
    g.player.velocity = (zq3_vec3){0,0,0};
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

    /* Initial collision boundary: ground plane. Triangle-world collision is layered here. */
    if (g.player.origin.y < 1.7f) {
        g.player.origin.y = 1.7f;
        if (g.player.velocity.y < 0) g.player.velocity.y = 0;
        g.player.on_ground = 1;
    }
}

zq3_player_state zq3_get_player_state(void) { return g.player; }
void zq3_shutdown(void) { memset(&g, 0, sizeof(g)); }
