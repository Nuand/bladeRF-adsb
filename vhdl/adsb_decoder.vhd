library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;

library work ;
    use work.adsb_decoder_p.all ;

entity adsb_decoder is
  port (
    clock           :   in  std_logic ;
    reset           :   in  std_logic ;

    init            :   in  std_logic ;

    in_power        :   in  signed(INPUT_POWER_WIDTH-1 downto 0) ;
    in_valid        :   in  std_logic ;

    debug_rpl       :   out signed(INPUT_POWER_WIDTH-1 downto 0) ;

    out_message     :   out std_logic_vector(111 downto 0) ;
    out_valid       :   out std_logic
  ) ;
end entity ;

architecture arch of adsb_decoder is

    signal edge_out_power   :   signed(31 downto 0) ;
    signal edge_out_level   :   std_logic ;
    signal edge_out_valid   :   std_logic ;

    signal det_power        :   signed(31 downto 0) ;
    signal det_valid        :   std_logic ;

    signal det_som          :   std_logic_vector(0 downto 0) ;
    signal det_eom          :   std_logic_vector(0 downto 0) ;
    signal det_rpl          :   signed(31 downto 0) ;

begin

    U_edge_detector : entity work.edge_detector
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
        NUM_MESSAGE_DECODER =>  1
      ) port map (
        clock       =>  clock,
        reset       =>  reset,

        power_in    =>  edge_out_power,
        edge_in     =>  edge_out_level,
        in_valid    =>  edge_out_valid,

        power_out   =>  det_power,
        out_valid   =>  det_valid,
        som         =>  det_som,
        eom         =>  det_eom,
        rpl         =>  det_rpl
      ) ;

    -- Debug
    debug_rpl <= det_rpl ;

    -- Outputs
    out_message <= (others =>'0') ;
    out_valid <= '0' ;

end architecture ;

