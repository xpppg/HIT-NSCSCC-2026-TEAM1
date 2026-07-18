`include "def_cache.vh"
module dcache
#(
    parameter HIT_WD       = 2,
    parameter LRU_WD       = 1,
    parameter CACHELINE_WD = 512
)
(
    input wire         clk,
    input wire         rst,
    input wire         sram_en,
    input wire  [ 3:0] sram_wen,
    input wire  [31:0] sram_addr,
    input wire  [31:0] sram_waddr,
    input wire  [31:0] sram_wdata,
    input wire         refresh,
    input wire         cached,
    input wire  [CACHELINE_WD -1:0] cacheline_new,
    
    output wire        stallreq,
    output wire [31:0] sram_rdata,
    output wire        miss,
    output wire [31:0] raddr,
    output wire [31:0] waddr,
    output wire        write_back,
    output wire [CACHELINE_WD -1:0] cacheline_old
);

    wire [HIT_WD       -1:0] hit;
    wire [HIT_WD       -1:0] hit1;
    wire [LRU_WD       -1:0] lru;
    
    dcache_tag_v5 u_dcache_tag(
    	.clk        (clk             ),
        .rst        (rst             ),
        .flush      (1'b0            ),
        .stallreq   (stallreq        ),
        .cached     (cached          ),
        .sram_en    (sram_en         ),
        .sram_wen   (sram_wen        ),
        .sram_addr  (sram_addr       ),
        .sram_waddr (sram_waddr      ),
        .refresh    (refresh         ),
        .miss       (miss            ),
        .axi_raddr  (raddr           ),
        .write_back (write_back      ),
        .axi_waddr  (waddr           ),
        .hit        (hit             ),
        .hit1       (hit1            ),
        .lru        (lru             )
    );

    dcache_data_v5 u_dcache_data(
    	.clk           (clk          ),
        .rst           (rst          ),
        .write_back    (write_back   ),
        .hit           (hit          ),
        .hit1          (hit1         ),
        .lru           (lru          ),
        .cached        (cached       ),
        .sram_en       (sram_en      ),
        .sram_wen      (sram_wen     ),
        .sram_addr     (sram_addr    ),
        .sram_wdata    (sram_wdata   ),
        .sram_rdata    (sram_rdata   ),
        .refresh       (refresh      ),
        .cacheline_new (cacheline_new   ),
        .cacheline_old (cacheline_old   ) 
    );

endmodule