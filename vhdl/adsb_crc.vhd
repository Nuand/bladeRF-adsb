library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;

entity adsb_crc is
  port (
    clock       :   in  std_logic ;
    reset       :   in  std_logic ;

    busy        :   out std_logic ;

    data        :   in  std_logic_vector(111 downto 0) ;
    data_valid  :   in  std_logic ;

    crc         :   out std_logic_vector(23 downto 0) ;
    crc_good    :   out std_logic ;
    crc_valid   :   out std_logic
  ) ;
end entity ;

architecture arch of adsb_crc is

    -- synthesis_translate off
    -- Used for testbenching of known message
    constant GOOD : std_logic_vector(111 downto 0) := 112x"d001f7a69b7ecff20f584b80758d" ;
    -- synthesis_translate on

    constant CRC_POLY : std_logic_vector(24 downto 0) := 25x"1fff409" ;

    type fsm_t is (IDLE, CALCULATING, DONE) ;

    type state_t is record
        fsm     :   fsm_t ;
        count   :   natural range 0 to 14-1 ;
        data    :   std_logic_vector(data'range) ;
        crc     :   std_logic_vector(24 downto 0) ;
        busy    :   std_logic ;
        valid   :   std_logic ;
        good    :   std_logic ;
        nonzero :   std_logic ;
    end record ;

    signal current, future : state_t ;

begin

    sync : process(clock, reset)
    begin
        if( reset = '1' ) then
            current.fsm <= IDLE ;
            current.busy <= '1' ;
        elsif( rising_edge(clock) ) then
            current <= future ;
        end if ;
    end process ;

    async : process(all)
        variable crc : std_logic_vector(current.crc'range) ;
    begin
        future <= current ;
        case current.fsm is
            when IDLE =>
                future.busy <= '0' ;
                future.valid <= '0' ;
                future.good <= '0' ;
                future.nonzero <= '0' ;
                if( data_valid = '1' ) then
                    future.data <= data ;
                    future.fsm <= CALCULATING ;
                    future.crc <= (others =>'0') ;
                    future.busy <= '1' ;
                    -- MSB of first data byte (aka: bit 5 of DF field)
                    -- will denote if it's extended or not.
                    -- NOTE: This position will change depending on how
                    -- the data is fed into the CRC block
                    if( data(7) = '1' ) then
                        future.count <= 14-1 ;
                    else
                        future.count <= 7-1 ;
                    end if ;
                end if ;

            when CALCULATING =>
                if( current.nonzero = '0' and unsigned(current.data(7 downto 0)) /= 0 ) then
                    future.nonzero <= '1' ;
                end if ;
                future.data <= x"00" & current.data(current.data'high downto 8) ;
                crc := current.crc ;
                -- NOTE: This loop changes based on how data is fed into this
                -- CRC block.
                for i in 7 downto 0 loop
                    crc := crc(crc'high-1 downto 0) & current.data(i) ;
                    if( crc(crc'high) = '1' ) then
                        crc := crc xor CRC_POLY ;
                    end if ;
                end loop ;
                future.crc <= crc ;
                if( current.count = 0 ) then
                    future.fsm <= DONE ;
                else
                    future.count <= current.count - 1 ;
                end if ;

            when DONE =>
                future.fsm <= IDLE ;
                future.valid <= '1' ;
                if( to_integer(unsigned(current.crc)) = 0 and current.nonzero = '1' ) then
                    future.good <= '1' ;
                else
                    future.good <= '0' ;
                end if ;
                future.busy <= '0' ;

            when others =>
                future.fsm <= IDLE ;

        end case ;
    end process ;

    -- synthesis_translate off
    compare : process(clock, reset)
        variable count : natural := 0 ;
        variable diff : std_logic_vector(111 downto 0) ;
    begin
        if( rising_edge(clock) ) then
            if( current.valid = '1' and current.good = '0' ) then
                diff :=  data xor GOOD ;
                count := 0 ;
                for i in diff'range loop
                    if( diff(i) = '1' ) then
                        count := count + 1 ;
                    end if ;
                end loop ;
            end if ;
        end if ;
    end process ;
    -- synthesis_translate on

    -- Registered Outputs
    busy <= current.busy ;
    crc_good <= current.good ;
    crc_valid <= current.valid ;
    crc <= current.crc(crc'range) ;

end architecture ;

