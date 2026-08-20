`timescale 1ns / 1ps

module tb_avp_stream_dma_stop;
    reg clk = 0;
    reg resetn = 0;
    reg enable = 0;
    reg [31:0] base_addr = 32'h01000000;
    reg [31:0] byte_length = 32'd128;
    wire running;
    wire error;
    wire [31:0] fetched_pos;
    wire [63:0] stream_data;
    wire stream_valid;
    reg stream_ready = 1;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [3:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire [1:0] arlock;
    wire [3:0] arcache;
    wire [2:0] arprot;
    wire arvalid;
    reg arready = 1;
    reg [3:0] rid = 4'h5;
    reg [63:0] rdata = 0;
    reg [1:0] rresp = 0;
    reg rlast = 0;
    reg rvalid = 0;
    wire rready;
    integer beat;

    always #5 clk = ~clk;

    avp_stream_dma #(.AXI_ID(4'h5)) dut (
        .clk(clk), .resetn(resetn), .enable(enable),
        .base_addr(base_addr), .byte_length(byte_length),
        .running(running), .error(error), .fetched_pos(fetched_pos),
        .stream_data(stream_data), .stream_valid(stream_valid),
        .stream_ready(stream_ready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
        .m_axi_arsize(arsize), .m_axi_arburst(arburst),
        .m_axi_arlock(arlock), .m_axi_arcache(arcache),
        .m_axi_arprot(arprot), .m_axi_arvalid(arvalid),
        .m_axi_arready(arready), .m_axi_rid(rid), .m_axi_rdata(rdata),
        .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    task send_beat;
        input integer index;
        input integer last;
        begin
            @(negedge clk);
            rdata = index;
            rlast = last;
            rvalid = 1;
            while (!rready)
                @(negedge clk);
            @(negedge clk);
            rvalid = 0;
            rlast = 0;
        end
    endtask

    initial begin
        #25 resetn = 1;
        @(negedge clk);
        enable = 1;

        wait (arvalid);
        @(posedge clk);
        if (arlen != 4'd15)
            $fatal(1, "first burst length is not 16 beats");

        send_beat(1, 0);
        @(negedge clk);
        enable = 0;

        // The outstanding response must remain accepted after stop.
        for (beat = 2; beat <= 8; beat = beat + 1)
            send_beat(beat, 0);

        // Exercise a restart request before the old burst has drained.
        @(negedge clk);
        enable = 1;
        for (beat = 9; beat <= 16; beat = beat + 1)
            send_beat(beat, beat == 16);

        wait (arvalid);
        if (!running || error)
            $fatal(1, "DMA did not restart cleanly after drain");
        @(posedge clk);

        for (beat = 1; beat <= 16; beat = beat + 1)
            send_beat(beat, beat == 16);

        @(posedge clk);
        if (error)
            $fatal(1, "clean burst reported an AXI error");
        $display("PASS: stop drained through RLAST and restart succeeded");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout");
    end
endmodule
