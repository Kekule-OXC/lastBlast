# Clock constraints

#create_clock -name CLK_50MHZ -period 20.000ns [get_ports {CLK_50MHZ}] -waveform {0.000 10.000}
create_clock -name LPC_CLK    -period 30.000ns [get_ports {LPC_CLK}]    -waveform {0.000 15.000}


# Automatically constrain PLL and other generated clocks
#derive_pll_clocks -create_base_clocks
derive_pll_clocks

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty


