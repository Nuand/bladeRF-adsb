#ifndef __ADSB_H_
#define __ADSB_H_

#include "cnutil.h"



#define SPS 8
#define POWER_SAMPLE_SIZE (sizoef(int16_t))

#define PREAMBLE_LENGTH 16
#define DF_LENGTH 5
#define CA_LENGTH 3
#define ADDR_LENGTH 24
#define EXTENDED_FIELD_LENGTH 56
#define CRC_LENGTH 24

#define SHORT_MESSAGE_LENGTH (DF_LENGTH + CA_LENGTH + ADDR_LENGTH + CRC_LENGTH)
#define EXTENDED_MESSAGE_LENGTH (DF_LENGTH + CA_LENGTH + ADDR_LENGTH + EXTENDED_FIELD_LENGTH + CRC_LENGTH)

#define POWER_THRESHOLD 100
#define EDGE_POWER_THRESHOLD 20
#define EDGE_RATIO 1

#define SAMPLE_WINDOW 5
#define RCD_LENGTH ((PREAMBLE_LENGTH*SPS + EXTENDED_MESSAGE_LENGTH*SPS)*2 + 9)
#define EDGE_DETECTION_INDEX ((PREAMBLE_LENGTH*SPS + EXTENDED_MESSAGE_LENGTH*SPS)*2 + 4)


typedef struct
{
    uint32_t sd_remaining;
    uint16_t sd_buffer[EXTENDED_MESSAGE_LENGTH*SPS];
    int16_t *sd_current;
    uint16_t msg_type;
    uint8_t *data;
}message_t;

void init(uint8_t enable_filter, uint8_t enable_mix);


message_t* rx(c16_t *in_sample);

void print_stats();

#endif