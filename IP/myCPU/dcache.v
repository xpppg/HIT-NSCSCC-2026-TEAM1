module dcache
(
    input wire         clk,
    input wire         rst,
    //cpu interface
    input wire         cpu_en,
    input wire  [ 3:0] cpu_wen,
    input wire  [31:0] cpu_addr,
    input wire  [31:0] cpu_waddr,
    input wire  [31:0] cpu_wdata,
    input wire         cached_v,
    output wire [31:0] cpu_rdata,
    output wire        cpu_stall,
    //axi interface
    input  wire        arready,
    output wire        arvalid,
    output wire [31:0] araddr,

    input wire         rvalid,
    output wire        rready,
    input wire  [511:0] cacheline_new,

    input  wire        awready,
    output wire        awvalid,
    output reg  [31:0] awaddr,
    output reg  [511:0] awcacheline
    //表示写操作完成
    //,
    //input wire         bvalid,
    //output wire        bready
);

wire [1:0] hit;
wire [1:0] hit1;
wire lru;
wire [511:0] cacheline_old;

reg [3:0] stage;
reg [3:0] wstage;
parameter IDLE = 4'b1000,
          SEND = 4'b0100,
          REC  = 4'b0010,
          DONE = 4'b0001;

reg sel1;
reg [31:0] axi_raddr;
wire miss;
wire axi_wen;
wire [31:0] axi_waddr;

always @(posedge clk) begin
    if(rst) begin
        stage <= IDLE;
    end 
    else begin
        case(stage)
            IDLE: begin
                if(miss) begin
                    stage <= SEND;
                    axi_raddr <= {cpu_addr[31:6],6'b0};
                    sel1 <= lru;
                end
            end
            SEND: begin
                if(arready && arvalid)
                    stage <= REC;
            end
            REC: begin
                if(rready & rvalid) 
                    stage <= DONE;
            end
            DONE: begin
                if(wstage == DONE) 
                    stage <= IDLE;
            end
            default: stage <= IDLE;
        endcase
    end
end

always @(posedge clk) begin
    if(rst) begin
        wstage <= IDLE;
    end 
    else begin
        case(wstage)
            IDLE: begin
                if(stage == SEND & axi_wen) begin
                    wstage <= SEND;
                    awaddr <= axi_waddr;
                    awcacheline <= cacheline_old;
                end else if(stage == SEND & ~axi_wen) begin
                    wstage <= DONE;
                end
            end
            SEND: begin
                if(awready && awvalid)
                    wstage <= REC;
            end
            REC: begin
                wstage <= DONE;
            end
            DONE: begin
                if(stage == DONE) 
                    wstage <= IDLE;
            end
            default: wstage <= IDLE;
        endcase
    end
end

assign araddr = axi_raddr;
assign arvalid = (stage == SEND);

assign rready = (stage == REC);

assign awvalid = (wstage == SEND);
    
    dcache_tagv u_dcache_tagv(
    	.clk        (clk             ),
        .rst        (rst             ),
        .cached_v   (cached_v        ),
        .cpu_en     (cpu_en          ),
        .cpu_wen    (cpu_wen         ),
        .cpu_addr   (cpu_addr        ),
        .cpu_waddr  (cpu_waddr       ),
        .refresh    (rready & rvalid ),
        .miss       (miss            ),
        .axi_wen    (axi_wen         ),
        .axi_waddr  (axi_waddr       ),
        .hit        (hit             ),
        .hit1       (hit1            ),
        .lru        (lru             )
    );

    dcache_data u_dcache_data(
    	.clk           (clk             ),
        .rst           (rst             ),
        .hit           (hit             ),
        .hit1          (hit1            ),
        .sel1          (sel1            ),
        .cpu_wen       (cpu_wen         ),
        .cpu_addr      (cpu_addr        ),
        .cpu_wdata     (cpu_wdata       ),
        .cpu_rdata     (cpu_rdata       ),
        .refresh       (rready & rvalid ),
        .cacheline_new (cacheline_new   ),
        .cacheline_old (cacheline_old   ) 
    );

assign cpu_stall = miss | ~stage[3];

endmodule