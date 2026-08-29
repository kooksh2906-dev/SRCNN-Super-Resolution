#include "srcnn_crc32.h"

u32 SrcnnCrc32(const u8 *data, u32 length)
{
    u32 crc = 0xFFFFFFFFU;
    u32 i;

    for (i = 0U; i < length; ++i) {
        u32 bit;
        crc ^= (u32)data[i];
        for (bit = 0U; bit < 8U; ++bit) {
            u32 mask = 0U - (crc & 1U);
            crc = (crc >> 1U) ^ (0xEDB88320U & mask);
        }
    }
    return ~crc;
}
