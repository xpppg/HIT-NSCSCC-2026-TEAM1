// =====================================================================
// dcache_l2_tagv.v
// 32KB 二级 D-Cache 标签阵列
//   - 2 路组相联, 64B/行(512bit), 行大小与L1保持一致
//   - 32KB = 256 组 x 2 路 x 64B  =>  index=8bit, tag=18bit, offset=6bit
//   - 每行 tag entry = {valid(1), dirty(1), tag(18)} = 20bit
//   - LRU 沿用 L1 的单比特"受害者指针"方案:
//        lru_r[index] == 0  => way0 是当前受害者(下一次替换 way0)
//        lru_r[index] == 1  => way1 是当前受害者(下一次替换 way1)
//     每次命中或分配后, 把受害者指针指向"另一路", 即被访问路变为MRU
// =====================================================================
module dcache_l2_tagv(
    input  wire        clk,
    input  wire        rst,

    // 当前事务的行地址(offset位不参与tag查找, 可为任意值)
    input  wire [31:0] addr,

    // 组合输出: 命中信息
    output wire        hit_any,     // 该组内两路是否有命中
    output wire        hit_way,     // 命中的路号(仅在hit_any=1时有意义), 0=way0,1=way1

    // 组合输出: 当前组的替换受害者信息(用于miss时判断是否需要先写回)
    output wire        victim_way,
    output wire        victim_valid,
    output wire        victim_dirty,
    output wire [17:0] victim_tag,

    // 提交口: 写tag/valid/dirty(用于 命中写 / 缺失分配), 并更新LRU指针
    input  wire        alloc_en,
    input  wire        alloc_way,
    input  wire        alloc_dirty,

    // 仅更新LRU(不改tag/dirty), 用于读命中时把命中路标记为MRU
    input  wire        touch_en,
    input  wire        touch_way
);

    // {valid, dirty, tag[17:0]}
    reg [255:0] valid_way0;
    reg [255:0] valid_way1;
    (* ram_style = "block" *) reg [18:0] tag_way0 [0:255];
    (* ram_style = "block" *) reg [18:0] tag_way1 [0:255];
    reg  [255:0] lru_r;

    wire [17:0] tag_f = addr[31:14];
    wire [7:0]  index = addr[13:6];

    wire        v0 = valid_way0[index];
    wire        v1 = valid_way1[index];
    reg         d0;
    reg  [17:0] t0;
    reg         d1;
    reg  [17:0] t1;
    //wire        d0 = tag_way0[index][18];
    //wire [17:0] t0 = tag_way0[index][17:0];
    //wire        d1 = tag_way1[index][18];
    //wire [17:0] t1 = tag_way1[index][17:0];
    always @(posedge clk) begin
        if (rst) begin
            d0 <= 1'b0;
            t0 <= 18'b0;
            d1 <= 1'b0;
            t1 <= 18'b0;
        end
        else begin
            d0 <= tag_way0[index][18];
            t0 <= tag_way0[index][17:0];
            d1 <= tag_way1[index][18];
            t1 <= tag_way1[index][17:0];
        end
    end

    wire hit_way0 = v0 & (t0 == tag_f);
    wire hit_way1 = v1 & (t1 == tag_f);

    assign hit_any = hit_way0 | hit_way1;
    assign hit_way = hit_way1;          // 只在hit_any=1时有效

    assign victim_way   = lru_r[index];
    assign victim_valid = victim_way ? v1 : v0;
    assign victim_dirty = victim_way ? d1 : d0;
    assign victim_tag   = victim_way ? t1 : t0;

    always @(posedge clk) begin
        if (rst) begin
            valid_way0 <= 256'b0;
            valid_way1 <= 256'b0;
        end
        else if (alloc_en) begin
            if (alloc_way) begin 
                valid_way1[index] <= 1'b1;
                tag_way1[index] <= {alloc_dirty, tag_f};
            end else begin
                valid_way0[index] <= 1'b1;
                tag_way0[index] <= {alloc_dirty, tag_f};
            end
        end
    end

    always @(posedge clk) begin
        if (rst)
            lru_r <= 256'b0;
        else if (alloc_en)
            lru_r[index] <= ~alloc_way;
        else if (touch_en)
            lru_r[index] <= ~touch_way;
    end

endmodule
