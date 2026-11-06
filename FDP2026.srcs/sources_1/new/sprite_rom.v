`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// sprite_rom - the little pictures shown under the white line on a hit (Ji Yong)
//
// Each sprite is 16 px wide x 8 px tall: one 16-bit row per line, top row first,
// leftmost pixel = bit 15. A 1 is a lit pixel, so you can see the picture in the 1s.
//   SPR_NOTE   piano (any key): an eighth note
//   SPR_HIHAT  drum lane 0 (crash / hi-hat): two cymbals on a stand
//   SPR_SNARE  drum lane 1: a snare drum with two sticks
//   SPR_KICK   drum lane 2 (bass): the kick drum's front head
// Pure lookup table (combinational), like font_rom.
//////////////////////////////////////////////////////////////////////////////////

module sprite_rom (
    input      [1:0]  sprite,       // which picture (SPR_ codes below)
    input      [2:0]  row,          // 0 = top row
    output reg [15:0] bits          // that row, bit 15 = leftmost pixel
    );

    localparam [1:0] SPR_NOTE = 2'd0, SPR_HIHAT = 2'd1, SPR_SNARE = 2'd2, SPR_KICK = 2'd3;

    always @(*) begin
        case ({sprite, row})
            // ---- eighth note ----
            {SPR_NOTE, 3'd0}:  bits = 16'b0000000011100000;
            {SPR_NOTE, 3'd1}:  bits = 16'b0000000010011000;
            {SPR_NOTE, 3'd2}:  bits = 16'b0000000010000100;
            {SPR_NOTE, 3'd3}:  bits = 16'b0000000010000000;
            {SPR_NOTE, 3'd4}:  bits = 16'b0000000010000000;
            {SPR_NOTE, 3'd5}:  bits = 16'b0000011110000000;
            {SPR_NOTE, 3'd6}:  bits = 16'b0000111110000000;
            {SPR_NOTE, 3'd7}:  bits = 16'b0000011100000000;
            // ---- hi-hat: top cymbal, rod, bottom cymbal, stand ----
            {SPR_HIHAT, 3'd0}: bits = 16'b0000000110000000;
            {SPR_HIHAT, 3'd1}: bits = 16'b0000111111110000;
            {SPR_HIHAT, 3'd2}: bits = 16'b0111111111111110;
            {SPR_HIHAT, 3'd3}: bits = 16'b0000000110000000;
            {SPR_HIHAT, 3'd4}: bits = 16'b0111111111111110;
            {SPR_HIHAT, 3'd5}: bits = 16'b0000111111110000;
            {SPR_HIHAT, 3'd6}: bits = 16'b0000000110000000;
            {SPR_HIHAT, 3'd7}: bits = 16'b0000111111110000;
            // ---- snare: two sticks hitting the rim, body with lugs ----
            {SPR_SNARE, 3'd0}: bits = 16'b0100000000000010;
            {SPR_SNARE, 3'd1}: bits = 16'b0010000000000100;
            {SPR_SNARE, 3'd2}: bits = 16'b0111111111111110;
            {SPR_SNARE, 3'd3}: bits = 16'b0100000000000010;
            {SPR_SNARE, 3'd4}: bits = 16'b0100100100100010;
            {SPR_SNARE, 3'd5}: bits = 16'b0100000000000010;
            {SPR_SNARE, 3'd6}: bits = 16'b0111111111111110;
            {SPR_SNARE, 3'd7}: bits = 16'b0000000000000000;
            // ---- kick: round front head with a logo in the middle ----
            {SPR_KICK, 3'd0}:  bits = 16'b0000011111100000;
            {SPR_KICK, 3'd1}:  bits = 16'b0001100000011000;
            {SPR_KICK, 3'd2}:  bits = 16'b0010000000000100;
            {SPR_KICK, 3'd3}:  bits = 16'b0010001111000100;
            {SPR_KICK, 3'd4}:  bits = 16'b0010001111000100;
            {SPR_KICK, 3'd5}:  bits = 16'b0010000000000100;
            {SPR_KICK, 3'd6}:  bits = 16'b0001100000011000;
            {SPR_KICK, 3'd7}:  bits = 16'b0000011111100000;
            default:           bits = 16'd0;
        endcase
    end

endmodule
