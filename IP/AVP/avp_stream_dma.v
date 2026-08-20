`timescale 1ns / 1ps

// Continuous 64-bit AXI3 MM2S reader.  One burst is outstanding, bursts are
// limited to 16 beats, and no request crosses a 4 KiB boundary.
module avp_stream_dma #(
    parameter [3:0] AXI_ID = 4'h5
)(
    input  wire        clk,
    input  wire        resetn,
    input  wire        enable,
    input  wire [31:0] base_addr,
    input  wire [31:0] byte_length,
    output reg         running,
    output reg         error,
    output reg  [31:0] fetched_pos,

    output wire [63:0] stream_data,
    output wire        stream_valid,
    input  wire        stream_ready,

    output wire [3:0]  m_axi_arid,
    output wire [31:0] m_axi_araddr,
    output wire [3:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire [1:0]  m_axi_arlock,
    output wire [3:0]  m_axi_arcache,
    output wire [2:0]  m_axi_arprot,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [3:0]  m_axi_rid,
    input  wire [63:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready
);
    reg [31:0] next_addr;
    reg [31:0] words_left;
    reg arvalid_reg;
    reg [31:0] araddr_reg;
    reg [4:0] planned_beats;
    reg [4:0] response_left;
    reg burst_active;

    function automatic [4:0] choose_beats;
        input [31:0] remaining;
        input [8:0] word_in_page;
        reg [9:0] page_remaining;
        begin
            page_remaining = 10'd512 - {1'b0, word_in_page};
            if (remaining < 16)
                choose_beats = remaining[4:0];
            else if (page_remaining < 16)
                choose_beats = page_remaining[4:0];
            else
                choose_beats = 5'd16;
        end
    endfunction

    wire read_take = m_axi_rvalid && m_axi_rready;
    wire expected_last = response_left == 5'd1;
    assign stream_data = m_axi_rdata;
    assign stream_valid = m_axi_rvalid && running && burst_active;
    // Once an AXI read address has been accepted, every response beat must be
    // consumed even when software stops the stream.  In drain mode the data
    // is discarded, but RREADY remains asserted until RLAST so the
    // interconnect can retire the outstanding transaction.
    assign m_axi_rready = burst_active && (running ? stream_ready : 1'b1);
    assign m_axi_arid = AXI_ID;
    assign m_axi_araddr = araddr_reg;
    assign m_axi_arlen = planned_beats[3:0] - 1'b1;
    assign m_axi_arsize = 3'b011;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock = 2'b00;
    assign m_axi_arcache = 4'b0000;
    assign m_axi_arprot = 3'b000;
    assign m_axi_arvalid = arvalid_reg;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            running <= 1'b0; error <= 1'b0;
            fetched_pos <= 0; next_addr <= 0; words_left <= 0;
            arvalid_reg <= 1'b0; araddr_reg <= 0; planned_beats <= 0;
            response_left <= 0; burst_active <= 1'b0;
        end else begin
            if (!enable) begin
                running <= 1'b0; error <= 1'b0; fetched_pos <= 0;
                words_left <= 0;
                // ARVALID is intentionally retained until ARREADY.  AXI does
                // not permit a master to withdraw a request after asserting
                // VALID.  Any accepted request is drained below.
            end else if (!running && !error && !arvalid_reg &&
                         !burst_active) begin
                error <= 1'b0; fetched_pos <= 0;
                if (base_addr[2:0] != 0 || byte_length == 0 ||
                    byte_length[2:0] != 0) begin
                    running <= 1'b0;
                    error <= 1'b1;
                end else begin
                    running <= 1'b1;
                    next_addr <= base_addr;
                    words_left <= byte_length >> 3;
                end
            end

            if (running && enable) begin
                if (!arvalid_reg && !burst_active && words_left != 0) begin
                    araddr_reg <= next_addr;
                    planned_beats <= choose_beats(words_left, next_addr[11:3]);
                    arvalid_reg <= 1'b1;
                end
            end

            // Complete an address handshake even if enable was removed after
            // ARVALID was asserted.  Requests accepted while stopped enter
            // drain mode and do not advance the circular-buffer pointers.
            if (arvalid_reg && m_axi_arready) begin
                arvalid_reg <= 1'b0;
                burst_active <= 1'b1;
                response_left <= planned_beats;
                if (running && enable) begin
                    next_addr <= next_addr +
                                 {24'b0, planned_beats, 3'b000};
                    words_left <= words_left - {27'b0, planned_beats};
                end
            end

            if (read_take) begin
                if (running && enable) begin
                    if (m_axi_rresp != 2'b00 || m_axi_rid != AXI_ID ||
                        (m_axi_rlast != expected_last)) begin
                        error <= 1'b1;
                        running <= 1'b0;
                        arvalid_reg <= 1'b0;
                        // Even an erroneous burst must be drained through
                        // RLAST; otherwise it poisons the following transfer.
                        if (m_axi_rlast) begin
                            burst_active <= 1'b0;
                            response_left <= 0;
                        end else if (response_left != 0) begin
                            response_left <= response_left - 1'b1;
                        end
                    end else begin
                        fetched_pos <= (fetched_pos + 8 >= byte_length) ?
                            0 : fetched_pos + 8;
                        if (expected_last) begin
                            burst_active <= 1'b0;
                            response_left <= 0;
                            if (words_left == 0) begin
                                next_addr <= base_addr;
                                words_left <= byte_length >> 3;
                            end
                        end else begin
                            response_left <= response_left - 1'b1;
                        end
                    end
                end else begin
                    // Stop/error drain path.  Ignore payload and response
                    // attributes, but consume the complete accepted burst.
                    if (m_axi_rlast) begin
                        burst_active <= 1'b0;
                        response_left <= 0;
                    end else if (response_left != 0) begin
                        response_left <= response_left - 1'b1;
                    end
                end
            end
        end
    end
endmodule
