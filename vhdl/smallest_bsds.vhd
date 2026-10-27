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
    type magnitude_array_t is array(natural range <>) of signed(7 downto 0);
    type hits_t is array(natural range <>) of boolean;
    signal magnitude_ext : magnitude_array_t(ranks_ext'range);
    signal magnitude_short : magnitude_array_t(ranks_short'range);

    -- Keep ranking updates separate from the wide bit-mask decoder and allow
    -- local copies of its index drivers near their destinations.
    attribute preserve : boolean;
    attribute dont_retime : boolean;
    attribute maxfan : integer;
    attribute preserve of ranks_ext, ranks_short : signal is true;
    attribute dont_retime of ranks_ext, ranks_short, magnitude_ext,
                             magnitude_short : signal is true;
    attribute maxfan of ranks_ext, ranks_short : signal is 16;

    signal idx : integer range 0 to 111 ;

begin

    compare : process(clock, reset)
        variable hits_ext : hits_t(ranks_ext'range);
        variable hits_short : hits_t(ranks_short'range);
        variable earlier_ext, earlier_short : boolean;
        variable magnitude : signed(7 downto 0);
    begin
        if( reset = '1' ) then
            -- Unset all the elements
            for i in ranks_ext'range loop
                ranks_ext(i) <= UNSET ;
                ranks_short(i) <= UNSET ;
            end loop ;
            idx <= 0 ;
            finished <= '0' ;
            magnitude_ext <= (others => (others => '0'));
            magnitude_short <= (others => (others => '0'));
        elsif( rising_edge(clock) ) then
            finished <= '0' ;
            if( clear = '1' ) then
                -- Unset all the elements when we clear
                for i in ranks_ext'range loop
                    ranks_ext(i) <= UNSET ;
                    ranks_short(i) <= UNSET ;
                end loop ;
                idx <= 0 ;
                magnitude_ext <= (others => (others => '0'));
                magnitude_short <= (others => (others => '0'));
            else
                -- On each new BSD ...
                if( bsd_valid = '1' ) then
                    -- Shift in the original bits
                    bits <= bits(bits'high-1 downto 0) & bhd ;

                    -- Store exactly numeric_std's signed ABS, including its
                    -- minimum-negative overflow, beside each rank. Compare all
                    -- ranks in parallel, then select only incoming/previous/self
                    -- at each slot rather than cascading an insertion mux chain.
                    magnitude := abs(bsd);
                    for i in ranks_ext'range loop
                        hits_ext(i) := not ranks_ext(i).set or magnitude < magnitude_ext(i);
                        hits_short(i) := not ranks_short(i).set or magnitude < magnitude_short(i);
                    end loop;
                    earlier_ext := false;
                    earlier_short := false;
                    for i in ranks_ext'range loop
                        if earlier_ext then
                            ranks_ext(i) <= ranks_ext(i-1);
                            magnitude_ext(i) <= magnitude_ext(i-1);
                        elsif hits_ext(i) then
                            ranks_ext(i).value <= bsd ;
                            ranks_ext(i).index <= idx ;
                            ranks_ext(i).set <= true ;
                            magnitude_ext(i) <= magnitude;
                        end if ;
                        if idx < 54 then
                            if earlier_short then
                                ranks_short(i) <= ranks_short(i-1);
                                magnitude_short(i) <= magnitude_short(i-1);
                            elsif hits_short(i) then
                                ranks_short(i).value <= bsd ;
                                ranks_short(i).index <= idx ;
                                ranks_short(i).set <= true ;
                                magnitude_short(i) <= magnitude;
                            end if ;
                        end if;
                        earlier_ext := earlier_ext or hits_ext(i);
                        earlier_short := earlier_short or hits_short(i);
                    end loop;

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

