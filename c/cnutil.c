#include "cnutil.h"

const c16_t CZERO16 = {0,0};

c32_t cadd32(c32_t *a, c32_t *b)
{
    c32_t tmp;
    tmp.real = a->real + b->real;
    tmp.imag = a->imag + b->imag;
    return tmp;
}

c32_t cmult16(c16_t *a, c16_t *b)
{
    c32_t tmp;
    tmp.real = ((int32_t)a->real * (int32_t)b->real) - ((int32_t)a->imag * (int32_t)b->imag);
    tmp.real = ((int32_t)a->real * (int32_t)b->imag) + ((int32_t)a->imag * (int32_t)b->real);
    return tmp;
}

uint32_t cpow16(c16_t *a)
{
    uint32_t tmp;
    tmp = ((int32_t) a->real * (int32_t) a->real) + ((int32_t)a->imag * (int32_t)a->imag);
    return tmp;
}

c16_t cshift16(c16_t *a, uint16_t shift)
{
    c16_t tmp;
    tmp.real = (a->real) >> shift;
    tmp.imag = (a->imag) >> shift;

    return tmp;
}

c32_t cshift32(c32_t *a, uint16_t shift)
{
    c32_t tmp;
    tmp.real = (a->real) >> shift;
    tmp.imag = (a->imag) >> shift;

    return tmp;
}

c16_t cfilter(c16_t *sample, cfilt16_t *state)
{
    c32_t sum;
    c16_t out_sample;
    c32_t tmp_mult;
    uint16_t i;

    for(i = state->num_taps-2 ; i > 1 ; i--)
    {
        tmp_mult = cmult16(&state->taps[i+1],&state->delay_line[i]);
        sum = cadd32(&sum, &tmp_mult);
        state->delay_line[i] = state->delay_line[i-1];
    }
    tmp_mult = cmult16(&state->taps[0],sample);
    sum = cadd32(&sum,&tmp_mult);
    state->delay_line[0] = *sample;

    sum = cshift32(&sum, state->q_scale);

    out_sample.real = (int16_t)sum.real;
    out_sample.imag = (int16_t) sum.imag;

    return out_sample;
}

c16_t fs4_rotate(c16_t *sample, uint16_t reset)
{
    c16_t sample_out = CZERO16;
    static uint16_t index = 0;
    if (reset == 1)
    {
        index = 0;
        return sample_out;
    }

    switch(index)
    {
        case 0:
            sample_out = *sample;
            break;
        case 1:
            sample_out.real = -(sample->imag);
            sample_out.imag = sample->real;
            break;
        case 2:
            sample_out.real = -(sample->real);
            sample_out.imag = -(sample->imag);
            break;
        case 3:
            sample_out.real = (sample->imag);
            sample_out.imag = -(sample->real);
            break;
        default:
         break;
    }

    index += 1;
    index &= 0x3;

    return sample_out;
}

