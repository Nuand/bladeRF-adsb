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

int main(int argc, char *argv[]) {
    int sockfd = -1 ;
    int status ;
    struct bladerf *dev = NULL ;
    uint8_t messages[4096] ;
    char ascii_buf[1024] ;
    bladerf_fpga_size fpga_size ;

    struct module_config tx_config = {
        .module = BLADERF_MODULE_TX,
        .frequency  = 300000000,
        .bandwidth  = 1500000,
        .samplerate = 80000,
        .rx_lna     = BLADERF_LNA_GAIN_MAX,
        .vga1       = -14,
        .vga2       = 0
    } ;

    struct module_config rx_config = {
        .module     = BLADERF_MODULE_RX,
        .frequency  = 1086000000,
        .bandwidth  = 14000000,
        .samplerate = 16000000,
        .rx_lna     = BLADERF_LNA_GAIN_MAX,
        .vga1       = 10,
        .vga2       = 6
    } ;

    if ( argc >= 2 ) {
        if ( !strcmp(argv[1], "min") )
            rx_config.rx_lna = BLADERF_LNA_GAIN_BYPASS ;
        else if ( !strcmp(argv[1], "mid") )
            rx_config.rx_lna = BLADERF_LNA_GAIN_MID ;
        else if ( !strcmp(argv[1], "max") )
            rx_config.rx_lna = BLADERF_LNA_GAIN_MAX ;

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
    status = bladerf_open(&dev, "*") ;
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
    else {
        fprintf( stderr, "Incompatible FPGA size.\n") ;
        goto close ;
    }
    if (status < 0 ) {
        fprintf( stderr, "Couldn't load FPGA: %s\n", bladerf_strerror(status) ) ;
        goto close ;
    }

    /* Configure TX */
    status = configure_module(dev, &tx_config) ;
    if ( status < 0 ) {
        fprintf( stderr, "Couldn't configure TX module: %s\n", bladerf_strerror(status) ) ;
        goto close ;
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
