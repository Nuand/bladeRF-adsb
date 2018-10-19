library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;

library work ;
    use work.adsb_decoder_p.all ;

entity adsb_decoder is
  generic (
    NUM_DECODERS    :       positive    := 8
  );
  port (
    clock           :   in  std_logic ;
    reset           :   in  std_logic ;

    init            :   in  std_logic ;

    in_power        :   in  signed(INPUT_POWER_WIDTH-1 downto 0) ;
    in_valid        :   in  std_logic ;

    debug_rpl       :   out signed(INPUT_POWER_WIDTH-1 downto 0) ;

    out_messages    :   out messages_t(NUM_DECODERS-1 downto 0) ;
    out_valid       :   out std_logic_vector(NUM_DECODERS-1 downto 0)
  ) ;
end entity ;

architecture arch of adsb_decoder is

    signal edge_out_power   :   signed(INPUT_POWER_WIDTH-1 downto 0) ;
    signal edge_out_level   :   std_logic ;
    signal edge_out_valid   :   std_logic ;

    signal det_power        :   signed(INPUT_POWER_WIDTH-1 downto 0) ;
    signal det_valid        :   std_logic ;

    signal det_som          :   std_logic_vector(NUM_DECODERS-1 downto 0) ;
    signal det_rpl          :   signed(INPUT_POWER_WIDTH-1 downto 0) ;

    signal decoder_busy     :   std_logic_vector(NUM_DECODERS-1 downto 0) ;

    signal msgs_decoded     :   messages_t(NUM_DECODERS-1 downto 0);
    signal msgs_valid       :   std_logic_vector(NUM_DECODERS-1 downto 0);

begin

    U_adsb_edge_detector : entity work.adsb_edge_detector
      port map (
        clock       =>  clock,
        reset       =>  reset,

        init        =>  init,

        power_in    =>  in_power,
        in_valid    =>  in_valid,

        power_out   =>  edge_out_power,
        edge_out    =>  edge_out_level,
        out_valid   =>  edge_out_valid
      ) ;

    U_preamble_detector : entity work.preamble_detector
      generic map (
        NUM_MESSAGE_DECODER =>  NUM_DECODERS
      ) port map (
        clock           =>  clock,
        reset           =>  reset,

        power_in        =>  edge_out_power,
        edge_in         =>  edge_out_level,
        in_valid        =>  edge_out_valid,

        decoder_busy    =>  decoder_busy,

        power_out       =>  det_power,
        out_valid       =>  det_valid,
        som             =>  det_som,
        rpl             =>  det_rpl
      ) ;


    generate_decoders : for i in 0 to NUM_DECODERS-1 generate
        U_message_decoder : entity work.message_decoder
          port map (
            clock       =>  clock,
            reset       =>  reset,

            busy        =>  decoder_busy(i),

            power_in    =>  det_power,
            rpl_in      =>  det_rpl,
            som         =>  det_som(i),
            in_valid    =>  det_valid,

            msg_bits    =>  msgs_decoded(i),
            msg_valid   =>  msgs_valid(i)
          ) ;
    end generate;

    check_crc_valid : process(clock, reset)
        type integers_t is array(natural range <>) of integer ;
        variable passes : integers_t(NUM_DECODERS-1 downto 0) := (others => 0) ;
        variable total_passes : integer := 0 ;
    begin
        if( rising_edge(clock) ) then
            for i in 0 to NUM_DECODERS-1 loop
                if( msgs_valid(i) = '1' ) then
                    passes(i) := passes(i) + 1 ;
                    total_passes := total_passes + 1 ;
                    --report "DECODER " & integer'image(i) & ": MESSAGE DECODED! (" & integer'image(passes(i)) & ")" ;
                end if ;
            end loop;
        end if ;
    end process ;

    -- Debug
    debug_rpl <= det_rpl ;

    -- Outputs
    out_messages <= msgs_decoded ;
    out_valid <= msgs_valid ;

end architecture ;

