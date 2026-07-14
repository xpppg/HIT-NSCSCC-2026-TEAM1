module icache (
    input            clk             ,  // 时钟
    input            resetn          ,  // 低有效复位信号

    //  Sram-Like接口信号，用于CPU访问Cache
    input          cpu_req      ,    //由CPU发送至Cache
    input  [ 31:0] cpu_addr     ,    //由CPU发送至Cache
    output [ 31:0] cache_rdata  ,    //由Cache返回给CPU
    output [ 31:0] cache_rdata2 ,    //由Cache返回给CPU
    output         cache_stall  ,

    //  AXI接口信号，用于Cache访问主存
    output [ 31:0] araddr ,              //Cache向主存发起读请求时所使用的地址
    output         arvalid,              //Cache向主存发起读请求的请求信号
    input          arready,              //读请求能否被接收的握手信号

    input  [511:0] rcacheline ,              //主存向Cache返回的数据
    input          rvalid    ,              //主存向Cache返回数据时的数据有效信号
    output         rready                //标识当前的Cache已经准备好可以接收主存返回的数据
);

wire [63:0] lru;
wire hit0;
wire hit1;
wire miss;

reg [2:0] stage;
parameter IDLE = 3'b100,
          SEND = 3'b010,
          REC  = 3'b001;

reg [31:0] axi_addr;
reg sel0;

always @(posedge clk) begin
    if(~resetn) begin
        stage <= IDLE;
    end 
    else begin
        case(stage)
            IDLE: begin
                if(miss) begin
                    stage <= SEND;
                    axi_addr <= {cpu_addr[31:6],6'b0};
                    sel0 <= ~lru[cpu_addr[11:6]];
                end
            end
            SEND: begin
                if(arready && arvalid)
                    stage <= REC;
            end
            REC: begin
                if(rready & rvalid) 
                    stage <= IDLE;
            end
            default: stage <= IDLE;
        endcase
    end
end

assign araddr = axi_addr;
assign arvalid = (stage == SEND);

assign rready = (stage == REC);

wire tagv_we;
wire [31:0] tagv_waddr;

assign tagv_we = rvalid & rready;
assign tagv_waddr = axi_addr;

cache_tagv cache_tagv(
    .clk(clk),
    .resetn(resetn),
    .re(cpu_req),
    .raddr(cpu_addr),
    .hit0(hit0),
    .hit1(hit1),
    .miss(miss),
    .lru(lru),

    .we(tagv_we),
    .sel0(sel0),
    .waddr(tagv_waddr)
);

cache_data cache_data(
    .clk(clk),
    .resetn(resetn),

    .raddr(cpu_addr),
    .re_way_sel0(hit0),
    .rdata(cache_rdata),
    .rdata2(cache_rdata2),

    .we(rvalid & rready),
    .waddr(axi_addr),
    .we_way_sel0(sel0),
    .wcacheline(rcacheline)
);


assign cache_stall = miss | ~stage[2];


//wire cache_addr_ok;
//assign cache_addr_ok = (stage == IDLE) && (hit0 || hit1);

//reg rdata_valid;

//always @(posedge clk) begin
//    if(~resetn) begin
//        rdata_valid <= 1'b0;
//    end
//    else if(cache_addr_ok) begin
//        rdata_valid <= 1'b1;
//    end else begin
//        rdata_valid <= 1'b0;
//    end
//end

endmodule
