/*
 * Copyright (c) 2025 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Wrapper for all TinyQV peripherals
//
// Address space:
// 0x800_0000 - 03f: Reserved by project wrapper (time, debug, etc)
// 0x800_0040 - 07f: GPIO configuration
// 0x800_0080 - 0bf: UART TX
// 0x800_00c0 - 0ff: UART RX
// 0x800_0100 - 3ff: 12 user peripherals (64 bytes each, word and halfword access supported, each has an interrupt)
// 0x800_0400 - 4ff: 16 simple peripherals (16 bytes each, byte access only)
module tinyQV_peripherals (
    input         clk,
    input         rst_n,

    input  [7:0]  ui_in,        // The input PMOD, always available
    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected

    input [10:0]  addr_in,
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready,

    input         data_read_complete,  // Set by TinyQV when a read is complete

    output [15:2] user_interrupts  // User peripherals get interrupts 2-15
);

    // Registered data out to TinyQV
    reg  [31:0] data_out_r;
    reg         data_out_hold;
    reg         data_ready_r;

    reg         last_txn_req;
    wire        txn_req = (data_read_n != 2'b11 || data_write_n != 2'b11);

    // Muxed data out direct from selected peripheral
    reg [31:0] data_from_peri;
    reg        data_ready_from_peri;

    wire [31:0] data_from_user_peri   [0:15];
    wire [7:0]  data_from_simple_peri [0:15];
    wire        data_ready_from_user_peri   [0:15];

    wire [7:0]  uo_out_from_user_peri   [0:15];
    wire [7:0]  uo_out_from_simple_peri [0:15];
    reg [7:0] uo_out_comb;
    assign uo_out = uo_out_comb;

    // Register the data output from the peripheral.  This improves timing and
    // also simplifies the peripheral interface (no need for the peripheral to care 
    // about holding data_out until data_read_complete - it looks like it is read 
    // synchronously).
    always @(posedge clk) begin
        if (!rst_n) begin
            data_out_hold <= 0;
            last_txn_req <= 0;
        end else begin
            if (data_read_complete) data_out_hold <= 0;

            if (!data_out_hold && data_ready_from_peri && data_read_n != 2'b11) begin
                data_out_hold <= 1;
                data_out_r <= data_from_peri;
            end

            last_txn_req <= txn_req;

            // Data ready must be registered because data_out is.
            data_ready_r <= (last_txn_req && txn_req && data_ready_from_peri);
        end
    end

    assign data_out = data_out_r;
    assign data_ready = data_ready_r;

    // --------------------------------------------------------------------- //
    // Decode the address to select the active peripheral

    localparam PERI_GPIO = 1;
    localparam PERI_UART_TX = 2;
    localparam PERI_UART_RX = 3;

    reg [15:0] peri_user;
    reg [15:0] peri_simple;

    always @(*) begin
        peri_user = 0;
        peri_simple = 0;

        if (addr_in[10]) begin
            peri_simple[addr_in[7:4]] = 1;
            data_from_peri = {24'h0, data_from_simple_peri[addr_in[7:4]]};
            data_ready_from_peri = 1;
        end else begin
            peri_user[addr_in[9:6]] = 1;
            data_from_peri = data_from_user_peri[addr_in[9:6]];
            data_ready_from_peri = data_ready_from_user_peri[addr_in[9:6]];
        end
    end

    assign data_from_user_peri[0] = 32'h0;
    assign data_ready_from_user_peri[0] = 0;
    assign uo_out_from_user_peri[0] = 8'h0;

    // --------------------------------------------------------------------- //
    // GPIO

    reg [4:0] gpio_out_func_sel [0:7];
    reg [7:0] gpio_out;

    always @(posedge clk) begin
        if (!rst_n) begin
            gpio_out <= 0;
        end else if (peri_user[PERI_GPIO]) begin
            if (addr_in[5:0] == 6'h0) begin
                if (data_write_n != 2'b11) gpio_out <= data_in[7:0];
            end
        end
    end

    assign data_from_user_peri[PERI_GPIO] = (addr_in[5:0] == 6'h0) ? {24'h0, gpio_out} :
                                            (addr_in[5:0] == 6'h4) ? {24'h0, ui_in}    :
                                            ({addr_in[5], addr_in[1:0]} == 3'b100) ? {27'h0, gpio_out_func_sel[addr_in[4:2]]} :
                                            32'h0;
    assign data_ready_from_user_peri[PERI_GPIO] = 1;
    assign uo_out_from_user_peri[PERI_GPIO] = gpio_out;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin
            always @(posedge clk) begin
                if (!rst_n) begin
                    gpio_out_func_sel[i] <= (i == 0) ? PERI_UART_TX : 
                                            (i == 1) ? PERI_UART_RX : PERI_GPIO;
                end else if (peri_user[PERI_GPIO]) begin
                    if ({addr_in[5], addr_in[1:0]} == 3'b100 && addr_in[4:2] == i) begin
                        if (data_write_n != 2'b11) gpio_out_func_sel[i] <= data_in[4:0];
                    end
                end
            end

            always @(*) begin
                uo_out_comb[i] = 0;

                if (gpio_out_func_sel[i][4]) begin
                    uo_out_comb[i] = uo_out_from_simple_peri[gpio_out_func_sel[i][3:0]][i];
                end else begin
                    uo_out_comb[i] = uo_out_from_user_peri[gpio_out_func_sel[i][3:0]][i];
                end
            end            
        end
    endgenerate

    // --------------------------------------------------------------------- //
    // UART

    tqvp_uart_tx i_uart_tx (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[PERI_UART_TX]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n | {2{~peri_user[PERI_UART_TX]}}),
        .data_read_n(data_read_n   | {2{~peri_user[PERI_UART_TX]}}),

        .data_out(data_from_user_peri[PERI_UART_TX]),
        .data_ready(data_ready_from_user_peri[PERI_UART_TX]),

        .user_interrupt(user_interrupts[PERI_UART_TX])
    );

    tqvp_uart_rx i_uart_rx (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[PERI_UART_RX]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n | {2{~peri_user[PERI_UART_RX]}}),
        .data_read_n(data_read_n   | {2{~peri_user[PERI_UART_RX]}}),

        .data_out(data_from_user_peri[PERI_UART_RX]),
        .data_ready(data_ready_from_user_peri[PERI_UART_RX]),

        .user_interrupt(user_interrupts[PERI_UART_RX])
    );

    // --------------------------------------------------------------------- //
    // Full interface peripherals

    tqvp_example i_user_peri04 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_user_peri[4]),

        .address(addr_in[5:0]),
        .data_in(data_in),

        .data_write_n(data_write_n | {2{~peri_user[4]}}),
        .data_read_n(data_read_n   | {2{~peri_user[4]}}),

        .data_out(data_from_user_peri[4]),
        .data_ready(data_ready_from_user_peri[4]),

        .user_interrupt(user_interrupts[4])
    );

    // Unallocated peripherals, move up to explicit entry above to add a design.
    generate
        for (i = 5; i < 16; i = i + 1) begin
            tqvp_example i_user_peri (
                .clk(clk),
                .rst_n(rst_n),

                .ui_in(ui_in),
                .uo_out(uo_out_from_user_peri[i]),

                .address(addr_in[5:0]),
                .data_in(data_in),

                .data_write_n(data_write_n | {2{~peri_user[i]}}),
                .data_read_n(data_read_n   | {2{~peri_user[i]}}),

                .data_out(data_from_user_peri[i]),
                .data_ready(data_ready_from_user_peri[i]),

                .user_interrupt(user_interrupts[i])
            );
        end
    endgenerate

    // --------------------------------------------------------------------- //
    // Simple interface peripherals

    tqvp_edge_counter i_edge_counter (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[0]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[0]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[0])
    );

    tqvp_simple_example i_user_simple01 (
        .clk(clk),
        .rst_n(rst_n),

        .ui_in(ui_in),
        .uo_out(uo_out_from_simple_peri[1]),

        .address(addr_in[3:0]),

        .data_write((data_write_n != 2'b11) & peri_simple[1]),
        .data_in(data_in[7:0]),

        .data_out(data_from_simple_peri[1])
    );

    // Unallocated peripherals, move up to explicit entry above to add a design.
    generate
        for (i = 2; i < 16; i = i + 1) begin
            tqvp_simple_example i_user_simple (
                .clk(clk),
                .rst_n(rst_n),

                .ui_in(ui_in),
                .uo_out(uo_out_from_simple_peri[i]),

                .address(addr_in[3:0]),

                .data_write((data_write_n != 2'b11) & peri_simple[i]),
                .data_in(data_in[7:0]),

                .data_out(data_from_simple_peri[i])
            );
        end
    endgenerate

endmodule
