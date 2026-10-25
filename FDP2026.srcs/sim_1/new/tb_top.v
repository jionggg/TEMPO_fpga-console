`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.10.2026 21:33:24
// Design Name: 
// Module Name: tb_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// Simulates My_Top_Module with given Oled_Display.v listens on the JA / JB
// SPI wires like the real OLED chip would, 
// writes each screen's first frame to a .ppm image. 
// Also measures the 6.25 MHz clock and the 1 ms tick.

module tb_top;
    reg clk = 0;
    always #5 clk = ~clk;                 // 100 MHz

    reg  [15:0] sw = 0;
    wire [15:0] led;
    wire [7:0]  JA, JB;
    wire mic_cs, mic_sclk;

    My_Top_Module dut (
        .clk(clk), .btnC(1'b0), .btnU(1'b0), .btnD(1'b0), .btnR(1'b0),
        .sw(sw), .led(led), .JA(JA), .JB(JB),
        .mic_cs(mic_cs), .mic_miso(1'b0), .mic_sclk(mic_sclk)
    );

    // ---- clock checks
    realtime t_prev = 0, period = 0;
    always @(posedge dut.clk_6p25M) begin
        if (t_prev != 0) period = $realtime - t_prev;
        t_prev = $realtime;
    end
    integer ticks = 0;
    always @(posedge clk) if (dut.ms_tick) ticks = ticks + 1;

    // ---- SPI listener: one per screen. Sample sdin on rising sclk while cs is low
    //      and d_cn is high (pixel data). 16 bits = one RGB565 pixel.
    task automatic dummy; endtask

    reg [15:0] shA = 0, shB = 0;
    integer bitA = 0, bitB = 0, pixA = 0, pixB = 0;
    reg [15:0] frameA [0:6143];
    reg [15:0] frameB [0:6143];
    reg doneA = 0, doneB = 0;

    always @(posedge JA[3]) if (!JA[0] && JA[4] && !doneA) begin
        shA = {shA[14:0], JA[1]};
        bitA = bitA + 1;
        if (bitA == 16) begin
            frameA[pixA] = shA; pixA = pixA + 1; bitA = 0;
            if (pixA == 6144) doneA = 1;
        end
    end
    always @(posedge JB[3]) if (!JB[0] && JB[4] && !doneB) begin
        shB = {shB[14:0], JB[1]};
        bitB = bitB + 1;
        if (bitB == 16) begin
            frameB[pixB] = shB; pixB = pixB + 1; bitB = 0;
            if (pixB == 6144) doneB = 1;
        end
    end

    task write_ppm(input [8*32-1:0] name, input integer which);
        integer f, i; reg [15:0] c;
        begin
            f = $fopen(name, "w");
            $fwrite(f, "P3\n96 64\n255\n");
            for (i = 0; i < 6144; i = i + 1) begin
                c = which ? frameB[i] : frameA[i];
                $fwrite(f, "%0d %0d %0d\n", (c[15:11]*255)/31, (c[10:5]*255)/63, (c[4:0]*255)/31);
            end
            $fclose(f);
        end
    endtask

    // FPGA registers power up as 0; the simulator starts them as X. Oled_Display
    // runs with reset tied to 0, so give its registers the FPGA's power-up value.
    initial begin
        #1;
        dut.oled_piano.state = 0; dut.oled_piano.frame_counter = 0; dut.oled_piano.delay = 0;
        dut.oled_piano.spi_word = 0; dut.oled_piano.spi_word_bit_count = 0;
        dut.oled_drum.state  = 0; dut.oled_drum.frame_counter  = 0; dut.oled_drum.delay  = 0;
        dut.oled_drum.spi_word  = 0; dut.oled_drum.spi_word_bit_count  = 0;
    end

    initial begin
        wait (doneA && doneB);
        $display("6.25 MHz clock period: %0.1f ns (expect 160.0)", period);
        $display("ms ticks so far: %0d at t = %0.3f ms", ticks, $realtime / 1e6);
        $display("first frame received: JA %0d px, JB %0d px at t = %0.3f ms", pixA, pixB, $realtime / 1e6);
        $display("pmoden JA=%b JB=%b, vccen JA=%b JB=%b", JA[7], JB[7], JA[6], JB[6]);
        write_ppm("frame_JA_piano.ppm", 0);
        write_ppm("frame_JB_drum.ppm", 1);
        $finish;
    end
    initial begin
        #400_000_000;                     // 400 ms safety stop
        $display("TIMEOUT: JA %0d px, JB %0d px", pixA, pixB);
        $finish;
    end
endmodule
