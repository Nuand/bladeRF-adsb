library ieee ;
    use ieee.std_logic_1164.all ;

package adsb_decoder_p is

    constant INPUT_POWER_WIDTH  :   natural     := 24 ;

    type messages_t is array(natural range <>) of std_logic_vector(111 downto 0) ;

end package ;

