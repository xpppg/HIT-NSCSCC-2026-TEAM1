module axi2_to_i2s (
  input  wire        s_axi_ctrl_aclk   ,
  input  wire        s_axi_ctrl_aresetn,
  (*mark_debug="true"*) input  wire        s_axi_ctrl_awvalid,
  (*mark_debug="true"*) output reg         s_axi_ctrl_awready,
  (*mark_debug="true"*) input  wire [ 7:0] s_axi_ctrl_awaddr ,
  (*mark_debug="true"*) input  wire        s_axi_ctrl_arvalid,
  (*mark_debug="true"*) output reg         s_axi_ctrl_arready,
  (*mark_debug="true"*) input  wire [ 7:0] s_axi_ctrl_araddr ,
  (*mark_debug="true"*) input  wire        s_axi_ctrl_wvalid ,
  (*mark_debug="true"*) output reg         s_axi_ctrl_wready ,
  input  wire [31:0] s_axi_ctrl_wdata  ,
  (*mark_debug="true"*) output reg         s_axi_ctrl_bvalid ,
  (*mark_debug="true"*) input  wire        s_axi_ctrl_bready ,
  output wire [ 1:0] s_axi_ctrl_bresp  ,
  (*mark_debug="true"*) output reg         s_axi_ctrl_rvalid ,
  (*mark_debug="true"*) input  wire        s_axi_ctrl_rready ,
  output reg  [31:0] s_axi_ctrl_rdata  ,
  output wire [ 1:0] s_axi_ctrl_rresp  ,
  output wire        irq               ,
  input  wire        aud_mclk          , // 22.5792Mhz for 44.1khz || 24.576mhz for 48khz
  input  wire        aud_mrst          ,
  output wire        lrclk_out         ,
  output wire        sclk_out          ,
  output wire        sdata_0_out       ,
  input  wire        s_axis_aud_aclk   ,
  input  wire        s_axis_aud_aresetn,
  input  wire [31:0] s_axis_aud_tdata  ,
  input  wire [ 2:0] s_axis_aud_tid    ,
  input  wire        s_axis_aud_tvalid ,
  output wire        s_axis_aud_tready
);

assign irq = '0; // NO USED

// Controlling registers
  logic [31:0] reg_ver, reg_conf, reg_ctrl, reg_validate, reg_int_ctrl, reg_int_status, reg_timing_ctrl, reg_channel_ctrl;
  logic [31:0] wdata_q ;
  logic [ 5:0] waddr_q ;
  logic        wvalid_q;

  logic [31:0] rdata_d ;
  logic [ 5:0] raddr_q ;
  logic        rvalid_q;

// Controlling registers reader
  assign s_axi_ctrl_rresp = '0;
  always_ff @(posedge s_axi_ctrl_aclk) begin
    if(~s_axi_ctrl_aresetn) begin
      rvalid_q           <= '0;
      s_axi_ctrl_rvalid  <= '0;
      s_axi_ctrl_arready <= '1;
      s_axi_ctrl_rdata <= 'x;
      raddr_q <= 'x;
    end else begin
      if(rvalid_q) begin
        s_axi_ctrl_rvalid <= '1;
        if(!s_axi_ctrl_rvalid) begin
          s_axi_ctrl_rdata <= rdata_d;
        end
        if(s_axi_ctrl_rvalid & s_axi_ctrl_rready) begin
          rvalid_q           <= '0;
          s_axi_ctrl_rvalid  <= '0;
          s_axi_ctrl_arready <= '1;
        end
      end else begin
        if(s_axi_ctrl_arvalid & s_axi_ctrl_arready) begin
          raddr_q            <= s_axi_ctrl_araddr[7:2];
          rvalid_q           <= '1;
          s_axi_ctrl_rvalid  <= '0;
          s_axi_ctrl_arready <= '0;
        end
      end
    end
  end

  always_comb begin
    case (raddr_q[2:0])
      /*3'd0*/ default: begin
        rdata_d = reg_ver;
      end
      3'd1 : begin
        rdata_d = reg_conf;
      end
      3'd2 : begin
        rdata_d = reg_ctrl;
      end
      3'd3 : begin
        rdata_d = reg_validate;
      end
      3'd4 : begin
        rdata_d = reg_int_ctrl;
      end
      3'd5 : begin
        rdata_d = reg_int_status;
      end
      3'd6 : begin
        rdata_d = reg_timing_ctrl;
      end
      3'd7 : begin
        rdata_d = reg_channel_ctrl;
      end
    endcase
    if(raddr_q[5:3]) begin
      rdata_d = '0;
    end
  end

// Controlling register writer.
  typedef logic[1:0] w_fsm_t;
  w_fsm_t w_fsm_q            ;
  localparam w_fsm_t S_WAIT_ADDR  = 2'd0;
  localparam w_fsm_t S_WAIT_DATA  = 2'd1;
  localparam w_fsm_t S_WAIT_WRITE = 2'd2;
  localparam w_fsm_t S_WAIT_RESP  = 2'd3;

  assign s_axi_ctrl_bresp = '0;
  always_ff @(posedge s_axi_ctrl_aclk) begin
    if(~s_axi_ctrl_aresetn) begin
      w_fsm_q            <= S_WAIT_ADDR;
      wvalid_q           <= '0;
      s_axi_ctrl_awready <= '1;
      s_axi_ctrl_wready  <= '0;
      s_axi_ctrl_bvalid  <= '0;
      waddr_q            <= 'x;
      wdata_q            <= 'x;
    end else begin
      case(w_fsm_q)
        /*S_WAIT_ADDR*/ default: begin
          if(s_axi_ctrl_awvalid) begin
            w_fsm_q            <= S_WAIT_DATA;
            waddr_q            <= s_axi_ctrl_awaddr[7:2];
            s_axi_ctrl_awready <= '0;
            s_axi_ctrl_wready  <= '1;
          end
        end
        S_WAIT_DATA : begin
          wdata_q <= s_axi_ctrl_wdata;
          if(s_axi_ctrl_wvalid) begin
            w_fsm_q           <= S_WAIT_WRITE;
            wvalid_q          <= '1;
            s_axi_ctrl_wready <= '0;
          end
        end
        S_WAIT_WRITE : begin
          wvalid_q          <= '0;
          w_fsm_q           <= S_WAIT_RESP;
          s_axi_ctrl_bvalid <= '1;
        end
        S_WAIT_RESP : begin
          if(s_axi_ctrl_bready) begin
            w_fsm_q            <= S_WAIT_ADDR;
            s_axi_ctrl_bvalid  <= '0;
            s_axi_ctrl_awready <= '1;
          end
        end
      endcase
    end
  end

  always_ff @(posedge s_axi_ctrl_aclk) begin
    if(~s_axi_ctrl_aresetn) begin
      reg_ver <= {16'd2, 16'd0};
      reg_conf <= {15'd0, 1'd0, 4'd0, 4'd2, 7'b0, 1'b1};
      reg_ctrl <= 32'd1;
      reg_validate <= '0;
      reg_int_ctrl <= '0;
      reg_int_status <= '0;
      reg_timing_ctrl <= '0;
      reg_channel_ctrl <= '0;
    end else begin
      if(wvalid_q) begin
        if(waddr_q == 5'd2) begin // CTRL
          reg_ctrl[2:0] <= wdata_q; // ENOUGH
        end
      end
    end
  end

// FIFO DATA EXTRACION
// ONLY FETCH CHANNEL 0-1 DATA
// AND TWO DATA FORM ONE VALID INPUT FOR I2S GENERATION
logic[31:0] formed_data_q;
logic formed_half_q;
logic formed_valid_q;
logic formed_ready_q;
(*mark_debug="true"*) wire formed_valid = !formed_ready_q || formed_valid_q;
assign s_axis_aud_tready = !formed_valid_q || formed_ready_q;
always_ff @(posedge s_axis_aud_aclk) begin
  if(s_axis_aud_tvalid && s_axis_aud_tready) begin
    formed_data_q[31:16] <= formed_data_q[15:0];
    formed_data_q[15:0]  <= s_axis_aud_tdata[15:0];
  end
end
always_ff @(posedge s_axis_aud_aclk) begin
  if(~s_axis_aud_aresetn) begin
    formed_valid_q <= '0;
    formed_half_q  <= '0;
  end else begin
    if(s_axis_aud_tvalid && s_axis_aud_tready) begin
      formed_valid_q <= formed_half_q;
      formed_half_q  <= ~formed_half_q;
    end
  end
end
// SKID BUF
(*mark_debug="true"*) wire formed_ready;
reg  [31:0] formed_data_skid_q;
(*mark_debug="true"*) wire [31:0] formed_data = formed_ready_q ? formed_data_q : formed_data_skid_q;
always_ff @(posedge s_axis_aud_aclk) begin
  if(~s_axis_aud_aresetn) begin
    formed_ready_q <= '1;
  end else begin
    formed_ready_q <= (!formed_valid_q && formed_ready_q) || formed_ready;
  end
end
always_ff @(posedge s_axis_aud_aclk) begin
  if(formed_ready_q) begin
    formed_data_skid_q <= formed_data_q;
  end
end

// ASYNC - FIFO from s_axis_aud_aclk to aud_mclk
(*mark_debug="true"*) wire i2s_dat_valid, i2s_dat_ready;
(*mark_debug="true"*) wire [31:0] i2s_dat;
cdc_fifo_gray # (
    .WIDTH(32),
    .LOG_DEPTH(2),
    .SYNC_STAGES(2)
  )
  cdc_fifo_gray_inst (
    .src_rst_ni(s_axis_aud_aresetn),
    .src_clk_i(s_axis_aud_aclk),
    .src_data_i(formed_data),
    .src_valid_i(formed_valid),
    .src_ready_o(formed_ready),

    .dst_rst_ni(~aud_mrst),
    .dst_clk_i(aud_mclk),
    .dst_data_o(i2s_dat),
    .dst_valid_o(i2s_dat_valid),
    .dst_ready_i(i2s_dat_ready)
  );
// I2S Generation
  i2s_gen  i2s_gen_inst (
    .aud_clk_i(aud_mclk),
    .aud_rst_i(aud_mrst),
    .sclk_o(sclk_out),
    .wclk_o(lrclk_out),
    .sdata_o(sdata_0_out),
    .audio_data_i(i2s_dat),
    .audio_data_valid_i(i2s_dat_valid),
    .audio_data_ready_o(i2s_dat_ready)
  );

endmodule