`timescale 1ns / 1ps
`default_nettype none

module zx81 (
    input wire         clk_25mhz,
    input wire         usb_fpga_bd_dp,
    input wire         usb_fpga_bd_dn,
    input wire         ear,

    output wire [3:0]  audio_l,
    output wire [3:0]  audio_r,

    output wire        usb_fpga_pu_dp,
    output wire        usb_fpga_pu_dn,
    output wire [7:0]  led,
    input  wire [6:0]  btn,

    output wire        hsync,
    output wire        vsync,
    output wire[3:0]   red,
    output wire[3:0]   green,
    output wire[3:0]   blue,
    output wire[3:0]   gpdi_dp,

    output wire oled_csn,
    output wire oled_clk,
    output wire oled_mosi,
    output wire oled_dc,
    output wire oled_resn,

    output wire[13:0]  gp,
    output wire[13:0]  gn
  );

  //assign led = ps2_key[7:0];

  assign gn[12] = hsync;
  assign gn[13] = vsync;

  // Set usb to PS/2 mode
  assign usb_fpga_pu_dp = 1;
  assign usb_fpga_pu_dn = 1;

  wire video; // 1-bit video signal (black/white)

  // Trivial conversion for audio
  wire mic,spk;
  assign audio_l = {4{spk}};
  assign audio_r = {4{mic}};
  

  // Power-on RESET (8 clocks)
  reg [7:0] poweron_reset = 8'h00;
  always @(posedge clk_sys) begin
    poweron_reset <= {poweron_reset[6:0],1'b1};
  end

  wire clkdvi;
  wire clk_sys; 

  pll pll_i (
    .clkin(clk_25mhz),
    .clkout0(clkdvi), // 125 Mhz, DDR bit rate
    .clkout1(clk_sys),  //  13 Mhz system clock
  );

  wire [10:0] ps2_key;

  // Video timing
  wire vde;
  wire csync, cvideo;
  // The ZX80/ZX81 core
  fpga_zx81 the_core (
    .clk_sys(clk_sys),
    .reset_n(poweron_reset[7] & btn[0]),
    .ear(ear),
    .ps2_key(ps2_key),
    .csync_o(csync),
    .cvideo_o(cvideo),
    .video(video),
    .hsync(hsync),
    .vsync(vsync),
    .vde(vde),
    .mic(mic),
    .spk(spk),
    .led(led),
    .led1({gp[0], gp[1], gp[2], gp[3], gn[0], gn[1], gn[2], gn[3]}),
    .led2({gp[7], gp[8], gp[9], gp[10], gn[7], gn[8], gn[9], gn[10]})
  );

  assign red = video ? 4'b1111 : 4'b0000;
  assign green = video ? 4'b1111 : 4'b0000;
  assign blue = video ? 4'b1111 : 4'b0000;

  // Get PS/2 keyboard events
  ps2 ps2_kbd (
     .clk(clk_sys),
     .ps2_clk(usb_fpga_bd_dp),
     .ps2_data(usb_fpga_bd_dn),
     .ps2_key(ps2_key)
  );

  reg R_hsync, R_vsync;
  reg [10:0] R_csync_cnt;
  always @(posedge clkdvi)
  begin
    if(csync | vde)
    begin
      R_csync_cnt <= 0;
      R_hsync <= 0;
      R_vsync <= 0;
    end
    else
    begin
      R_hsync <= 1;
      if(R_csync_cnt[10])
        R_vsync <= 1;
      else
        R_csync_cnt <= R_csync_cnt+1;
    end
  end
  
  // Convert VGA to DVI
  HDMI_out vga2dvid
  (
    .pixclk(clk_25mhz),
    .pixclk_x5(clkdvi),
    .red({8{video[0]}}),
    .green({8{video[0]}}),
    .blue({8{video[0]}}),
    .hSync(R_hsync),
    .vSync(R_vsync),
    .vde(vde),
    .gpdi_dp(gpdi_dp)
  );

  reg [1:0] R_clk_pixel;
  always @(posedge clkdvi)
    R_clk_pixel <= {clk_sys,R_clk_pixel[1]}; 
  wire clk_pixel_ena = R_clk_pixel == 2'b10 ? 1 : 0;


  wire [15:0] color = cvideo ? 16'hFFFF : 16'h0000;
  lcd_video
  #(
    .c_clk_mhz(125),
    .c_vga_sync(1),
    .c_x_size(240),
    .c_y_size(240),
    .c_color_bits(16)
  )
  lcd_video_instance
  (
    .clk(clkdvi), // 125 MHz
    .reset(~btn[0]),
    .clk_pixel_ena(clk_pixel_ena),
    .blank(~vde),
    .hsync(R_hsync),
    .vsync(R_vsync),
    .color(color),
    .spi_resn(oled_resn),
    .spi_clk(oled_clk),
    .spi_dc(oled_dc),
    .spi_mosi(oled_mosi)
  );
  assign oled_csn = 1;

endmodule
