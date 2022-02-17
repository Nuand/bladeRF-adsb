#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h> 


#include <libbladeRF.h>

#define FPGA_FNAME_115 "./adsbx115.rbf"
#define FPGA_FNAME_40 "./adsbx40.rbf"
#define FPGA_FNAME_A4 "./adsbxA4.rbf"
#define FPGA_FNAME_A5 "./adsbxA5.rbf"
#define FPGA_FNAME_A9 "./adsbxA9.rbf"

bool dump_messages = true ;

int config_socket() {
    int sockfd;

    struct sockaddr_in serv_addr;
    struct hostent *server;

    char buffer[256];
    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) 
        return -1;
    server = gethostbyname("127.0.0.1");
    if (server == NULL) {
        return -1;
    }
    bzero((char *) &serv_addr, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    bcopy((char *)server->h_addr, 
         (char *)&serv_addr.sin_addr.s_addr,
         server->h_length);
    /* dump1090 listens on port 30001 */
    serv_addr.sin_port = htons(30001);
    if (connect(sockfd,(struct sockaddr *)&serv_addr,sizeof(serv_addr)) < 0) 
        return -1;

    return sockfd;
}

/* The RX and TX modules are configured independently for these parameters */
struct module_config {
    int unified_gain;
    bladerf_module module;
    unsigned int frequency;
    unsigned int bandwidth;
    unsigned int samplerate;
    /* Gains */
    bladerf_lna_gain rx_lna;
    int vga1;
    int vga2;
};

void handler(int s) {
    fprintf( stderr, "Shutting down (%d)\n", s ) ;
    dump_messages = false ;
    return ;
}

int configure_module(struct bladerf *dev, struct module_config *c)
{
    int status;

    status = bladerf_set_frequency(dev, c->module, c->frequency);
    if (status != 0) {
        fprintf(stderr, "Failed to set frequency = %u: %s\n",
                c->frequency, bladerf_strerror(status));
        return status;
    }
    status = bladerf_set_sample_rate(dev, c->module, c->samplerate, NULL);
    if (status != 0) {
        fprintf(stderr, "Failed to set samplerate = %u: %s\n",
                c->samplerate, bladerf_strerror(status));
        return status;
    }
    status = bladerf_set_bandwidth(dev, c->module, c->bandwidth, NULL);
    if (status != 0) {
        fprintf(stderr, "Failed to set bandwidth = %u: %s\n",
                c->bandwidth, bladerf_strerror(status));
        return status;
    }
    switch (c->module) {
        case BLADERF_MODULE_RX:
            /* Configure the gains of the RX LNA, RX VGA1, and RX VGA2  */
            if (c->unified_gain) {
                status = bladerf_set_gain_mode(dev, BLADERF_CHANNEL_RX(0), BLADERF_GAIN_MGC);
                if (status != 0) {
                    fprintf(stderr, "Failed to set gain mode to manual: %s\n",
                            bladerf_strerror(status));
                    return status;
                }
                status = bladerf_set_gain(dev, BLADERF_CHANNEL_RX(0), c->unified_gain);
                if (status != 0) {
                    fprintf(stderr, "Failed to set gain: %s\n",
                            bladerf_strerror(status));
                    return status;
                }
                return status;
            }
            status = bladerf_set_lna_gain(dev, c->rx_lna);
            if (status != 0) {
                fprintf(stderr, "Failed to set RX LNA gain: %s\n",
                        bladerf_strerror(status));
                return status;
            }
            status = bladerf_set_rxvga1(dev, c->vga1);
            if (status != 0) {
                fprintf(stderr, "Failed to set RX VGA1 gain: %s\n",
                        bladerf_strerror(status));
                return status;
            }
            status = bladerf_set_rxvga2(dev, c->vga2);
            if (status != 0) {
                fprintf(stderr, "Failed to set RX VGA2 gain: %s\n",
                        bladerf_strerror(status));
                return status;
            }
            break;
        case BLADERF_MODULE_TX:
            /* Configure the TX VGA1 and TX VGA2 gains */
            status = bladerf_set_txvga1(dev, c->vga1);
            if (status != 0) {
                fprintf(stderr, "Failed to set TX VGA1 gain: %s\n",
                        bladerf_strerror(status));
                return status;
            }
            status = bladerf_set_txvga2(dev, c->vga2);
            if (status != 0) {
                fprintf(stderr, "Failed to set TX VGA2 gain: %s\n",
                        bladerf_strerror(status));
                return status;
            }
            break;
        default:
            status = BLADERF_ERR_INVAL;
            fprintf(stderr, "%s: Invalid module specified (%d)\n",
                    __FUNCTION__, c->module);
    }
    return status;
}

#ifndef LIBBLADERF_API_VERSION
#error LIBBLADERF_API_VERSION is not defined in headers. At minimum libbladeRF version 2.0.0 is required.
#endif
#if ( LIBBLADERF_API_VERSION < 0x2000000 )
#error Incompatible libbladeRF header version. At minimum libbladeRF version 2.0.0 is required.
#endif

int main(int argc, char *argv[]) {
    int sockfd = -1 ;
    int status ;
    struct bladerf *dev = NULL ;
    uint8_t messages[4096] ;
    char ascii_buf[1024] ;
    bladerf_fpga_size fpga_size ;

    struct module_config rx_config = {
        .module     = BLADERF_MODULE_RX,
        .frequency  = 1086000000,
        .bandwidth  = 14000000,
        .samplerate = 16000000,
        .rx_lna     = BLADERF_LNA_GAIN_MAX,
        .vga1       = 10,
        .vga2       = 6,
        .unified_gain = 0
    } ;

    if ( argc >= 2 ) {
        if ( !strcmp(argv[1], "min") )
            rx_config.rx_lna = BLADERF_LNA_GAIN_BYPASS ;
        else if ( !strcmp(argv[1], "mid") )
            rx_config.rx_lna = BLADERF_LNA_GAIN_MID ;
        else if ( !strcmp(argv[1], "max") )
            rx_config.rx_lna = BLADERF_LNA_GAIN_MAX ;
        else if ( !strcmp(argv[1], "unified") ) {
            rx_config.unified_gain = 35;
            goto bypass_lna;
        }

        fprintf( stderr, "Set LNA to %s\n",
               (rx_config.rx_lna == BLADERF_LNA_GAIN_BYPASS) ? "Min" :
                   (rx_config.rx_lna == BLADERF_LNA_GAIN_MID ? "Mid" : "Max" )
              );
    }

    if ( argc >= 3 ) {
        rx_config.vga1 = atoi(argv[2]);
        fprintf( stderr, "Set RXGA1 to %d\n", rx_config.vga1 ) ;
    }

    if ( argc >= 4 ) {
        rx_config.vga2 = atoi(argv[3]);
        fprintf( stderr, "Set RXGA2 to %d\n", rx_config.vga2 ) ;
    }

bypass_lna:

    sockfd = config_socket();
    if ( sockfd == -1 ) {
        fprintf( stderr, "Could not connect to local dump1090 server\n");
        return 1;
    }

    /* Register ^C event handler */
    struct sigaction action ;
    action.sa_handler = handler ;
    sigemptyset(&action.sa_mask) ;
    action.sa_flags = 0 ;

    sigaction(SIGINT, &action, NULL) ;

    /* Open the device */
    status = bladerf_open(&dev, NULL) ;
    if ( status < 0) {
        fprintf( stderr, "Couldn't open device: %s\n", bladerf_strerror(status)) ;
        goto out ;
    }

    /* Figure out FPGA size */
    status = bladerf_get_fpga_size(dev, &fpga_size ) ;
    if ( status < 0) {
        fprintf( stderr, "Couldn't determine FPGA size: %s\n", bladerf_strerror(status) ) ;
        goto close ;
    }

    /* Load the FPGA */
    if ( fpga_size == BLADERF_FPGA_40KLE ) 
        status = bladerf_load_fpga(dev, FPGA_FNAME_40) ;
    else if ( fpga_size == BLADERF_FPGA_115KLE ) 
        status = bladerf_load_fpga(dev, FPGA_FNAME_115) ;
    else if ( fpga_size == BLADERF_FPGA_A4 )
        status = bladerf_load_fpga(dev, FPGA_FNAME_A4) ;
    else if ( fpga_size == BLADERF_FPGA_A5 )
        status = bladerf_load_fpga(dev, FPGA_FNAME_A5) ;
    else if ( fpga_size == BLADERF_FPGA_A9 )
        status = bladerf_load_fpga(dev, FPGA_FNAME_A9) ;
    else {
        status = bladerf_load_fpga(dev, FPGA_FNAME_A4) ;
    }

    if (fpga_size == BLADERF_FPGA_A4 || fpga_size == BLADERF_FPGA_A5 || fpga_size == BLADERF_FPGA_A9) {
        rx_config.unified_gain = 35;
    }

    if (status < 0 ) {
        fprintf( stderr, "Couldn't load FPGA: %s\n", bladerf_strerror(status) ) ;
        goto close ;
    }

    bladerf_close(dev);
    status = bladerf_open(&dev, NULL) ;
    if ( status < 0) {
        fprintf( stderr, "Couldn't open device: %s\n", bladerf_strerror(status)) ;
        goto out ;
    }

    /* Configure RX */
    status = configure_module(dev, &rx_config) ;
    if ( status < 0 ) {
        fprintf( stderr, "Couldn't configure RX module: %s\n", bladerf_strerror(status) ) ;
        goto close ;
    }

    /* Configure RX sample stream */
    status = bladerf_sync_config(dev, BLADERF_MODULE_RX, BLADERF_FORMAT_SC16_Q11, 2, 1024, 1, 5000) ;
    if ( status < 0 ) {
        fprintf(stderr, "Couldn't configure RX stream: %s\n", bladerf_strerror(status) ) ;
        goto close ;
    }

    /* Enable RX */
    status = bladerf_enable_module(dev, BLADERF_MODULE_RX, true) ;
    if ( status < 0 ) {
        fprintf(stderr, "Couldn't enable RX module: %s\n", bladerf_strerror(status) ) ;
        goto close ;
    }

    /* Read messages and print them out */
    while( dump_messages == true ) {
        int i, k, end ;
        status = bladerf_sync_rx(dev, messages, 1024, NULL, 5000) ;
        if ( status < 0 ) {
            fprintf( stderr, "Error receiving samples: %s\n", bladerf_strerror(status) ) ;
            goto close ;
        }
        for( i = 0 ; i < 4096 ; i+=16 ) {
            if ( (messages[i]&0x01) == 1 ) {
                if ( (messages[i+2]&0x80) == 0x80 ) {
                    end = 14 ;
                } else {
                    end = 7 ;
                }

                strcpy( ascii_buf, "*" ) ;
                for( k = 0; k < end ; k++ ) {
                    sprintf( ascii_buf + 1 + k * 2, "%2.2x", messages[i+2+k] ) ;
                }
                strcat(ascii_buf, ";\n") ;

                /* Print out to console */
                printf("%s\n", ascii_buf);

                /* Send ASCII hex message to socket */
                if (sockfd != -1) {
                   if (send(sockfd, ascii_buf, strlen(ascii_buf), 0) == -1 )
                       return 1 ;
                }
            }
        }
    }

    /* Clean up */
    fprintf( stderr, "Completed\n" ) ;

close:
    bladerf_close(dev) ;

out:
    return 0 ;
}
