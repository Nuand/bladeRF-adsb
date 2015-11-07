library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;

library work ;
    use work.smallest_bsds_p.all ;

entity bit_flipper is
  port(
    clock           :   in  std_logic;
    reset           :   in  std_logic;

    start           :   in  std_logic ;

    busy            :   out std_logic ;

    in_bsd          :   in  signed(7 downto 0);
    in_bhd          :   in  std_logic;
    in_valid        :   in  std_logic ;

    msg_bits        :   out std_logic_vector(111 downto 0) ;
    msg_valid       :   out std_logic
  );
end entity;

architecture arch of bit_flipper is

    signal smallest_bits    :   std_logic_vector(111 downto 0) ;

    signal crc_good         :   std_logic ;
    signal crc_valid        :   std_logic ;

    signal flip_mask_ext    :   std_logic_vector(111 downto 0) ;
    signal flip_mask_short  :   std_logic_vector(111 downto 0) ;

    signal flipped_ext      :   std_logic_vector(111 downto 0) ;
    signal flipped_short    :   std_logic_vector(111 downto 0) ;

    signal flipped_msg      :   std_logic_vector(111 downto 0) ;
    signal flipped_valid    :   std_logic ;

    signal smallest_clear   :   std_logic ;
    signal smallest_done    :   std_logic ;

    signal smallest_ext     :   elements_t(0 to 4) ;
    signal smallest_short   :   elements_t(0 to 4) ;

    type fsm_t is (IDLE, WAIT_FOR_SMALLEST, GEN_FLIP_MASK, APPLY_FLIP, START_CRC, CHECK_CRC) ;
    signal fsm : fsm_t ;

    -- Given the iteration we are, calculate the bit flip mask to apply
    function calculate_flip_mask( iter : unsigned ; smallest : elements_t ) return std_logic_vector is
        variable rv : std_logic_vector(111 downto 0) := (others =>'0') ;
    begin
        assert iter'length = 5
            report "Iteration length can only be 5 bits long"
            severity failure ;
        assert smallest'length = 5
            report "Smallest elements length can only be 5 elements"
            severity failure ;
        for i in rv'range loop
            for j in smallest'range loop
                if( iter(j) = '1' and smallest(j).index = i ) then
                    rv(i) := '1' ;
                    exit ;
                end if ;
            end loop ;
        end loop ;
        return rv ;
    end function ;

    function swizzle( x : std_logic_vector ) return std_logic_vector is
        variable rv : std_logic_vector(111 downto 0) ;
        constant n : integer := 112/8 ;
    begin
        for i in 0 to n-1 loop
            rv((n-i)*8-1 downto (n-i-1)*8) := x((i+1)*8-1 downto i*8) ;
        end loop ;
        return rv ;
    end function ;

begin

    smallest_clear <= '1' when reset = '1' else
                      start and not smallest_done when rising_edge(clock) ;

    U_smallest : entity work.smallest_bsds
      port map (
        clock           =>  clock,
        reset           =>  reset,

        clear           =>  smallest_clear,

        finished        =>  smallest_done,

        bsd             =>  in_bsd,
        bhd             =>  in_bhd,
        bsd_valid       =>  in_valid,

        bits            =>  smallest_bits,
        smallest_ext    =>  smallest_ext,
        smallest_short  =>  smallest_short
      ) ;

    U_crc : entity work.adsb_crc
      port map (
        clock       =>  clock,
        reset       =>  reset,

        busy        =>  open,

        data        =>  flipped_msg,
        data_valid  =>  flipped_valid,

        crc         =>  open,
        crc_good    =>  crc_good,
        crc_valid   =>  crc_valid
      ) ;

    good_count : process(clock, reset)
        variable count : integer ;
    begin
        if( reset = '1' ) then
            count := 0 ;
        elsif( rising_edge(clock) ) then
            if( crc_good = '1' and crc_valid = '1' ) then
                count := count + 1 ;
            end if ;
        end if ;
    end process ;

    brute_force : process(clock, reset)
        variable iter : unsigned(4 downto 0) := (others =>'0') ;
    begin
        if( reset = '1' ) then
            msg_bits <= (others =>'0') ;
            msg_valid <= '0' ;
            busy <= '0' ;
        elsif( rising_edge(clock) ) then
            msg_valid <= '0' ;
            case fsm is
                when IDLE =>
                    busy <= '0' ;
                    iter := (others =>'0') ;
                    if( start = '1' ) then
                        fsm <= WAIT_FOR_SMALLEST ;
                        busy <= '1' ;
                    end if ;

                when WAIT_FOR_SMALLEST =>
                    if( smallest_done = '1' ) then
                        fsm <= GEN_FLIP_MASK ;
                    end if ;

                when GEN_FLIP_MASK =>
                    flip_mask_ext <= calculate_flip_mask( iter, smallest_ext ) ;
                    flip_mask_short <= calculate_flip_mask( iter, smallest_short ) ;
                    fsm <= APPLY_FLIP ;

                when APPLY_FLIP =>
                    flipped_ext <= smallest_bits xor flip_mask_ext ;
                    flipped_short <= smallest_bits xor flip_mask_short ;
                    fsm <= START_CRC ;

                when START_CRC =>
                    -- NOTE: Smarter things can be done here for short versus long bit flipping
                    flipped_msg <= swizzle(flipped_ext) ;
                    flipped_valid <= '1' ;
                    fsm <= CHECK_CRC ;

                when CHECK_CRC =>
                    flipped_valid <= '0' ;
                    if( crc_valid = '1' ) then
                        if( crc_good = '1' ) then
                            --report "Good CRC found on iteration " & integer'image(to_integer(iter)) & "!" ;
                            msg_bits <= flipped_msg ;
                            msg_valid <= '1' ;
                            fsm <= IDLE ;
                        else
                            if( iter < 31 ) then
                                iter := iter + 1 ;
                                fsm <= GEN_FLIP_MASK ;
                            else
                                --report "Done iterating and didn't find a good one" ;
                                fsm <= IDLE ;
                            end if ;
                        end if ;
                    end if ;

                when others =>
                    fsm <= IDLE ;

            end case ;
        end if ;
    end process ;

end architecture;

