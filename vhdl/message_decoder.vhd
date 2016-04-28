library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;

library work ;
    use work.adsb_decoder_p.all ;

entity message_decoder is
  port(
    clock       :   in  std_logic;
    reset       :   in  std_logic;

    busy        :   out std_logic ;

    power_in    :   in  signed(INPUT_POWER_WIDTH-1 downto 0);
    rpl_in      :   in  signed(INPUT_POWER_WIDTH-1 downto 0);
    som         :   in  std_logic;
    in_valid    :   in  std_logic;

    msg_bits    :   out std_logic_vector(111 downto 0) ;
    msg_valid   :   out std_logic
  );
end entity;


architecture arch of message_decoder is

    constant SPS                        :   integer := 8;
    constant SPB                        :   integer := 2;
    constant EXTENDED_MESSAGE_LENGTH    :   integer := 112*SPS*SPB*2;

    signal rpl_reg                      :   signed(INPUT_POWER_WIDTH-1 downto 0);
    signal rpl_reg_valid                :   std_logic;

    signal bsd                          :   signed(7 downto 0);
    signal bhd                          :   std_logic;
    signal bsd_valid                    :   std_logic;

    signal power                        :   signed(INPUT_POWER_WIDTH-1 downto 0);
    signal power_valid                  :   std_logic;
    signal power_delay                  :   signed(INPUT_POWER_WIDTH-1 downto 0);
    signal power_delay_valid            :   std_logic;

    signal active                       :   std_logic;

    signal accum_byte                   :   std_logic_vector(7 downto 0);
    signal byte_reg                     :   std_logic_vector(7 downto 0);
    signal byte_reg_valid               :   std_logic;

    signal flipper_busy                 :   std_logic;
    signal flipper_bits                 :   std_logic_vector(111 downto 0) ;
    signal flipper_valid                :   std_logic ;

begin

    busy <= flipper_busy ;
    msg_bits <= flipper_bits ;
    msg_valid <= flipper_valid ;

    delay_input : process(clock,reset)
        variable downcount : integer range 0 to (EXTENDED_MESSAGE_LENGTH);
        variable ignored : integer ;
    begin
        if(reset = '1') then
            power_valid <= '0';
            active <= '0';
            rpl_reg_valid <= '0';
            ignored := 0 ;
        elsif rising_edge(clock) then

            rpl_reg_valid <= '0';
            power_valid <= '0';

            power_delay <= power;
            power_delay_valid <= power_valid;

            if(som = '1') or (active = '1') then
                power <= power_in;
                power_valid <= in_valid;
            end if;

            if(downcount > 0) then
                downcount := downcount -1;
            else
                active <= '0';
            end if;

            if som ='1' and active = '0' then
                rpl_reg_valid <= '1';
                rpl_reg <= rpl_in;

                active <= '1';
                downcount := EXTENDED_MESSAGE_LENGTH;
            elsif som = '1' and active = '1' then
                -- report "Already busy and ignored request" ;
                ignored := ignored + 1 ;
            end if;

        end if;
    end process;

    -- Gate the input to the bsd calculator based on the som flag
    U_bsd_calculator : entity work.bsd_calculator
      port map(
        clock           =>  clock,
        reset           =>  reset,

        power_in        =>  power_delay,
        power_in_valid  =>  power_delay_valid,

        rpl_in          =>  rpl_reg,
        rpl_valid       =>  rpl_reg_valid,

        bsd             =>  bsd,
        bhd             =>  bhd,
        out_valid       =>  bsd_valid
      );

    U_bit_flipper : entity work.bit_flipper
      port map (
        clock       =>  clock,
        reset       =>  reset,

        start       =>  rpl_reg_valid,

        busy        =>  flipper_busy,

        in_bsd      =>  bsd,
        in_bhd      =>  bhd,
        in_valid    =>  bsd_valid,

        msg_bits    =>  flipper_bits,
        msg_valid   =>  flipper_valid
      ) ;

end architecture;

