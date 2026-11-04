// One authoritative settings bank; both settings-page and plot shortcuts write
// here. Configuration is session-local (reset reloads defaults).
module ui_user_settings #(parameter CONTACT_CYCLES=2500000)(
 input wire clk,rst_n,touch_valid,touch_down,
 input wire [13:0] touch_x,touch_y,
 input wire [2:0] view,
 input wire [7:0] section,
 output reg [63:0] knob_steps,
 output reg [1:0] knob_page,apply_step,
 output reg [23:0] plot_scales
);
 reg finger;
 reg [21:0] quiet;
 integer row,col,tile,field,i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   knob_steps<={32{2'd2}};knob_page<=0;apply_step<=2;
   plot_scales<=0;finger<=0;quiet<=0;
  end else begin
   if(quiet<CONTACT_CYCLES)quiet<=quiet+1'b1;
   else finger<=0;
   if(touch_valid)begin
    quiet<=0;
    if(!touch_down)finger<=0;
    else begin
     finger<=1;
     if(!finger)begin
      if(view==3 && section==1)begin
       if(touch_y>=576 && touch_y<612)begin
        if(touch_x>=48 && touch_x<208)knob_page<=knob_page-1'b1;
        if(touch_x>=496 && touch_x<656)knob_page<=knob_page+1'b1;
       end
       if(touch_y>=144 && touch_y<176 && touch_x>=432 && touch_x<656)
        for(i=0;i<32;i=i+1)knob_steps[i*2+:2]<=apply_step;
       for(row=0;row<8;row=row+1)for(col=0;col<4;col=col+1)
        if(touch_y>=208+row*44 && touch_y<244+row*44 &&
           touch_x>=352+col*80 && touch_x<416+col*80)begin
         knob_steps[(knob_page*8+row)*2+:2]<=col;apply_step<=col;
        end
      end
      // Rows in DISPLAY, and the same four pads in each tile footer:
      // amplitude -, amplitude +, horizontal -, horizontal +.
      for(tile=0;tile<6;tile=tile+1)for(col=0;col<4;col=col+1)begin
       if(!((tile==0 || tile==5) && col>=2))begin
       if((view==3 && section==2 && touch_y>=200+tile*56 && touch_y<240+tile*56 &&
           touch_x>=528+col*160 && touch_x<656+col*160) ||
          (view==1 && touch_y>=96+(tile/3)*296+258 && touch_y<96+(tile/3)*296+278 &&
           touch_x>=24+(tile%3)*418+20+col*92 && touch_x<24+(tile%3)*418+104+col*92))begin
        field=tile*4+(col>=2 ? 2 : 0);
        if(col==0 || col==2)begin
         if(plot_scales[field+:2]!=0)plot_scales[field+:2]<=plot_scales[field+:2]-1'b1;
        end else if(plot_scales[field+:2]!=3)plot_scales[field+:2]<=plot_scales[field+:2]+1'b1;
       end
       end
      end
     end
    end
   end
  end
 end
endmodule
