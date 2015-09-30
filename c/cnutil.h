#ifndef __CMULT_H_
#define __CMULT_H_

#include <stdint.h>



typedef struct  
{
	int16_t real;
	int16_t imag;
}c16_t;

typedef struct 
{
	int32_t real;
	int32_t imag;
}c32_t;


typedef struct 
{
	/* data */
	uint32_t num_taps;
	uint16_t q_scale;
	c16_t * taps;
	c16_t * delay_line;
}cfilt16_t;

c32_t cmult16(c16_t *a, c16_t *b);


uint32_t cpow16(c16_t *a);


c16_t cshift16(c16_t *a, uint16_t shift);
c32_t cshift32(c32_t *a, uint16_t shift);


c16_t cfilter(c16_t *sample, cfilt16_t *state);

c16_t fs4_rotate(c16_t *sample, uint16_t reset);

#endif