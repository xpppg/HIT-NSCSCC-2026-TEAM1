// =====================================================================
// dcache_top.v
// 集成示例: CPU <-> L1(dcache) <-> L2(dcache_l2) <-> 主存
// 说明: L1的AXI主设备端口(arvalid/araddr/... , awvalid/awaddr/awcacheline...)
//       与L2的L1从端口(l1_ar*, l1_r*, l1_aw*)信号语义完全一致, 可直接对接。
// =====================================================================
module dcache_top
(
    input  wire         clk,
    input  wire         rst,

    // ---------------- CPU <-> L1 ----------------
    input  wire         cpu_en,
    input  wire  [3:0]  cpu_wen,
    input  wire  [31:0] cpu_addr,
    input  wire  [31:0] cpu_waddr,
    input  wire  [31:0] cpu_wdata,
    input  wire         cached_v,
    output wire  [31:0] cpu_rdata,
    output wire         cpu_stall,

    // ---------------- L2 <-> 主存(对外AXI精简接口) ----------------
    input  wire         arready,
    output wire         arvalid,
    output wire  [31:0] araddr,

    input  wire         rvalid,
    output wire         rready,
    input  wire [511:0] cacheline_new,

    input  wire         awready,
    output wire         awvalid,
    output wire  [31:0] awaddr,
    output wire [511:0] awcacheline
);

    // L1 <-> L2 内部连线
    wire         l2_arready, l2_arvalid;
    wire [31:0]  l2_araddr;
    wire         l2_rvalid, l2_rready;
    wire [511:0] l2_rdata;
    wire         l2_awready, l2_awvalid;
    wire [31:0]  l2_awaddr;
    wire [511:0] l2_awdata;

    dcache u_dcache (
        .clk        (clk),
        .rst        (rst),

        .cpu_en     (cpu_en),
        .cpu_wen    (cpu_wen),
        .cpu_addr   (cpu_addr),
        .cpu_waddr  (cpu_waddr),
        .cpu_wdata  (cpu_wdata),
        .cached_v   (cached_v),
        .cpu_rdata  (cpu_rdata),
        .cpu_stall  (cpu_stall),

        // L1把L2当作"主存"来访问
        .arready      (l2_arready),
        .arvalid      (l2_arvalid),
        .araddr       (l2_araddr),

        .rvalid       (l2_rvalid),
        .rready       (l2_rready),
        .cacheline_new(l2_rdata),

        .awready      (l2_awready),
        .awvalid      (l2_awvalid),
        .awaddr       (l2_awaddr),
        .awcacheline  (l2_awdata)
    );

    dcache_l2 u_dcache_l2 (
        .clk         (clk),
        .rst         (rst),

        // L1侧(从设备)
        .l1_arvalid  (l2_arvalid),
        .l1_arready  (l2_arready),
        .l1_araddr   (l2_araddr),

        .l1_rvalid   (l2_rvalid),
        .l1_rready   (l2_rready),
        .l1_rdata    (l2_rdata),

        .l1_awvalid  (l2_awvalid),
        .l1_awready  (l2_awready),
        .l1_awaddr   (l2_awaddr),
        .l1_awdata   (l2_awdata),

        // 主存侧(主设备) -- 直接透传到本模块外部端口
        .arready      (arready),
        .arvalid      (arvalid),
        .araddr       (araddr),

        .rvalid       (rvalid),
        .rready       (rready),
        .cacheline_new(cacheline_new),

        .awready      (awready),
        .awvalid      (awvalid),
        .awaddr       (awaddr),
        .awcacheline  (awcacheline)
    );

endmodule
