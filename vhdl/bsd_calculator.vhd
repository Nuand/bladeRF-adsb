library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;

library work ;
    use work.adsb_decoder_p.all ;

entity bsd_calculator is
  port(
    clock           : in std_logic;
    reset           : in std_logic;

    rpl_in          : in signed(INPUT_POWER_WIDTH-1 downto 0);
    rpl_valid       : in std_logic;

    power_in        : in signed(INPUT_POWER_WIDTH-1 downto 0);
    power_in_valid  : in std_logic;

    bsd             : out signed(7 downto 0);
    bhd             : out std_logic;
    out_valid       : out std_logic
  );
end entity;

architecture arch of bsd_calculator is

    constant SPS        : integer := 8;

    type weight_array_t is array(natural range <>) of integer range 0 to 3;
    constant weights    : weight_array_t(0 to SPS-1) := (0,0,1,1,1,1,0,0) ; -- (1,1,2,2,2,2,1,1);

    signal sample_count : integer range 0 to 2*SPS;

    signal score0       : signed(INPUT_POWER_WIDTH-1 downto 0);
    signal score1       : signed(INPUT_POWER_WIDTH-1 downto 0);
    signal score0_reg   : signed(INPUT_POWER_WIDTH-1 downto 0);
    signal score1_reg   : signed(INPUT_POWER_WIDTH-1 downto 0);

    signal rpl_low      : signed(INPUT_POWER_WIDTH-1 downto 0);
    signal rpl_high     : signed(INPUT_POWER_WIDTH-1 downto 0);
    signal rpl_lowlow   : signed(INPUT_POWER_WIDTH-1 downto 0);

    type bsd_hit_t is array(natural range <>) of signed(7 downto 0);
    signal typeA        : bsd_hit_t(0 to 2*SPS-1);
    signal typeB        : bsd_hit_t(0 to 2*SPS-1);

    signal bsd_request  : std_logic;
    signal score_it     : std_logic;


begin

    --this is the main loop responsible for scoring the samples
    calculate : process(clock,reset)
        variable sps_downcount : integer range 0 to SPS;
        variable b0_index : integer range 0 to SPS-1;
        variable b1_index : integer range SPS to (2*SPS)-1;
        variable local_count : integer range 0 to 15;

        variable tmp_score1 : signed(INPUT_POWER_WIDTH-1 downto 0);
        variable tmp_score0 : signed(INPUT_POWER_WIDTH-1 downto 0);
    begin
        if(reset ='1') then
            score0 <= (others => '0');
            score1 <= (others => '0');
            bsd_request <= '0';
            sample_count <= 0;

            b0_index := 0;
            b1_index := SPS;

        elsif( rising_edge(clock)) then
            bsd_request <= '0';
            out_valid <= bsd_request;
            if(bsd_request ='1') then
                bsd <= resize(score1_reg - score0_reg, bsd'length);
                if(score1_reg > score0_reg) then
                    bhd <= '1';
                else
                    bhd <= '0';
                end if;
            end if;

            if score_it = '1' then
                if(local_count > 7) then
                    tmp_score1 := resize(shift_left(typeA(b0_index), weights(b0_index)) -
                                        shift_left(typeA(b1_index), weights(b0_index)) -
                                        shift_left(typeB(b0_index),weights(b0_index)) +
                                        shift_left(typeB(b1_index),weights(b0_index)),tmp_score1'length);

                    score1 <= score1 + tmp_score1;

                    tmp_score0 := resize(shift_left(typeA(b1_index),weights(b0_index)) -
                                        shift_left(typeA(b0_index),weights(b0_index)) -
                                        shift_left(typeB(b1_index),weights(b0_index)) +
                                        shift_left(typeB(b0_index),weights(b0_index)),tmp_score0'length);

                    score0 <= score0 + tmp_score0;

                    if(b0_index = 7) then
                        bsd_request <= '1';
                        score1_reg <= score1;
                        score0_reg <= score0;
                        score1 <= (others => '0');
                        score0 <= (others => '0');
                        b0_index := 0;
                        b1_index := SPS;
                    else
                        b0_index := b0_index + 1;
                        b1_index := b1_index + 1;
                    end if;
                end if;

                if (local_count = 15) then
                    local_count := 0;
                else
                    local_count := local_count + 1;
                end if;
            end if;

            score_it <= power_in_valid;

            if(power_in_valid = '1') then
                if ((power_in > rpl_low) and (power_in < rpl_high)) then
                    typeA(sample_count) <= to_signed(1,8);
                    typeB(sample_count) <=to_signed(0,8);
                elsif (power_in < rpl_lowlow) then
                    typeA(sample_count) <= to_signed(0,8);
                    typeB(sample_count) <= to_signed(1,8);
                else
                    typeA(sample_count) <= to_signed(0,8);
                    typeB(sample_count) <= to_signed(0,8);
                end if;

                if(sample_count = 15) then
                    sample_count <= 0;
                else
                    sample_count <= sample_count + 1;
                end if;
            end if;

            if(rpl_valid = '1') then
                rpl_low <= rpl_in  - (shift_right(rpl_in,1) + shift_right(rpl_in,2));
                rpl_high <= rpl_in + shift_right(rpl_in,1) + shift_right(rpl_in,2);
                rpl_lowlow <= shift_right(rpl_in  - (shift_right(rpl_in,1) + shift_right(rpl_in,2)),1);
                sample_count <= 0;
                local_count := 0;
            end if;

        end if;
    end process;

end architecture;

