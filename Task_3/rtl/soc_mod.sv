module soc_mod #(
  SramInitFile = ""
) (
  // Clock and reset.
  input  logic clk_i,
  input  logic rst_ni,

  // UART receive and transmit.
  input  logic uart_rx_i,
  output logic uart_tx_o,

  output logic spi_sck_o,
  output logic spi_sck_en_o,
  output logic spi_csb_o,
  output logic spi_csb_en_o,

  
  // Added by Deyaa Al-khatib 17th of Feb 11PM
  output logic [3:0] spi_sd_o,
  output logic [3:0] spi_sd_en_o,
  input  logic [3:0] spi_sd_i,
  // End of the addition

  // Added by Deyaa Al-khatib 25th of Feb 11PM
  input  logic tck_i,
  input  logic tms_i,
  input  logic tdi_i,
  output logic tdo_o,

  //Added by Deyaa Al-khatib 1st of mar 12PM
  output logic ndmreset_req_o


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
  logic                     ibex_instr_req;
  logic [DataWidth-1:0]     ibex_instr_addr;
  logic                     ibex_instr_rvalid;
  logic [DataWidth-1:0]     ibex_instr_rdata;
  logic                     ibex_instr_gnt;
  jtag_pkg::jtag_req_t jtag_req;
  jtag_pkg::jtag_rsp_t jtag_rsp;
  logic                debug_req;
  logic              irq_timer;
  logic              irq_plic;
  logic              msip_plic;
  // Added by Deyaa Al-Khatib at 6th of mar 2026
  logic              intr_uart_tx_watermark;
  logic              intr_uart_rx_watermark;
  logic              intr_uart_tx_done;
  logic              intr_uart_rx_overflow;
  logic              intr_uart_rx_frame_err;
  logic              intr_uart_rx_break_err;
  logic              intr_uart_rx_timeout;
  logic              intr_uart_rx_parity_err;
  logic              intr_uart_tx_empty;
  //end of addition 
  // Instantiate our Ibex CPU.
  ibex_top_tracing #(
    .MHPMCounterNum  ( 10                  ),
    .RV32M           ( ibex_pkg::RV32MFast ),
    .RV32B           ( ibex_pkg::RV32BNone ),
    .DbgTriggerEn    ( 1'b1                ),
    .DbgHwBreakNum   ( 4                   ),
    .DmHaltAddr      ( 32'h00010800        ),
    .DmExceptionAddr ( 32'h00010808        ),
    .DmBaseAddr      ( 32'h00010000        )
  ) u_ibex_top_tracing (
    .clk_i,
    .rst_ni,

    .test_en_i   ('b0),
    .scan_rst_ni (1'b1),
    .ram_cfg_i   ('b0),

    .hart_id_i   (32'b0),
    // First instruction executed is at 0x0 + 0x80.
    .boot_addr_i (32'h00100000),

    .instr_req_o        (ibex_instr_req),
    .instr_gnt_i        (ibex_instr_gnt),
    .instr_rvalid_i     (ibex_instr_rvalid),
    .instr_addr_o       (ibex_instr_addr),
    .instr_rdata_i      (ibex_instr_rdata),
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

    .irq_software_i (msip_plic),
    .irq_timer_i    (irq_timer),
    .irq_external_i (irq_plic),
    .irq_fast_i     (15'b0),
    .irq_nm_i       (1'b0),

    .scramble_key_valid_i ('0),
    .scramble_key_i       ('0),
    .scramble_nonce_i     ('0),
    .scramble_req_o       ( ),

    .debug_req_i         (debug_req),
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
    .intr_tx_watermark_o  (intr_uart_tx_watermark),
    .intr_tx_empty_o      (intr_uart_tx_empty),
    .intr_rx_watermark_o  (intr_uart_rx_watermark),
    .intr_tx_done_o       (intr_uart_tx_done),
    .intr_rx_overflow_o   (intr_uart_rx_overflow),
    .intr_rx_frame_err_o  (intr_uart_rx_frame_err),
    .intr_rx_break_err_o  (intr_uart_rx_break_err),
    .intr_rx_timeout_o    (intr_uart_rx_timeout),
    .intr_rx_parity_err_o (intr_uart_rx_parity_err)
  );
  spi_host spi_host(
    .clk_i,
    .rst_ni,


    .tl_i(tl_spi_host_h2d),
    .tl_o(tl_spi_host_d2h),


    .cio_sck_o(spi_sck_o),
    .cio_sck_en_o(spi_sck_en_o),
    .cio_csb_o(spi_csb_o),
    .cio_csb_en_o(spi_csb_en_o),
    .cio_sd_o(spi_sd_o),
    .cio_sd_en_o(spi_sd_en_o),
    .cio_sd_i(spi_sd_i), // Added by Deyaa Al-khatib 17th of Feb 11PM // End of the addition

    .alert_rx_i(prim_alert_pkg::ALERT_RX_DEFAULT),
    .alert_tx_o(),

    .passthrough_i(spi_device_pkg::PASSTHROUGH_REQ_DEFAULT),
    .passthrough_o(),
    
    .intr_error_o(),
    .intr_spi_event_o()
  );
  // Our RAM
  prim_ram_2p #(
    .Width           ( DataWidth                         ),
    .DataBitsPerMask ( 8                                 ),
    .Depth           ( 2 ** (SramAddrWidth) ),
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

    .b_req_i   (1'b0),
    .b_write_i (1'b0),
    .b_addr_i  (1'b0),
    .b_wdata_i (1'b0),
    .b_wmask_i (1'b0),
    .b_rdata_o (),

    .cfg_i ('0)
  );



  // TileLink signals.
  tlul_pkg::tl_h2d_t tl_ibex_lsu_h2d;
  tlul_pkg::tl_d2h_t tl_ibex_lsu_d2h;
  tlul_pkg::tl_h2d_t tl_ibex_instr_h2d;
  tlul_pkg::tl_d2h_t tl_ibex_instr_d2h; 
  tlul_pkg::tl_h2d_t tl_sram_h2d;
  tlul_pkg::tl_d2h_t tl_sram_d2h;
  tlul_pkg::tl_h2d_t tl_uart_h2d;
  tlul_pkg::tl_d2h_t tl_uart_d2h;
  //Added by Deyaa Al-khateeb
  tlul_pkg::tl_d2h_t tl_spi_host_d2h;
  tlul_pkg::tl_h2d_t tl_spi_host_h2d;
  // End of addition
  //Added by Deyaa Al-Khateeb on 25th of Feb 2026
  tlul_pkg::tl_h2d_t tl_rv_dm_sba_h2d;
  tlul_pkg::tl_d2h_t tl_rv_dm_sba_d2h;
  tlul_pkg::tl_h2d_t tl_rv_dm_mem_h2d;
  tlul_pkg::tl_d2h_t tl_rv_dm_mem_d2h;
  tlul_pkg::tl_h2d_t tl_rv_dm_regs_h2d;
  tlul_pkg::tl_d2h_t tl_rv_dm_regs_d2h;
  tlul_pkg::tl_h2d_t tl_rv_timer_h2d;
  tlul_pkg::tl_d2h_t tl_rv_timer_d2h;
  tlul_pkg::tl_h2d_t tl_rv_plic_h2d;
  tlul_pkg::tl_d2h_t tl_rv_plic_d2h;

 always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sram_data_rvalid <= '0;
    end else begin
      sram_data_rvalid <= sram_data_req & ~sram_data_we;
    end
  end
  




  assign jtag_req = '{tck: tck_i, tms: tms_i, trst_n: 1'b1, tdi: tdi_i};
  assign tdo_o    = jtag_rsp.tdo;


  // Our main data bus.
  xbar_main xbar (
    // Clock and reset.
    .clk_i,
    .rst_ni,

    // Host interfaces.
    .tl_ibex_lsu_i (tl_ibex_lsu_h2d),
    .tl_ibex_lsu_o (tl_ibex_lsu_d2h),

    // Device interfaces.
    .tl_rv_plic_o (tl_rv_plic_h2d),
    .tl_rv_plic_i (tl_rv_plic_d2h),
    .tl_rv_timer_o(tl_rv_timer_h2d),
    .tl_rv_timer_i(tl_rv_timer_d2h),
    .tl_sram_o (tl_sram_h2d),
    .tl_sram_i (tl_sram_d2h),
    .tl_uart_o (tl_uart_h2d),
    .tl_uart_i (tl_uart_d2h),
    .tl_spi_host_o (tl_spi_host_h2d),
    .tl_spi_host_i (tl_spi_host_d2h),
    .tl_ibex_instr_i (tl_ibex_instr_h2d),
    .tl_ibex_instr_o (tl_ibex_instr_d2h),
    .tl_rv_dm_mem_o  (tl_rv_dm_mem_h2d),
    .tl_rv_dm_mem_i  (tl_rv_dm_mem_d2h),
    .tl_rv_dm_regs_o (tl_rv_dm_regs_h2d),
    .tl_rv_dm_regs_i (tl_rv_dm_regs_d2h),
    .tl_rv_dm_sba_i  (tl_rv_dm_sba_h2d),
    .tl_rv_dm_sba_o  (tl_rv_dm_sba_d2h),
    .scanmode_i (prim_mubi_pkg::MuBi4False)
  );


  // TileLink host adapter to connect Ibex to bus.
  tlul_adapter_host #(
    .EnableCmdIntgGen(1),
    .EnableDataIntgGen(1)
  ) ibex_lsu_host_adapter (
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
  tlul_adapter_host #(
      .EnableCmdIntgGen(1),
      .EnableDataIntgGen(1)
  ) ibex_instr_host_adapter (
      .clk_i,
      .rst_ni,

      .req_i        (ibex_instr_req),
      .gnt_o        (ibex_instr_gnt),
      .addr_i       (ibex_instr_addr),
      .we_i         (1'b0),
      .wdata_i      (1'b0),
      .wdata_intg_i (1'b0),
      .be_i         (4'hF),
      .instr_type_i (prim_mubi_pkg::MuBi4True),

      .valid_o      (ibex_instr_rvalid),
      .rdata_o      (ibex_instr_rdata),
      .rdata_intg_o (),
      .err_o        (),
      .intg_err_o   (),

      .tl_o         (tl_ibex_instr_h2d),
      .tl_i         (tl_ibex_instr_d2h)
    );
  // TileLink device adapter to connect SRAM to bus.
  tlul_adapter_sram #(
    .SramAw           ( SramAddrWidth),
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

   rv_dm #(
    .IdcodeValue (32'h00000001)
  ) u_rv_dm (
    .clk_i,
    .clk_lc_i             (clk_i),
    .rst_ni,
    .rst_lc_ni            (1'b1),
    .next_dm_addr_i       ('0),
    .lc_hw_debug_en_i     (lc_ctrl_pkg::On),
    .lc_dft_en_i          (lc_ctrl_pkg::Off),
    .pinmux_hw_debug_en_i (lc_ctrl_pkg::On),
    .otp_dis_rv_dm_late_debug_i (prim_mubi_pkg::MuBi8True),
    .scanmode_i           (prim_mubi_pkg::MuBi4False),
    .scan_rst_ni          (1'b1),
    .ndmreset_req_o       (ndmreset_req_o),
    .dmactive_o           (),
    .debug_req_o          (debug_req),
    .unavailable_i        (1'b0),
    .regs_tl_d_i          (tl_rv_dm_regs_h2d),
    .regs_tl_d_o          (tl_rv_dm_regs_d2h),
    .mem_tl_d_i           (tl_rv_dm_mem_h2d),
    .mem_tl_d_o           (tl_rv_dm_mem_d2h),
    .sba_tl_h_o           (tl_rv_dm_sba_h2d),
    .sba_tl_h_i           (tl_rv_dm_sba_d2h),
    .alert_rx_i           (prim_alert_pkg::ALERT_RX_DEFAULT),
    .alert_tx_o           (),
    .jtag_i               (jtag_req),
    .jtag_o               (jtag_rsp)
  );




 rv_timer u_rv_timer (
      .clk_i,
      .rst_ni   ,
      .tl_i     (tl_rv_timer_h2d),
      .tl_o     (tl_rv_timer_d2h),
      .alert_rx_i ('0),
      .alert_tx_o (   ),
      .intr_timer_expired_hart0_timer0_o (irq_timer)
    );
 rv_plic u_rv_plic (
      .clk_i,
      .rst_ni    ,
      .tl_i       (tl_rv_plic_h2d),
      .tl_o       (tl_rv_plic_d2h),
      .intr_src_i ({176'b0,
                intr_uart_tx_empty,
                intr_uart_rx_parity_err,
                intr_uart_rx_timeout,
                intr_uart_rx_break_err,
                intr_uart_rx_frame_err,
                intr_uart_rx_overflow,
                intr_uart_tx_done,
                intr_uart_rx_watermark,
                intr_uart_tx_watermark,
                1'b0}), 
      .irq_o      (irq_plic),
      .irq_id_o   ( ),
      .msip_o     (msip_plic),
      .alert_rx_i (prim_alert_pkg::ALERT_RX_DEFAULT),
      .alert_tx_o ( )
    );
endmodule
