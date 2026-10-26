library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;

library work ;
    use work.adsb_decoder_p.all ;

entity preamble_detector is
  generic(
    NUM_MESSAGE_DECODER : integer := 1
  );
  port(
    clock           :   in  std_logic;
    reset           :   in  std_logic;

    power_in        :   in  signed(INPUT_POWER_WIDTH-1 downto 0);
    edge_in         :   in  std_logic;
    in_valid        :   in  std_logic;

    decoder_busy    :   in  std_logic_vector(NUM_MESSAGE_DECODER-1 downto 0);

    power_out       :   out signed(INPUT_POWER_WIDTH-1 downto 0);
    out_valid       :   out std_logic;
    som             :   out std_logic_vector( NUM_MESSAGE_DECODER-1 downto 0);
    rpl             :   out signed(INPUT_POWER_WIDTH-1 downto 0)
  );
end entity;


architecture arch of preamble_detector is

    constant RPL_DOUBLECHECK        : integer := 3;
    constant SPS                    : integer := 8;
    constant SPB                    : integer := 2;
    constant PREAMBLE_LENGTH        : integer := 8; -- preamble bits
    constant PREAMBLE_BUFFER_LENGTH : integer := SPS*SPB*PREAMBLE_LENGTH; -- 8 * 2 * 8 = 128 samples

    --preambles are detected after the 5usec completes the 4th bit, this leaves 3usec to downcount
     -- 48 samples from the end of the last asserted bit in the preamble
    constant MESSAGE_DELAY          : integer := 48;

    constant POWER_THRESHOLD        : signed(INPUT_POWER_WIDTH-1 downto 0) := to_signed(integer(5000),INPUT_POWER_WIDTH);
    constant SAMPLE_WINDOW          : integer := 5;

    constant sum0_in                : integer := SAMPLE_WINDOW-1;
    constant sum1_in                : integer := 2*SPS + SAMPLE_WINDOW-1;
    constant sum2_in                : integer := 7*SPS + SAMPLE_WINDOW-1;
    constant sum3_in                : integer := 9*SPS + SAMPLE_WINDOW-1;

    constant sum0_out               : integer := 0;
    constant sum1_out               : integer := 2*SPS;
    constant sum2_out               : integer := 7*SPS;
    constant sum3_out               : integer := 9*SPS;

    constant OUTPUT_TAP             : integer := sum3_in;

    signal edge_qualifier           : std_logic_vector(3 downto 0);
    signal edge_register            : std_logic_vector(3 downto 0);

    type power_array is array(natural range <>) of signed(INPUT_POWER_WIDTH-1 downto 0);
    signal power_grid               : power_array (PREAMBLE_BUFFER_LENGTH-1 downto 0);
    signal edge_grid                : std_logic_vector(PREAMBLE_BUFFER_LENGTH-1 downto 0);

    signal register_valid           : std_logic;
    signal preamble_detected        : std_logic;
    signal register_rpl             : signed(INPUT_POWER_WIDTH-1 downto 0);

    function positive_max(a, b : signed) return signed is
        variable current_max : signed(INPUT_POWER_WIDTH-1 downto 0) := (others => '0');
    begin
        if a > current_max then
            current_max := a;
        end if;
        if b > current_max then
            current_max := b;
        end if;
        return current_max;
    end function;

    function greater_power(a, b : signed) return signed is
    begin
        if b > a then
            return b;
        end if;
        return a;
    end function;

    type tap_array is array (0 to 3) of natural;
    constant WINDOW_TAPS : tap_array := (sum0_out, sum1_out, sum2_out, sum3_out);
    type window_samples_array is array (0 to 3) of power_array(4 downto 0);
    type window_pairs_array is array (0 to 3) of power_array(2 downto 0);
    type window_merge_array is array (0 to 3) of power_array(1 downto 0);
    signal window_samples : window_samples_array;
    signal window_pairs : window_pairs_array;
    signal window_merge : window_merge_array;

    signal rpl_countdown            : integer range 0 to 3;
    signal som_pending              : std_logic_vector(NUM_MESSAGE_DECODER-1 downto 0);

begin

    detection : process(clock,reset)
        variable sum0 : signed(INPUT_POWER_WIDTH-1 downto 0);
        variable sum1 : signed(INPUT_POWER_WIDTH-1 downto 0);
        variable sum2 : signed(INPUT_POWER_WIDTH-1 downto 0);
        variable sum3 : signed(INPUT_POWER_WIDTH-1 downto 0);
        variable max : power_array( 3 downto 0);
        variable max_alt : power_array( 3 downto 0);
    begin
        if( reset = '1' ) then
            preamble_detected <= '0';
            register_valid <= '0';
            sum0 := (others => '0');
            sum1 := (others => '0');
            sum2 := (others => '0');
            sum3 := (others => '0');
            power_grid <= (others => (others => '0'));
            edge_grid <= (others => '0');
            window_samples <= (others => (others => (others => '0')));
            window_pairs <= (others => (others => (others => '0')));
            window_merge <= (others => (others => (others => '0')));
        elsif (rising_edge(clock))then
            edge_register <= (others => '0');
            if(register_valid = '1') then
                if( (sum0 > POWER_THRESHOLD) and
                    (sum1 > POWER_THRESHOLD) and
                    (sum2 > POWER_THRESHOLD) and
                    (sum3 > POWER_THRESHOLD)) then
                    case ( to_integer( unsigned(edge_qualifier))) is
                        when 3 | 5 | 9 | 6 | 10 | 12 | 7 | 11 | 14 | 15 =>
                            preamble_detected <= '1';
                            edge_register <= edge_qualifier;
                        when others => preamble_detected <= '0';
                    end case;
                else
                    preamble_detected <= '0';
                end if;

                register_rpl <= resize(shift_right( (max(0) + max(1) + max(2) + max(3)), 2 ) ,rpl'length);
            end if;

            if(in_valid = '1') then
                power_grid <= power_in & power_grid(power_grid'length-1 downto 1);
                edge_grid <= edge_in & edge_grid(edge_grid'length-1 downto 1);

                --update sums
                sum0 := sum0 + power_grid(sum0_in) - power_grid(sum0_out);
                sum1 := sum1 + power_grid(sum1_in) - power_grid(sum1_out);
                sum2 := sum2 + power_grid(sum2_in) - power_grid(sum2_out);
                sum3 := sum3 + power_grid(sum3_in) - power_grid(sum3_out);

                --register edges
                edge_qualifier(0) <= edge_grid(sum0_out);
                edge_qualifier(1) <= edge_grid(sum1_out);
                edge_qualifier(2) <= edge_grid(sum2_out);
                edge_qualifier(3) <= edge_grid(sum3_out);

                -- Look three valid samples ahead in the grid, then perform one
                -- comparison per stage. Each stage advances only with in_valid,
                -- so the final maximum still describes the current window and
                -- adds no output latency, including across idle clock cycles.
                for i in WINDOW_TAPS'range loop
                    max(i) := greater_power(window_merge(i)(0), window_merge(i)(1));
                    window_merge(i)(0) <= greater_power(window_pairs(i)(0), window_pairs(i)(1));
                    window_merge(i)(1) <= window_pairs(i)(2);
                    window_pairs(i)(0) <= greater_power(window_samples(i)(0), window_samples(i)(1));
                    window_pairs(i)(1) <= greater_power(window_samples(i)(2), window_samples(i)(3));
                    window_pairs(i)(2) <= window_samples(i)(4);
                    for j in 0 to 4 loop
                        window_samples(i)(j) <= positive_max(
                            power_grid(WINDOW_TAPS(i) + j + 3),
                            to_signed(0, INPUT_POWER_WIDTH));
                    end loop;
                end loop;
            end if;

            register_valid <= in_valid;
        end if;
    end process;

    count_detections : process(clock, reset)
        variable detections : integer := 0 ;
    begin
        if( reset = '1' ) then
            detections := 0 ;
        elsif( rising_edge(clock) ) then
            if( preamble_detected = '1' ) then
                detections := detections + 1 ;
            end if ;
        end if ;
    end process ;

    clock_out : process(clock, reset)
        variable current_rpl            : signed(INPUT_POWER_WIDTH-1 downto 0);
        variable pending_downcount      : integer range 0 to MESSAGE_DELAY;
        variable message_active         : std_logic_vector(NUM_MESSAGE_DECODER-1 downto 0);
        variable current_decoder_index  : integer range 0 to NUM_MESSAGE_DECODER-1;
        variable ignored                : integer ;
        variable coulda                 : integer ;
        variable larger_rpl             : boolean;
        variable cleared_rpl            : boolean;
    begin
        if( reset = '1') then
            som <= (others => '0');
            current_rpl := (others => '0');
            message_active := (others => '0');
            som_pending <= (others => '0');
            current_decoder_index := 0;
            current_rpl := to_signed(0,current_rpl'length);
            ignored := 0 ;
            coulda := 0 ;
        elsif (rising_edge(clock)) then
            som <= (others => '0');
            out_valid <= register_valid;
            power_out <= power_grid(122);
            rpl <= current_rpl;
            if( register_valid = '1') then
                -- Compare with the old value in parallel with countdown/clear
                -- selection, rather than placing a clear mux before a second
                -- wide comparison on the feedback path.
                larger_rpl := register_rpl > current_rpl;
                cleared_rpl := false;

                --begin counting down the remainder of the preamble
                if som_pending(current_decoder_index)  = '1' then
                    if pending_downcount > 0 then
                        pending_downcount := pending_downcount -1;
                    else
                        -- NOTE: Not sure what to do with this logic to count correctly
                        -- and get rid of passing preambles which aren't good anymore?
                        if( decoder_busy(current_decoder_index) = '0' ) then
                            message_active(current_decoder_index) := '1';
                            som(current_decoder_index) <= '1';
                            som_pending(current_decoder_index) <= '0';
                            current_rpl := to_signed(0,current_rpl'length);
                            cleared_rpl := true;

                            if (current_decoder_index = NUM_MESSAGE_DECODER-1) then
                                current_decoder_index := 0;
                            else
                                current_decoder_index := current_decoder_index +1;
                            end if;
                        else
                            -- report "Current decoder busy - possible lost preamble" ;
                            som_pending(current_decoder_index) <= '0' ;
                            current_rpl := (others =>'0') ;
                            cleared_rpl := true;
                            for i in decoder_busy'range loop
                                if decoder_busy(i) = '0' then
                                    coulda := coulda + 1 ;
                                    exit ;
                                end if ;
                            end loop ;
                            ignored := ignored + 1 ;
                        end if ;
                    end if;
                end if;

                if ( preamble_detected = '1') then
                    if (cleared_rpl and register_rpl > to_signed(0, INPUT_POWER_WIDTH)) or
                       (not cleared_rpl and larger_rpl) then
                        current_rpl := register_rpl;
                        pending_downcount := 3;
                        som_pending(current_decoder_index) <= '1';
                    end if;
                end if;

            end if;
        end if;
    end process;

end architecture;

