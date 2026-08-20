module axi_datamover  #(
    parameter ADDR_WIDTH = 64
  )(
      // MM2S Primary Clock / Reset input
      input aclk,
      (*mark_debug="true"*) input aresetn,

      // MM2S Soft Shutdown
      (*mark_debug="true"*) input  halt_dm,
      (*mark_debug="true"*) output reg halt_complete_dm,

      // Memory Map to Stream Command FIFO and Status FIFO Async CLK/RST //////////////
      // User Command Interface Ports (AXI Stream)
      (*mark_debug="true"*) input  s_axis_mm2s_cmd_tvalid,
      (*mark_debug="true"*) output s_axis_mm2s_cmd_tready,
      input [40+ADDR_WIDTH-1:0] s_axis_mm2s_cmd_tdata,

      // User Status Interface Ports (AXI Stream)
      (*mark_debug="true"*) output m_axis_mm2s_sts_tvalid,
      (*mark_debug="true"*) input  m_axis_mm2s_sts_tready,
      (*mark_debug="true"*) output reg [7:0] m_axis_mm2s_sts_tdata,

      // MM2S AXI Address Channel I/O  //////////////////////////////////////
      (*mark_debug="true"*) output reg [ADDR_WIDTH-1:0] m_axi_mm2s_araddr,
      (*mark_debug="true"*) output reg  [7:0] m_axi_mm2s_arlen,
      output  [2:0] m_axi_mm2s_arsize,
      output  [1:0] m_axi_mm2s_arburst,
      output  [2:0] m_axi_mm2s_arprot,
      output  [3:0] m_axi_mm2s_arcache,
      output  [3:0] m_axi_mm2s_aruser,
      (*mark_debug="true"*) output        m_axi_mm2s_arvalid,
      (*mark_debug="true"*) input         m_axi_mm2s_arready,

      // MM2S AXI MMap Read Data Channel I/O  //////////////////////////////-
      input  [31:0] m_axi_mm2s_rdata,
      input   [1:0] m_axi_mm2s_rresp,
      input         m_axi_mm2s_rlast,
      input         m_axi_mm2s_rvalid,
      output        m_axi_mm2s_rready,

      // MM2S AXI Master Stream Channel I/O  ////////////////////////////////
      output [31:0] m_axis_mm2s_tdata,
      (*mark_debug="true"*) output m_axis_mm2s_tvalid,
      (*mark_debug="true"*) input  m_axis_mm2s_tready
    );
    // I2S WILL NEED 64-BYTE OF DATA
    (*mark_debug="true"*) reg sft_reseting;
    reg [3:0] tag_q;
    (*mark_debug="true"*) reg busy_q, finish_q;
    (*mark_debug="true"*) reg r_fifo_ready_q;
    wire r_fifo_ready;
    always_ff @(posedge aclk) begin
        r_fifo_ready_q <= r_fifo_ready;
    end
    assign m_axi_mm2s_arsize  = 3'b010;
    assign m_axi_mm2s_arburst = 2'b01;
    assign m_axi_mm2s_arprot  = '0;
    assign m_axi_mm2s_arcache = '0;
    assign m_axi_mm2s_aruser  = '0;
    assign s_axis_mm2s_cmd_tready = ~busy_q && r_fifo_ready_q && !sft_reseting;
    assign m_axis_mm2s_sts_tvalid = finish_q && busy_q && !sft_reseting;
    always_ff @(posedge aclk) begin
        if(~aresetn) begin
            busy_q <= '0;
        end else begin
            if(s_axis_mm2s_cmd_tvalid && s_axis_mm2s_cmd_tready && !sft_reseting) begin
                busy_q <= '1;
            end else if((m_axis_mm2s_sts_tvalid && m_axis_mm2s_sts_tready) || (sft_reseting && finish_q && busy_q)) begin
                busy_q <= '0;
            end
        end
    end
    always_ff @(posedge aclk) begin
        if(~aresetn) begin
            finish_q <= '0;
        end else begin
            if(s_axis_mm2s_cmd_tvalid && s_axis_mm2s_cmd_tready) begin
                finish_q <= '0;
            end else if(m_axi_mm2s_rvalid && m_axi_mm2s_rready && m_axi_mm2s_rlast) begin
                finish_q <= '1;
            end
        end
    end
    always_ff @(posedge aclk) begin
        m_axis_mm2s_sts_tdata[7:4] <= '0;
        if(s_axis_mm2s_cmd_tvalid && s_axis_mm2s_cmd_tready) begin
            m_axi_mm2s_araddr <= s_axis_mm2s_cmd_tdata[31+ADDR_WIDTH:32];
            m_axi_mm2s_arlen <= s_axis_mm2s_cmd_tdata[10:2] - 8'd1;
            m_axis_mm2s_sts_tdata[3:0] <= s_axis_mm2s_cmd_tdata[35+ADDR_WIDTH:32+ADDR_WIDTH];
        end
    end

    // DATA HANDSHAKING AR
    reg ar_handshake_need;
    always_ff @(posedge aclk) begin
        if(~aresetn) begin
            ar_handshake_need <= '1;
        end else begin
            if(s_axis_mm2s_cmd_tvalid && s_axis_mm2s_cmd_tready) begin
                ar_handshake_need <= '1;
            end else if (m_axi_mm2s_arvalid && m_axi_mm2s_arready) begin
                ar_handshake_need <= '0;
            end
        end
    end
    assign m_axi_mm2s_arvalid = ar_handshake_need && busy_q;

    // DATA FIFO FOR R
    // 64Byte per transaction
    // Totally size == 128Byte(32Words), ready for next transaction when FIFO SPACE == 64Byte.
    wire fifo_full, fifo_empty;
    wire [3:0] fifo_usage;
    assign m_axi_mm2s_rready  = ~fifo_full;
    assign m_axis_mm2s_tvalid = ~fifo_empty;
    fifo_v3 #(
        .DATA_WIDTH  (32  ),
        .DEPTH       (16  ),
        .FALL_THROUGH(1'b0)
      ) r_beats_queue (
        .clk_i     (aclk              ),
        .rst_ni    (aresetn           ),
        .flush_i   (sft_reseting      ),
        .testmode_i(1'b0              ),
        .data_i    (m_axi_mm2s_rdata  ),
        .push_i    (m_axi_mm2s_rvalid  && m_axi_mm2s_rready ),
        .full_o    (fifo_full         ),
        .data_o    (m_axis_mm2s_tdata ),
        .pop_i     (m_axis_mm2s_tready && m_axis_mm2s_tvalid),
        .empty_o   (fifo_empty        ),
        .usage_o   (fifo_usage        )
      );
    assign r_fifo_ready = fifo_usage <= 4'd2 || fifo_empty;

    // SOFT RESET LOGIC
    always_ff @(posedge aclk) begin
        if(~aresetn) begin
            sft_reseting <= '0;
            halt_complete_dm <= '0;
        end else begin
            if(halt_dm) begin
                sft_reseting <= '1;
                halt_complete_dm <= '0;
            end else if(sft_reseting) begin
                if(~busy_q) begin // deassert situation
                    sft_reseting <= '0;
                    halt_complete_dm <= '1;
                end
            end
        end
    end

endmodule
