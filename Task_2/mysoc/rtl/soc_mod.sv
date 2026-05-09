module soc_mod #(
  SramInitFile = ""
) (
  // Clock and reset.
  input  logic clk_i,
  input  logic rst_ni,

  // UART receive and transmit.
  input  logic uart_rx_i,
  output logic uart_tx_o
);
  // Local parameters.
  localparam int unsigned MemSize       = 128 * 1024; // 128 KiB
  localparam int unsigned DataWidth     = 32;
  localparam int unsigned AddrOffset    = $clog2(DataWidth / 8);
  localparam int unsigned SramAddrWidth = $clog2(MemSize) - AddrOffset;

  // Read/write signals.
  logic                     ibex_req;
  logic                     ibex_gnt;
  logic                     ibex_we;
  logic [(DataWidth/8)-1:0] ibex_be;
  logic [DataWidth-1:0]     ibex_addr;
  logic [DataWidth-1:0]     ibex_wdata;
  logic                     ibex_rvalid;
  logic [DataWidth-1:0]     ibex_rdata;
  logic                     ibex_err;
  logic                     sram_data_req;
  logic                     sram_data_we;
  logic [SramAddrWidth-1:0] sram_data_addr;
  logic [DataWidth-1:0]     sram_data_wmask;
  logic [DataWidth-1:0]     sram_data_wdata;
  logic                     sram_data_rvalid;
  logic [DataWidth-1:0]     sram_data_rdata;
  logic                     sram_instr_req;
  logic [DataWidth-1:0]     sram_instr_addr;
  logic                     sram_instr_rvalid;
  logic [DataWidth-1:0]     sram_instr_rdata;

  // Instantiate our Ibex CPU.
  ibex_top_tracing #(
    .MHPMCounterNum  ( 10                  ),
    .RV32M           ( ibex_pkg::RV32MFast ),
    .RV32B           ( ibex_pkg::RV32BNone ),
    .DbgTriggerEn    ( 1'b0                ),
    .DbgHwBreakNum   ( 0                   )
  ) u_ibex_top_tracing (
    .clk_i,
    .rst_ni,

    .test_en_i   ('b0),
    .scan_rst_ni (1'b1),
    .ram_cfg_i   ('b0),

    .hart_id_i   (32'b0),
    // First instruction executed is at 0x0 + 0x80.
    .boot_addr_i (32'h00100000),

    .instr_req_o        (sram_instr_req),
    .instr_gnt_i        (sram_instr_req),
    .instr_rvalid_i     (sram_instr_rvalid),
    .instr_addr_o       (sram_instr_addr),
    .instr_rdata_i      (sram_instr_rdata),
    .instr_rdata_intg_i ('0),
    .instr_err_i        ('0),

    .data_req_o        (ibex_req),
    .data_gnt_i        (ibex_gnt),
    .data_rvalid_i     (ibex_rvalid),
    .data_we_o         (ibex_we),
    .data_be_o         (ibex_be),
    .data_addr_o       (ibex_addr),
    .data_wdata_o      (ibex_wdata),
    .data_wdata_intg_o ( ),
    .data_rdata_i      (ibex_rdata),
    .data_rdata_intg_i ('0),
    .data_err_i        (ibex_err),

    .irq_software_i (1'b0),
    .irq_timer_i    (1'b0),
    .irq_external_i (1'b0),
    .irq_fast_i     (15'b0),
    .irq_nm_i       (1'b0),

    .scramble_key_valid_i ('0),
    .scramble_key_i       ('0),
    .scramble_nonce_i     ('0),
    .scramble_req_o       ( ),

    .debug_req_i         ('0),
    .crash_dump_o        ( ),
    .double_fault_seen_o ( ),

    .fetch_enable_i         ('1),
    .alert_minor_o          ( ),
    .alert_major_internal_o ( ),
    .alert_major_bus_o      ( ),
    .core_sleep_o           ( )
  );

  // Instantiate our UART block.
  uart u_uart (
    .clk_i,
    .rst_ni,

    .cio_rx_i    (uart_rx_i),
    .cio_tx_o    (uart_tx_o),
    .cio_tx_en_o ( ),

    // Inter-module signals.
    .tl_i (tl_uart_h2d),
    .tl_o (tl_uart_d2h),

    // Interrupts.
    .intr_tx_watermark_o  ( ),
    .intr_tx_empty_o      ( ),
    .intr_rx_watermark_o  ( ),
    .intr_tx_done_o       ( ),
    .intr_rx_overflow_o   ( ),
    .intr_rx_frame_err_o  ( ),
    .intr_rx_break_err_o  ( ),
    .intr_rx_timeout_o    ( ),
    .intr_rx_parity_err_o ( )
  );

  // Our RAM
  prim_ram_2p #(
    .Width           ( DataWidth                         ),
    .DataBitsPerMask ( 8                                 ),
    .Depth           ( 2 ** (SramAddrWidth - AddrOffset) ),
    .MemInitFile     ( SramInitFile                      )
  ) u_ram (
    .clk_a_i (clk_i),
    .clk_b_i (clk_i),

    .a_req_i   (sram_data_req),
    .a_write_i (sram_data_we),
    .a_addr_i  (sram_data_addr),
    .a_wdata_i (sram_data_wdata),
    .a_wmask_i (sram_data_wmask),
    .a_rdata_o (sram_data_rdata),

    .b_req_i   (sram_instr_req),
    .b_write_i (1'b0),
    .b_addr_i  (sram_instr_addr[SramAddrWidth-1+AddrOffset:AddrOffset]),
    .b_wdata_i (DataWidth'(0)),
    .b_wmask_i (DataWidth'(0)),
    .b_rdata_o (sram_instr_rdata),

    .cfg_i ('0)
  );

  // Single-cycle read response.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sram_data_rvalid  <= '0;
      sram_instr_rvalid <= '0;
    end else begin
      sram_data_rvalid <= sram_data_req & ~sram_data_we;
      sram_instr_rvalid <= sram_instr_req;
    end
  end

  // TileLink signals.
  tlul_pkg::tl_h2d_t tl_ibex_lsu_h2d;
  tlul_pkg::tl_d2h_t tl_ibex_lsu_d2h;
  tlul_pkg::tl_h2d_t tl_sram_h2d;
  tlul_pkg::tl_d2h_t tl_sram_d2h;
  tlul_pkg::tl_h2d_t tl_uart_h2d;
  tlul_pkg::tl_d2h_t tl_uart_d2h;

  // Our main data bus.
  xbar_main xbar (
    // Clock and reset.
    .clk_i,
    .rst_ni,

    // Host interfaces.
    .tl_ibex_lsu_i (tl_ibex_lsu_h2d),
    .tl_ibex_lsu_o (tl_ibex_lsu_d2h),

    // Device interfaces.
    .tl_sram_o (tl_sram_h2d),
    .tl_sram_i (tl_sram_d2h),
    .tl_uart_o (tl_uart_h2d),
    .tl_uart_i (tl_uart_d2h),

    .scanmode_i (prim_mubi_pkg::MuBi4False)
  );


  // TileLink host adapter to connect Ibex to bus.
  tlul_adapter_host ibex_lsu_host_adapter (
    .clk_i,
    .rst_ni,

    .req_i        (ibex_req),
    .gnt_o        (ibex_gnt),
    .addr_i       (ibex_addr),
    .we_i         (ibex_we),
    .wdata_i      (ibex_wdata),
    .wdata_intg_i ('0),
    .be_i         (ibex_be),
    .instr_type_i (prim_mubi_pkg::MuBi4False),

    .valid_o      (ibex_rvalid),
    .rdata_o      (ibex_rdata),
    .rdata_intg_o (),
    .err_o        (ibex_err),
    .intg_err_o   (),

    .tl_o         (tl_ibex_lsu_h2d),
    .tl_i         (tl_ibex_lsu_d2h)
  );

  // TileLink device adapter to connect SRAM to bus.
  tlul_adapter_sram #(
    .SramAw           ( SramAddrWidth - AddrOffset ),
    .EnableRspIntgGen ( 0                          )
  ) sram_a_device_adapter (
    .clk_i,
    .rst_ni,

    // TL-UL interface.
    .tl_i        (tl_sram_h2d),
    .tl_o        (tl_sram_d2h),

    // Control interface.
    .en_ifetch_i (prim_mubi_pkg::MuBi4True),

    // SRAM interface.
    .req_o        (sram_data_req),
    .req_type_o   ( ),
    .gnt_i        (sram_data_req),
    .we_o         (sram_data_we),
    .addr_o       (sram_data_addr),
    .wdata_o      (sram_data_wdata),
    .wmask_o      (sram_data_wmask),
    .intg_error_o ( ),
    .rdata_i      (sram_data_rdata),
    .rvalid_i     (sram_data_rvalid),
    .rerror_i     (2'b00),

    // Readback functionality not required.
    .compound_txn_in_progress_o (),
    .readback_en_i              (prim_mubi_pkg::MuBi4False),
    .readback_error_o           (),
    .wr_collision_i             (1'b0),
    .write_pending_i            (1'b0)
  );
endmodule
