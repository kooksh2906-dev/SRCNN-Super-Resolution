#include "srcnn_hw.h"

#include "srcnn_time.h"
#include "xil_io.h"

u32 SrcnnHw_Version(void)
{
    return Xil_In32(SRCNN_NPU_BASE + SRCNN_REG_VERSION);
}

u32 SrcnnHw_Status(void)
{
    return Xil_In32(SRCNN_NPU_BASE + SRCNN_REG_STATUS);
}

int SrcnnHw_SetTilePosition(u32 tile_x, u32 tile_y, u32 *readback)
{
    u32 tile_pos;
    u32 observed;

    if ((tile_x >= 16U) || (tile_y >= 16U) ||
        (readback == (u32 *)0)) {
        return -1;
    }

    tile_pos = ((tile_y & 0x0FU) << 4U)
             |  (tile_x & 0x0FU);

    Xil_Out32(
        SRCNN_NPU_BASE + SRCNN_REG_TILE_POS,
        tile_pos
    );

    observed = Xil_In32(SRCNN_NPU_BASE + SRCNN_REG_TILE_POS);
    *readback = observed;

    return (observed == tile_pos) ? 0 : -2;
}

void SrcnnHw_WriteInputLe(const u8 input[SRCNN_INPUT_BYTES])
{
    u32 i;
    for (i = 0U; i < SRCNN_INPUT_PIXELS; ++i) {
        u32 bits = (u32)input[2U * i] | ((u32)input[2U * i + 1U] << 8U);
        Xil_Out32(SRCNN_INPUT_BRAM_BASE + (i << 2U), bits);
    }
}

int SrcnnHw_Run(u32 *cycle_count, u32 *final_status)
{
    u64 deadline;
    u32 status;

    Xil_Out32(SRCNN_NPU_BASE + SRCNN_REG_CTRL, SRCNN_CTRL_CLEAR);
    Xil_Out32(SRCNN_NPU_BASE + SRCNN_REG_CTRL, SRCNN_CTRL_START);
    deadline = SrcnnTime_DeadlineMs(SRCNN_NPU_TIMEOUT_MS);

    do {
        status = SrcnnHw_Status();
        if ((status & SRCNN_STATUS_DONE) != 0U) {
            *cycle_count = Xil_In32(SRCNN_NPU_BASE + SRCNN_REG_CYCLE_COUNT);
            *final_status = status;
            return ((status & SRCNN_STATUS_ERROR) == 0U) ? 0 : -2;
        }
    } while (!SrcnnTime_Expired(deadline));

    *cycle_count = Xil_In32(SRCNN_NPU_BASE + SRCNN_REG_CYCLE_COUNT);
    *final_status = SrcnnHw_Status();
    return -1;
}

void SrcnnHw_ReadCenterLe(u8 output[SRCNN_OUTPUT_BYTES])
{
    u32 y;
    u32 x;
    u32 index = 0U;

    for (y = 8U; y < 24U; ++y) {
        for (x = 8U; x < 24U; ++x) {
            u32 pixel_address = y * 32U + x;
            u16 pixel;
            Xil_Out32(SRCNN_NPU_BASE + SRCNN_REG_FINAL_ADDR, pixel_address);
            pixel = (u16)(Xil_In32(SRCNN_NPU_BASE + SRCNN_REG_FINAL_DATA) & 0xFFFFU);
            output[index++] = (u8)(pixel & 0xFFU);
            output[index++] = (u8)(pixel >> 8U);
        }
    }
}
