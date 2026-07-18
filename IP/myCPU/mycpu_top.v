`include "def_cache.vh"
module core_top(
    input           aclk,
    input           aresetn,
    input    [ 7:0] intrpt, 
    //AXI interface 
    //read reqest
    output   [ 3:0] arid,
    output   [31:0] araddr,
    output   [ 7:0] arlen,
    output   [ 2:0] arsize,
    output   [ 1:0] arburst,
    output   [ 1:0] arlock,
    output   [ 3:0] arcache,
    output   [ 2:0] arprot,
    output          arvalid,
    input           arready,
    //read back
    input    [ 3:0] rid,
    input    [31:0] rdata,
    input    [ 1:0] rresp,
    input           rlast,
    input           rvalid,
    output          rready,
    //write request
    output   [ 3:0] awid,
    output   [31:0] awaddr,
    output   [ 7:0] awlen,
    output   [ 2:0] awsize,
    output   [ 1:0] awburst,
    output   [ 1:0] awlock,
    output   [ 3:0] awcache,
    output   [ 2:0] awprot,
    output          awvalid,
    input           awready,
    //write data
    output   [ 3:0] wid,
    output   [31:0] wdata,
    output   [ 3:0] wstrb,
    output          wlast,
    output          wvalid,
    input           wready,
    //write back
    input    [ 3:0] bid,
    input    [ 1:0] bresp,
    input           bvalid,
    output          bready,

    //debug
    input           break_point,//无需实现功能，仅提供接口即可，输�?1’b0
    input           infor_flag,//无需实现功能，仅提供接口即可，输�?1’b0
    input  [ 4:0]   reg_num,//无需实现功能，仅提供接口即可，输�?5’b0
    output          ws_valid,//无需实现功能，仅提供接口即可
    output [31:0]   rf_rdata,//无需实现功能，仅提供接口即可

    //debug info
    output [31:0] debug0_wb_pc,
    output [ 3:0] debug0_wb_rf_wen,
    output [ 4:0] debug0_wb_rf_wnum,
    output [31:0] debug0_wb_rf_wdata,
    output [31:0] debug1_wb_pc,
    output [ 3:0] debug1_wb_rf_wen,
    output [ 4:0] debug1_wb_rf_wnum,
    output [31:0] debug1_wb_rf_wdata
    //output        stall1,
    //output        stall2,
    //output wire [6:0]  arstate0,
    //output wire [5:0]  rstate0,
    //output wire [6:0]  awstate0,
    //output wire [31:0] raddr0,
    //output wire [31:0] pc_buf_EXE,
    //output wire        EXE_vaild,
    //output wire [3:0]  data_we,
    //output wire [31:0] data_addr,
    //output wire [31:0] data_wdata,
    //output wire [4:0]  debug_data_v,
    //output wire        debug_wb,
    //output wire [ 5:0] debug_ecode,
    //output wire [ 8:0] debug_esubcode,
    //output wire [ 6:0] debug_mux,
    //output wire [31:0] debug_pc,
    //output wire [31:0] debug_inst,
    //output wire        debug_valid,
    //output wire [18:0] debug_tlb_vppn
);
    assign ws_valid = 1'b0; // debug interface, not used
    assign rf_rdata = 32'b0; // debug interface, not used

    wire clk = aclk;
    wire rst = ~aresetn;

    wire inst_sram_en;
    wire [31:0] inst_sram_addr;
    wire [31:0] inst_sram_rdata;
    wire [31:0] inst_sram_rdata2;

    wire data_sram_en;
    wire [3:0] data_sram_wen;
    wire [31:0] data_sram_addr;
    wire [31:0] data_sram_waddr;
    wire [2:0] data_sram_rsize; 
    wire [31:0] data_sram_wdata;
    wire [31:0] data_sram_rdata;
    wire [31:0] data_sram_rdata2;

    wire inst_cached_v;
    wire data_cached_v;    

    // cache_top
    wire icache_refresh, dcache_refresh;
    wire icache_arvalid, dcache_miss;
    wire icache_arready;
    wire [31:0] icache_raddr, dcache_raddr;
    wire icache_write_back, dcache_write_back;
    wire [31:0] icache_waddr, dcache_waddr;
    wire [`CACHELINE_WIDTH-1:0] icache_cacheline_old, dcache_cacheline_old;
    wire [`CACHELINE_WIDTH-1:0] icache_cacheline_new, dcache_cacheline_new;
    wire [511:0] icache_cacheline_new_axi;
    wire [511:0] icache_cacheline_new_vcache;
    wire icache_refresh_vcache;
    wire icache_refresh_axi;
    wire ivcache_hit;
    wire [511:0] dcache_cacheline_new_axi;
    wire [511:0] dcache_cacheline_new_buffer;
    wire dcache_refresh_buffer;
    wire dcache_refresh_axi;
    wire dbuffer_hit;
    wire dbuffer_ren;
    wire [31:0] dbuffer_raddr;
    wire dbuffer_refresh;
    wire [511:0] dbuffer_cacheline_new;
    wire axi_aw_free;

    // uncache
    wire        uncache_refresh;
    wire        uncache_en;
    wire [3:0]  uncache_wen;
    wire [31:0] uncache_addr;
    wire [2:0] uncache_rsize;
    wire [31:0] uncache_wdata;
    wire [31:0] uncache_rdata;
    wire        uncache_hit;

    wire [31:0] dcache_temp_rdata;
    wire [31:0] uncache_temp_rdata;

    
    wire stallreq_icache;
    wire stallreq_dcache;
    wire stallreq_uncache;
    wire fetch_stall;
    wire cpu_stall;

    assign fetch_stall = stallreq_icache;
    assign cpu_stall = stallreq_dcache | stallreq_uncache;
    //new
    reg         reset;
    always @(posedge aclk) begin
        reset <= ~aresetn;
    end
    wire inst_sram_en_out;
    wire [31:0] inst_sram_addr_out;

    wire data_sram_en_out;
    wire [3:0] data_sram_wen_out;
    wire [2:0] data_sram_rsize_out;
    wire [31:0] data_sram_addr_out;
    wire [31:0] data_sram_waddr_out;
    wire [31:0] data_sram_wdata_out;

    wire data_cached_v_out;  

    reg inst_sram_en_buf;
    reg [31:0] inst_sram_addr_buf;

    reg data_sram_en_buf;
    reg [3:0] data_sram_wen_buf;
    reg [2:0] data_sram_rsize_buf;
    reg [31:0] data_sram_addr_buf;
    reg [31:0] data_sram_waddr_buf;
    reg [31:0] data_sram_wdata_buf;
    reg inst_cached_v_buf;
    reg data_cached_v_buf;
    
    reg fetch_stall_buf;
    reg cpu_stall_buf;
    always @(posedge aclk) begin
        if(reset)
        begin
            inst_sram_en_buf <= 1'b0;
            inst_sram_addr_buf <= 32'b0;

            //inst_cached_v_buf <= 1'b0;
        end
        else if(~fetch_stall_buf | ~fetch_stall)
        begin
            inst_sram_en_buf <= inst_sram_en_out;
            inst_sram_addr_buf <= inst_sram_addr_out;

            //inst_cached_v_buf <= inst_cached_v_out;
        end
    end

    always @(posedge aclk) begin
        if(reset)
        begin
            data_sram_en_buf <= 1'b0;
            data_sram_wen_buf <= 4'b0;
            data_sram_rsize_buf <= 3'b0;
            data_sram_addr_buf <= 32'b0;
            data_sram_waddr_buf <= 32'b0;
            data_sram_wdata_buf <= 32'b0;

            data_cached_v_buf <= 1'b0;
        end
        else if(~cpu_stall_buf | ~cpu_stall)
        begin
            data_sram_en_buf <= data_sram_en_out;
            data_sram_wen_buf <= data_sram_wen_out;
            data_sram_rsize_buf <= data_sram_rsize_out;
            data_sram_addr_buf <= data_sram_addr_out;
            data_sram_waddr_buf <= data_sram_waddr_out;
            data_sram_wdata_buf <= data_sram_wdata_out;

            data_cached_v_buf <= data_cached_v_out;
        end
    end
    always @(posedge aclk) begin
        if(reset) begin
            fetch_stall_buf <= 1'b0;
            cpu_stall_buf <= 1'b0;
        end else begin
            fetch_stall_buf <= fetch_stall;
            cpu_stall_buf <= cpu_stall;
        end
    end

    assign inst_sram_en = fetch_stall_buf ? inst_sram_en_buf : inst_sram_en_out;
    assign inst_sram_addr = fetch_stall_buf ? inst_sram_addr_buf : inst_sram_addr_out;

//    assign inst_cached_v = fetch_stall_buf ? inst_cached_v_buf : inst_cached_v_out;

    assign data_sram_en = cpu_stall_buf ? data_sram_en_buf : data_sram_en_out;
    assign data_sram_wen = cpu_stall_buf ? data_sram_wen_buf : data_sram_wen_out;
    assign data_sram_rsize = cpu_stall_buf ? data_sram_rsize_buf : data_sram_rsize_out;
    assign data_sram_addr = cpu_stall_buf ? data_sram_addr_buf : data_sram_addr_out;
    assign data_sram_waddr = cpu_stall_buf ? data_sram_waddr_buf : data_sram_waddr_out;
    assign data_sram_wdata = cpu_stall_buf ? data_sram_wdata_buf : data_sram_wdata_out;

    assign data_cached_v = cpu_stall_buf ? data_cached_v_buf : data_cached_v_out;


    mycpu_core u_mycpu_core(
        .clk                    (aclk              ),
        .resetn                 (aresetn           ),
        .intrpt                 (intrpt            ),

        .inst_sram_en           (inst_sram_en_out      ),
        .inst_sram_addr         (inst_sram_addr_out    ),
        .inst_sram_rdata        (inst_sram_rdata       ),
        .inst_sram_rdata2       (inst_sram_rdata2      ),

        .data_sram_en           (data_sram_en_out      ),
        .data_sram_wen          (data_sram_wen_out     ),
        .data_sram_rsize        (data_sram_rsize_out   ),
        .data_sram_addr         (data_sram_addr_out    ),
        .data_sram_waddr        (data_sram_waddr_out   ),
        .data_sram_wdata        (data_sram_wdata_out   ),
        .data_sram_rdata        (data_sram_rdata       ),
        .dcache_v               (data_cached_v_out     ),
        
        .fetch_stall            (fetch_stall_buf       ),
        .cpu_stall              (cpu_stall_buf         ),

        .debug_wb_pc            (debug0_wb_pc       ),
        .debug_wb_rf_we         (debug0_wb_rf_wen   ),
        .debug_wb_rf_wnum       (debug0_wb_rf_wnum  ),
        .debug_wb_rf_wdata      (debug0_wb_rf_wdata ),
        .debug1_wb_pc           (debug1_wb_pc       ),
        .debug1_wb_rf_we        (debug1_wb_rf_wen   ),
        .debug1_wb_rf_wnum      (debug1_wb_rf_wnum  ),
        .debug1_wb_rf_wdata     (debug1_wb_rf_wdata )
    );
    //assign data_we = data_sram_wen_out;
    //assign data_addr = data_sram_addr_out;
    //assign data_wdata = data_sram_wdata_out;

    icache u_icache(
        .clk           (clk                  ),
        .resetn        (aresetn              ),
        .cpu_req       (inst_sram_en         ),
        .cpu_addr      (inst_sram_addr       ),
        .cache_rdata   (inst_sram_rdata      ),
        .cache_rdata2  (inst_sram_rdata2     ),
        .cache_stall   (stallreq_icache      ),

        .araddr        (icache_raddr         ),
        .arvalid       (icache_arvalid       ),
        .arready       (icache_arready       ),

        .rcacheline    (icache_cacheline_new ),
        .rvalid        (icache_refresh       ),
        .rready        (                     )
    );
    
    assign icache_refresh = icache_refresh_axi;
    assign icache_cacheline_new = icache_cacheline_new_axi;
    //assign icache_refresh = icache_refresh_axi | icache_refresh_vcache;
    //assign icache_cacheline_new = icache_refresh_axi ? icache_cacheline_new_axi : 
    //                                                   icache_cacheline_new_vcache;

    vcache u_ivcache(
        .clk           (clk                        ),
        .rst           (rst                        ),

        .wen           (icache_write_back          ),
        .waddr         (icache_waddr               ),
        .cacheline_w   (icache_cacheline_old       ),

        .vcache_en     (                           ),
        .raddr         (inst_sram_addr             ),
        .hit           (ivcache_hit                ),
        .refresh       (icache_refresh_vcache      ),
        .cacheline_r   (icache_cacheline_new_vcache)
    );

    dcache u_dcache(
        .clk           (clk           ),
        .rst           (rst           ),
        .sram_en       (data_sram_en       ),
        .sram_wen      (data_sram_wen      ),
        .sram_addr     (data_sram_addr     ),
        .sram_waddr    (data_sram_waddr    ),
        .sram_wdata    (data_sram_wdata    ),
        .refresh       (dcache_refresh       ),
        .cached        (data_cached_v        ),
        .cacheline_new (dcache_cacheline_new ),

        .stallreq      (stallreq_dcache      ),
        .sram_rdata    (dcache_temp_rdata    ),
        .miss          (dcache_miss          ),
        .raddr         (dcache_raddr         ),
        .waddr         (dcache_waddr         ),
        .write_back    (dcache_write_back    ),
        .cacheline_old (dcache_cacheline_old )
    );
    /*
    assign dcache_refresh = dcache_refresh_axi | dcache_refresh_buffer;
    assign dcache_cacheline_new = dcache_refresh_axi ? dcache_cacheline_new_axi : dcache_cacheline_new_buffer;
    */
    assign dcache_refresh = dcache_refresh_axi;
    assign dcache_cacheline_new = dcache_cacheline_new_axi;
/*
    dbuffer u_dbuffer(
        .clk           (clk           ),
        .rst           (rst           ),

        .cache_ren     (dcache_miss   ),
        .cache_raddr   (dcache_raddr  ),
        .cache_wen     (dcache_write_back  ),
        .cache_waddr   (dcache_waddr       ),
        .buffer_hit    (                   ),
        .cache_refresh (                   ),
        .buffer_cacheline_old (dcache_cacheline_new_buffer),

        .buffer_ren    (              ),
        .buffer_raddr  (              ),

        .axi_aw_free   (axi_aw_free),
        .buffer_refresh(dbuffer_refresh),
        .buffer_cacheline_new (dbuffer_cacheline_new)
    );
*/
    assign dbuffer_hit = 1'b0;
    assign dcache_refresh_buffer = 1'b0;
    assign dbuffer_ren = 1'b0;
    assign dbuffer_raddr = 32'b0;

    reg data_cached_r;
    always @ (posedge clk) begin
        data_cached_r <= data_cached_v;
    end
    assign data_sram_rdata = data_cached_r ? dcache_temp_rdata : uncache_temp_rdata;
    
    
    uncache u_uncache(
        .clk        (clk                          ),
        .rst        (rst                          ),
        .stallreq   (stallreq_uncache             ),
        .conf_en    (data_sram_en & ~data_cached_v),
        .conf_wen   (data_sram_wen                ),
        .conf_rsize (data_sram_rsize              ),
        .conf_addr  (data_sram_addr               ),
        .conf_wdata (data_sram_wdata              ),
        .conf_rdata (uncache_temp_rdata           ), 
        .axi_en     (uncache_en                   ),
        .axi_wsel   (uncache_wen                  ),
        .axi_addr   (uncache_addr                 ),
        .axi_rsize  (uncache_rsize                ),
        .axi_wdata  (uncache_wdata                ),
        .reload     (uncache_refresh              ),
        .axi_rdata  (uncache_rdata                )
    );
    
    axi_control u_axi_control(
        .clk                  (clk                  ),
        .rst                  (rst                  ),
        
        .icache_ren           (icache_arvalid       ),
        .icache_arready       (icache_arready       ),
        .icache_raddr         (icache_raddr         ),
        .icache_cacheline_new (icache_cacheline_new_axi ),
        .icache_refresh       (icache_refresh_axi       ),
        
        .dcache_ren           (dcache_miss          ),
        .dcache_raddr         (dcache_raddr         ),
        .dcache_cacheline_new (dcache_cacheline_new_axi ),

        .dcache_wen           (dcache_write_back    ),
        .dcache_waddr         (dcache_waddr         ),
        .dcache_cacheline_old (dcache_cacheline_old ),
        .dbuffer_hit          (dbuffer_hit          ),
        .dcache_refresh       (dcache_refresh_axi   ),
        
        .dbuffer_ren          (dbuffer_ren          ),
        .dbuffer_raddr        (dbuffer_raddr        ),
        .dbuffer_cacheline_new(dbuffer_cacheline_new),
        .dbuffer_refresh      (dbuffer_refresh      ),
        .axi_aw_free          (axi_aw_free          ),

        .uncache_en           (uncache_en           ),
        .uncache_wen          (uncache_wen          ),
        .uncache_rsize        (uncache_rsize        ),
        .uncache_addr         (uncache_addr         ),
        .uncache_wdata        (uncache_wdata        ),
        .uncache_rdata        (uncache_rdata        ),
        .uncache_refresh      (uncache_refresh      ),

        .arid                 (arid                 ),
        .araddr               (araddr               ),
        .arlen                (arlen                ),
        .arsize               (arsize               ),
        .arburst              (arburst              ),
        .arlock               (arlock               ),
        .arcache              (arcache              ),
        .arprot               (arprot               ),
        .arvalid              (arvalid              ),
        .arready              (arready              ),
        .rid                  (rid                  ),
        .rdata                (rdata                ),
        .rresp                (rresp                ),
        .rlast                (rlast                ),
        .rvalid               (rvalid               ),
        .rready               (rready               ),
        .awid                 (awid                 ),
        .awaddr               (awaddr               ),
        .awlen                (awlen                ),
        .awsize               (awsize               ),
        .awburst              (awburst              ),
        .awlock               (awlock               ),
        .awcache              (awcache              ),
        .awprot               (awprot               ),
        .awvalid              (awvalid              ),
        .awready              (awready              ),
        .wid                  (wid                  ),
        .wdata                (wdata                ),
        .wstrb                (wstrb                ),
        .wlast                (wlast                ),
        .wvalid               (wvalid               ),
        .wready               (wready               ),
        .bid                  (bid                  ),
        .bresp                (bresp                ),
        .bvalid               (bvalid               ),
        .bready               (bready               )
        //debug
        //.arstate0            (arstate0            ),
        //.rstate0             (rstate0             ),
        //.awstate0            (awstate0            ),
        //.raddr0              (raddr0              )
    );
    
    //assign stall1 = stallreq_dcache;
    //assign stall2 = stallreq_uncache;

endmodule 