#include <stddef.h>

#include "srcnn_uart.h"

#include "xparameters.h"
#include "xuartps.h"
#include "xuartps_hw.h"

#ifndef XPAR_XUARTPS_0_BASEADDR
#define XPAR_XUARTPS_0_BASEADDR 0xE0001000U
#endif

static XUartPs gUart;

int SrcnnUart_Init(void)
{
    XUartPs_Config *config;
    int status;

#ifdef SDT
    config = XUartPs_LookupConfig((UINTPTR)XPAR_XUARTPS_0_BASEADDR);
#else
    config = XUartPs_LookupConfig(XPAR_XUARTPS_0_DEVICE_ID);
#endif
    if (config == NULL) {
        return XST_FAILURE;
    }

    status = XUartPs_CfgInitialize(&gUart, config, config->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }
    XUartPs_SetOperMode(&gUart, XUARTPS_OPER_MODE_NORMAL);
    return XUartPs_SetBaudRate(&gUart, SRCNN_UART_BAUD);
}

int SrcnnUart_TryReceive(u8 *byte)
{
    if (!XUartPs_IsReceiveData(gUart.Config.BaseAddress)) {
        return 0;
    }
    *byte = (u8)XUartPs_ReadReg(gUart.Config.BaseAddress, XUARTPS_FIFO_OFFSET);
    return 1;
}

u8 SrcnnUart_ReceiveBlocking(void)
{
    u8 byte;
    while (!SrcnnUart_TryReceive(&byte)) {
    }
    return byte;
}

void SrcnnUart_Send(const u8 *data, u32 length)
{
    u32 i;
    for (i = 0U; i < length; ++i) {
        XUartPs_SendByte(gUart.Config.BaseAddress, data[i]);
    }
}
