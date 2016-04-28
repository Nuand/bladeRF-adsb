library ieee ;
    use ieee.std_logic_1164.all ;
    use ieee.numeric_std.all ;
    use ieee.math_real.all ;

library work ;
    use work.adsb_decoder_p.all ;
    use work.constellation_mapper_p.all ;

entity adsb_fe is
  port (
    clock       :   in  std_logic ;
    reset       :   in  std_logic ;

    in_i        :   in  signed(15 downto 0) ;
    in_q        :   in  signed(15 downto 0) ;
    in_valid    :   in  std_logic ;

    out_power   :   out signed(INPUT_POWER_WIDTH-1 downto 0) ;
    out_valid   :   out std_logic
  ) ;
end entity ;

architecture arch of adsb_fe is

    constant ADSB_FIR : real_array_t := (
       -0.000216247569686,
       -0.000020724358659,
        0.000123766030519,
        0.000318482422536,
        0.000456463780913,
        0.000415041799656,
        0.000124323884803,
       -0.000368199608286,
       -0.000876954712595,
       -0.001130575705366,
       -0.000892166593419,
       -0.000103306549465,
        0.001022007654987,
        0.002020458262442,
        0.002342720046275,
        0.001612248911395,
       -0.000129358168311,
       -0.002321556391756,
       -0.004020043390952,
       -0.004262395933029,
       -0.002538656106627,
        0.000841820235738,
        0.004692674044728,
        0.007304733049356,
        0.007137767524445,
        0.003594115605862,
       -0.002478216415413,
       -0.008847746093807,
       -0.012620455755530,
       -0.011431850349189,
       -0.004652151489444,
        0.005928945775480,
        0.016360799223919,
        0.021805836336930,
        0.018479917160421,
        0.005561084359393,
       -0.013734999696855,
       -0.032495397736209,
       -0.041966304256972,
       -0.034433198103896,
       -0.006176262454164,
        0.040586302435419,
        0.097582796450275,
        0.152409921101041,
        0.191978580808684,
        0.206393968476306,
        0.191978580808684,
        0.152409921101041,
        0.097582796450275,
        0.040586302435419,
       -0.006176262454164,
       -0.034433198103896,
       -0.041966304256972,
       -0.032495397736209,
       -0.013734999696855,
        0.005561084359393,
        0.018479917160421,
        0.021805836336930,
        0.016360799223919,
        0.005928945775480,
       -0.004652151489444,
       -0.011431850349189,
       -0.012620455755530,
       -0.008847746093807,
       -0.002478216415413,
        0.003594115605862,
        0.007137767524445,
        0.007304733049356,
        0.004692674044728,
        0.000841820235738,
       -0.002538656106627,
       -0.004262395933029,
       -0.004020043390952,
       -0.002321556391756,
       -0.000129358168311,
        0.001612248911395,
        0.002342720046275,
        0.002020458262442,
        0.001022007654987,
       -0.000103306549465,
       -0.000892166593419,
       -0.001130575705366,
       -0.000876954712595,
       -0.000368199608286,
        0.000124323884803,
        0.000415041799656,
        0.000456463780913,
        0.000318482422536,
        0.000123766030519,
       -0.000020724358659,
       -0.000216247569686
    );

    signal mixed_i      :   signed(in_i'range) ;
    signal mixed_q      :   signed(in_q'range) ;
    signal mixed_valid  :   std_logic ;

    signal filt_i       :   signed(in_i'range) ;
    signal filt_q       :   signed(in_q'range) ;
    signal filt_valid   :   std_logic ;

    signal pow          :   signed(out_power'range) ;
    signal pow_valid    :   std_logic ;

begin

    mfs_4_mix : process(clock,reset)
        variable index : unsigned(1 downto 0);
    begin
        if( reset = '1' ) then
            index := to_unsigned(0,index'length);
            mixed_valid <= '0';
        elsif rising_edge(clock) then

            mixed_valid <= in_valid;
            if( in_valid = '1') then
                case to_integer(index) is
                    when 0=>
                        mixed_i <=  in_i ;
                        mixed_q <=  in_q ;
                    when 1=>
                        mixed_i <=  in_q ;
                        mixed_q <= -in_i ;
                    when 2 =>
                        mixed_i <= -in_i ;
                        mixed_q <= -in_q ;
                    when 3=>
                        mixed_i <= -in_q ;
                        mixed_q <=  in_i ;

                    when others =>
                        report "ERROR IN INDEX!";
                end case;

                index := index + to_unsigned(1,index'length);
            end if;
        end if;
    end process;

    -- Filter
    U_filter_re : entity work.fir_filter(systolic)
      generic map (
        CPS             => 2,
        INPUT_WIDTH     => mixed_i'length,
        OUTPUT_WIDTH    => filt_i'length,
        ACCUM_SCALE     => 24,
        H               => ADSB_FIR
      ) port map(
        clock           => clock,
        reset           => reset,

        in_sample       => mixed_i,
        in_valid        => mixed_valid,

        out_sample      => filt_i,
        out_valid       => filt_valid
        );

    U_filter_im : entity work.fir_filter(systolic)
      generic map (
        CPS             => 2,
        INPUT_WIDTH     => mixed_q'length,
        OUTPUT_WIDTH    => filt_q'length,
        ACCUM_SCALE     => 24,
        H               => ADSB_FIR
      ) port map(
        clock           => clock,
        reset           => reset,

        in_sample       => mixed_q,
        in_valid        => mixed_valid,

        out_sample      => filt_q,
        out_valid       => open
      );

    -- Power Calculation
    compute_power : process(clock,reset)
    begin
        if reset = '1' then
            pow_valid <= '0' ;
            out_valid <= '0' ;
        elsif rising_edge(clock) then
            out_power <= pow ;
            out_valid <= pow_valid ;
            pow_valid <= filt_valid;

            if(filt_valid = '1') then
                pow <= resize( filt_i*filt_i,pow'length) + resize(filt_q*filt_q,pow'length);
            end if;
        end if;
    end process;

end architecture ;

