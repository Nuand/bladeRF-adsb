library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;

entity message_decoder is
    port(
        clock : in std_logic;
        reset : in std_logic;

        power_in : in signed(31 downto 0);
        rpl_in : in signed(31 downto 0);
        som : in std_logic;
        eom : in std_logic;
        in_valid : in std_logic;

        message_byte : out unsigned(7 downto 0);
        message_rdy : out std_logic;
        message_read : in std_logic
    );
end entity;


architecture arch of message_decoder is
    --
    signal bsd : signed(7 downto 0);
    signal bhd : std_logic;
    signal bsd_valid : std_logic;

    signal power : signed(31 downto 0);
    signal power_valid : std_logic;

    signal active : std_logic;

    signal accum_byte : std_logic_vector(7 downto 0);
    signal byte_reg : std_logic_vector(7 downto 0);
    signal byte_reg_valid : std_logic;


    signal busy : std_logic; 
    signal message_bits : std_logic_vector(111 downto 0);
    signal message_bits_valid : std_logic;

    signal crc : std_logic_vector(23 downto 0);
    signal crc_good : std_logic;
    signal crc_valid : std_logic;

begin

    delay_input : process(clock,reset)
    begin
        if(reset = '1') then
            --
            active <= '0';
        elsif rising_edge(clock) then
                --
            power_valid <= '0';

            if(som = '1') or (active = '1') then
                power <= power_in;
                power_valid <= in_valid;
            end if;

            if som ='1' then
                active <= '1';
            end if;

            if eom = '1' then
                active <= '0';
            end if;

        end if;
    end process;

    --gate the input to the bsd calculator based on the som flag
    U_bsd_calculator : entity work.bsd_calculator 
    port map(
        clock   => clock,
        reset   => reset,

        power_in    => power,
        power_in_valid => power_valid,

        rpl_in      => rpl_in,
        rpl_valid    => in_valid and som,

        bsd         => bsd,
        bhd         => bhd,
        out_valid   => bsd_valid
    );

    bits_to_bytes : process(clock,reset)
        variable bit_count : integer range 0 to 8;
    begin
        if (reset = '1') then
            --
            byte_reg_valid <= '0';
            accum_byte <= (others => '0');
            bit_count := 0;
        elsif rising_edge(clock) then

            byte_reg_valid <= '0';
            if(bit_count = 8) then
                byte_reg <= accum_byte;
                byte_reg_valid <= '1';
                bit_count := 0;
            end if;


            if(bsd_valid =  '1') then
                accum_byte <= accum_byte(accum_byte'length-2 downto 0) & bhd;
                bit_count := bit_count +1;
            end if;
        end if;
    end process;

    crc_prep : process(clock,reset)
        variable message_byte_count : integer range 0 to 14;
    begin
        if (reset = '1') then  
            message_bits_valid <= '0';
            message_byte_count := 0;

        elsif rising_edge(clocK) then

            message_bits_valid <= '0';

            if(message_byte_count = 14) then
                message_bits_valid <= '1';
                message_byte_count := 0;
            end if;

            if(byte_reg_valid = '1') then
                message_byte_count := message_byte_count +1;
                message_bits <= byte_reg & message_bits(message_bits'length-1 downto 8);
            end if;

        end if;
    end process;



    U_adsb_crc : entity work.adsb_crc
      port map (
        clock       =>  clock,
        reset       =>  reset,

        busy        =>  busy,

        data        =>  message_bits,
        data_valid  =>  message_bits_valid,

        crc         =>  crc,
        crc_good    =>  crc_good,
        crc_valid   =>  crc_valid
      ) ;


    check_crc_valid : process(clock, reset)
        variable passes : natural := 0 ;
        variable failures : natural := 0 ;
    begin
        if( rising_edge(clock) ) then
            if( crc_valid = '1' ) then
                if( crc_good = '1' ) then
                    passes := passes + 1 ;
                    report "CRC check PASSED! (" & integer'image(passes) & "/" & integer'image(failures) & ")" ;
                else
                    failures := failures + 1 ;
                    report "CRC check FAILED! (" & integer'image(passes) & "/" & integer'image(failures) & ")";
                end if ;
            end if ;
        end if ;
    end process ;


end architecture;
