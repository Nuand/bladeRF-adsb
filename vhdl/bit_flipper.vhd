library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;


entity bit_flipper is
    port(
        clock : in std_logic;
        reset : in std_logic;

        bsd : in signed(7 downto 0);
        bhd : in std_logic;
        out_valid : in std_logic
    );
end entity;


architecture arch of bit_flipper is
    --
begin

end architecture;