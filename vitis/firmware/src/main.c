#include <stddef.h>

#include "srcnn_crc32.h"
#include "srcnn_hw.h"
#include "srcnn_time.h"
#include "srcnn_uart.h"
#include "xstatus.h"

#define PROTOCOL_VERSION       1U
#define COMMAND_PROCESS_TILE   1U
#define COMMAND_PING           2U

#define REQUEST_HEADER_BYTES   20U
#define RESPONSE_HEADER_BYTES  28U
#define UART_FRAME_TIMEOUT_MS  5000U

#define RESPONSE_OK            0U
#define RESPONSE_BAD_VERSION   1U
#define RESPONSE_BAD_COMMAND   2U
#define RESPONSE_BAD_LENGTH    3U
#define RESPONSE_BAD_CRC       4U
#define RESPONSE_RX_TIMEOUT    5U
#define RESPONSE_NPU_TIMEOUT   6U
#define RESPONSE_NPU_ERROR     7U
#define RESPONSE_HW_VERSION    8U
#define RESPONSE_BAD_TILE_POSITION 9U
#define RESPONSE_TILE_POS_IO   10U

typedef struct {
    u8 version;
    u8 command;
    u8 tile_x;
    u8 tile_y;
    u32 sequence;
    u32 payload_length;
    u32 payload_crc32;
} Request;

static u8 gInput[SRCNN_INPUT_BYTES];
static u8 gOutput[SRCNN_OUTPUT_BYTES];

static u32 ReadLe32(const u8 *source)
{
    return (u32)source[0]
        | ((u32)source[1] << 8U)
        | ((u32)source[2] << 16U)
        | ((u32)source[3] << 24U);
}

static void WriteLe32(u8 *destination, u32 value)
{
    destination[0] = (u8)(value & 0xFFU);
    destination[1] = (u8)((value >> 8U) & 0xFFU);
    destination[2] = (u8)((value >> 16U) & 0xFFU);
    destination[3] = (u8)((value >> 24U) & 0xFFU);
}

static int ReceiveExact(u8 *destination, u32 length, u32 timeout_ms)
{
    u64 deadline = SrcnnTime_DeadlineMs(timeout_ms);
    u32 received = 0U;

    while (received < length) {
        if (SrcnnUart_TryReceive(&destination[received])) {
            ++received;
        } else if (SrcnnTime_Expired(deadline)) {
            return -1;
        }
    }
    return 0;
}

static void WaitForRequestMagic(void)
{
    static const u8 magic[4] = {'S', 'R', 'Q', '1'};
    u32 matched = 0U;

    while (matched < 4U) {
        u8 byte = SrcnnUart_ReceiveBlocking();
        if (byte == magic[matched]) {
            ++matched;
        } else {
            matched = (byte == magic[0]) ? 1U : 0U;
        }
    }
}

static int ReceiveRequest(Request *request)
{
    u8 rest[REQUEST_HEADER_BYTES - 4U];

    WaitForRequestMagic();
    if (ReceiveExact(rest, sizeof(rest), UART_FRAME_TIMEOUT_MS) != 0) {
        return -1;
    }
    request->version = rest[0];
    request->command = rest[1];
    request->tile_x = rest[2];
    request->tile_y = rest[3];
    request->sequence = ReadLe32(&rest[4]);
    request->payload_length = ReadLe32(&rest[8]);
    request->payload_crc32 = ReadLe32(&rest[12]);
    return 0;
}

static void SendResponse(
    u8 response_status,
    u8 command,
    u32 sequence,
    const u8 *payload,
    u32 payload_length,
    u32 cycle_count,
    u32 npu_status)
{
    u8 header[RESPONSE_HEADER_BYTES];
    u32 payload_crc = (payload_length == 0U) ? 0U : SrcnnCrc32(payload, payload_length);

    header[0] = 'S';
    header[1] = 'R';
    header[2] = 'S';
    header[3] = '1';
    header[4] = PROTOCOL_VERSION;
    header[5] = response_status;
    header[6] = command;
    header[7] = 0U;
    WriteLe32(&header[8], sequence);
    WriteLe32(&header[12], payload_length);
    WriteLe32(&header[16], payload_crc);
    WriteLe32(&header[20], cycle_count);
    WriteLe32(&header[24], npu_status);

    SrcnnUart_Send(header, sizeof(header));
    if (payload_length != 0U) {
        SrcnnUart_Send(payload, payload_length);
    }
}

static void HandlePing(const Request *request)
{
    u8 version_payload[4];
    u32 version = SrcnnHw_Version();
    WriteLe32(version_payload, version);
    SendResponse(
        (version == SRCNN_EXPECTED_VERSION) ? RESPONSE_OK : RESPONSE_HW_VERSION,
        request->command,
        request->sequence,
        version_payload,
        sizeof(version_payload),
        0U,
        SrcnnHw_Status());
}

static void HandleProcessTile(const Request *request)
{
    u32 cycles = 0U;
    u32 npu_status = 0U;
    u32 tile_pos_readback = 0U;
    int run_status;
    int tile_pos_status;

    if (request->payload_length != SRCNN_INPUT_BYTES) {
        SendResponse(RESPONSE_BAD_LENGTH, request->command, request->sequence,
                     NULL, 0U, 0U, SrcnnHw_Status());
        return;
    }
    if (ReceiveExact(gInput, SRCNN_INPUT_BYTES, UART_FRAME_TIMEOUT_MS) != 0) {
        SendResponse(RESPONSE_RX_TIMEOUT, request->command, request->sequence,
                     NULL, 0U, 0U, SrcnnHw_Status());
        return;
    }
    if (SrcnnCrc32(gInput, SRCNN_INPUT_BYTES) != request->payload_crc32) {
        SendResponse(RESPONSE_BAD_CRC, request->command, request->sequence,
                     NULL, 0U, 0U, SrcnnHw_Status());
        return;
    }
    if (SrcnnHw_Version() != SRCNN_EXPECTED_VERSION) {
        SendResponse(RESPONSE_HW_VERSION, request->command, request->sequence,
                     NULL, 0U, 0U, SrcnnHw_Status());
        return;
    }

    tile_pos_status = SrcnnHw_SetTilePosition(
        (u32)request->tile_x,
        (u32)request->tile_y,
        &tile_pos_readback);
    if (tile_pos_status == -1) {
        SendResponse(RESPONSE_BAD_TILE_POSITION, request->command,
                     request->sequence, NULL, 0U, 0U,
                     SrcnnHw_Status());
        return;
    }
    if (tile_pos_status != 0) {
        SendResponse(RESPONSE_TILE_POS_IO, request->command,
                     request->sequence, NULL, 0U, 0U,
                     SrcnnHw_Status());
        return;
    }

    SrcnnHw_WriteInputLe(gInput);
    run_status = SrcnnHw_Run(&cycles, &npu_status);
    if (run_status == -1) {
        SendResponse(RESPONSE_NPU_TIMEOUT, request->command, request->sequence,
                     NULL, 0U, cycles, npu_status);
        return;
    }
    if (run_status != 0) {
        SendResponse(RESPONSE_NPU_ERROR, request->command, request->sequence,
                     NULL, 0U, cycles, npu_status);
        return;
    }

    SrcnnHw_ReadCenterLe(gOutput);
    SendResponse(RESPONSE_OK, request->command, request->sequence,
                 gOutput, SRCNN_OUTPUT_BYTES, cycles, npu_status);
}

int main(void)
{
    SrcnnTime_Init();
    if (SrcnnUart_Init() != XST_SUCCESS) {
        for (;;) {
        }
    }

    for (;;) {
        Request request;
        if (ReceiveRequest(&request) != 0) {
            continue;
        }
        if (request.version != PROTOCOL_VERSION) {
            SendResponse(RESPONSE_BAD_VERSION, request.command, request.sequence,
                         NULL, 0U, 0U, SrcnnHw_Status());
        } else if (request.command == COMMAND_PING) {
            if (request.payload_length == 0U) {
                HandlePing(&request);
            } else {
                SendResponse(RESPONSE_BAD_LENGTH, request.command, request.sequence,
                             NULL, 0U, 0U, SrcnnHw_Status());
            }
        } else if (request.command == COMMAND_PROCESS_TILE) {
            HandleProcessTile(&request);
        } else {
            SendResponse(RESPONSE_BAD_COMMAND, request.command, request.sequence,
                         NULL, 0U, 0U, SrcnnHw_Status());
        }
    }
}
