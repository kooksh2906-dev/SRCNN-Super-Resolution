#ifndef SRCNN_HW_H
#define SRCNN_HW_H

#include "xil_types.h"
#include "xparameters.h"

#define SRCNN_INPUT_PIXELS       1024U
#define SRCNN_INPUT_BYTES        (SRCNN_INPUT_PIXELS * 2U)
#define SRCNN_OUTPUT_PIXELS      256U
#define SRCNN_OUTPUT_BYTES       (SRCNN_OUTPUT_PIXELS * 2U)

#define SRCNN_INPUT_BRAM_BASE    XPAR_AXI_BRAM_CTRL_0_BASEADDR
#define SRCNN_NPU_BASE           XPAR_AXI4_SRCNN_NPU_0_BASEADDR

#define SRCNN_REG_CTRL           0x00U
#define SRCNN_REG_STATUS         0x04U
#define SRCNN_REG_FINAL_ADDR     0x08U
#define SRCNN_REG_FINAL_DATA     0x0CU
#define SRCNN_REG_CYCLE_COUNT    0x10U
#define SRCNN_REG_VERSION        0x1CU
#define SRCNN_REG_TILE_POS       0x20U

#define SRCNN_CTRL_START         0x00000001U
#define SRCNN_CTRL_CLEAR         0x00000002U
#define SRCNN_STATUS_DONE        0x00000002U
#define SRCNN_STATUS_ERROR       0x00000004U
#define SRCNN_EXPECTED_VERSION   0x00010001U

#define SRCNN_NPU_TIMEOUT_MS     1000U

u32 SrcnnHw_Version(void);
u32 SrcnnHw_Status(void);
int SrcnnHw_SetTilePosition(u32 tile_x, u32 tile_y, u32 *readback);
void SrcnnHw_WriteInputLe(const u8 input[SRCNN_INPUT_BYTES]);
int SrcnnHw_Run(u32 *cycle_count, u32 *final_status);
void SrcnnHw_ReadCenterLe(u8 output[SRCNN_OUTPUT_BYTES]);

#endif
