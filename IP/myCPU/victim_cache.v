module vcache(//全相联 八个条目
    input  wire         clk,
    input  wire         rst,
    // 写端口
    input  wire         wen,
    input  wire [ 31:0] waddr,
    input  wire [511:0] cacheline_w,

    // 读端口
    input  wire         vcache_en,       
    input  wire [31:0]  raddr,
    output wire         hit,
    output reg          refresh,
    output reg  [511:0] cacheline_r
);
reg  [  4:0] times;
reg  [511:0] cache_way [31:0];
wire [ 31:0] cache_hit;
reg  [ 25:0] cache_tag [31:0];
reg  [ 31:0] cache_v;


reg [1:0] stage_r;//r通道状态机
reg [1:0] stage_w;//w通道状态机

parameter IDLE = 2'b10,
	      ACTIVE = 2'b01;

always @(posedge clk) begin
    if(rst) begin
        stage_w <= IDLE;
        times   <= 5'b0;
        cache_v <= 32'b0;
    end 
    else begin
        case(stage_w)
            IDLE: begin
                if(wen) begin
                    stage_w <= ACTIVE;
                end else begin
                    stage_w <= IDLE;
                end
            end
            ACTIVE: begin
                if(wen) begin
                    cache_way[times] <= cacheline_w;
                    cache_tag[times] <= waddr[31:6];
                    cache_v[times]   <= 1'b1;
                end
                else begin
                    stage_w <= IDLE;
                    times   <= times + 1'b1;
                end
            end
            default: stage_w <= IDLE;
        endcase
    end
end

assign cache_hit[0] = (raddr[31:6] == cache_tag[0]) && cache_v[0];
assign cache_hit[1] = (raddr[31:6] == cache_tag[1]) && cache_v[1];
assign cache_hit[2] = (raddr[31:6] == cache_tag[2]) && cache_v[2];
assign cache_hit[3] = (raddr[31:6] == cache_tag[3]) && cache_v[3];
assign cache_hit[4] = (raddr[31:6] == cache_tag[4]) && cache_v[4];
assign cache_hit[5] = (raddr[31:6] == cache_tag[5]) && cache_v[5];
assign cache_hit[6] = (raddr[31:6] == cache_tag[6]) && cache_v[6];
assign cache_hit[7] = (raddr[31:6] == cache_tag[7]) && cache_v[7];
assign cache_hit[8] = (raddr[31:6] == cache_tag[8]) && cache_v[8];
assign cache_hit[9] = (raddr[31:6] == cache_tag[9]) && cache_v[9];
assign cache_hit[10] = (raddr[31:6] == cache_tag[10]) && cache_v[10];
assign cache_hit[11] = (raddr[31:6] == cache_tag[11]) && cache_v[11];
assign cache_hit[12] = (raddr[31:6] == cache_tag[12]) && cache_v[12];
assign cache_hit[13] = (raddr[31:6] == cache_tag[13]) && cache_v[13];
assign cache_hit[14] = (raddr[31:6] == cache_tag[14]) && cache_v[14];
assign cache_hit[15] = (raddr[31:6] == cache_tag[15]) && cache_v[15];
assign cache_hit[16] = (raddr[31:6] == cache_tag[16]) && cache_v[16];
assign cache_hit[17] = (raddr[31:6] == cache_tag[17]) && cache_v[17];
assign cache_hit[18] = (raddr[31:6] == cache_tag[18]) && cache_v[18];
assign cache_hit[19] = (raddr[31:6] == cache_tag[19]) && cache_v[19];
assign cache_hit[20] = (raddr[31:6] == cache_tag[20]) && cache_v[20];
assign cache_hit[21] = (raddr[31:6] == cache_tag[21]) && cache_v[21];
assign cache_hit[22] = (raddr[31:6] == cache_tag[22]) && cache_v[22];
assign cache_hit[23] = (raddr[31:6] == cache_tag[23]) && cache_v[23];
assign cache_hit[24] = (raddr[31:6] == cache_tag[24]) && cache_v[24];
assign cache_hit[25] = (raddr[31:6] == cache_tag[25]) && cache_v[25];
assign cache_hit[26] = (raddr[31:6] == cache_tag[26]) && cache_v[26];
assign cache_hit[27] = (raddr[31:6] == cache_tag[27]) && cache_v[27];
assign cache_hit[28] = (raddr[31:6] == cache_tag[28]) && cache_v[28];
assign cache_hit[29] = (raddr[31:6] == cache_tag[29]) && cache_v[29];
assign cache_hit[30] = (raddr[31:6] == cache_tag[30]) && cache_v[30];
assign cache_hit[31] = (raddr[31:6] == cache_tag[31]) && cache_v[31];

assign hit = |cache_hit;

always @(posedge clk) begin
    if(rst) begin
        stage_r <= IDLE;
        refresh <= 1'b0;
    end 
    else begin
        case(stage_r)
            IDLE: begin
                if(hit && vcache_en) begin
                    stage_r <= ACTIVE;
                    refresh <= 1'b1;
                    cacheline_r  <= ({512{cache_hit[0]}} & cache_way[0]) |
                                    ({512{cache_hit[1]}} & cache_way[1]) |
                                    ({512{cache_hit[2]}} & cache_way[2]) |
                                    ({512{cache_hit[3]}} & cache_way[3]) |
                                    ({512{cache_hit[4]}} & cache_way[4]) |
                                    ({512{cache_hit[5]}} & cache_way[5]) |
                                    ({512{cache_hit[6]}} & cache_way[6]) |
                                    ({512{cache_hit[7]}} & cache_way[7]) |
                                    ({512{cache_hit[8]}} & cache_way[8]) |
                                    ({512{cache_hit[9]}} & cache_way[9]) |
                                    ({512{cache_hit[10]}} & cache_way[10]) |
                                    ({512{cache_hit[11]}} & cache_way[11]) |
                                    ({512{cache_hit[12]}} & cache_way[12]) |
                                    ({512{cache_hit[13]}} & cache_way[13]) |
                                    ({512{cache_hit[14]}} & cache_way[14]) |
                                    ({512{cache_hit[15]}} & cache_way[15]) |
                                    ({512{cache_hit[16]}} & cache_way[16]) |
                                    ({512{cache_hit[17]}} & cache_way[17]) |
                                    ({512{cache_hit[18]}} & cache_way[18]) |
                                    ({512{cache_hit[19]}} & cache_way[19]) |
                                    ({512{cache_hit[20]}} & cache_way[20]) |
                                    ({512{cache_hit[21]}} & cache_way[21]) |
                                    ({512{cache_hit[22]}} & cache_way[22]) |
                                    ({512{cache_hit[23]}} & cache_way[23]) |
                                    ({512{cache_hit[24]}} & cache_way[24]) |
                                    ({512{cache_hit[25]}} & cache_way[25]) |
                                    ({512{cache_hit[26]}} & cache_way[26]) |
                                    ({512{cache_hit[27]}} & cache_way[27]) |
                                    ({512{cache_hit[28]}} & cache_way[28]) |
                                    ({512{cache_hit[29]}} & cache_way[29]) |
                                    ({512{cache_hit[30]}} & cache_way[30]) |
                                    ({512{cache_hit[31]}} & cache_way[31]);
                end else begin
                    stage_r <= IDLE;
                end
            end
            ACTIVE: begin
                stage_r <= IDLE;
                refresh <= 1'b0;
            end
            default: stage_r <= IDLE;
        endcase
    end
end

endmodule
