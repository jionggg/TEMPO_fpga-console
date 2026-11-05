`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// font_rom - the shapes of the characters, 5 px wide x 7 px tall (Ji Yong)
//
// Each character is 35 bits: 7 rows of 5 bits, top row first. A 1 is a lit pixel,
// so you can see the character in the 1s below (look at the "0" or the "P").
//   glyph[34:30] = top row,  glyph[4:0] = bottom row
//   inside a row, the leftmost bit is the leftmost pixel
//
// Pure lookup table (combinational): give it a code, it answers straight away.
// Character codes are the CH_ names in TEMPO_layout.vh; digits 0..9 are codes 0..9.
//////////////////////////////////////////////////////////////////////////////////

module font_rom (
    input      [4:0]  code,     // which character
    output reg [34:0] glyph     // its 35 pixels, top row first
    );

    `include "TEMPO_layout.vh"     // CH_X, CH_P, ...

    always @(*) begin
        case (code)
            5'd0: glyph = {5'b01110,
                           5'b10001,
                           5'b10011,
                           5'b10101,
                           5'b11001,
                           5'b10001,
                           5'b01110};
            5'd1: glyph = {5'b00100,
                           5'b01100,
                           5'b00100,
                           5'b00100,
                           5'b00100,
                           5'b00100,
                           5'b01110};
            5'd2: glyph = {5'b01110,
                           5'b10001,
                           5'b00001,
                           5'b00010,
                           5'b00100,
                           5'b01000,
                           5'b11111};
            5'd3: glyph = {5'b11111,
                           5'b00010,
                           5'b00100,
                           5'b00010,
                           5'b00001,
                           5'b10001,
                           5'b01110};
            5'd4: glyph = {5'b00010,
                           5'b00110,
                           5'b01010,
                           5'b10010,
                           5'b11111,
                           5'b00010,
                           5'b00010};
            5'd5: glyph = {5'b11111,
                           5'b10000,
                           5'b11110,
                           5'b00001,
                           5'b00001,
                           5'b10001,
                           5'b01110};
            5'd6: glyph = {5'b00110,
                           5'b01000,
                           5'b10000,
                           5'b11110,
                           5'b10001,
                           5'b10001,
                           5'b01110};
            5'd7: glyph = {5'b11111,
                           5'b00001,
                           5'b00010,
                           5'b00100,
                           5'b01000,
                           5'b01000,
                           5'b01000};
            5'd8: glyph = {5'b01110,
                           5'b10001,
                           5'b10001,
                           5'b01110,
                           5'b10001,
                           5'b10001,
                           5'b01110};
            5'd9: glyph = {5'b01110,
                           5'b10001,
                           5'b10001,
                           5'b01111,
                           5'b00001,
                           5'b00010,
                           5'b01100};
            CH_X: glyph = {5'b00000,
                           5'b00000,
                           5'b10001,
                           5'b01010,
                           5'b00100,
                           5'b01010,
                           5'b10001};
            CH_P: glyph = {5'b11110,
                           5'b10001,
                           5'b10001,
                           5'b11110,
                           5'b10000,
                           5'b10000,
                           5'b10000};
            CH_E: glyph = {5'b11111,
                           5'b10000,
                           5'b10000,
                           5'b11110,
                           5'b10000,
                           5'b10000,
                           5'b11111};
            CH_R: glyph = {5'b11110,
                           5'b10001,
                           5'b10001,
                           5'b11110,
                           5'b10100,
                           5'b10010,
                           5'b10001};
            CH_F: glyph = {5'b11111,
                           5'b10000,
                           5'b10000,
                           5'b11110,
                           5'b10000,
                           5'b10000,
                           5'b10000};
            CH_C: glyph = {5'b01110,
                           5'b10001,
                           5'b10000,
                           5'b10000,
                           5'b10000,
                           5'b10001,
                           5'b01110};
            CH_T: glyph = {5'b11111,
                           5'b00100,
                           5'b00100,
                           5'b00100,
                           5'b00100,
                           5'b00100,
                           5'b00100};
            CH_G: glyph = {5'b01110,
                           5'b10001,
                           5'b10000,
                           5'b10111,
                           5'b10001,
                           5'b10001,
                           5'b01111};
            CH_O: glyph = {5'b01110,
                           5'b10001,
                           5'b10001,
                           5'b10001,
                           5'b10001,
                           5'b10001,
                           5'b01110};
            CH_D: glyph = {5'b11100,
                           5'b10010,
                           5'b10001,
                           5'b10001,
                           5'b10001,
                           5'b10010,
                           5'b11100};
            CH_M: glyph = {5'b10001,
                           5'b11011,
                           5'b10101,
                           5'b10101,
                           5'b10001,
                           5'b10001,
                           5'b10001};
            CH_I: glyph = {5'b01110,
                           5'b00100,
                           5'b00100,
                           5'b00100,
                           5'b00100,
                           5'b00100,
                           5'b01110};
            CH_S: glyph = {5'b01111,
                           5'b10000,
                           5'b10000,
                           5'b01110,
                           5'b00001,
                           5'b00001,
                           5'b11110};
            default: glyph = 35'd0;          // CH_SP (blank) and unused codes
        endcase
    end

endmodule


//////////////////////////////////////////////////////////////////////////////////
// char_cell - one character on the screen: is pixel (x, y) part of its ink?
//
// Same idea as tile_slot: one small checker per character, and the caller ORs
// the answers together. (x0, y0) is the character's top-left pixel.
//////////////////////////////////////////////////////////////////////////////////

module char_cell (
    input  [6:0] x,             // pixel column being asked about
    input  [5:0] y,             // pixel row being asked about
    input  [6:0] x0,            // this character's leftmost column
    input  [5:0] y0,            // this character's top row
    input  [4:0] code,          // which character to draw here
    output       on             // 1 = this pixel is lit
    );

    // Is the pixel inside this character's 5 x 7 box?
    wire in_box = (x >= x0) && (x < x0 + 5) && (y >= y0) && (y < y0 + 7);

    // Where inside the box? col 0..4 from the left, row 0..6 from the top.
    wire [2:0] col = x - x0;
    wire [2:0] row = y - y0;

    wire [34:0] glyph;
    font_rom font (.code(code), .glyph(glyph));

    // Row r, column c is bit 34 - (5r + c): the top-left pixel is bit 34.
    assign on = in_box && glyph[34 - (row * 5 + col)];

endmodule
