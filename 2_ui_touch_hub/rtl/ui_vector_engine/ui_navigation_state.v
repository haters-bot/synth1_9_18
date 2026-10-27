// Page switches commit only at vertical sync. Navigation never resets synth state.
module ui_navigation_state #(parameter CONTACT_CYCLES=2500000)(
 input wire clk,rst_n,frame_start,
 input wire touch_valid,touch_down,
 input wire [13:0] touch_x,touch_y,
 output reg [1:0] view,
 output reg [7:0] settings_section_id,
 output wire capture_active,
 output reg show_diagnostics,
 output reg delta_valid,
 output reg [7:0] delta_id,
 output reg signed [7:0] delta_value
);
 reg [1:0] requested,last_page;
 reg finger,owned_contact;
 reg [21:0] quiet;
 wire master_area=touch_x>=1140 && touch_x<=1230 && touch_y<44;
 wire header=touch_y<44 && !master_area;
 assign capture_active=view!=0 || requested!=view || owned_contact ||
                       (touch_valid && touch_down && header);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   view<=0;requested<=0;last_page<=0;finger<=0;owned_contact<=0;settings_section_id<=8'd1;
   quiet<=0;show_diagnostics<=0;delta_valid<=0;delta_id<=0;delta_value<=0;
  end else begin
   delta_valid<=0;
   if(frame_start)view<=requested;
   if(quiet<CONTACT_CYCLES)quiet<=quiet+1'b1;
   else begin finger<=0;owned_contact<=0;end
   if(touch_valid)begin
    quiet<=0;
    if(!touch_down)begin finger<=0;owned_contact<=0;end
    else begin
     finger<=1;
     if(!finger)begin
      owned_contact<=view!=0 || header || requested!=view;
      if(header)begin
       if(touch_x>=16 && touch_x<112)begin
        if(view==3)requested<=last_page;
        else begin last_page<=view;requested<=3;end
       end else if(touch_x>=128 && touch_x<320)requested<=0;
       else if(touch_x>=336 && touch_x<576)requested<=1;
       else if(touch_x>=592 && touch_x<800)requested<=2;
      end else if(view==3 && touch_y>=160 && touch_y<=480)begin
       if(touch_x>=48 && touch_x<=416)requested<=0;
       else if(touch_x>=456 && touch_x<=824)requested<=1;
       else if(touch_x>=864 && touch_x<=1232)requested<=2;
      end else if(view==2)begin
       if(touch_y>=88 && touch_y<=120)begin
        if(touch_x>=32 && touch_x<336)settings_section_id<=8'd1;
        else if(touch_x>=336 && touch_x<632)settings_section_id<=8'd2;
        else if(touch_x>=632 && touch_x<928)settings_section_id<=8'd3;
        else if(touch_x>=928 && touch_x<=1248)settings_section_id<=8'd4;
       end
       if(settings_section_id==8'd1 && touch_x>=880 && touch_x<=1216 && touch_y>=520 && touch_y<=584)
        show_diagnostics<=!show_diagnostics;

      end
     end
    end
   end
  end
 end
endmodule
