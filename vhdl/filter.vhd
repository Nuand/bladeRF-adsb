library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;
    use ieee.math_real.all ;

library work ;
    use work.adsb_decoder_p.all ;

entity adsb_filter is
  generic (
    IN_WIDTH        :       positive                    := 16 ;
    OUT_WIDTH       :       positive                    := 16 ;
    OUT_SHIFT       :       natural                     := 12 ;
    COEFF_WIDTH     :       positive                    := 16 ;
    ACCUM_WIDTH     :       positive                    := 32 ;
    COEFF_SCALE     :       real                        := 4096.0
  ) ;
  port (
    clock       :   in  std_logic ;
    reset       :   in  std_logic ;

    in_real     :   in  signed(IN_WIDTH-1 downto 0) ;
    in_imag     :   in  signed(IN_WIDTH-1 downto 0) ;
    in_valid    :   in  std_logic ;

    out_real    :   out signed(OUT_WIDTH-1 downto 0) ;
    out_imag    :   out signed(OUT_WIDTH-1 downto 0) ;
    out_valid   :   out std_logic
  ) ;
end entity ;

architecture arch of adsb_filter is

    constant H_REAL : real_array_t := (
         0.000160545350358,
        -0.000366048452660,
        -0.000376026556579,
        -0.000373446090727,
        -0.000190262840876,
         0.000267028727949,
         0.000926989090486,
         0.001475806958215,
         0.001415649309576,
         0.000319527421089,
        -0.001790067838862,
        -0.004157203891254,
        -0.005372475818846,
        -0.003958142843588,
         0.000672638435938,
         0.007411177013118,
         0.013267475982319,
         0.014337138356342,
         0.007678774473321,
        -0.006571408585021,
        -0.023970170691367,
        -0.036324797911250,
        -0.034274523881958,
        -0.011131800085463,
         0.033569446586354,
         0.092508911317109,
         0.152009699530610,
         0.196214494595155,
         0.212544275495700,
         0.196214494595155,
         0.152009699530610,
         0.092508911317109,
         0.033569446586354,
        -0.011131800085463,
        -0.034274523881958,
        -0.036324797911250,
        -0.023970170691367,
        -0.006571408585021,
         0.007678774473321,
         0.014337138356342,
         0.013267475982319,
         0.007411177013118,
         0.000672638435938,
        -0.003958142843588,
        -0.005372475818846,
        -0.004157203891254,
        -0.001790067838862,
         0.000319527421089,
         0.001415649309576,
         0.001475806958215,
         0.000926989090486,
         0.000267028727949,
        -0.000190262840876,
        -0.000373446090727,
        -0.000376026556579,
        -0.000366048452660,
         0.000160545350358
    ) ;

    type sample_t is record
        re  :   signed(in_real'range) ;
        im  :   signed(in_imag'range) ;
    end record ;

    type product_t is record
        re  :   signed(ACCUM_WIDTH - 1 downto 0) ;
        im  :   signed(ACCUM_WIDTH - 1 downto 0) ;
    end record ;

    function "*"( L : real ; R : real_array_t ) return integer_array_t is
        variable rv : integer_array_t(R'range) ;
    begin
        for i in R'range loop
            rv(i) := integer(round(L*R(i))) ;
        end loop ;
        return rv ;
    end function ;

    function "*"( L : sample_t ; R : signed ) return product_t is
        variable rv : product_t ;
    begin
        rv.re := resize(L.re * R, rv.re'length) ;
        rv.im := resize(L.im * R, rv.im'length) ;
        return rv ;
    end function ;

    constant H : integer_array_t := COEFF_SCALE*H_REAL ;

    constant H_CENTER : integer := integer(ceil(real(H_REAL'length)/2.0)) - 1 ;

    function "+"(L : sample_t ; R : sample_t ) return sample_t is
        variable rv : sample_t ;
    begin
        rv.re := L.re + R.re ;
        rv.im := L.im + R.im ;
        return rv ;
    end function ;

    function"+"( L, R : product_t ) return product_t is
        variable rv : product_t ;
    begin
        rv.re := L.re + R.re ;
        rv.im := L.im + R.im ;
        return rv ;
    end function ;

    type samples_t is array (natural range <>) of sample_t ;

    type products_t is array (natural range <>) of product_t ;

    signal state : samples_t(H_REAL'range) := (others =>((others =>'0'), (others =>'0')));

    signal presums : samples_t(0 to H_CENTER) ;

    signal products : products_t(0 to H_CENTER) ;

    signal accums : products_t(0 to H_CENTER) ;

    signal tree_start : std_logic ;

    type tree_t is array (natural range <>, natural range<>) of product_t ;

    constant NUM_STAGES : natural := integer(ceil(log2(real(H_CENTER)))) ;

    function zeroize return tree_t is
        variable rv : tree_t(0 to NUM_STAGES-1, 0 to H_CENTER) ;
    begin
        for i in 0 to NUM_STAGES-1 loop
            for j in 0 to H_CENTER loop
                rv(i, j) := (re => (others => '0'), im =>(others =>'0')) ;
            end loop ;
        end loop ;
        return rv ;
    end function ;

    signal tree : tree_t(0 to NUM_STAGES-1, 0 to H_CENTER) := ZEROIZE ;
    signal tree_valids : std_logic_vector(0 to NUM_STAGES-1) ;

    signal presum : std_logic ;

    signal multiply : std_logic ;

    signal accum : std_logic ;

    constant CPS : positive := 2 ;

    signal taps : samples_t(0 to integer(ceil(real(H'length)/real(CPS)/2.0))) ;

    signal sel : natural range 0 to CPS-1 ;

begin

    -- Shift state
    shift_state : process(clock, reset)
        variable sample : sample_t ;
    begin
        if( reset = '1' ) then
            presum <= '0' ;
        elsif( rising_edge(clock) ) then
            presum <= in_valid ;
            sample.re := in_real ;
            sample.im := in_imag ;
            if( in_valid = '1' ) then
                state <= sample & state(0 to state'high-1) ;
            end if ;
        end if ;
    end process ;

    -- Tap mux
    for i in taps'range generate
        taps(i) <= state(CPS*i+sel) ;
    end generate ;

    -- Presum
    make_presums : process(clock, reset)
        variable presum_delay : std_logic ;
        variable l, r : natural ;
    begin
        if( reset = '1' ) then
            presum_delay := '0' ;
            multiply <= '0' ;
        elsif( rising_edge(clock) ) then
            if( presum = '1' ) then
                for i in 0 to H_CENTER loop
                    l := 2*i ;
                    r := H'high-l ;
                    if( l < r ) then
                        presums(i) <= state(l) + state(r) ;
                    elsif( l = r ) then
                        presums(i) <= state(l) ;
                   end if ;
                end loop ;
            elsif( presum_delay = '1' ) then
                for i in 0 to H_CENTER-1 loop
                    l := 2*i+1 ;
                    r := H'high-l+1 ;
                    if( l < r ) then
                        presums(i) <= state(l) + state(r) ;
                    elsif( l = r ) then
                        presums(i) <= state(l) ;
                    end if ;
                end loop ;
            end if ;
            multiply <= presum ;
            presum_delay := presum ;
        end if ;
    end process ;

    -- Products
    make_products : process(clock, reset)
        variable multiply_delay : std_logic ;
    begin
        if( reset = '1' ) then
            accum <= '0' ;
            multiply_delay := '0' ;
        elsif( rising_edge(clock) ) then
            accum <= multiply ;
            if( multiply = '1' ) then
                for i in presums'range loop
                    if( 2*i < H'high ) then
                        products(i) <= presums(i) * to_signed(H(2*i), ACCUM_WIDTH) ;
                    end if ;
                end loop ;
            elsif( multiply_delay = '1' ) then
                for i in presums'range loop
                    if( 2*i+1 < H'high ) then
                        products(i) <= presums(i) * to_signed(H(2*i+1), ACCUM_WIDTH) ;
                    end if ;
                end loop ;
            end if ;
            multiply_delay := multiply ;
        end if ;
    end process ;

    -- Accumulate
    accumulate_and_kick_tree : process(clock, reset)
        variable accum_delay : std_logic ;
    begin
        if( reset = '1' ) then
            accum_delay := '0' ;
            tree_start <= '0' ;
        elsif( rising_edge(clock) ) then
            if( accum = '1' ) then
                for i in accums'range loop
                    accums(i) <= products(i) ;
                end loop ;
            elsif( accum_delay = '1' ) then
                for i in accums'range loop
                    accums(i) <= accums(i) + products(i) ;
                end loop ;
            end if ;
            tree_start <= accum_delay ;
            accum_delay := accum ;
        end if ;
    end process ;

    -- Tree adder
    tree_adder : process(clock, reset)
    begin
        if( reset = '1' ) then
            tree_valids <= (others =>'0') ;
        elsif( rising_edge(clock) ) then
            tree_valids <= tree_start & tree_valids(0 to tree_valids'high-1) ;

            for tap in 0 to tree'length(1) loop
                tree(0, tap) <= accums(tap) ;
            end loop ;

            for stage in 1 to tree_valids'high loop
                if( tree_valids(stage) = '1' ) then
                    for tap in 0 to tree'length(1)/2 loop
                        tree(stage,tap) <= tree(stage-1,2*tap) + tree(stage-1,2*tap+1) ;
                    end loop ;
                end if ;
            end loop ;
        end if ;
    end process ;


    -- Output
    out_real <= resize(shift_right(tree(tree'high(1),0).re, OUT_SHIFT), out_real'length) ;
    out_imag <= resize(shift_right(tree(tree'high(1),0).im, OUT_SHIFT), out_imag'length) ;
    out_valid <= tree_valids(tree_valids'high) ;

end architecture ;

