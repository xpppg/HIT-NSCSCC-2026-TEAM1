module data_bram_bank (
    input wire clka,
    input wire ena,
    input wire [3:0] wea,
    input wire [5:0] addra,
    input wire [31:0] dina,
    output reg [31:0] douta
);

// 内存数组：128个32位字
reg [31:0] ram [0:63];

// 写操作：字节使能
always @(posedge clka) begin
    if (ena) begin
        if (wea[0]) ram[addra][7:0]   <= dina[7:0];
        if (wea[1]) ram[addra][15:8]  <= dina[15:8];
        if (wea[2]) ram[addra][23:16] <= dina[23:16];
        if (wea[3]) ram[addra][31:24] <= dina[31:24];
        douta <= ram[addra]; // 在写操作后，输出当前地址的数据（Write First模式）
    end else begin
        douta <= ram[addra]; // 如果使能无效，则输出当前地址的数据
    end
end

endmodule

module btb_bram (
    input wire clka,
    input wire ena,
    input wire wea,
    input wire [9:0] addra,
    input wire [31:0] dina,
    input wire clkb,
    input wire enb,
    input wire [9:0] addrb,
    output reg [31:0] doutb
);

// 内存数组：1024个32位字
reg [31:0] ram [0:1023];

// 写操作：字节使能
always @(posedge clka) begin
    if (ena) begin
        if (wea) ram[addra] <= dina;
    end
end

always @(posedge clkb) begin
    if(enb) begin
        doutb <= ram[addrb]; 
    end
end


endmodule