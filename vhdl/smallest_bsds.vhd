library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;

package smallest_bsds_p is

    type element_t is record
        value   :   signed(7 downto 0) ;
        index   :   integer range 0 to 111 ;
        set     :   boolean ;
    end record ;

    type elements_t is array(natural range <>) of element_t ;

    constant UNSET : element_t := (
        value   => (others => '-'),
        index   => 0,
        set     => false
    ) ;

end package ;

library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;

library work ;
    use work.smallest_bsds_p.all ;

entity smallest_bsds is
  port (
    clock           :   in  std_logic ;
    reset           :   in  std_logic ;

    clear           :   in  std_logic ;

    finished        :   out std_logic ;

    bsd             :   in  signed(7 downto 0) ;
    bhd             :   in  std_logic ;
    bsd_valid       :   in  std_logic ;

    bits            :   out std_logic_vector(111 downto 0) ;
    smallest_ext    :   out elements_t(0 to 4) ;
    smallest_short  :   out elements_t(0 to 4)
  ) ;
end entity ;

architecture arch of smallest_bsds is

    signal ranks_ext    : elements_t(smallest_ext'range) ;
    signal ranks_short  : elements_t(smallest_short'range) ;

    signal idx : integer range 0 to 111 ;

begin

    compare : process(clock, reset)
    begin
        if( reset = '1' ) then
            -- Unset all the elements
            for i in ranks_ext'range loop
                ranks_ext(i) <= UNSET ;
                ranks_short(i) <= UNSET ;
            end loop ;
            idx <= 0 ;
            finished <= '0' ;
        elsif( rising_edge(clock) ) then
            finished <= '0' ;
            if( clear = '1' ) then
                -- Unset all the elements when we clear
                for i in ranks_ext'range loop
                    ranks_ext(i) <= UNSET ;
                    ranks_short(i) <= UNSET ;
                end loop ;
                idx <= 0 ;
            else
                -- On each new BSD ...
                if( bsd_valid = '1' ) then
                    -- Shift in the original bits
                    bits <= bits(bits'high-1 downto 0) & bhd ;

                    -- Iterate over the current rankings
                    -- For long messages
                    for i in ranks_ext'range loop
                        -- If the incoming BSD is less than the current ranking, or
                        -- the ranking hasn't been set, then set it, shift all the
                        -- others down, and exit the loop early
                        if( ranks_ext(i).set = false or abs(bsd) < abs(ranks_ext(i).value) ) then
                            ranks_ext(i).value <= bsd ;
                            ranks_ext(i).index <= idx ;
                            ranks_ext(i).set <= true ;
                            for x in i+1 to ranks_ext'high loop
                                ranks_ext(x) <= ranks_ext(x-1) ;
                            end loop ;
                            exit ;
                        end if ;
                    end loop ;

                    -- For short messages
                    if(idx < 54 ) then
                        for i in ranks_short'range loop
                            if( ranks_short(i).set = false or abs(bsd) < abs(ranks_short(i).value ) ) then
                                ranks_short(i).value <= bsd ;
                                ranks_short(i).index <= idx ;
                                ranks_short(i).set <= true ;
                                for x in i+1 to ranks_short'high loop
                                    ranks_short(x) <= ranks_short(x-1) ;
                                end loop ;
                                exit ;
                            end if ;
                        end loop ;
                    end if ;

                    -- We only have up to 111 indices
                    if( idx < 111 ) then
                        idx <= idx + 1 ;
                    else
                        finished <= '1' ;
                        --report "Index could not be incremented"
                        --    severity warning ;
                    end if ;
                end if ;
            end if ;
        end if ;
    end process ;

    smallest_ext <= ranks_ext ;
    smallest_short <= ranks_short ;

end architecture ;

