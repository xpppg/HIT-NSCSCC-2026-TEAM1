module dcache
(
    input wire         clk,
    input wire         rst,
    //cpu interface
    input wire         sram_en,
    input wire  [ 3:0] sram_wen,
    input wire  [31:0] sram_addr,
    input wire  [31:0] sram_waddr,
    input wire  [31:0] sram_wdata,
    input wire         cached,
    output wire [31:0] sram_rdata,
    output wire        stallreq,
    //axi interface
    input  wire        arready,
    output wire        arvalid,
    output wire [31:0] araddr,

    input wire         rvalid,
    output wire        rready,
    input wire  [511:0] cacheline_new,

    input  wire        awready,
    output wire        awvalid,
    output wire [31:0] axi_waddr,
    output wire [511:0] cacheline_old
    //表示写操作完成
    //,
    //input wire         bvalid,
    //output wire        bready
);

wire [1:0] hit;
wire [1:0] hit1;
wire lru;

reg [2:0] stage;
parameter IDLE = 3'b100,
          SEND = 3'b010,
          REC  = 3'b001;

reg sel1;
reg [31:0] axi_raddr;

always @(posedge clk) begin
    if(rst) begin
        stage <= IDLE;
    end 
    else begin
        case(stage)
            IDLE: begin
                if(miss) begin
                    stage <= SEND;
                    axi_raddr <= {sram_addr[31:6],6'b0};
                    sel1 <= lru;
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
    
    dcache_tag_v5 u_dcache_tag(
    	.clk        (clk             ),
        .rst        (rst             ),
        .stallreq   (stallreq        ),
        .cached     (cached          ),
        .sram_en    (sram_en         ),
        .sram_wen   (sram_wen        ),
        .sram_addr  (sram_addr       ),
        .sram_waddr (sram_waddr      ),
        .refresh    (refresh         ),
        .axi_ren    (axi_ren         ),
        .axi_wen    (axi_wen         ),
        .axi_waddr  (axi_waddr       ),
        .hit        (hit             ),
        .hit1       (hit1            ),
        .lru        (lru             )
    );

    dcache_data_v5 u_dcache_data(
    	.clk           (clk          ),
        .rst           (rst          ),
        .hit           (hit          ),
        .hit1          (hit1         ),
        .sel1          (sel1         ),
        .sram_wen      (sram_wen     ),
        .sram_addr     (sram_addr    ),
        .sram_wdata    (sram_wdata   ),
        .sram_rdata    (sram_rdata   ),
        .refresh       (refresh      ),
        .cacheline_new (cacheline_new   ),
        .cacheline_old (cacheline_old   ) 
    );

assign cache_stall = miss | ~stage[2];

endmodule