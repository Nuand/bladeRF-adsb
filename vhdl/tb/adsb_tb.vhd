library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;

library std ;
    use std.textio.all ;

entity adsb_tb is
end entity ;

architecture arch of adsb_tb is

    procedure nop( signal clock : in std_logic ; count : natural ) is
    begin
        for i in 1 to count loop
            wait until rising_edge( clock ) ;
        end loop ;
    end procedure ;

    constant Thp            :   time                                := 1.0/16.0e6/2.0 * 1 sec ;
    constant FNAME          :   string                              := "input.dat" ;

    signal clock            :   std_logic                           := '1' ;
    signal reset            :   std_logic                           := '1' ;

    signal edge_init        :   std_logic                           := '0' ;
    signal edge_in_power    :   signed(31 downto 0) ;
    signal edge_in_valid    :   std_logic ;

    signal edge_out_power   :   signed(31 downto 0) ;
    signal edge_out_level   :   std_logic ;
    signal edge_out_valid   :   std_logic ;

    signal det_power        :   signed(31 downto 0) ;
    signal det_valid        :   std_logic ;

    signal det_som          :   std_logic_vector(0e6 downto 0) ;
    signal det_eom          :   std_logic_vector(0 downto 0) ;
    signal det_rpl          :   signed(31 downto 0) ;

    signal dec_byte         :   unsigned(7 downto 0) ;
    signal dec_ready        :   std_logic ;

begin

    clock <= not clock after Thp ;

    U_edge_detector : entity work.edge_detector
      port map (
        clock       =>  clock,
        reset       =>  reset,

        init        =>  edge_init,

        power_in    =>  edge_in_power,
        in_valid    =>  edge_in_valid,

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

    U_message_decoder : entity work.message_decoder
    port map(
        clock       => clock,
        reset       => reset,

        power_in    => det_power,
        rpl_in      => det_rpl,
        som         => det_som(0),
        eom         => det_eom(0),
        in_valid    => det_valid,

        message_byte    =>  dec_byte,
        message_rdy     =>  dec_ready,
        message_read => '1'
    );

    tb : process
        variable status :   file_open_status ;
        type binfile is file of character ;
        file fin        :   binfile ;
        variable c      :   character ;
        variable i, q   :   integer ;
    begin
        nop( clock, 100 ) ;

        reset <= '0' ;
        edge_in_valid <= '0';
        nop( clock, 100 ) ;

        edge_init <= '1' ;
        nop( clock, 1 ) ;
        edge_init <= '0' ;
        nop( clock, 100 ) ;

        -- Open up sample file
        file_open( status, fin, FNAME ) ;
        assert status = OPEN_OK
            report "Could not open file: " & fname
            severity failure ;

        -- Iterate through the file
        while not endfile(fin) loop

            -- Read the 16-bit I sample
            read(fin, c) ;
            i := character'pos(c) ;
            read(fin, c) ;
            i := i + character'pos(c)*256 ;
            read(fin, c) ;

            -- Read the 16-bit Q sample
            q := character'pos(c) ;
            read(fin, c) ;
            q := q + character'pos(c)*256 ;

            -- Handle negative numbers
            if( i > 32767 ) then
                i := i - 65536 ;
            end if ;

            if( q > 32767 ) then
                q := q - 65536 ;
            end if ;

            -- Feed it into the front end
            edge_in_power <= to_signed( i*i+q*q, edge_in_power'length) ;
            edge_in_valid <= '1' ;
            nop( clock, 1 ) ;
            edge_in_valid <= '0' ;
            nop( clock, 1 ) ;
        end loop ;

        -- Done with the file, so close it
        file_close( fin ) ;

        -- Wait a little bit
        nop( clock, 1000 ) ;

        report "-- End of Simulation --" severity failure ;
    end process ;

end architecture ;

