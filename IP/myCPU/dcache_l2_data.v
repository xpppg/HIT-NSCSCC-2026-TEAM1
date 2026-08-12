// =====================================================================
// dcache_l2_data.v
// 32KB 二级 D-Cache 数据阵列
//   - 2路 x 256组 x 512bit(64B)
//   - L2 只做"整行读/整行写"(来自L1的整行写回, 来自内存的整行填充,
//     以及送回L1/送回内存的整行读出), 不存在字节使能的字级访问,
//     因此无需像L1那样拆成16个32bit bank + 译码, 直接用整行宽存储即可。
//   - 读为同步读(1拍延迟), 与真实BRAM行为一致。
// =====================================================================
module dcache_l2_data(
    input  wire         clk,
    input  wire         rst,

    input  wire [7:0]   index,     // 当前事务的组号
    input  wire         way,       // 当前事务访问的路号(0/1)

    input  wire         wr_en,     // 整行写使能
    input  wire [511:0] wr_data,

    output wire [511:0] rd_data    // 1拍后有效(地址由index/way给出)
);

    (* ram_style = "block" *) reg [511:0] mem_way0 [255:0];
    (* ram_style = "block" *) reg [511:0] mem_way1 [255:0];

    reg [511:0] rd_way0;
    reg [511:0] rd_way1;
    reg         way_d;

    always @(posedge clk) begin
        if (wr_en) begin
            if (way)
                mem_way1[index] <= wr_data;
            else
                mem_way0[index] <= wr_data;
        end
    end

    always @(posedge clk) begin
        rd_way0 <= mem_way0[index];
        rd_way1 <= mem_way1[index];
        way_d   <= way;
    end

    assign rd_data = way_d ? rd_way1 : rd_way0;

endmodule
