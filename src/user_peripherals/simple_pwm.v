/*
 * Copyright (c) 2025 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Simple PWM peripheral for TinyQV
module tqvp_simple_pwm (
    input         clk,
    input         rst_n,

    input  [7:0]  ui_in,        // The input PMOD, always available
    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected

    input [3:0]   address,      // Address within this peripheral's address space

    input         data_write,   // Data write request from the TinyQV core.
    input [7:0]   data_in,      // Data in to the peripheral, valid when data_write is high.
    
    output [7:0]  data_out      // Data out from the peripheral, set this in accordance with the supplied address
);

    // Level is a read/write register at address 0
    reg [7:0] level;
    always @(posedge clk) begin
        if (!rst_n) begin
            level <= 0;
        end else begin
            if (address == 4'h0) begin
                if (data_write) level <= data_in;
            end
        end
    end

    reg [7:0] count;
    reg pwm;

    always @(posedge clk) begin
        if (!rst_n) begin
            count <= 0;
        end else begin
            // Wrap at 254 so that a level of 0-255 goes from always off to always on.
            count <= count + 1;
            if (count == 8'hfe) count <= 8'h00;
        end
    end

    always @(posedge clk) begin
        pwm <= count < level;
    end

    assign uo_out = {8{pwm}};

    // Address 0 reads the level register.  
    // Address 1 reads the current PWM count
    // All other addresses read 0.
    assign data_out = (address == 4'h0) ? level :
                      (address == 4'h1) ? count :
                      8'h0;
endmodule
