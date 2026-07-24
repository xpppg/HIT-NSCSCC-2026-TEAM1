module dbuffer
(
    input wire          clk,
    input wire          rst,
    
    input  wire         cache_ren,
    input  wire [31:0]  cache_raddr,
    input  wire         cache_wen,
    input  wire [31:0]  cache_waddr,
    output wire         buffer_hit,
    output reg          cache_refresh,
    output reg  [511:0] buffer_cacheline_old,

    output reg          buffer_ren,
    output reg  [31:0]  buffer_raddr,
    
    input  wire         axi_aw_free,
    input  wire         buffer_refresh,
    input  wire [511:0] buffer_cacheline_new
);
reg raddr_wait;
reg [31:0] raddr_old;
reg [31:0] raddr_old2;

reg [511:0] buffer_way;
reg [ 25:0] buffer_tag;
reg buffer_v;

reg [511:0] buffer_way2;
reg [ 25:0] buffer_tag2;
reg buffer_v2;

wire buffer_hit1;
wire buffer_hit2;
reg  cache_refresh1;
reg  cache_refresh2;
wire flush1;
wire flush2;
wire flush3;
reg  flush3_flag;
reg  buffer_inv;

reg [1:0] pre_stage;//预取状态机
parameter IDLE = 2'b10,
	      WAIT = 2'b01;


assign buffer_hit1 = ((buffer_tag == cache_raddr[31:6]) && buffer_v && pre_stage[1]);
assign buffer_hit2 = ((buffer_tag2 == cache_raddr[31:6]) && buffer_v2 && pre_stage[1]);
assign buffer_hit = buffer_hit1 | buffer_hit2;

assign flush1 = cache_wen && (cache_waddr[31:6] == buffer_tag);
assign flush2 = cache_wen && (cache_waddr[31:6] == buffer_tag2);
assign flush3 = cache_wen && (cache_waddr[31:6] == buffer_raddr[31:6]);

always @(posedge clk) begin
    if(rst) begin
        raddr_old <= 32'b0;
        raddr_old2 <= 32'b0;
        raddr_wait <= 1'b0;
    end 
    else begin
        if(cache_ren & ~raddr_wait & pre_stage[1]) begin
            raddr_old <= cache_raddr;
            raddr_old2 <= raddr_old;
            raddr_wait <= 1'b1;
        end
        else if(~cache_ren) begin
            raddr_wait <= 1'b0;
        end
    end
end

always @(posedge clk) begin
    if(rst) begin
        cache_refresh <= 1'b0;
        cache_refresh1 <= 1'b0;
        cache_refresh2 <= 1'b0;
    end 
    else begin
        if(cache_ren && buffer_hit1 && ~cache_refresh) begin
            cache_refresh <= 1'b1;
            cache_refresh1 <= 1'b1;
            buffer_cacheline_old <= buffer_way;
        end 
        else if(cache_ren && buffer_hit2 && ~cache_refresh) begin
            cache_refresh <= 1'b1;
            cache_refresh2 <= 1'b1;
            buffer_cacheline_old <= buffer_way2;
        end
        else begin
            cache_refresh <= 1'b0;
            cache_refresh1 <= 1'b0;
            cache_refresh2 <= 1'b0;
        end
    end
end

always @(posedge clk) begin
    if(rst) begin
        buffer_v <= 1'b0;
        buffer_v2 <= 1'b0;
    end 
    else begin
        if(buffer_refresh && ~flush3 && ~flush3_flag) begin
            buffer_v <= 1'b1;
            buffer_v2 <= buffer_v;
        end 
        if(cache_refresh1 | flush1) begin
            buffer_v <= 1'b0;
        end
        if(cache_refresh2 | flush2) begin
            buffer_v2 <= 1'b0;
        end
    end
end


always @(posedge clk) begin
    if(rst) begin
        pre_stage <= IDLE;
        buffer_ren <= 1'b0;
        buffer_raddr <= 32'b0;
    end 
    else begin
        case(pre_stage)
            IDLE: begin
                if(((cache_raddr == raddr_old + 32'd64) | (cache_raddr == raddr_old2 + 32'd64)) && cache_ren) begin
                    pre_stage <= WAIT;
                    buffer_ren <= 1'b1;
                    buffer_raddr <= cache_raddr + 32'd64;
                end else begin
                    pre_stage <= IDLE;
                end
            end
            WAIT: begin
                if(buffer_refresh) begin
                    pre_stage <= IDLE;
                    buffer_ren <= 1'b0;
                    if(~flush3 & ~flush3_flag) begin
                        buffer_way <= buffer_cacheline_new;
                        buffer_tag <= buffer_raddr[31:6];
                        buffer_way2 <= buffer_way;
                        buffer_tag2 <= buffer_tag;
                    end
                end else begin
                    pre_stage <= WAIT;
                end
            end
            default: pre_stage <= IDLE;
        endcase
    end
end

always @(posedge clk) begin
    if(rst) begin
        flush3_flag <= 1'b0;
    end 
    else begin
        if(flush3 && pre_stage == WAIT && ~buffer_refresh) begin
            flush3_flag <= 1'b1;
        end else if(buffer_refresh) begin
            flush3_flag <= 1'b0;
        end
    end
end

//wire debug1;
//wire debug2;
//assign debug1 = (cache_raddr == raddr_old + 32'd64) && cache_ren && (pre_stage == IDLE);
//assign debug2 = (cache_raddr == raddr_old2 + 32'd64) && cache_ren && (pre_stage == IDLE);

endmodule