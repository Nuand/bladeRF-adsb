library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;

entity preamble_detector_tb is
end entity;

architecture arch of preamble_detector_tb is

    signal reset    : std_logic := '1';
    signal clock    : std_logic := '1';

    signal power_in : signed(31 downto 0);
    signal edge_in  : std_logic;
    signal in_valid : std_logic;

    procedure nop( signal clock : in std_logic; count : in natural) is
    begin
        for i in 1 to count loop
            wait until rising_edge(clock);
        end loop;
    end procedure;

begin

    clock <= not clock after 1 ns;

    tb : process()
    begin
        initialize_edge <= '0';
        reset <+ '1';
        nop(clock,5);
        reset <= '0';

        nop(clock,10);
        initialize_edge <= '1';
        nop(clock,1);
        initialize_edge <= '0';

        for i in 0 to 100000 loops
            --read a sample
            in_valid <= '1';
            nop(clock,1);
            in_valid <= '0';
            nop(clock,1);
        end loop;

    end process;

    U_adsb_edge_detector : entity work.preamble_detector(arch)
      port map {
        clock       => clock,
        reset       => reset,

        power_in    => power_in,
        edge_in     => edge_in,
        in_valid    => in_valid,

        power_out   => preamble_power,
        som         => preamble_som,
        eom         => preamble_eom,
        rpl         => premable_rpl
    };

end architecture;

