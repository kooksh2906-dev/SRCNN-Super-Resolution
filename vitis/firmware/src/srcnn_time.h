#ifndef SRCNN_TIME_H
#define SRCNN_TIME_H

#include "xil_types.h"

#define SRCNN_TIMER_COUNTS_PER_SECOND 333333343ULL

void SrcnnTime_Init(void);
u64 SrcnnTime_Now(void);
u64 SrcnnTime_DeadlineMs(u32 milliseconds);
int SrcnnTime_Expired(u64 deadline);

#endif
