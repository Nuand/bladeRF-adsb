library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;

library work ;
    use work.adsb_decoder_p.all ;

entity adsb_edge_detector is
  port (
    clock       : in std_logic;
    reset       : in std_logic;

    init        : in std_logic;

    power_in    : in signed(INPUT_POWER_WIDTH-1 downto 0);
    in_valid    : in std_logic;

    power_out   : out signed(INPUT_POWER_WIDTH-1 downto 0);
    edge_out    : out std_logic;
    out_valid   : out std_logic
  );
end entity;

architecture arch of adsb_edge_detector is

    constant SPS                : integer := 8;
    constant EDGE_BUFFER_LENGTH : integer := SPS + 1;
    constant CENTER_TAP         : integer := EDGE_BUFFER_LENGTH-5;
    constant POWER_THRESHOLD    : signed := to_signed(integer(100),INPUT_POWER_WIDTH);

    type power_array is array(natural range <>) of signed(INPUT_POWER_WIDTH-1 downto 0);
    signal power_grid           : power_array (0 to EDGE_BUFFER_LENGTH-1);

    signal power_exceeds_thresh : std_logic_vector(0 to EDGE_BUFFER_LENGTH-1);
    signal edge_grid            : std_logic_vector(0 to CENTER_TAP-1);

    signal valid_delay          : std_logic_vector((2*EDGE_BUFFER_LENGTH)-1 downto 0);

begin

    shift_input : process(clock,reset)
        variable tmp_power      : integer;
        variable p_center       : signed(INPUT_POWER_WIDTH-1 downto 0);
        variable p_center_m1    : signed(INPUT_POWER_WIDTH-1 downto 0);
        variable p_center_p1    : signed(INPUT_POWER_WIDTH-1 downto 0);
        variable calculate_edge : std_logic;
        variable exceeds_count  : integer range 0 to 5;
        variable edge_detected  : std_logic;
        variable sample_counter : integer := 0;
    begin
        if(reset = '1') then
            calculate_edge := '0';
            valid_delay <= (others => '0');
        elsif(rising_edge(clock)) then
            if(calculate_edge = '1')  then
                sample_counter := sample_counter +1;
                --check the ratios
                p_center := power_grid(CENTER_TAP-1);
                p_center_m1 := power_grid(CENTER_TAP-2);
                p_center_p1 := power_grid(CENTER_TAP);
                if(  (p_center > p_center_m1 ) and
                    (p_center < p_center_p1) and
                    (exceeds_count >= 5)) then

                    edge_grid <= edge_grid(1 to CENTER_TAP-1) & '1';
                    edge_detected := '1';
                else
                    edge_grid <= edge_grid(1 to CENTER_TAP-1) & '0';
                    edge_detected := '0';
                end if;
            else
                edge_detected := '0';
            end if;

            if(in_valid = '1') then
                power_grid <= power_grid(1 to power_grid'length-1) & power_in;

                if(power_in > POWER_THRESHOLD) then
                    power_exceeds_thresh <= power_exceeds_thresh(1 to power_grid'length-1) & '1';
                else
                    power_exceeds_thresh <= power_exceeds_thresh(1 to power_grid'length-1) & '0';
                end if;

                tmp_power := to_integer( unsigned(power_exceeds_thresh(CENTER_TAP to EDGE_BUFFER_LENGTH-1)));
                case (tmp_power) is
                    when 30 | 35 | 33 | 27 | 17 => exceeds_count := 4;
                    when 31=> exceeds_count := 5;
                    when others => exceeds_count := 0;
                end case;
            end if;

            valid_delay <= in_valid & valid_delay(valid_delay'length-1 downto 1);

            --register output
            out_valid <= valid_delay(0);
            power_out <= power_grid(0);
            edge_out <= edge_grid(0);

            calculate_edge := in_valid;
        end if;
    end process;

end architecture;

