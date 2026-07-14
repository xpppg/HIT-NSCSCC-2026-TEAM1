module uncache(
    input wire clk,
    input wire rst,
    output wire stallreq,

    input wire conf_en,
    input wire [3:0] conf_wen,
    input wire [2:0] conf_rsize,
    input wire [31:0] conf_addr,
    input wire [31:0] conf_wdata,
    output reg [31:0] conf_rdata,

    output reg axi_en, 
    output reg [3:0] axi_wsel, 
    output reg [31:0] axi_addr, 
    output reg [2:0] axi_rsize, 
    output reg [31:0] axi_wdata,

    input wire reload,
    input wire [31:0] axi_rdata
);
reg [2:0] stage;
parameter IDLE = 3'b100,
	      WAIT = 3'b010,
		  DONE = 3'b001;

always @(posedge clk) begin
    if(rst) begin
        stage <= IDLE;
        axi_en <= 1'b0;
    end 
    else begin
        case(stage)
            IDLE: begin
                if(conf_en) begin
                    stage <= WAIT;
                    axi_en <= 1'b1;
                    axi_wsel <= conf_wen;
                    axi_addr <= conf_addr;
                    axi_wdata <= conf_wdata;
                    axi_rsize <= conf_rsize;
                end else begin
                    stage <= IDLE;
                    axi_en <= 1'b0;
                end
            end
            WAIT: begin
                if(reload) begin
                    stage <= DONE;
                    conf_rdata <= axi_rdata;
                    axi_en <= 1'b0;
                end else begin
                    stage <= WAIT;
                end
            end
            DONE: begin
                stage <= IDLE;
            end
            default: stage <= IDLE;
        endcase
    end
end

assign stallreq = ~(conf_en & (stage == DONE)) & conf_en;

endmodule