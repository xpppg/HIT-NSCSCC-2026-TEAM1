module xil_audio_formatter
   (s_axi_lite_aclk,
    s_axi_lite_aresetn,
    s_axi_lite_awvalid,
    s_axi_lite_awready,
    s_axi_lite_awaddr,
    s_axi_lite_wvalid,
    s_axi_lite_wready,
    s_axi_lite_wdata,
    s_axi_lite_bresp,
    s_axi_lite_bvalid,
    s_axi_lite_bready,
    s_axi_lite_arvalid,
    s_axi_lite_arready,
    s_axi_lite_araddr,
    s_axi_lite_rvalid,
    s_axi_lite_rready,
    s_axi_lite_rdata,
    s_axi_lite_rresp,
    m_axis_mm2s_aclk,
    m_axis_mm2s_aresetn,
    aud_mclk,
    aud_mreset,
    irq_mm2s,
    m_axis_mm2s_tvalid,
    m_axis_mm2s_tready,
    m_axis_mm2s_tdata,
    m_axis_mm2s_tid,
    m_axi_mm2s_araddr,
    m_axi_mm2s_arlen,
    m_axi_mm2s_arsize,
    m_axi_mm2s_arburst,
    m_axi_mm2s_arprot,
    m_axi_mm2s_arcache,
    m_axi_mm2s_aruser,
    m_axi_mm2s_arvalid,
    m_axi_mm2s_arready,
    m_axi_mm2s_rdata,
    m_axi_mm2s_rresp,
    m_axi_mm2s_rlast,
    m_axi_mm2s_rvalid,
    m_axi_mm2s_rready);
  input s_axi_lite_aclk;
  input s_axi_lite_aresetn;
  input s_axi_lite_awvalid;
  output s_axi_lite_awready;
  input [11:0]s_axi_lite_awaddr;
  input s_axi_lite_wvalid;
  output s_axi_lite_wready;
  input [31:0]s_axi_lite_wdata;
  output [1:0]s_axi_lite_bresp;
  output s_axi_lite_bvalid;
  input s_axi_lite_bready;
  input s_axi_lite_arvalid;
  output s_axi_lite_arready;
  input [11:0]s_axi_lite_araddr;
  output s_axi_lite_rvalid;
  input s_axi_lite_rready;
  output [31:0]s_axi_lite_rdata;
  output [1:0]s_axi_lite_rresp;
  input m_axis_mm2s_aclk;
  input m_axis_mm2s_aresetn;
  input aud_mclk;
  input aud_mreset;
  output irq_mm2s;
  output m_axis_mm2s_tvalid;
  input m_axis_mm2s_tready;
  output [31:0]m_axis_mm2s_tdata;
  output [7:0]m_axis_mm2s_tid;
  output [31:0]m_axi_mm2s_araddr;
  output [7:0]m_axi_mm2s_arlen;
  output [2:0]m_axi_mm2s_arsize;
  output [1:0]m_axi_mm2s_arburst;
  output [2:0]m_axi_mm2s_arprot;
  output [3:0]m_axi_mm2s_arcache;
  output [3:0]m_axi_mm2s_aruser;
  output m_axi_mm2s_arvalid;
  input m_axi_mm2s_arready;
  input [31:0]m_axi_mm2s_rdata;
  input [1:0]m_axi_mm2s_rresp;
  input m_axi_mm2s_rlast;
  input m_axi_mm2s_rvalid;
  output m_axi_mm2s_rready;

  wire aud_mclk;
  wire aud_mreset;
  wire irq_mm2s;
  wire [31:0]m_axi_mm2s_araddr;
  wire [0:0]io_m_axi_mm2s_arburst ;
  wire [7:0]m_axi_mm2s_arlen;
  wire m_axi_mm2s_arready;
  wire [1:1]io_m_axi_mm2s_arsize ;
  wire m_axi_mm2s_arvalid;
  wire [31:0]m_axi_mm2s_rdata;
  wire m_axi_mm2s_rlast;
  wire m_axi_mm2s_rready;
  wire [1:0]m_axi_mm2s_rresp;
  wire m_axi_mm2s_rvalid;
  wire m_axis_mm2s_aclk;
  wire m_axis_mm2s_aresetn;
  wire [31:0]m_axis_mm2s_tdata;
  wire [3:0]io_m_axis_mm2s_tid ;
  wire m_axis_mm2s_tready;
  wire m_axis_mm2s_tvalid;
  wire s_axi_lite_aclk;
  wire [11:0]s_axi_lite_araddr;
  wire s_axi_lite_aresetn;
  wire s_axi_lite_arready;
  wire s_axi_lite_arvalid;
  wire [11:0]s_axi_lite_awaddr;
  wire s_axi_lite_awready;
  wire s_axi_lite_awvalid;
  wire s_axi_lite_bready;
  wire [1:1]io_s_axi_lite_bresp ;
  wire s_axi_lite_bvalid;
  wire [31:0]s_axi_lite_rdata;
  wire s_axi_lite_rready;
  wire [1:1]io_s_axi_lite_rresp ;
  wire s_axi_lite_rvalid;
  wire [31:0]s_axi_lite_wdata;
  wire s_axi_lite_wready;
  wire s_axi_lite_wvalid;
  wire NLW_inst_irq_s2mm_UNCONNECTED;
  wire NLW_inst_m_axi_s2mm_awvalid_UNCONNECTED;
  wire NLW_inst_m_axi_s2mm_bready_UNCONNECTED;
  wire NLW_inst_m_axi_s2mm_wlast_UNCONNECTED;
  wire NLW_inst_m_axi_s2mm_wvalid_UNCONNECTED;
  wire NLW_inst_s_axis_s2mm_tready_UNCONNECTED;
  wire [1:1]NLW_inst_m_axi_mm2s_arburst_UNCONNECTED;
  wire [3:0]NLW_inst_m_axi_mm2s_arcache_UNCONNECTED;
  wire [2:0]NLW_inst_m_axi_mm2s_arprot_UNCONNECTED;
  wire [2:0]NLW_inst_m_axi_mm2s_arsize_UNCONNECTED;
  wire [3:0]NLW_inst_m_axi_mm2s_aruser_UNCONNECTED;
  wire [63:0]NLW_inst_m_axi_s2mm_awaddr_UNCONNECTED;
  wire [1:0]NLW_inst_m_axi_s2mm_awburst_UNCONNECTED;
  wire [3:0]NLW_inst_m_axi_s2mm_awcache_UNCONNECTED;
  wire [7:0]NLW_inst_m_axi_s2mm_awlen_UNCONNECTED;
  wire [2:0]NLW_inst_m_axi_s2mm_awprot_UNCONNECTED;
  wire [2:0]NLW_inst_m_axi_s2mm_awsize_UNCONNECTED;
  wire [3:0]NLW_inst_m_axi_s2mm_awuser_UNCONNECTED;
  wire [31:0]NLW_inst_m_axi_s2mm_wdata_UNCONNECTED;
  wire [3:0]NLW_inst_m_axi_s2mm_wstrb_UNCONNECTED;
  wire [7:4]NLW_inst_m_axis_mm2s_tid_UNCONNECTED;
  wire [0:0]NLW_inst_s_axi_lite_bresp_UNCONNECTED;
  wire [0:0]NLW_inst_s_axi_lite_rresp_UNCONNECTED;

  assign m_axi_mm2s_arburst[1] = '0 ;
  assign m_axi_mm2s_arburst[0] = io_m_axi_mm2s_arburst [0];
  assign m_axi_mm2s_arcache[3] = '0 ;
  assign m_axi_mm2s_arcache[2] = '0 ;
  assign m_axi_mm2s_arcache[1] = '1 ;
  assign m_axi_mm2s_arcache[0] = '1 ;
  assign m_axi_mm2s_arprot[2] = '0 ;
  assign m_axi_mm2s_arprot[1] = '0 ;
  assign m_axi_mm2s_arprot[0] = '0 ;
  assign m_axi_mm2s_arsize[2] = '0 ;
  assign m_axi_mm2s_arsize[1] = io_m_axi_mm2s_arsize [1];
  assign m_axi_mm2s_arsize[0] = '0 ;
  assign m_axi_mm2s_aruser[3] = '0 ;
  assign m_axi_mm2s_aruser[2] = '0 ;
  assign m_axi_mm2s_aruser[1] = '0 ;
  assign m_axi_mm2s_aruser[0] = '0 ;
  assign m_axis_mm2s_tid[7] = '0 ;
  assign m_axis_mm2s_tid[6] = '0 ;
  assign m_axis_mm2s_tid[5] = '0 ;
  assign m_axis_mm2s_tid[4] = '0 ;
  assign m_axis_mm2s_tid[3:0] = io_m_axis_mm2s_tid [3:0];
  assign s_axi_lite_bresp[1] = io_s_axi_lite_bresp [1];
  assign s_axi_lite_bresp[0] = '0 ;
  assign s_axi_lite_rresp[1] = io_s_axi_lite_rresp [1];
  assign s_axi_lite_rresp[0] = '0 ;
  stolen_audio_formatter #(
    .C_FAMILY("artix7"),
    .C_INCLUDE_S2MM(0),
    .C_MAX_NUM_CHANNELS_S2MM(2),
    .C_PACKING_MODE_S2MM(0),
    .C_S2MM_DATAFORMAT(1),
    .C_INCLUDE_MM2S(1),
    .C_MAX_NUM_CHANNELS_MM2S(2),
    .C_PACKING_MODE_MM2S(0),
    .C_MM2S_DATAFORMAT(2),
    .C_S2MM_ADDR_WIDTH(32),
    .C_MM2S_ADDR_WIDTH(32),
    .C_S2MM_ASYNC_CLOCK(1),
    .C_MM2S_ASYNC_CLOCK(1)
  )inst
       (.aud_mclk(aud_mclk),
        .aud_mreset(aud_mreset),
        .irq_mm2s(irq_mm2s),
        .irq_s2mm(NLW_inst_irq_s2mm_UNCONNECTED),
        .m_axi_mm2s_araddr(m_axi_mm2s_araddr),
        .m_axi_mm2s_arburst({NLW_inst_m_axi_mm2s_arburst_UNCONNECTED[1],io_m_axi_mm2s_arburst }),
        .m_axi_mm2s_arcache(NLW_inst_m_axi_mm2s_arcache_UNCONNECTED[3:0]),
        .m_axi_mm2s_arlen(m_axi_mm2s_arlen),
        .m_axi_mm2s_arprot(NLW_inst_m_axi_mm2s_arprot_UNCONNECTED[2:0]),
        .m_axi_mm2s_arready(m_axi_mm2s_arready),
        .m_axi_mm2s_arsize({NLW_inst_m_axi_mm2s_arsize_UNCONNECTED[2],io_m_axi_mm2s_arsize ,NLW_inst_m_axi_mm2s_arsize_UNCONNECTED[0]}),
        .m_axi_mm2s_aruser(NLW_inst_m_axi_mm2s_aruser_UNCONNECTED[3:0]),
        .m_axi_mm2s_arvalid(m_axi_mm2s_arvalid),
        .m_axi_mm2s_rdata(m_axi_mm2s_rdata),
        .m_axi_mm2s_rlast(m_axi_mm2s_rlast),
        .m_axi_mm2s_rready(m_axi_mm2s_rready),
        .m_axi_mm2s_rresp(m_axi_mm2s_rresp),
        .m_axi_mm2s_rvalid(m_axi_mm2s_rvalid),
        .m_axi_s2mm_awaddr(NLW_inst_m_axi_s2mm_awaddr_UNCONNECTED[31:0]),
        .m_axi_s2mm_awburst(NLW_inst_m_axi_s2mm_awburst_UNCONNECTED[1:0]),
        .m_axi_s2mm_awcache(NLW_inst_m_axi_s2mm_awcache_UNCONNECTED[3:0]),
        .m_axi_s2mm_awlen(NLW_inst_m_axi_s2mm_awlen_UNCONNECTED[7:0]),
        .m_axi_s2mm_awprot(NLW_inst_m_axi_s2mm_awprot_UNCONNECTED[2:0]),
        .m_axi_s2mm_awready(1'b0),
        .m_axi_s2mm_awsize(NLW_inst_m_axi_s2mm_awsize_UNCONNECTED[2:0]),
        .m_axi_s2mm_awuser(NLW_inst_m_axi_s2mm_awuser_UNCONNECTED[3:0]),
        .m_axi_s2mm_awvalid(NLW_inst_m_axi_s2mm_awvalid_UNCONNECTED),
        .m_axi_s2mm_bready(NLW_inst_m_axi_s2mm_bready_UNCONNECTED),
        .m_axi_s2mm_bresp({1'b0,1'b0}),
        .m_axi_s2mm_bvalid(1'b0),
        .m_axi_s2mm_wdata(NLW_inst_m_axi_s2mm_wdata_UNCONNECTED[31:0]),
        .m_axi_s2mm_wlast(NLW_inst_m_axi_s2mm_wlast_UNCONNECTED),
        .m_axi_s2mm_wready(1'b0),
        .m_axi_s2mm_wstrb(NLW_inst_m_axi_s2mm_wstrb_UNCONNECTED[3:0]),
        .m_axi_s2mm_wvalid(NLW_inst_m_axi_s2mm_wvalid_UNCONNECTED),
        .m_axis_mm2s_aclk(m_axis_mm2s_aclk),
        .m_axis_mm2s_aresetn(m_axis_mm2s_aresetn),
        .m_axis_mm2s_tdata(m_axis_mm2s_tdata),
        .m_axis_mm2s_tid({NLW_inst_m_axis_mm2s_tid_UNCONNECTED[7:4],io_m_axis_mm2s_tid }),
        .m_axis_mm2s_tready(m_axis_mm2s_tready),
        .m_axis_mm2s_tvalid(m_axis_mm2s_tvalid),
        .s_axi_lite_aclk(s_axi_lite_aclk),
        .s_axi_lite_araddr(s_axi_lite_araddr),
        .s_axi_lite_aresetn(s_axi_lite_aresetn),
        .s_axi_lite_arready(s_axi_lite_arready),
        .s_axi_lite_arvalid(s_axi_lite_arvalid),
        .s_axi_lite_awaddr(s_axi_lite_awaddr),
        .s_axi_lite_awready(s_axi_lite_awready),
        .s_axi_lite_awvalid(s_axi_lite_awvalid),
        .s_axi_lite_bready(s_axi_lite_bready),
        .s_axi_lite_bresp({io_s_axi_lite_bresp ,NLW_inst_s_axi_lite_bresp_UNCONNECTED[0]}),
        .s_axi_lite_bvalid(s_axi_lite_bvalid),
        .s_axi_lite_rdata(s_axi_lite_rdata),
        .s_axi_lite_rready(s_axi_lite_rready),
        .s_axi_lite_rresp({io_s_axi_lite_rresp ,NLW_inst_s_axi_lite_rresp_UNCONNECTED[0]}),
        .s_axi_lite_rvalid(s_axi_lite_rvalid),
        .s_axi_lite_wdata(s_axi_lite_wdata),
        .s_axi_lite_wready(s_axi_lite_wready),
        .s_axi_lite_wvalid(s_axi_lite_wvalid),
        .s_axis_s2mm_aclk(1'b0),
        .s_axis_s2mm_aresetn(1'b0),
        .s_axis_s2mm_tdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axis_s2mm_tid({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axis_s2mm_tready(NLW_inst_s_axis_s2mm_tready_UNCONNECTED),
        .s_axis_s2mm_tvalid(1'b0));
endmodule
