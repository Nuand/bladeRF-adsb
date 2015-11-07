library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;

library work ;
    use work.smallest_bsds_p.all ;

entity smallest_bsds_tb is
end entity ;

architecture arch of smallest_bsds_tb is

    procedure nop(signal clock : in std_logic ; count : natural ) is
    begin
        for i in 1 to count loop
            wait until rising_edge(clock) ;
        end loop ;
    end procedure ;

    signal clock        :   std_logic           := '1' ;
    signal reset        :   std_logic           := '1' ;

    signal clear        :   std_logic           := '0' ;

    signal finished     :   std_logic ;

    signal bhd          :   std_logic           := '0' ;
    signal bsd          :   signed(7 downto 0)  := (others =>'0') ;
    signal bsd_valid    :   std_logic           := '0' ;

    signal smallest_short   :   elements_t(0 to 4) ;
    signal smallest_ext     :   elements_t(0 to 4) ;

    procedure print_element( x : element_t ; i : integer ) is
    begin
        report "element(" & integer'image(i) & "): " &
            "value => " & integer'image(to_integer(x.value)) & ", " &
            "index => " & integer'image(x.index) & ", " &
            "set => " & boolean'image(x.set) ;
    end procedure ;

begin

    clock <= not clock after 1 ns ;

    U_smallest : entity work.smallest_bsds
      port map (
        clock       =>  clock,
        reset       =>  reset,

        clear       =>  clear,

        bsd         =>  bsd,
        bhd         =>  bhd,
        bsd_valid   =>  bsd_valid,

        finished    =>  finished,

        smallest_ext    =>  smallest_ext,
        smallest_short  =>  smallest_short
      ) ;

    tb : process
    begin
        reset <= '1' ;
        nop( clock, 100 ) ;

        reset <= '0' ;
        nop( clock, 100 ) ;

        clear <= '1' ;
        nop( clock, 1 ) ;
        clear <= '0' ;
        nop( clock, 10 ) ;

        for i in 0 to 111 loop
            bsd <= to_signed( i, bsd'length ) ;
            bsd_valid <= '1' ;
            nop( clock, 1 ) ;
            bsd_valid <= '0' ;
            nop( clock, 15 ) ;
        end loop ;

        report "Counting up check" ;
        for i in smallest_ext'range loop
            print_element( smallest_ext(i), i ) ;
        end loop ;

        clear <= '1' ;
        nop( clock, 1 ) ;
        clear <= '0' ;
        nop( clock, 10 ) ;

        for i in 111 downto 0 loop
            bsd <= to_signed( i, bsd'length ) ;
            bsd_valid <= '1' ;
            nop( clock, 1 ) ;
            bsd_valid <= '0' ;
            nop( clock, 15 ) ;
        end loop ;

        report "Counting down check" ;
        for i in smallest_ext'range loop
            print_element( smallest_ext(i), i ) ;
        end loop ;

        clear <= '1' ;
        nop( clock, 1 ) ;
        clear <= '0' ;
        nop( clock, 10 ) ;

        for i in 0 to 111 loop
            bsd <= to_signed( (i-64), bsd'length ) ;
            bsd_valid <= '1' ;
            nop( clock, 1 ) ;
            bsd_valid <= '0' ;
            nop( clock, 15 ) ;
        end loop ;

        report "Negative check" ;
        for i in smallest_ext'range loop
            print_element( smallest_ext(i), i ) ;
        end loop ;

        clear <= '1' ;
        nop( clock, 1 ) ;
        clear <= '0' ;
        nop( clock, 10 ) ;

        report "-- End of simulation --" severity failure ;

    end process ;

end architecture ;

