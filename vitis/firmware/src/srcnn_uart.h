#ifndef SRCNN_UART_H
#define SRCNN_UART_H

#include "xil_types.h"
#include "xstatus.h"

#ifndef SRCNN_UART_BAUD
#define SRCNN_UART_BAUD 115200U
#endif

int SrcnnUart_Init(void);
int SrcnnUart_TryReceive(u8 *byte);
u8 SrcnnUart_ReceiveBlocking(void);
void SrcnnUart_Send(const u8 *data, u32 length);

#endif
