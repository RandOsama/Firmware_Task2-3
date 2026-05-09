module top_verilator (input logic clk_i, rst_ni);
  logic uart_rx;
  logic uart_tx;
  logic spi_sck_o;
  logic spi_sck_en_o;
  logic spi_csb_o;
  logic spi_csb_en_o;
  // Added by Deyaa Al-khatib 17th of Feb 11PM
  logic [3:0] spi_sd_o;
  logic [3:0] spi_sd_en_o;
  logic [3:0] spi_sd_i;

  logic tck;
  logic tdi;
  logic tms;
  logic tdo;
  logic ndmreset_req;
  // End of the addition

  // Our SoC
  soc_mod #(
  ) u_soc_mod (
    .clk_i,
    .rst_ni,

    .uart_rx_i (uart_rx),
    .uart_tx_o (uart_tx),

    .spi_sck_o(spi_sck_o),
    .spi_sck_en_o(spi_sck_en_o),
    .spi_csb_o(spi_csb_o),
    .spi_csb_en_o(spi_csb_en_o),
    // Added by Deyaa Al-khatib 17th of Feb 11PM
    .spi_sd_o    (spi_sd_o),
    .spi_sd_en_o (spi_sd_en_o),
    .spi_sd_i    (spi_sd_i),
    // End of the addition
    .tck_i(tck),
    .tms_i(tms),
    .tdi_i(tdi),
    .tdo_o(tdo),
    .ndmreset_req_o(ndmreset_req)

  );

  // Virtual UART
  uartdpi #(
    .BAUD ( 921_600    ),
    .FREQ ( 50_000_000 )
  ) u_uartdpi (
    .clk_i,
    .rst_ni,
    .active(1'b1       ),
    .tx_o  (uart_rx),
    .rx_i  (uart_tx)
  );
  // Added by Deyaa Al-Khatib on 25th of feb
  jtagdpi #(
      .Name       ("jtag0"),
      .ListenPort (44853)
    ) u_jtagdpi (
      .clk_i,
      .rst_ni,
      .active      (1'b1),
      .jtag_tck    (tck),
      .jtag_tms    (tms),
      .jtag_tdi    (tdi),
      .jtag_tdo    (tdo),
      .jtag_trst_n (),
      .jtag_srst_n ()
    );
    // End of addition
  // Added by Deyaa Al-khatib 17th of Feb 11PM

  // SPI IO lines — same tristate wiring pattern used in spid_passthrough_tb.sv
  // All 4 io lines are bidirectional in QSPI mode:
  //   spi_host drives when sd_en_o[i]=1, spiflash drives when io_oe=1, otherwise Z
  wire spi_io0 = spi_sd_en_o[0] ? spi_sd_o[0] : 1'bz;
  wire spi_io1 = spi_sd_en_o[1] ? spi_sd_o[1] : 1'bz;
  wire spi_io2 = spi_sd_en_o[2] ? spi_sd_o[2] : 1'bz;
  wire spi_io3 = spi_sd_en_o[3] ? spi_sd_o[3] : 1'bz;
  // Feed all IO lines back to spi_host input
  assign spi_sd_i = {spi_io3, spi_io2, spi_io1, spi_io0};
  // Debug system reset
  wire rst_ni_combined = rst_ni & ~ndmreset_req;
  // PicoRV32 SPI flash behavioral model — plain Verilog, Verilator compatible.
  // Flash contents loaded from firmware.hex via $readmemh (or +firmware=<path> plusarg).
  spiflash u_spiflash (
    .csb (spi_csb_o),
    .clk (spi_sck_o),
    .io0 (spi_io0),
    .io1 (spi_io1),
    .io2 (spi_io2),
    .io3 (spi_io3)
  );

  // End of the addition

  export "DPI-C" function mhpmcounter_num;

  function automatic int unsigned mhpmcounter_num();
    return u_soc_mod.u_ibex_top_tracing.u_ibex_top.u_ibex_core.cs_registers_i.MHPMCounterNum;
  endfunction

  export "DPI-C" function mhpmcounter_get;

  function automatic longint unsigned mhpmcounter_get(int index);
    return u_soc_mod.u_ibex_top_tracing.u_ibex_top.u_ibex_core.cs_registers_i.mhpmcounter[index];
  endfunction

endmodule
