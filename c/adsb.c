
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include "adsb.h"



//crc polynomial   24 23 22 21 20 19 18 17 16 15 14 13 10 3 1
//[ 1 1 1 1 1 1 1 1 1 1 1 1 1 0 1 0 0 0 0 0 0 1 0 0 1]
const uint32_t CRC_POLY = 0x00FFF409;
//const uint32_t CRC_POLY = 0x902FFF00;
uint32_t CRC_LUT[256];

void init_crc_lut(){
  uint32_t i,j;
  uint32_t crc;

  for(i = 0; i < 256; i++){
    crc = i << 16;
    for(j = 0; j < 8; j++){
      if(crc & 0x800000){
        crc = ((crc << 1) ^ CRC_POLY) & 0xffffff;
      }
      else{
        crc  = (crc << 1) & 0xffffff;
      }

    }
    CRC_LUT[i] = crc & 0xffffff;
  }
}

uint32_t check_crc(uint8_t *msg, uint32_t length){
  uint32_t i;
  uint32_t crc=0;
  for(i = 0; i < length; i++){
    crc = CRC_LUT[ ((crc >> 16) ^ msg[i]) & 0xff] ^ (crc << 8);
  }
  return crc &0xffffff;
}


const uint8_t WEIGHTS[SPS] = { 1, 1 ,2, 2, 2, 2, 1, 1 } ;

double bb_h_filt[] = {
  -0.000216247569686,
  -0.000020724358659,
   0.000123766030519,
   0.000318482422536,
   0.000456463780913,
   0.000415041799656,
   0.000124323884803,
  -0.000368199608286,
  -0.000876954712595,
  -0.001130575705366,
  -0.000892166593419,
  -0.000103306549465,
   0.001022007654987,
   0.002020458262442,
   0.002342720046275,
   0.001612248911395,
  -0.000129358168311,
  -0.002321556391756,
  -0.004020043390952,
  -0.004262395933029,
  -0.002538656106627,
   0.000841820235738,
   0.004692674044728,
   0.007304733049356,
   0.007137767524445,
   0.003594115605862,
  -0.002478216415413,
  -0.008847746093807,
  -0.012620455755530,
  -0.011431850349189,
  -0.004652151489444,
   0.005928945775480,
   0.016360799223919,
   0.021805836336930,
   0.018479917160421,
   0.005561084359393,
  -0.013734999696855,
  -0.032495397736209,
  -0.041966304256972,
  -0.034433198103896,
  -0.006176262454164,
   0.040586302435419,
   0.097582796450275,
   0.152409921101041,
   0.191978580808684,
   0.206393968476306,
   0.191978580808684,
   0.152409921101041,
   0.097582796450275,
   0.040586302435419,
  -0.006176262454164,
  -0.034433198103896,
  -0.041966304256972,
  -0.032495397736209,
  -0.013734999696855,
   0.005561084359393,
   0.018479917160421,
   0.021805836336930,
   0.016360799223919,
   0.005928945775480,
  -0.004652151489444,
  -0.011431850349189,
  -0.012620455755530,
  -0.008847746093807,
  -0.002478216415413,
   0.003594115605862,
   0.007137767524445,
   0.007304733049356,
   0.004692674044728,
   0.000841820235738,
  -0.002538656106627,
  -0.004262395933029,
  -0.004020043390952,
  -0.002321556391756,
  -0.000129358168311,
   0.001612248911395,
   0.002342720046275,
   0.002020458262442,
   0.001022007654987,
  -0.000103306549465,
  -0.000892166593419,
  -0.001130575705366,
  -0.000876954712595,
  -0.000368199608286,
   0.000124323884803,
   0.000415041799656,
   0.000456463780913,
   0.000318482422536,
   0.000123766030519,
  -0.000020724358659,
  -0.000216247569686
};


struct adsb_state
{
    cfilt16_t rx_filt;


    uint32_t low_if;
    uint32_t bb_filt;
    uint64_t samples_consumed;
    uint32_t preambles_detected;
    uint32_t discard_count;
    uint32_t messages_rxd;
    uint32_t brute_forced_count;

    uint32_t rcd_buffer[RCD_LENGTH];
    uint8_t leading_edges[RCD_LENGTH];
    uint8_t falling_edges[RCD_LENGTH];

    uint32_t active_message_count;

    message_t *active_message_buffers[16];
    uint32_t num_active_message_buffers;

    message_t *pending_message_buffers[16];
    uint32_t num_pending_message_buffers;


} current_state;




extern uint8_t known_msg[];


void init( uint8_t enable_filter, uint8_t enable_mix)
{
    uint32_t i;
    current_state.samples_consumed = 0;
    current_state.preambles_detected = 0;
    current_state.messages_rxd = 0;
    current_state.discard_count = 0;
    current_state.brute_forced_count = 0;

    current_state.low_if = enable_mix;
    current_state.bb_filt = enable_filter;

    memset(current_state.rcd_buffer,0,sizeof(current_state.rcd_buffer[0])*RCD_LENGTH);
    memset(current_state.leading_edges,0,sizeof(current_state.leading_edges[0])*RCD_LENGTH);
    //memset(current_state.falling_edges,0,sizeof(current_state.falling_edges[0]*RCD_LENGTH));

    current_state.num_active_message_buffers = 16;
    for (i = 0; i < current_state.num_active_message_buffers; i++){
        current_state.active_message_buffers[i] = NULL;
    }


    current_state.num_pending_message_buffers = 16;
    for (i = 0; i < current_state.num_pending_message_buffers; i++){
        current_state.pending_message_buffers[i] = NULL;
    }

    //initialize the bb filt
    current_state.rx_filt.num_taps = sizeof(bb_h_filt)/sizeof(double);
    current_state.rx_filt.q_scale = 12;
    current_state.rx_filt.taps = malloc(current_state.rx_filt.num_taps *sizeof(c16_t));
    current_state.rx_filt.delay_line = malloc(current_state.rx_filt.num_taps *sizeof(c16_t));

    for(i = 0; i < current_state.rx_filt.num_taps; i++){
      current_state.rx_filt.taps[i].real  = (int16_t)(bb_h_filt[i] * (1 << current_state.rx_filt.q_scale));
      current_state.rx_filt.taps[i].imag  = (int16_t)(bb_h_filt[i] * (1 << current_state.rx_filt.q_scale));
    }
    memset(current_state.rx_filt.delay_line,0, sizeof(c16_t) * current_state.rx_filt.num_taps);


    init_crc_lut();
}

static inline void flipbit(uint8_t *buffer, uint32_t bit_loc ){
  buffer[bit_loc >> 4] ^= (1 << (bit_loc & 0x7));
}

uint32_t brute_force(int32_t *bsd, uint8_t *msg_bits,uint32_t msg_length){
uint32_t i,j,k,l;

  uint32_t rx_crc_e = 0;
  //determine the location of the 5 weakest bits
  int32_t weak_val[5] = {0,0,0,0,0};
  uint32_t weak_loc[5] = {0,0,0,0,0};

  int16_t weak_count = 1;//always start witht he weakest sd


  //
  uint32_t cur_min = abs(bsd[0]);
  weak_val[0] = cur_min;
  weak_loc[0] = 0;

  for(i = 1; i < msg_length; i++)
  {
    //if it's greater than the current min threshold, check to see if we've found
    //5 min yet, if we haven't add it to the list and update the min, if we've found
    //5 skip this sample
    if(abs(bsd[i]) >=  cur_min){

      if(weak_count < 5){
        weak_loc[weak_count] = i;
        weak_val[weak_count] = abs(bsd[i]);
        ++weak_count;
        cur_min = abs(bsd[i]);
      }
    }else{
      //if it's lower, check if we've found 5 min, if 5havent been found yet add it

      if(weak_count < 5){
        weak_loc[weak_count] = i;
        weak_val[weak_count] = abs(bsd[i]);
        ++weak_count;
      }
      //else remove the current largeest value in the 5 weakest list
      else{

        uint32_t max = 0;
        uint32_t max_loc = 0;
        //replace the largest
        for(j = 0; j < 5; j++){
            if(weak_val[j] > max){
              max = weak_val[j];
              max_loc = j;
            }
        }

        weak_val[max_loc] = abs(bsd[i]);
        weak_loc[max_loc] = i;
        cur_min = abs(bsd[i]);
      }
    }
  }


  //at this point we have the 5 weakest sd and their location
  //attempt the various flipped permutations to see if the crc passes
  for(i = 0; i < 2; i++)
  {
    for(j = 0; j <  2; j++){

      for(k = 0; k < 2; k++){
      //flip bit 5 and recalc

        for(l = 0; l < 2; l++){
          flipbit(msg_bits,weak_loc[4]);
          uint32_t calc_crc = check_crc(msg_bits, msg_length/8 -3);
          uint32_t rx_crc = (msg_bits[msg_length/8 -3] << 16) | (msg_bits[msg_length/8-2] << 8) | msg_bits[msg_length/8-1];

          if( !(rx_crc ^ calc_crc) && (rx_crc != 0)){
            return 1;
          }

          flipbit(msg_bits,weak_loc[4]);
          calc_crc = check_crc(msg_bits, msg_length/8 -3);
          rx_crc = (msg_bits[msg_length/8 -3] << 16) | (msg_bits[msg_length/8 -2] << 8) | msg_bits[msg_length/8-1];

          if( !(rx_crc ^ calc_crc)  && (rx_crc != 0) ){
            return 1;
          }


          flipbit(msg_bits,weak_loc[3]);
        }
        flipbit(msg_bits,weak_loc[2]);
      }
      flipbit(msg_bits,weak_loc[1]);

    }
    flipbit(msg_bits,weak_loc[0]);
  }


  return 0;
}



message_t* rx(c16_t *in_sample)
{
    uint32_t i,j,preamble_detected=0;
    message_t *completed_message = NULL;
    c16_t samp_bb ;

    if(current_state.low_if){
    //mix to baseband
    samp_bb = fs4_rotate(in_sample,0);
    }
    else{
        samp_bb = *in_sample;
    }


    c16_t samp_filt;
    if(current_state.bb_filt){
    //run the filter

    samp_filt = cfilter(&samp_bb, &current_state.rx_filt);
    }
    else{
        samp_filt = samp_bb;
    }
    //input sample is q12, output is now power at q24
    uint32_t samp_powq24 = cpow16(&samp_filt);

    //rescale power to q12

    uint32_t samp_pow = samp_powq24 >> 0;
    //printf("samp %d %d pow %d \n",samp_filt.real,samp_filt.imag, samp_powq24);

    current_state.samples_consumed++;

    for(i = 0; i < RCD_LENGTH-1; i++)
    {
        current_state.rcd_buffer[i] = current_state.rcd_buffer[i+1];
        current_state.leading_edges[i] = current_state.leading_edges[i+1];
#ifdef FALLING_EDGE_SEARCh
        current_state.falling_edges[i] = current_state.rcd_buffer[i+1];
#endif
    }
    current_state.rcd_buffer[RCD_LENGTH-1] = samp_pow;
    current_state.leading_edges[RCD_LENGTH-1] = 0;

    uint32_t count = 0;
    uint32_t center_sample = current_state.rcd_buffer[EDGE_DETECTION_INDEX];
    //edge detection routine
    for(i = 0; i < 5; i++){
        if( current_state.rcd_buffer[EDGE_DETECTION_INDEX + i] > POWER_THRESHOLD ){
            count++;
        }
    }

    //ifthe 5 samples past the center point exceeds
    //the threshold then find if the current sample is larger
    //the previous and subsequent
    if(count >= 5)
    {
        uint32_t prior_sample = current_state.rcd_buffer[EDGE_DETECTION_INDEX-1];
        uint32_t prior_ratio = center_sample/(prior_sample+1);
        uint32_t subsequent_sample =current_state.rcd_buffer[EDGE_DETECTION_INDEX+1];
        uint32_t subsequent_ratio = center_sample/(subsequent_sample+1);


/*        if( ( prior_ratio >= 1 ) &&
            ( subsequent_ratio < 1)) {
            current_state.leading_edges[EDGE_DETECTION_INDEX] = 1;
        }*/

            if( (center_sample >= (prior_sample) ) && (center_sample < (subsequent_sample+1) )){
            current_state.leading_edges[EDGE_DETECTION_INDEX] = 1;

            }
/*        printf(" %" PRIu64" edge %d count detected %d %d %d, ratio %d/%d\n",
            current_state.samples_consumed,
            current_state.leading_edges[EDGE_DETECTION_INDEX],
            current_state.rcd_buffer[EDGE_DETECTION_INDEX-1],
            center_sample,
            current_state.rcd_buffer[EDGE_DETECTION_INDEX+1],
            prior_ratio,
            subsequent_ratio );*/
    }


#ifdef FALLING_EDGE_SEARCH
    count = 0;
    //edge detection routine
    for(i = 0; i < 5; i++){
        if( current_state.edge_buffer[i] > POWER_THRESHOLD ){
            count++;
        }
    }
    //ifthe 5 samples past the center point exceeds
    //the threshold then find if the current sample is larger
    //the previous and subsequent
    if(count == 5)
    {
        if( ((current_state.rcd_buffer[4-1]/center_sample) >  EDGE_RATIO) &&
            ((current_state.rcd_buffer[4+1]/center_sample) <  EDGE_RATIO t)){
            current_state.falling_edges[4] = 1;
        }
    }
#endif


    //preamble detection
        //preamble is 8us long with 4 active PPM periods from:
        // 0.0:0.5 usec, samples 0:1*SPS-1
        // 1.0:1.5 usec, samples 2*SPS:3*SPS-1
        // 3.5:4.0 usec, samples 7*SPS:8*SPS
        // 4.5:5.0 usec  samples 9*SPS:10*SPS-1

        //if the sum in those 4 sample regions exceeds the threshold
        //and there were leading edges detected there then a preamble has been
        //detected
    uint32_t i0_sum = 0;
    uint32_t i1_sum = 0;
    uint32_t i2_sum = 0;
    uint32_t i3_sum = 0;


    uint32_t max_b0 = 0;
    uint32_t max_b1 = 0;
    uint32_t max_b2 = 0;
    uint32_t max_b3 = 0;

    for(i = 0; i < SAMPLE_WINDOW; i++){
        i0_sum += current_state.rcd_buffer[i];
        i1_sum += current_state.rcd_buffer[2*SPS + i];
        i2_sum += current_state.rcd_buffer[7*SPS + i];
        i3_sum += current_state.rcd_buffer[9*SPS + i];


        //determine a reference power level for the 4 asserted preamble bits
      //do this while looping over the samples for the preamble detection
          if( current_state.rcd_buffer[i] > max_b0){
            max_b0 = current_state.rcd_buffer[i];
          }
          if( current_state.rcd_buffer[2*SPS  + i] > max_b1){
            max_b1 = current_state.rcd_buffer[2*SPS  + i];
          }
          if( current_state.rcd_buffer[7*SPS  + i] > max_b2){
            max_b2 = current_state.rcd_buffer[7*SPS  + i];
          }
          if( current_state.rcd_buffer[9*SPS  + i] > max_b3){
            max_b3 = current_state.rcd_buffer[9*SPS  + i];
          }
    }

    if( (i0_sum > POWER_THRESHOLD) &&
        (i1_sum > POWER_THRESHOLD) &&
        (i2_sum > POWER_THRESHOLD) &&
        (i3_sum > POWER_THRESHOLD) &&
        ( (current_state.leading_edges[0]  +
            current_state.leading_edges[2*SPS] +
            current_state.leading_edges[7*SPS] +
            current_state.leading_edges[9*SPS]) > 1) ){
        preamble_detected = 1;

  /*   printf(" %" PRIu64" detected with %d %d %d %d - edges *%d %d *%d %d %d %d %d *%d %d *%d\n",
        current_state.samples_consumed,i0_sum,i1_sum,i2_sum,i3_sum,
         current_state.leading_edges[0],
            current_state.leading_edges[1*SPS],
            current_state.leading_edges[2*SPS],
            current_state.leading_edges[3*SPS],
            current_state.leading_edges[4*SPS],
            current_state.leading_edges[5*SPS],
            current_state.leading_edges[6*SPS],
            current_state.leading_edges[7*SPS],
            current_state.leading_edges[8*SPS],
            current_state.leading_edges[9*SPS]);*/
    }
    uint32_t rpl = max_b0 + max_b1 + max_b2 + max_b3;
    rpl >>= 2;


    //allocate enough memory for a new message
    // DF       - 5 bits
    // CA       - 3 bits
    // Addr     - 24 bits
    // Extended - 56 bits
    // CRC      - 24 bits

    //Short message total = 56 bits
    //Extended message total = 112 bits
    //always allocate enough memory for the extended message
    if(preamble_detected)
    {

      current_state.preambles_detected++;

      uint32_t means[4];
        // run the consistent power test
      means[0] = i0_sum >> 2;
      means[1] = i1_sum >> 2;
      means[2] = i2_sum >> 2;
      means[3] = i3_sum >> 2;


      uint32_t cpl_high = rpl + ((rpl>>1) + (rpl>>2)  );
      uint32_t cpl_low = rpl - ((rpl>>1) + (rpl>>2) );
      uint32_t cpl_lowlow = cpl_low >> 1 ;
      uint32_t cpl_count = 0;
      for (i = 0; i < 4; i ++)
      {
        //printf("mean %d cpl_low %d cpl_high %d\n", means[i],cpl_low,cpl_high);
        if( (means[i] >= cpl_low) && (cpl_high >= means[i]))
        {
          cpl_count++;
        }
      }

      if(cpl_count < 2){
        //discard preamble
        current_state.discard_count++;
        return NULL;
      }
      //end consistent power test


      //todo:implement DF validation

      //end DF validation


      uint32_t slice[EXTENDED_MESSAGE_LENGTH*SPS*2];
      memcpy( slice,
              &current_state.rcd_buffer[(PREAMBLE_LENGTH*SPS)-1],
              sizeof(uint32_t) * EXTENDED_MESSAGE_LENGTH*SPS*2 );

      //dump the state of the rcd buffer
      /*for(i = 0; i < SPS*(EXTENDED_MESSAGE_LENGTH + PREAMBLE_LENGTH); i++){
        printf("[%d] = %d\n",i, current_state.rcd_buffer[i]);
      }*/


      uint8_t *bits_e = malloc(EXTENDED_MESSAGE_LENGTH * sizeof(uint8_t));
      uint8_t *msg = malloc(EXTENDED_MESSAGE_LENGTH/8 * sizeof(uint8_t));
      int32_t bsd[EXTENDED_MESSAGE_LENGTH];

      int16_t typeA[2*SPS];
      int16_t typeB[2*SPS];
      //printf("populated slice! high %d low %d  count %d means %d %d %d %d\n",cpl_high,cpl_low,cpl_count, means[0],means[1],means[2],means[3]);


      for(i = 0; i < EXTENDED_MESSAGE_LENGTH*2; i += 2){
          uint32_t j;

          //compare all samples against the rpl
          for (j = 0 ; j< SPS*2; j++){
            if( (slice[(i*SPS)+j] > cpl_low) && (slice[(i*SPS)+j] < cpl_high)){
              typeA[j] = 1;
              typeB[j] = 0;
            }
            else if( slice[(i*SPS)+j] < cpl_lowlow ){
              typeA[j] = 0;
              typeB[j] = 1;
            } else{
              typeA[j] = 0;
              typeB[j] = 0;
            }
          }

          int32_t score1 = 0;
          int32_t score0 = 0;

          //weight the samples
          for(j = 0; j < SPS; j++){
            score1 += ((typeA[j]      * WEIGHTS[j]) - (typeA[j+SPS] *WEIGHTS[j]) - (typeB[j]     * WEIGHTS[j]) +  (typeB[j+SPS] *WEIGHTS[j]));
            score0 += ((typeA[j+SPS]  * WEIGHTS[j]) - (typeA[j]     *WEIGHTS[j]) - (typeB[j+SPS] * WEIGHTS[j]) +  (typeB[j]     *WEIGHTS[j]));
          }

 /*         printf("msg[%3d] = %2d %2d  slice - %4d %4d %4d %4d %4d %4d %4d %4d |  %4d %4d %4d %4d %4d %4d %4d %4d \n", i/2, score1,score0,
            slice[(i*SPS)+0],
            slice[(i*SPS)+1],
            slice[(i*SPS)+2],
            slice[(i*SPS)+3],
            slice[(i*SPS)+4],
            slice[(i*SPS)+5],slice[(i*SPS)+6],slice[(i*SPS)+7],slice[(i*SPS)+8],


            slice[(i*SPS)+9],
            slice[(i*SPS)+10],
            slice[(i*SPS)+11],
            slice[(i*SPS)+12],
            slice[(i*SPS)+13],
            slice[(i*SPS)+14],
            slice[(i*SPS)+15]
            );
          printf("\t\t  - %4d %4d %4d %4d %4d %4d %4d %4d |  %4d %4d %4d %4d %4d %4d %4d %4d \n",
            typeA[0],
            typeA[1],
            typeA[2],
            typeA[3],
            typeA[4],
            typeA[5],typeA[6],typeA[7],typeA[8],


            typeA[9],
            typeA[10],
            typeA[11],
            typeA[12],
            typeA[13],
            typeA[14],
            typeA[15]
            );

                    printf("\t\t  - %4d %4d %4d %4d %4d %4d %4d %4d |  %4d %4d %4d %4d %4d %4d %4d %4d \n",
            typeB[0],
            typeB[1],
            typeB[2],
            typeB[3],
            typeB[4],
            typeB[5],typeB[6],typeB[7],typeB[8],


            typeB[9],
            typeB[10],
            typeB[11],
            typeB[12],
            typeB[13],
            typeB[14],
            typeB[15]
            );*/

          bsd[i/2] = score1 - score0;
          if(score1 > score0) {
            bits_e[i/2] = 1;
          }
          else{
            bits_e[i/2] = 0;
          }

      }


      for(i = 0; i < EXTENDED_MESSAGE_LENGTH; i+=8){

        msg[ i/8 ] =  (bits_e[i + 0] << 7)
                      | (bits_e[i + 1] << 6)
                      | (bits_e[i + 2] << 5)
                      | (bits_e[i + 3] << 4)
                      | (bits_e[i + 4] << 3)
                      | (bits_e[i + 5] << 2)
                      | (bits_e[i + 6] << 1)
                      | (bits_e[i + 7] << 0);
        //printf("extended msg [%d] = 0x%x new_bit %d\n",i/8,msg_e[i/8],bits_e[i]);
      }

      //validate short crc
      uint32_t short_crc = check_crc(msg, SHORT_MESSAGE_LENGTH/8 - 3);
      //validate extended crc
      uint32_t extended_crc = check_crc(msg, EXTENDED_MESSAGE_LENGTH/8 -3);

      uint32_t rx_crc_e = 0;
      uint32_t rx_crc_s = 0;

      rx_crc_s = (msg[4] << 16) | (msg[5] << 8) | msg[6];
      rx_crc_e = (msg[11] << 16) | (msg[12] << 8) | msg[13];


      //if both crc's fail try the various permutations of the weakest sd bits
      if( !(extended_crc ^ rx_crc_e) && (rx_crc_e != 0)){
        //printf("CRC PASSED! %"PRIu64  " 0x%x\n", current_state.samples_consumed,rx_crc_e);
        current_state.messages_rxd++;


        completed_message = (message_t *)malloc(sizeof(message_t));
        completed_message->data = msg;
        completed_message->sd_remaining = SPS * EXTENDED_MESSAGE_LENGTH;
        completed_message->sd_current = completed_message->sd_buffer;
        completed_message->msg_size = 14;

        current_state.active_message_count += 1;
      }
      else if( !(short_crc ^ rx_crc_s) && (rx_crc_s != 0) ){
                current_state.messages_rxd++;


        completed_message = (message_t *)malloc(sizeof(message_t));
        completed_message->data = msg;
        completed_message->sd_remaining = SPS * SHORT_MESSAGE_LENGTH;
        completed_message->sd_current = completed_message->sd_buffer;
        completed_message->msg_size = 7;

        current_state.active_message_count += 1;
      }
      else{
 /*       if(rx_crc_e != 0){
          for(i = 0; i < 14; i++){
                    if(   (msg[i] ^ known_msg[i])  ){
                        //printf("in msg[%d] 0x%x 0x%x - 0x%x\n",i, msg[i],known_msg[i], known_msg[i] ^ msg[i]);
                    }
                }
        printf("CRC FAILED 0x%x 0x%x\n",rx_crc_e, extended_crc);
        }*/
        if(brute_force(bsd,msg,EXTENDED_MESSAGE_LENGTH)){
          completed_message = (message_t *)malloc(sizeof(message_t));

          completed_message->data = msg;
          completed_message->sd_remaining = SPS * EXTENDED_MESSAGE_LENGTH;
          completed_message->sd_current = completed_message->sd_buffer;
          completed_message->msg_size = 14;
          current_state.active_message_count += 1;
          current_state.brute_forced_count += 1;

        }else if (brute_force(bsd,msg,SHORT_MESSAGE_LENGTH)){
          current_state.messages_rxd++;

          completed_message = (message_t *)malloc(sizeof(message_t));
          completed_message->data = msg;
          completed_message->sd_remaining = SPS * SHORT_MESSAGE_LENGTH;
          completed_message->sd_current = completed_message->sd_buffer;
          completed_message->msg_size = 7;

          current_state.active_message_count += 1;
        }
      }

/*      printf("preamble detected @ %"PRIu64 " %d %d crc 0x%x 0x%x extended end 0x%x 0x%x 0x%x -> 0x%x , xor 0x%x\n",
        current_state.samples_consumed,current_state.preambles_detected,rpl,short_crc,extended_crc,
        msg_e[11],msg_e[12],msg_e[13],rx_crc_e,extended_crc ^ rx_crc_e);*/


      if(completed_message == NULL){
        free(msg);
      }
      free(bits_e);
    }


    return completed_message;
}


void print_stats(){
  printf("samples processed:  %"PRIu64  "\n", current_state.samples_consumed);
  printf("samples discard_count:  %d\n", current_state.discard_count);
  printf("preambles detected: %6d\n", current_state.preambles_detected);
  printf("messages decoded:   %6d\n", current_state.messages_rxd);
  printf("messages brute force decoded:   %6d\n", current_state.brute_forced_count);
}


