module cache_tagv (
    input         clk     ,  // 时钟
    input         resetn  ,  // 低有效复位信号

    //cpu访问信号
    input  wire        re      ,    //由CPU发送至Cache
    input  wire [31:0] raddr   ,    //由CPU发送至Cache
    output wire        hit0    ,
    output wire        hit1    ,
    output wire        miss    ,
    output reg  [63:0] lru     ,    //0表示替换way0，1表示替换way1
    //写端口
    input  wire        we      ,
    input  wire        sel0    ,
    input  wire [31:0] waddr

);

reg [19:0] tag_way0 [63:0];//每个cacheline的tag位
reg [19:0] tag_way1 [63:0];
reg [63:0] valid_way0;//每个cacheline的有效位
reg [63:0] valid_way1;

wire [5:0] index;
wire [19:0] tag;



genvar i;//复位
generate
    for(i=0; i < 64; i = i + 1) begin
        initial begin
            tag_way0[i] = 20'b0;      //将tag ram在初始时清0
            tag_way1[i] = 20'b0; 
        end
    end
endgenerate



wire [5:0] windex;
assign windex = waddr[11:6];

//写入处理
always@(posedge clk) begin
    if(~resetn) begin
        valid_way0 <= 64'b0;        //复位时将所有Cache行置为无效
        valid_way1 <= 64'b0;
    end
    else begin
        if(we & sel0) begin
            valid_way0[windex] <= 1'b1;
            tag_way0[windex] <= waddr[31:12];
        end
        else if(we & ~sel0) begin
            valid_way1[windex] <= 1'b1;
            tag_way1[windex] <= waddr[31:12];
        end
    end
end

always @(posedge clk) begin
    if(~resetn) begin
        lru <= 64'b0;
    end
    else if(hit0 & ~hit1) begin
        lru[index] <= 1'b1;
    end
    else if(~hit0 & hit1) begin
        lru[index] <= 1'b0;
    end
end

assign index = raddr[11:6];
assign tag = raddr[31:12];

assign hit0 = (tag_way0[index] == tag) && valid_way0[index] && re;
assign hit1 = (tag_way1[index] == tag) && valid_way1[index] && re;

assign miss = re && ~hit0 && ~hit1;

endmodule
