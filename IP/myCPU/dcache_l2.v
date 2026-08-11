// =====================================================================
// dcache_l2.v
// 32KB 二级 D-Cache 主控模块, 位于 L1 dcache 与主存之间
//
// 参数: 2路组相联, 64B/512bit 行, 与L1行大小一致(便于整行搬运)
//       32KB = 256组 x 2路 x 64B  => index[13:6], tag[31:14], offset[5:0]
//
// 端口分两组总线, 协议均为"valid握手, 地址/数据在valid期间保持不变直到
// 对端ready", 与dcache.v中L1访问主存的AXI精简协议完全一致:
//   1) L1侧(从设备): L1是主设备, L2响应L1的两类请求
//        - 读通道(l1_ar/l1_r) : L1缺失时, 向L2取一整行
//        - 写通道(l1_aw)      : L1替换出脏行/有效行时, 把整行写回L2
//        (与L1自身到内存的接口一样, 不使用B响应通道, 即"fire-and-forget")
//   2) 内存侧(主设备): L2是主设备, 端口定义与dcache.v的主存接口完全相同,
//        可直接对接原来接在L1后面的那一路主存/AXI控制器。
//
// 脏位与写回策略(重点):
//   - L2标签为每一行维护真实的 dirty 位。
//   - L1对某行做写回(l1_aw)时无法区分"真脏"还是"仅被换出", 因此L2一律
//     将其视为脏行(alloc_dirty=1), 这是安全的上界(不会丢数据, 语义与
//     L1自身"淘汰即写回"的策略一致)。
//   - 从内存新填充进L2的行(读缺失分配)标记为干净(alloc_dirty=0)。
//   - L2自身淘汰一路时: 只有当受害路 valid&dirty 同时成立才会把该行
//     写回主存; 若受害路无效或只是"干净"副本(与内存一致), 则直接
//     丢弃/覆盖, 不产生到主存的写事务。这就是相对L1(每次有效淘汰都写回)
//     更进一步的、基于脏位的写回优化, 能显著减少L2->主存的写流量。
// =====================================================================
module dcache_l2
(
    input  wire         clk,
    input  wire         rst,

    // ------------------ L1 侧: L2作为从设备, L1作为主设备 ------------------
    // 读通道: L1缺失 -> 向L2取整行
    input  wire         l1_arvalid,
    output wire         l1_arready,
    input  wire [31:0]  l1_araddr,

    output wire         l1_rvalid,
    input  wire         l1_rready,
    output wire [511:0] l1_rdata,

    // 写通道: L1淘汰 -> 向L2整行写回
    input  wire         l1_awvalid,
    output wire         l1_awready,
    input  wire [31:0]  l1_awaddr,
    input  wire [511:0] l1_awdata,

    // ------------------ 主存侧: L2作为主设备(接口形式与dcache.v对主存一致) ------------------
    input  wire         arready,
    output wire         arvalid,
    output wire [31:0]  araddr,

    input  wire         rvalid,
    output wire         rready,
    input  wire [511:0] cacheline_new,

    input  wire         awready,
    output wire         awvalid,
    output wire [31:0]  awaddr,
    output wire [511:0] awcacheline
);

    // -------------------- FSM 状态定义 --------------------
    localparam S_IDLE       = 4'd0,  // 等待L1发起请求(读或写), 优先接受写回
               S_LOOKUP     = 4'd1,  // 组合查询tag, 决定命中/缺失/是否需要先淘汰
               S_RD_HIT     = 4'd2,  // 读命中: 等待数据阵列1拍读延迟
               S_RD_RESP    = 4'd3,  // 向L1返回读数据, 等待 l1_rready
               S_EV_READ    = 4'd4,  // 需要淘汰: 等待 victim 数据阵列1拍读延迟
               S_EV_SEND    = 4'd5,  // 把 victim line 写回主存, 等待 awready
               S_FETCH_SEND = 4'd6,  // 读缺失: 向主存发起AR, 等待arready
               S_FETCH_REC  = 4'd7,  // 读缺失: 等待主存rvalid, 收整行数据
               S_ALLOC_WR   = 4'd8;  // 提交: 写数据阵列 + 写tag(分配/命中写)

    reg  [3:0]   state;
    reg          mode;          // 0=读缺失填充(来自L1的ar请求) 1=写回(来自L1的aw请求)
    reg  [31:0]  req_addr;
    reg  [511:0] req_wdata;
    reg          target_way;    // 本次事务最终要写入/读出的路号
    reg  [17:0]  victim_tag_r;  // victim 的原tag(仅在需要淘汰时使用)
    reg          is_hit_r;      // 本次事务在L2是否命中
    reg  [511:0] fetched_data;  // 从主存取回的整行数据(读缺失路径)

    // -------------------- tag子模块查询/更新信号 --------------------
    wire        hit_any, hit_way;
    wire        victim_way, victim_valid, victim_dirty;
    wire [17:0] victim_tag;

    wire tag_alloc_en    = (state == S_ALLOC_WR);
    wire tag_alloc_way   = target_way;
    wire tag_alloc_dirty = mode;              // 写回路径->脏, 读填充路径->干净
    wire tag_touch_en    = (state == S_RD_HIT);
    wire tag_touch_way   = target_way;

    // -------------------- data子模块访问信号 --------------------
    wire [511:0] rd_data;
    wire [7:0]   data_index = req_addr[13:6];
    // S_LOOKUP阶段用组合的hit/victim路号提前打到地址口, 这样经过1拍寄存
    // 后, 进入S_RD_HIT/S_EV_READ时rd_data刚好有效, 不多耗一拍。
    wire         data_way   = (state == S_LOOKUP) ? (hit_any ? hit_way : victim_way)
                                                   : target_way;
    wire         data_wr_en   = (state == S_ALLOC_WR);
    wire [511:0] data_wr_data = mode ? req_wdata : fetched_data;

    // -------------------- L1侧握手 --------------------
    // 采用"写优先"仲裁: 同一拍两者都请求时先接受写回, 便于尽快腾空L1的
    // 淘汰行；读请求会在下一次空闲时被接受(L1侧会持续保持arvalid直到
    // 被接受, 与dcache.v自身的SEND状态语义一致)。
    assign l1_awready = (state == S_IDLE);
    assign l1_arready = (state == S_IDLE) & ~l1_awvalid;

    assign l1_rvalid = (state == S_RD_RESP);
    assign l1_rdata  = is_hit_r ? rd_data : fetched_data;

    // -------------------- 主存侧握手 --------------------
    assign arvalid = (state == S_FETCH_SEND);
    assign araddr  = {req_addr[31:6], 6'b0};

    assign rready  = (state == S_FETCH_REC);

    assign awvalid     = (state == S_EV_SEND);
    assign awaddr      = {victim_tag_r, req_addr[13:6], 6'b0};
    assign awcacheline = rd_data;

    // -------------------- 主状态机 --------------------
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (l1_awvalid) begin
                        mode      <= 1'b1;
                        req_addr  <= l1_awaddr;
                        req_wdata <= l1_awdata;
                        state     <= S_LOOKUP;
                    end
                    else if (l1_arvalid) begin
                        mode     <= 1'b0;
                        req_addr <= l1_araddr;
                        state    <= S_LOOKUP;
                    end
                end

                S_LOOKUP: begin
                    target_way   <= hit_any ? hit_way : victim_way;
                    victim_tag_r <= victim_tag;
                    is_hit_r     <= hit_any;
                    if (hit_any) begin
                        // 命中: 写回路径直接改数据+置脏; 读路径先取数据
                        state <= mode ? S_ALLOC_WR : S_RD_HIT;
                    end
                    else if (victim_valid & victim_dirty) begin
                        // 缺失且受害路是脏行 -> 必须先写回主存
                        state <= S_EV_READ;
                    end
                    else begin
                        // 缺失但受害路无效或干净 -> 无需写回, 直接分配/取数
                        state <= mode ? S_ALLOC_WR : S_FETCH_SEND;
                    end
                end

                S_RD_HIT: begin
                    state <= S_RD_RESP;
                end

                S_RD_RESP: begin
                    if (l1_rready) state <= S_IDLE;
                end

                S_EV_READ: begin
                    state <= S_EV_SEND;
                end

                S_EV_SEND: begin
                    if (awready) begin
                        state <= mode ? S_ALLOC_WR : S_FETCH_SEND;
                    end
                end

                S_FETCH_SEND: begin
                    if (arready) state <= S_FETCH_REC;
                end

                S_FETCH_REC: begin
                    if (rvalid) begin
                        fetched_data <= cacheline_new;
                        state        <= S_ALLOC_WR;
                    end
                end

                S_ALLOC_WR: begin
                    // 写回路径: 数据+tag(脏)写完即结束事务, 不等待L1的
                    // 二次确认(与L1对主存的写通道一样是fire-and-forget,
                    // l1_awready已经在S_IDLE那一拍完成了握手)。
                    // 读路径: 还需要把数据交给L1, 转S_RD_RESP。
                    state <= mode ? S_IDLE : S_RD_RESP;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // -------------------- 子模块例化 --------------------
    dcache_l2_tagv u_dcache_l2_tagv (
        .clk          (clk),
        .rst          (rst),
        .addr         (req_addr),
        .hit_any      (hit_any),
        .hit_way      (hit_way),
        .victim_way   (victim_way),
        .victim_valid (victim_valid),
        .victim_dirty (victim_dirty),
        .victim_tag   (victim_tag),
        .alloc_en     (tag_alloc_en),
        .alloc_way    (tag_alloc_way),
        .alloc_dirty  (tag_alloc_dirty),
        .touch_en     (tag_touch_en),
        .touch_way    (tag_touch_way)
    );

    dcache_l2_data u_dcache_l2_data (
        .clk     (clk),
        .rst     (rst),
        .index   (data_index),
        .way     (data_way),
        .wr_en   (data_wr_en),
        .wr_data (data_wr_data),
        .rd_data (rd_data)
    );

endmodule
