`timescale 1ns/1ps
module tb_performance_range41;
reg clk=0,rst_n=0,event_valid=0,event_on=0;
reg [6:0] event_note=0;
wire [31:0] active_keys,guide_keys;
wire [23:0] led_active,led_guide;
always #5 clk=~clk;
performance_key_state keys(.clk(clk),.rst_n(rst_n),.event_valid(event_valid),.event_on(event_on),.event_note(event_note),
 .clear_scheduled(1'b0),.manual_valid(1'b0),.manual_down(1'b0),.manual_key(5'd0),
 .remote_valid(1'b0),.remote_down(1'b0),.remote_key(5'd0),.active_keys(active_keys),.guide_keys(guide_keys));
performance_led_white_mapper leds(.active_keys(active_keys),.guide_keys(guide_keys),.led_active(led_active),.led_guide(led_guide));
task note(input integer n,input bit on);
 begin @(negedge clk);event_note=n;event_on=on;event_valid=1;
 @(negedge clk);event_valid=0;#1;end
endtask
integer key,white_count,pc;
reg [23:0] expected;
initial begin
 repeat(3)@(negedge clk);rst_n=1;
 if(keys.BASE_NOTE!=41 || leds.BASE_NOTE!=41)$fatal(1,"default hexadecimal base 29 mismatch");
 note(40,1);note(73,1);if(active_keys!==0)$fatal(1,"out-of-range note accepted");
 white_count=0;
 for(key=0;key<32;key=key+1)begin
  note(41+key,1);
  if(active_keys!==(32'h1<<key) || guide_keys!==active_keys)$fatal(1,"key index %0d",key);
  pc=(41+key)%12;expected=0;
  if(pc==0||pc==2||pc==4||pc==5||pc==7||pc==9||pc==11)begin
   expected=24'h1<<white_count;white_count=white_count+1;
  end
  if(led_active!==expected || led_guide!==expected)$fatal(1,"white mapping key %0d",key);
  if(led_active[23:19]!==0)$fatal(1,"unused five LEDs lit");
  note(41+key,0);if(active_keys!==0 || led_active!==0)$fatal(1,"stuck key or LED");
 end
 if(white_count!=19)$fatal(1,"must have 19 white keys");
 $display("PASS: default hex29=MIDI41 through key/guide/19 white LEDs, all 32 notes 41..72, rejects 40/73, last five LEDs dark");$finish;
end
initial begin #100000;$fatal(1,"range test timeout");end
endmodule
