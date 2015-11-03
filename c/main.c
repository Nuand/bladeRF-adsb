#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "cnutil.h"
#include "adsb.h"
#include <getopt.h>

uint8_t known_msg[] = {

0x8d,
0x75,
0x80,
0x4b,
0x58,
0x0f,
0xf2,
0xcf,
0x7e,
0x9b,
0xa6,
0xf7,
0x01,
0xd0
};

FILE *csv_save= NULL;

int main(int argc, char *argv[])
{
    char *in_filename = NULL;
    char *out_filename = NULL;
    int c;
    uint8_t enable_mix = 0;
    uint8_t enable_filter = 0;



    while((c = getopt(argc,argv, "i:o:mf")) != -1){
        switch(c)
        {
            case 'i':
                //strncpy(in_filename,optarg,20);
                in_filename = optarg ;
            break;
            case 'o':
                //strncpy(out_filename,optarg,20);
                out_filename = optarg ;
            break;
            case 'm':
            enable_mix = 1;
            break;
            case 'f':
            enable_filter =1;
            break;
            default:
            printf("unsupported arguement! %c",c);
            break;
        }

    }


    uint16_t eof = 0;

    FILE *sample_file = fopen(in_filename,"r");
    csv_save = fopen("csv_samples.dat","w");
    if(sample_file == NULL)
    {
        printf("unable to open sample file: %s", in_filename);
        return 0;
    }

    FILE *message_file = NULL;
    if(out_filename){
        message_file = fopen(out_filename,"w");
        if(message_file == NULL){
            printf("unable to open specified message file %s\n", out_filename);
        }
    }

    //configure adsb rx
    c16_t rx_sample;
    int rx_real;
    int rx_imag;
    message_t *rxmsg;
    uint16_t fixed_point = 1;
    uint16_t sample_count = 0;


    uint32_t valid_msg_count = 0;
    uint32_t duplicate_message_count = 0;
    uint32_t error_msg_count = 0;

    init(enable_filter,enable_mix);

    uint32_t current_sample = 0;
    uint32_t previous_sample = 0;
    uint32_t previous_error_sample = 0;
    uint32_t false_msg_count = 0;
    uint32_t dup_error = 0;


    if(fixed_point){
        while( !eof )
        {
            uint32_t elem_read = 0;
            elem_read = fread(&rx_sample.real, 1,sizeof(int16_t),sample_file);
            elem_read += fread(&rx_sample.imag, 1,sizeof(int16_t),sample_file);
            //printf("sample[%d] = %d %d\n",elem_read, rx_sample.real,rx_sample.imag);
            rxmsg = rx(&rx_sample);

            fprintf(csv_save,"%d,%d\n",rx_sample.real,rx_sample.imag);

            uint32_t error = 0;
            uint32_t zero_count = 0;
            if(rxmsg != NULL){

                uint32_t i,error_count = 0;;
                for(i = 0; i < 14; i++){
                    if(   (rxmsg->data[i] ^ known_msg[i]) && (rxmsg->data[i] != 0x00) ){
                        //printf("delta in msg[%d] 0x%x 0x%x - 0x%x\n",i, rxmsg->data[i],known_msg[i], known_msg[i] ^ rxmsg->data[i]);
                        error_count++;
                    }
                    if(rxmsg->data[i] == 0){
                        zero_count++;
                    }
                }
                if(zero_count == 14){

                    false_msg_count++;
                }
                else if(error_count)
                {
                    //printf("error_count %d sample %d previous valid %d previous error %d delta %d\n",error_count,current_sample,previous_sample,previous_error_sample,current_sample-previous_sample);
                    previous_error_sample = current_sample;
                    error_msg_count++;

                    if(current_sample < (previous_sample + 2)){
                        //printf("error close to valid %d %d\n", current_sample,previous_sample);
                    }
                }
                else{

                    if(current_sample < (previous_sample + (EXTENDED_MESSAGE_LENGTH* 8*2)) ) {
                        if( (current_sample - previous_sample)  > 2){
                            printf("might be double rx! %d %d\n", current_sample,previous_sample);
                        }
                        duplicate_message_count++;
                        if(error_count){
                            dup_error = 1;
                            printf("dup error\n");
                        }
                    }

                    if( (current_sample <= (previous_error_sample + 100)) ){
                        // printf("valid close to error %d %d\n",current_sample,previous_error_sample);
                    }
/*
                    printf("valid message found error_count %d sample %d previous valid %d previous error %d delta %d\n",error_count,current_sample,previous_sample,previous_error_sample,current_sample-previous_sample);
*/
                    previous_sample = current_sample;
                    valid_msg_count++;
                }


                if(message_file){
                    for(i = 0; i < rxmsg->msg_size; i++)
                    {
                        fprintf(message_file, "%x ", rxmsg->data[i]);
                    }
                    fprintf(message_file,"\n");
                }
                free(rxmsg->data);
                free(rxmsg);

            }
            current_sample++;

            //if(current_sample > (3131 + 112*8*2))return;
            eof = (elem_read == 4) ? 0 : 1;
        }


        print_stats();
        printf("total %d valid %d error %d dup %d false %d\n",valid_msg_count,valid_msg_count - duplicate_message_count,error_msg_count,duplicate_message_count,false_msg_count);
    }
    else{
        printf("reading float file\n");
        float rxf_real,rxf_imag;
        while( (eof = fscanf(sample_file, "%f,%f\n",&(rxf_real), &(rxf_imag)))  == 2 )
        {
            rx_sample.real = (int16_t)(2048.0*rxf_real);
            rx_sample.imag = (int16_t)(2048.0*rxf_imag);

            //printf("read sample %f %f, rx %d %d\n",rxf_real,rxf_imag,rx_sample.real,rx_sample.imag);
            rxmsg = rx(&rx_sample);
        }
        printf("eof= %d\n",eof);
        print_stats();
    }


    fclose(sample_file);
    if(message_file){
        fclose(message_file);
    }
    if(csv_save){
        fclose(csv_save);
    }
    return 0;
}
