library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;

entity adsb_crc_tb is
end entity ;

architecture arch of adsb_crc_tb is

    signal clock        :   std_logic       := '1' ;
    signal reset        :   std_logic       := '1' ;

    signal busy         :   std_logic ;

    signal data         :   std_logic_vector(111 downto 0)  := (others =>'0') ;
    signal data_valid   :   std_logic                       := '0' ;

    signal crc          :   std_logic_vector(23 downto 0) ;
    signal crc_good     :   std_logic ;
    signal crc_valid    :   std_logic ;

    procedure nop( signal clock : in std_logic ; count : natural ) is
    begin
        for i in 1 to count loop
            wait until rising_edge(clock) ;
        end loop ;
    end procedure ;

begin

    clock <= not clock after 1 ns ;

    U_adsb_crc : entity work.adsb_crc
      port map (
        clock       =>  clock,
        reset       =>  reset,

        busy        =>  busy,

        data        =>  data,
        data_valid  =>  data_valid,

        crc         =>  crc,
        crc_good    =>  crc_good,
        crc_valid   =>  crc_valid
      ) ;

    tb : process
    begin
        reset <= '1' ;
        nop( clock, 10 ) ;

        reset <= '0' ;
        nop( clock, 10 ) ;

        data <= x"dd_cc_bb_aa_99_88_77_66_55_44_33_22_11_00" ;
        data_valid <= '1' ;
        nop( clock, 1 ) ;
        data_valid <= '0' ;

        nop( clock, 100 ) ;
        data <= x"d0_01_f7_a6_9b_7e_cf_f2_0f_58_4b_80_75_8d" ;
        data_valid <= '1' ;
        nop( clock, 1 ) ;
        data_valid <= '0' ;

        nop( clock, 100 ) ;

        data <= x"dd_cc_bb_aa_99_88_77_66_55_44_33_22_11_00" ;
        data_valid <= '1' ;
        nop( clock, 1 ) ;
        data_valid <= '0' ;

        nop( clock, 100 ) ;

        report "-- End of Simulation --" severity failure ;
    end process ;

end architecture ;

