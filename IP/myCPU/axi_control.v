module axi_control(
    input  wire clk,
    input  wire rst,

    // icache 
    input  wire icache_ren, 
    output wire icache_arready,
    input  wire [31:0] icache_raddr,
    
    output reg  icache_refresh, 
    output wire [511:0] icache_cacheline_new,

    // dcache 
    input  wire dcache_ren, 
    input  wire [31:0] dcache_raddr, 
    output wire [511:0] dcache_cacheline_new,
    
    input  wire dcache_wen, 
    input  wire [31:0] dcache_waddr, 
    input  wire [511:0] dcache_cacheline_old, 

    input  wire dbuffer_hit,
    
    output reg  dcache_refresh, // fin
    
    //dbuffer
    input  wire dbuffer_ren,
    input  wire [31:0] dbuffer_raddr,
    output wire [511:0] dbuffer_cacheline_new,

    output reg  dbuffer_refresh,
    output wire axi_aw_free,

    // uncache  
    input  wire uncache_en,
    input  wire [3:0] uncache_wen,
    input  wire [2:0] uncache_rsize,
    input  wire [31:0] uncache_addr,
    input  wire [31:0] uncache_wdata,
    output wire [31:0] uncache_rdata,
    output wire uncache_refresh,
    
    //ar 读请求通道
    output wire [3 :0] arid   ,
    output wire [31:0] araddr ,
    output wire [3 :0] arlen  ,
    output wire [2 :0] arsize ,
    output wire [1 :0] arburst,
    output wire [1 :0] arlock ,
    output wire [3 :0] arcache,
    output wire [2 :0] arprot ,
    output wire        arvalid,
    input  wire        arready,
    //r 读响应通道
    input  wire [3 :0] rid    ,
    input  wire [31:0] rdata  ,
    input  wire [1 :0] rresp  ,
    input  wire        rlast  ,
    input  wire        rvalid ,
    output wire        rready ,
    //aw 写请求通道
    output wire [3 :0] awid   ,
    output wire [31:0] awaddr ,
    output wire [3 :0] awlen  ,
    output wire [2 :0] awsize ,
    output wire [1 :0] awburst,
    output wire [1 :0] awlock ,
    output wire [3 :0] awcache,
    output wire [2 :0] awprot ,
    output wire        awvalid,
    input  wire        awready,
    //w 写数据通道
    output wire [3 :0] wid    ,
    output wire [31:0] wdata  ,
    output wire [3 :0] wstrb  ,
    output wire        wlast  ,
    output wire        wvalid ,
    input  wire        wready ,
    //b 写响应通道
    input  wire [3 :0] bid    ,
    input  wire [1 :0] bresp  ,
    input  wire        bvalid ,
    output wire        bready ,
    //debug
    output wire [6:0]  arstate0,
    output wire [5:0]  rstate0,
    output wire [6:0]  awstate0,
    output wire [31:0] raddr0
);


assign arburst = 2'b01;
assign arlock = 2'b00;
assign arcache = 4'b0000;
assign arprot = 3'b000;

assign awburst = 2'b01;
assign awlock = 2'b00;
assign awcache = 4'b0000;
assign awprot = 3'b000;

reg [6:0] arstate;//ar通道状态机
parameter AR_START = 7'b1000000,
	      AR_uncache = 7'b0100000,//uncache read
		  AR_dcache = 7'b0010000,//dcache read
          AR_icache = 7'b0001000,//icache read
          AR_dbuffer = 7'b0000100,//dbuffer read
          AR_WAIT = 7'b0000010,
          AR_DONE = 7'b0000001;
reg [5:0] rstate;//r通道状态机
parameter R_START = 6'b100000,
	      R_uncache = 6'b010000,//uncache read
		  R_dcache = 6'b001000,//dcache read
          R_icache = 6'b000100,//icache read
          R_dbuffer = 6'b000010,//dbuffer read
          R_DONE = 6'b000001;
reg [6:0] awstate;//写请求通道状态机
parameter AW_START     = 7'b1000000,
          AW_uncache   = 7'b0100000,
          AW_dcache    = 7'b0010000,
          AW_uncache_w = 7'b0001000,
          AW_dcache_w  = 7'b0000100,
          AW_WAIT      = 7'b0000010,
          AW_DONE      = 7'b0000001;

reg  [ 2:0] arsize_buf;
reg  [31:0] araddr_buf;
reg  uncache_refresh_1;
reg  uncache_refresh_2;
reg  last_buffer;
assign arstate0 = arstate;
assign rstate0 = rstate;
assign awstate0 = awstate;
assign raddr0 = araddr_buf;

always @(posedge clk) begin
    if(rst) begin
        arstate <= AR_START;
        last_buffer <= 1'b0;
    end 
    else begin
        case(arstate)
            AR_START: begin
                if(uncache_en && (uncache_wen == 4'b0000)) begin
                    arstate <= AR_uncache;
                    araddr_buf <= uncache_addr;
                    arsize_buf <= uncache_rsize;
                end else if(dcache_ren & dbuffer_hit & ~dcache_wen) begin
                    if(dbuffer_ren) begin
                        arstate <= AR_dbuffer;
                        araddr_buf <= dbuffer_raddr;
                    end else begin
                        arstate <= AR_START;
                    end
                end else if(dcache_ren & dbuffer_hit & dcache_wen) begin
                    arstate <= AR_DONE;
                    araddr_buf <= dcache_raddr;
                end else if(dcache_ren && ~dcache_refresh) begin
                    arstate <= AR_dcache;
                    araddr_buf <= dcache_raddr;
                end else if(icache_ren) begin
                    arstate <= AR_icache;
                    araddr_buf <= icache_raddr;
                end else if(dbuffer_ren) begin
                    arstate <= AR_dbuffer;
                    araddr_buf <= dbuffer_raddr;
                end else begin
                    arstate <= AR_START;
                end
            end
            AR_uncache: begin
                if(arready & arvalid) begin
                    arstate <= AR_WAIT;
                end else begin
                    arstate <= AR_uncache;
                end
            end
            AR_dcache: begin
                if(arready & arvalid) begin
                    arstate <= AR_WAIT;
                end else begin
                    arstate <= AR_dcache;
                end
            end
            AR_icache: begin
                if(arready & arvalid) begin
                    arstate <= AR_WAIT;
                end else begin
                    arstate <= AR_icache;
                end
            end
            AR_dbuffer: begin
                if(arready & arvalid) begin
                    arstate <= AR_WAIT;
                    last_buffer <= 1'b1;
                end else begin
                    arstate <= AR_dbuffer;
                end
            end
            AR_WAIT: begin
                if(rstate == R_DONE) begin
                    if(last_buffer) begin
                        last_buffer <= 1'b0;
                        arstate <= AR_START;
                    end else if(dcache_ren && dcache_wen) begin 
                        arstate <= AR_DONE;
                    end else if(dcache_ren && ~dcache_wen) begin
                        arstate <= AR_START;
                    end else begin
                        arstate <= AR_START;
                    end
                end else begin
                    arstate <= AR_WAIT;
                end
            end
            AR_DONE: begin
                if(awstate == AW_DONE) begin
                    if(dbuffer_ren) begin
                        arstate <= AR_dbuffer;
                        araddr_buf <= dbuffer_raddr;
                    end else begin
                        arstate <= AR_START;
                    end
                end else begin
                    arstate <= AR_DONE;
                end
            end
            default: arstate <= AR_START;
        endcase
    end
end

assign arid = ({4{arstate == AR_uncache}} & 4'b0010 ) | 
              ({4{arstate == AR_dcache }} & 4'b0001 ) | 
              ({4{arstate == AR_icache }} & 4'b0000 ) | 
              ({4{arstate == AR_dbuffer}} & 4'b0001 ) ;
assign araddr = araddr_buf;
assign arvalid = (arstate == AR_uncache) | (arstate == AR_dcache) | (arstate == AR_icache) | (arstate == AR_dbuffer);
assign arlen = (arstate == AR_uncache) ? 4'b0 : 
               (arstate == AR_dcache) ? 4'hf : 
               (arstate == AR_icache) ? 4'hf :
               (arstate == AR_dbuffer) ? 4'hf : 4'b0;
assign arsize = (arstate == AR_uncache) ? arsize_buf : 3'b010;
assign icache_arready = (arstate == AR_icache);


//读响应通道
reg  [ 31:0] uncache_buf;
reg  [511:0] cacheline_buf;
reg  [  3:0] offset;
reg  [  3:0] offset2;

assign rready = (rstate == R_uncache) | (rstate == R_dcache) | (rstate == R_icache) | (rstate == R_dbuffer); 

always @(posedge clk) begin
    if(rst) begin
        rstate <= R_START;
        uncache_refresh_1 <= 1'b0;
        icache_refresh <= 1'b0;
        dcache_refresh <= 1'b0;
        dbuffer_refresh <= 1'b0;
        offset <= 4'b0;
    end 
    else begin
        case(rstate)
            R_START: begin
                if(arstate == AR_uncache) begin
                    rstate <= R_uncache;
                end else if(arstate == AR_dcache) begin
                    rstate <= R_dcache;
                end else if(arstate == AR_icache) begin
                    rstate <= R_icache;
                end else if(arstate == AR_dbuffer) begin
                    rstate <= R_dbuffer;
                end else begin
                    rstate <= R_START;
                end
            end
            R_uncache: begin
                if(rvalid & rready) begin
                    rstate <= R_DONE;
                    uncache_buf <= rdata;
                    uncache_refresh_1 <= 1'b1;
                end else begin
                    rstate <= R_uncache;
                end
            end
            R_dcache: begin
                if(rvalid & rready & ~rlast) begin
                    cacheline_buf[offset*32 +: 32] <= rdata;
                    offset <= offset + 4'b1;
                    rstate <= R_dcache;
                end else if(rvalid & rready & rlast) begin
                    cacheline_buf[offset*32 +: 32] <= rdata;
                    offset <= offset + 4'b1;
                    dcache_refresh <= 1'b1;
                    rstate <= R_DONE;
                end else begin
                    rstate <= R_dcache;
                end
            end
            R_icache: begin
                if(rvalid & rready & ~rlast) begin
                    cacheline_buf[offset*32 +: 32] <= rdata;
                    offset <= offset + 4'b1;
                    rstate <= R_icache;
                end else if(rvalid & rready & rlast) begin
                    cacheline_buf[offset*32 +: 32] <= rdata;
                    offset <= offset + 4'b1;
                    icache_refresh <= 1'b1;
                    rstate <= R_DONE;
                end else begin
                    rstate <= R_icache;
                end
            end
            R_dbuffer: begin
                if(rvalid & rready & ~rlast) begin
                    cacheline_buf[offset*32 +: 32] <= rdata;
                    offset <= offset + 4'b1;
                    rstate <= R_dbuffer;
                end else if(rvalid & rready & rlast) begin
                    cacheline_buf[offset*32 +: 32] <= rdata;
                    offset <= offset + 4'b1;
                    dbuffer_refresh <= 1'b1;
                    rstate <= R_DONE;
                end else begin
                    rstate <= R_dbuffer;
                end
            end
            R_DONE: begin
                rstate <= R_START;
                icache_refresh <= 1'b0;
                dcache_refresh <= 1'b0;
                dbuffer_refresh <= 1'b0;
                uncache_refresh_1 <= 1'b0;
                offset <= 4'b0;
            end
            default: rstate <= R_START;
        endcase
    end
end

assign icache_cacheline_new = cacheline_buf;
assign dcache_cacheline_new = cacheline_buf;
assign dbuffer_cacheline_new = cacheline_buf;
assign uncache_rdata = uncache_buf;

//写请求通道

reg [31:0] waddr_buf;
reg [31:0] wdata_buf;
reg [3:0] wstrb_buf;
reg [511:0] dcacheline_old_buf;
reg [2:0] uncache_size;
reg uncache_w;

assign axi_aw_free = (awstate == AW_START) | (waddr_buf == dcache_waddr);

always @(posedge clk) begin
    if(rst) begin
        awstate <= AW_START;
        uncache_refresh_2 <= 1'b0;
        offset2 <= 4'b0;
        uncache_w <= 1'b0;
    end 
    else begin
        case(awstate)
            AW_START: begin
                uncache_refresh_2 <= 1'b0;
                if(uncache_en && (uncache_wen != 4'b0000) && !uncache_refresh_2) begin
                    awstate <= AW_uncache;
                    waddr_buf <= uncache_addr;
                    wdata_buf <= uncache_wdata;
                    wstrb_buf <= uncache_wen;
                    uncache_w <= 1'b1;
                    case(uncache_wen)
                        4'b0001, 4'b0010, 4'b0100, 4'b1000: uncache_size <= 3'b000;
                        4'b0011, 4'b1100: uncache_size <= 3'b001;
                        4'b1111: uncache_size <= 3'b010;
                        default: uncache_size <= 3'b010; 
                    endcase
                end else if(dcache_wen && !dcache_refresh) begin
                    awstate <= AW_dcache;
                    waddr_buf <= dcache_waddr;
                end else begin
                    awstate <= AW_START;
                end
            end
            AW_uncache: begin
                if(awready & awvalid) begin
                    awstate <= AW_uncache_w;
                end else begin
                    awstate <= AW_uncache;
                end
            end
            AW_dcache: begin
                dcacheline_old_buf <= dcache_cacheline_old;
                if(awready & awvalid) begin
                    awstate <= AW_dcache_w;
                end else begin
                    awstate <= AW_dcache;
                end
            end
            AW_uncache_w: begin
                if(wready & wvalid & wlast) begin
                    awstate <= AW_WAIT;
                end else begin
                    awstate <= AW_uncache_w;
                end
            end
            AW_dcache_w: begin
                if(wready & wvalid & ~wlast) begin
                    offset2 <= offset2 + 4'b1;
                    awstate <= AW_dcache_w;
                end else if(wready & wvalid & wlast) begin
                    offset2 <= 4'b0;
                    awstate <= AW_WAIT;
                end else begin
                    awstate <= AW_dcache_w;
                end
            end
            AW_WAIT: begin
                if(bvalid & bready) begin
                    if(uncache_w) begin
                        uncache_refresh_2 <= 1'b1;
                        awstate <= AW_START;
                        uncache_w <= 1'b0;
                    end else begin
                        awstate <= AW_DONE;
                    end
                end else begin
                    awstate <= AW_WAIT;
                end
            end
            AW_DONE: begin
                if(arstate == AR_DONE) begin
                    awstate <= AW_START;
                end else begin
                    awstate <= AW_DONE;
                end
            end
            default: awstate <= AW_START;
        endcase
    end
end

assign awid    = ({4{awstate == AW_uncache}} & 4'b0010 ) | 
                 ({4{awstate == AW_dcache }} & 4'b0001 ) ;
assign awaddr  = waddr_buf;
assign awlen   = ({4{awstate == AW_uncache}} & 4'h0 ) | 
                 ({4{awstate == AW_dcache }} & 4'hf ) ;
assign awsize  = (awstate == AW_uncache) ? uncache_size : 3'b010;
assign awvalid = (awstate == AW_uncache) | (awstate == AW_dcache) ;
//写数据通道
assign wid     = ({4{awstate == AW_uncache_w}} & 4'b0010 ) | 
                 ({4{awstate == AW_dcache_w }} & 4'b0001 ) ;
assign wdata   = (awstate == AW_uncache_w) ? wdata_buf : dcacheline_old_buf[offset2*32+:32];
assign wstrb   = (awstate == AW_uncache_w) ? wstrb_buf : 4'b1111;
assign wlast   = (awstate == AW_uncache_w) ? 1'b1 : 
                 (offset2 == 4'b1111) ? 1'b1 : 1'b0;
assign wvalid  = (awstate == AW_uncache_w) | (awstate == AW_dcache_w);


//写响应通道
assign bready = 1'b1;

assign uncache_refresh = uncache_refresh_1 | uncache_refresh_2;

endmodule