#include "T6InflateBridge.h"
#include <zlib.h>

int zombies_t6_inflate_raw(
    const uint8_t *input,
    size_t inputSize,
    uint8_t *output,
    size_t outputCapacity,
    size_t *outputSize
) {
    if (!input || !output || !outputSize || inputSize == 0 || outputCapacity == 0) {
        return Z_STREAM_ERROR;
    }

    z_stream stream = {0};
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)inputSize;
    stream.next_out = output;
    stream.avail_out = (uInt)outputCapacity;

    int status = inflateInit2(&stream, -MAX_WBITS);
    if (status != Z_OK) {
        return status;
    }

    status = inflate(&stream, Z_FINISH);
    if (status == Z_STREAM_END) {
        *outputSize = (size_t)stream.total_out;
        inflateEnd(&stream);
        return Z_OK;
    }

    inflateEnd(&stream);
    return status;
}
