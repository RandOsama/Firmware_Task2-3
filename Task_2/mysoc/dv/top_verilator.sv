module top_verilator (input logic clk_i, rst_ni);
  logic uart_rx;
  logic uart_tx;

  // Our SoC
  soc_mod #(
  ) u_soc_mod (
    .clk_i,
    .rst_ni,

    .uart_rx_i (uart_rx),
    .uart_tx_o (uart_tx)
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

  export "DPI-C" function mhpmcounter_num;

  function automatic int unsigned mhpmcounter_num();
    return u_soc_mod.u_ibex_top_tracing.u_ibex_top.u_ibex_core.cs_registers_i.MHPMCounterNum;
  endfunction

  export "DPI-C" function mhpmcounter_get;

  function automatic longint unsigned mhpmcounter_get(int index);
    return u_soc_mod.u_ibex_top_tracing.u_ibex_top.u_ibex_core.cs_registers_i.mhpmcounter[index];
  endfunction

endmodule
