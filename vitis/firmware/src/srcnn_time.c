#include "srcnn_time.h"

#include "xil_io.h"

#ifndef XPAR_GLOBAL_TMR_BASEADDR
#define XPAR_GLOBAL_TMR_BASEADDR 0xF8F00200U
#endif

#define GTIMER_COUNTER_LOWER_OFFSET 0x00U
#define GTIMER_COUNTER_UPPER_OFFSET 0x04U
#define GTIMER_CONTROL_OFFSET       0x08U

void SrcnnTime_Init(void)
{
    u32 control = Xil_In32(XPAR_GLOBAL_TMR_BASEADDR + GTIMER_CONTROL_OFFSET);
    if ((control & 1U) == 0U) {
        Xil_Out32(XPAR_GLOBAL_TMR_BASEADDR + GTIMER_CONTROL_OFFSET, control | 1U);
    }
}

u64 SrcnnTime_Now(void)
{
    u32 high_before;
    u32 low;
    u32 high_after;

    do {
        high_before = Xil_In32(XPAR_GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_UPPER_OFFSET);
        low = Xil_In32(XPAR_GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_LOWER_OFFSET);
        high_after = Xil_In32(XPAR_GLOBAL_TMR_BASEADDR + GTIMER_COUNTER_UPPER_OFFSET);
    } while (high_before != high_after);

    return ((u64)high_before << 32) | (u64)low;
}

u64 SrcnnTime_DeadlineMs(u32 milliseconds)
{
    u64 ticks = (SRCNN_TIMER_COUNTS_PER_SECOND * (u64)milliseconds) / 1000ULL;
    return SrcnnTime_Now() + ticks;
}

int SrcnnTime_Expired(u64 deadline)
{
    return ((s64)(SrcnnTime_Now() - deadline) >= 0) ? 1 : 0;
}
