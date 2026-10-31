`include "params.vh"
// UI-only static controls added after the stable 53-slot modulation bank.
// Captured drags retain their ID across page changes. No UART pulse queues here:
// static_cc_sync reconciles the complete authoritative bank with FIFO acceptance.
module audio_controls_state #(parameter CONTACT_TIMEOUT=2500000)(
 input wire clk,rst_n,cancel,touch_valid,touch_down,
 input wire [13:0] touch_x,touch_y,
 input wire external_valid,
 input wire [7:0] external_id,
 input wire [6:0] external_value,
 input wire [132:0] legacy_values,
 output wire [237:0] extra_values,
 output reg [2:0] fx_page,
 output reg [1:0] warp_menu,
 output reg focus_valid,
 output reg [7:0] focus_id,
 output wire legacy_owner_valid,
 output wire [7:0] legacy_owner_id,
 output reg legacy_valid,
 output reg [7:0] legacy_id,
 output reg [6:0] legacy_value
);
 `include "audio_extra_controls.vh"
 reg [6:0] params[0:33];
 reg finger,drag;
 reg [7:0] captured;
 reg [13:0] anchor_x,anchor_y;
 reg [6:0] anchor_value;
 reg [21:0] watchdog;
 assign legacy_owner_valid=drag && finger && captured>=8'h60 && captured<=8'h72;
 assign legacy_owner_id=captured;
 genvar n;
 generate for(n=0;n<34;n=n+1)begin:bank assign extra_values[n*7+:7]=params[n];end endgenerate
 function [6:0] read_value;
  input [7:0] id;integer j;
  begin read_value=0;
   // Constant slices, avoiding the Gowin dynamic packed-read miscompile.
   for(j=0;j<34;j=j+1)read_value=read_value | ({7{id==8'hA0+j}} & params[j]);
   for(j=0;j<19;j=j+1)read_value=read_value | ({7{id==8'h60+j}} & legacy_values[j*7+:7]);
  end
 endfunction
 task set_value;
  input [7:0] id;input [6:0] value;
  begin
   if(id>=8'hA0 && id<=8'hC1)params[id-8'hA0]<=value>audio_extra_max(id-8'hA0) ? audio_extra_max(id-8'hA0) : value;
   else if(id>=8'h60 && id<=8'h72)begin legacy_valid<=1;legacy_id<=id;legacy_value<=value;end
  end
 endtask
 reg [7:0] hit_id;
 integer k;
 always @(*)begin
  hit_id=0;
  for(k=0;k<6;k=k+1)
   if(touch_x>=audio_cell_x(k) && touch_x<audio_cell_x(k)+166 &&
      touch_y>=audio_cell_y(k) && touch_y<audio_cell_y(k)+38)hit_id=audio_fx_cell_id(fx_page,k);
 end
 wire signed [16:0] delta=($signed({3'd0,touch_x})-$signed({3'd0,anchor_x})+
                          $signed({3'd0,anchor_y})-$signed({3'd0,touch_y})) >>> 1;
 wire signed [17:0] raw_value=$signed({11'd0,anchor_value})+delta;
 wire [6:0] next_value=raw_value<0 ? 0 : raw_value>127 ? 127 : raw_value[6:0];
 integer i,mode_col,mode_row,mode_number,osc_offset;
 reg [7:0] switch_id;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   for(i=0;i<34;i=i+1)params[i]<=audio_extra_default(i);
   fx_page<=0;warp_menu<=0;finger<=0;drag<=0;captured<=0;
   anchor_x<=0;anchor_y<=0;anchor_value<=0;watchdog<=0;
   legacy_valid<=0;legacy_id<=0;legacy_value<=0;
   focus_valid<=0;focus_id<=0;
  end else begin
   legacy_valid<=0;focus_valid<=0;
   if(external_valid && external_id>=8'hA0 && external_id<=8'hC1 && !(drag && captured==external_id))
    set_value(external_id,external_value);
   if(watchdog<CONTACT_TIMEOUT)watchdog<=watchdog+1'b1;
   else begin finger<=0;drag<=0;end
   if(cancel)begin finger<=0;drag<=0;warp_menu<=0;end
   else if(touch_valid)begin
    watchdog<=0;
    if(!touch_down)begin finger<=0;drag<=0;end
    else begin
     finger<=1;
     if(!finger)begin
      drag<=0;
      // A normal popup menu selects a mode independently of Amount.
      if(warp_menu!=0 && touch_y>=108 && touch_y<212 &&
         touch_x>=(warp_menu==1 ? 40 : 456) && touch_x<(warp_menu==1 ? 412 : 828))begin
       osc_offset=warp_menu==1 ? 40 : 456;
       mode_col=touch_x<osc_offset+124 ? 0 : touch_x<osc_offset+248 ? 1 : 2;
       mode_row=touch_y<134 ? 0 : touch_y<160 ? 1 : touch_y<186 ? 2 : 3;
       mode_number=mode_row*3+mode_col;
       set_value(warp_menu==1 ? `PARAM_ID_OSCA_WARP_MODE : `PARAM_ID_OSCB_WARP_MODE,mode_number);
       warp_menu<=0;
      end else if(touch_y>=212 && touch_y<236 && ((touch_x>=40 && touch_x<224)||(touch_x>=456 && touch_x<640)))
       warp_menu<=warp_menu==(touch_x<424 ? 1 : 2) ? 0 : touch_x<424 ? 1 : 2;
      else if(touch_y>=212 && touch_y<236 && ((touch_x>=240 && touch_x<408)||(touch_x>=656 && touch_x<824)))begin
       warp_menu<=0;
       if(touch_x<424)set_value(`PARAM_ID_OSCA_WT_INDEX,touch_x<324 ? (params[2]==0 ? `UI_WAVETABLE_COUNT-1 : params[2]-1'b1) : (params[2]==`UI_WAVETABLE_COUNT-1 ? 0 : params[2]+1'b1));
       else set_value(`PARAM_ID_OSCB_WT_INDEX,touch_x<740 ? (params[3]==0 ? `UI_WAVETABLE_COUNT-1 : params[3]-1'b1) : (params[3]==`UI_WAVETABLE_COUNT-1 ? 0 : params[3]+1'b1));
      end else if(touch_y>=372 && touch_y<404 && touch_x>=424 && touch_x<772)begin
       fx_page<=touch_x<482 ? 0 : touch_x<540 ? 1 : touch_x<598 ? 2 : touch_x<656 ? 3 : touch_x<714 ? 4 : 5;warp_menu<=0;
      end else if(touch_y>=410 && touch_y<440 && touch_x>=432 && touch_x<776)begin
       if(fx_page==5)begin
        switch_id=touch_x<608 ? `PARAM_ID_VIB_ENABLE : `PARAM_ID_PORTA_ENABLE;
        set_value(switch_id,read_value(switch_id)==0 ? 7'd127 : 7'd0);
       end else if(fx_page==3)begin
        set_value(`PARAM_ID_EFFECT_MODE,params[4] ^ (touch_x<608 ? 7'd1 : 7'd2));
       end else if(fx_page==0 && touch_x>=608)
        set_value(`PARAM_ID_DIST_TYPE,params[6]==2 ? 0 : params[6]+1'b1);
       else if(touch_x<608)begin
        switch_id=fx_page==0 ? `PARAM_ID_DIST_ENABLE : fx_page==1 ? `PARAM_ID_PHASER_ENABLE : fx_page==2 ? `PARAM_ID_CHORUS_ENABLE : `PARAM_ID_COMP_ENABLE;
        set_value(switch_id,read_value(switch_id)==0 ? 7'd127 : 7'd0);
       end
      end else if(hit_id!=0)begin
       captured<=hit_id;anchor_x<=touch_x;anchor_y<=touch_y;anchor_value<=read_value(hit_id);drag<=1;
       if(hit_id>=8'h60 && hit_id<=8'h72)begin focus_valid<=1;focus_id<=hit_id;end
      end else warp_menu<=0;
     end else if(drag)set_value(captured,next_value);
    end
   end
  end
 end
endmodule
