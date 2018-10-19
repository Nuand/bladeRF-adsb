set work nuand_adsb

vlib $work

vcom -work $work -2008 ../vhdl/adsb_decoder_p.vhd

vcom -work $work -2008 ../vhdl/adsb_edge_detector.vhd
vcom -work $work -2008 ../vhdl/preamble_detector.vhd
vcom -work $work -2008 ../vhdl/smallest_bsds.vhd

vcom -work $work -2008 ../vhdl/bsd_calculator.vhd
vcom -work $work -2008 ../vhdl/adsb_crc.vhd
vcom -work $work -2008 ../vhdl/bit_flipper.vhd
vcom -work $work -2008 ../vhdl/message_decoder.vhd
vcom -work $work -2008 ../vhdl/message_aggregator.vhd
vcom -work $work -2008 ../../synthesis/constellation_mapper.vhd
vcom -work $work -2008 ../../synthesis/fir_filter.vhd
vcom -work $work -2008 ../vhdl/adsb_fe.vhd

# Top level
vcom -work $work -2008 ../vhdl/adsb_decoder.vhd

# Test benches
vcom -work $work -2008 ../vhdl/tb/adsb_crc_tb.vhd
vcom -work $work -2008 ../vhdl/tb/adsb_tb.vhd
vcom -work $work -2008 ../vhdl/tb/smallest_bsds_tb.vhd
