library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;

library work ;
    use work.adsb_decoder_p.all ;

entity message_aggregator is
  generic (
    MSGS_PER_TIMEOUT    :       positive    := 128 ;
    PACKET_TIMEOUT      :       positive    := 32000000/100 ;
    NUM_DECODERS        :       positive    := 8
  ) ;
  port (
    clock               :   in  std_logic ;
    reset               :   in  std_logic ;

    in_messages         :   in  messages_t(NUM_DECODERS-1 downto 0) ;
    in_valid            :   in  std_logic_vector(NUM_DECODERS-1 downto 0) ;

    out_message         :   out std_logic_vector(127 downto 0) ;
    out_valid           :   out std_logic
  ) ;
end entity ;

architecture arch of message_aggregator is

    type holding_t is record
        msg     :   std_logic_vector(111 downto 0) ;
        valid   :   std_logic ;
    end record ;

    type holdings_t is array(natural range <>) of holding_t ;

    signal holding  :   holdings_t(NUM_DECODERS-1 downto 0) ;

    signal clear    :   std_logic_vector(NUM_DECODERS-1 downto 0) ;

begin

    hold_msg : process(clock, reset)
    begin
        if( reset = '1' ) then
            for i in holding'range loop
                holding(i).valid <= '0' ;
            end loop ;
        elsif( rising_edge(clock) ) then
            for i in holding'range loop
                if( clear(i) = '1' ) then
                    holding(i).valid <= '0' ;
                else
                    if( in_valid(i) = '1' ) then
                        if( holding(i).valid = '0' ) then
                            holding(i).msg <= in_messages(i) ;
                            holding(i).valid <= '1' ;
                        else
                            report "Lost a message in aggregator" severity warning ;
                        end if ;
                    end if ;
                end if ;
            end loop ;
        end if ;
    end process ;

    round_robin : process(clock, reset)
        variable count : natural range 0 to MSGS_PER_TIMEOUT-1 := MSGS_PER_TIMEOUT-1 ;
        variable downcount : natural range 0 to PACKET_TIMEOUT := PACKET_TIMEOUT ;
        variable idx : natural range 0 to NUM_DECODERS-1 := 0 ;
        variable new_count : natural range 0 to MSGS_PER_TIMEOUT-1 ;
    begin
        if( reset = '1' ) then
            idx := 0 ;
            count := MSGS_PER_TIMEOUT-1 ;
            downcount := PACKET_TIMEOUT ;
            out_valid <= '0' ;
            clear <= (others =>'0') ;
        elsif( rising_edge(clock) ) then
            out_valid <= '0' ;
            clear <= (others =>'0') ;
            new_count := count ;
            -- Check timeout
            if( downcount > 0 ) then
                downcount := downcount - 1 ;
            else
                if( count > 0 ) then
                    new_count := count - 1 ;
                    out_message <= (others =>'0') ;
                    out_valid <= '1' ;
                else
                    new_count := MSGS_PER_TIMEOUT-1 ;
                    downcount := PACKET_TIMEOUT ;
                end if ;
            end if ;

            -- Round robin on the holding inputs
            if( holding(idx).valid = '1' ) then
                out_message <= holding(idx).msg & x"0001" ;
                out_valid <= '1' ;
                if( count > 0 ) then
                    new_count := count - 1 ;
                else
                    new_count := MSGS_PER_TIMEOUT-1 ;
                    if( downcount > 0 ) then
                        downcount := PACKET_TIMEOUT ;
                    end if ;
                end if ;
                clear(idx) <= '1' ;
            end if ;

            count := new_count ;

            -- Move to the next input
            if( idx > 0 ) then
                idx := idx - 1 ;
            else
                idx := NUM_DECODERS - 1 ;
            end if ;
        end if ;
    end process ;

end architecture ;

