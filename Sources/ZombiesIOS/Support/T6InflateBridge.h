#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Inflates one T6 XChunk encoded as a raw DEFLATE stream.
/// Returns Z_OK on success and writes the decompressed byte count to outputSize.
int zombies_t6_inflate_raw(
    const uint8_t *input,
    size_t inputSize,
    uint8_t *output,
    size_t outputCapacity,
    size_t *outputSize
);

#ifdef __cplusplus
}
#endif
