library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;

package adsb_decoder_p is

    constant INPUT_POWER_WIDTH  :   natural     := 24 ;

    type messages_t is array(natural range <>) of std_logic_vector(111 downto 0) ;

    function larger_power(a, b : signed) return boolean;

end package ;

package body adsb_decoder_p is
    function larger_power(a, b : signed) return boolean is
        constant CHUNK : positive := INPUT_POWER_WIDTH / 4;
        type flags_t is array(0 to 3) of boolean;
        variable gt, eq : flags_t;
    begin
        if is_x(std_logic_vector(a)) or is_x(std_logic_vector(b)) then
            return false;
        end if;
        for i in 0 to 3 loop
            if i = 3 then
                gt(i) := a((i+1)*CHUNK-1 downto i*CHUNK) > b((i+1)*CHUNK-1 downto i*CHUNK);
            else
                gt(i) := unsigned(a((i+1)*CHUNK-1 downto i*CHUNK)) > unsigned(b((i+1)*CHUNK-1 downto i*CHUNK));
            end if;
            eq(i) := a((i+1)*CHUNK-1 downto i*CHUNK) = b((i+1)*CHUNK-1 downto i*CHUNK);
        end loop;
        -- Parallel six-bit comparisons and a prefix select avoid a full-width
        -- carry comparison followed by countdown and register-enable selection.
        return gt(3) or (eq(3) and gt(2)) or
               (eq(3) and eq(2) and gt(1)) or
               (eq(3) and eq(2) and eq(1) and gt(0));
    end function;
end package body;
