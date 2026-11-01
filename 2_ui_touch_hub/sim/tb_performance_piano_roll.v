`timescale 1ns/1ps
module tb_performance_piano_roll;
reg clk=0,rst_n=0,tick=0,clear=0,push=0,on=0,start=0,stop=0,pause=0;
reg follow=0,hit=0,ready=1,frame=0;
reg [31:0] stamp=0;
reg [6:0] note=0,velocity=100,base=7'h29;
reg [13:0] y=192;
wire running,valid,done,error;
wire [31:0] score_time,displayed,body,attack;
wire [14:0] count;
wire [13:0] address;
wire [46:0] record;
wire visible;
integer bank,t,r,k,checks=0,i;
reg [31:0] expected,expected_attack;
integer bin_lo,bin_hi;
integer ons[0:6],offs[0:6],keys[0:6];
reg [31:0] before_pause;
always #10 clk=~clk;
performance_event_scheduler #(.MAX_EVENTS(16384)) scheduler(
 .clk(clk),.rst_n(rst_n),.tick_1ms(tick),.clear_events(clear),
 .event_push(push),.event_time_ms(stamp),.event_note(note),.event_velocity(velocity),.event_on(on),
 .start(start),.stop(stop),.pause(pause),.follow_mode(follow),.follow_step(hit),.event_ready(ready),
 .running(running),.event_valid(valid),.song_time_ms(score_time),.done(done),.load_error(error),
 .loaded_events(count),.preview_address(address),.preview_record(record));
performance_piano_roll #(.MAX_EVENTS(16384)) dut(
 .clk(clk),.rst_n(rst_n),.frame_start(frame),.running(running),
 .invalidate(start||stop||clear||push),.song_time_ms(score_time),.base_note(base),
 .loaded_events(count),.preview_address(address),.preview_record(record),.raster_y(y),
 .body_keys(body),.onset_keys(attack),.visible(visible),.displayed_time_ms(displayed));
task step;begin @(negedge clk);end endtask
task load;input integer ms,key,is_on;begin
 stamp=ms;note=base+key;on=is_on;push=1;step;push=0;step;
end endtask
task new_score;begin stop=1;step;stop=0;clear=1;step;clear=0;step;end endtask
task play;begin start=1;step;start=0;repeat(12)step;end endtask
task ms;begin tick=1;step;tick=0;repeat(12)step;end endtask
task publish;integer n;begin
 n=0;
 while(dut.state!=11 && n<200000)begin step;n=n+1;end
 if(n>=200000)$fatal(1,"roll builder stalled state=%d",dut.state);
 frame=1;step;frame=0;step;
 if(!visible)$fatal(1,"completed bitmap did not publish");
end endtask
task refresh;begin
 // Discard an in-flight bitmap at the previous score time, then publish
 // one whose independent captured time is the current paused/waiting score.
 publish;
 if(displayed!=score_time)publish;
 if(displayed!=score_time)$fatal(1,"preview did not converge to score time");
end endtask
task check_picture;begin
 for(r=0;r<207;r=r+1)begin
  y=192+r;repeat(2)step;
  expected=0;expected_attack=0;
  bin_lo=displayed+(206-r)*8;bin_hi=bin_lo+7;
  for(k=0;k<7;k=k+1)begin
   if(offs[k]>displayed && ons[k]<=bin_hi && offs[k]>=bin_lo)
    expected=expected|(32'd1<<keys[k]);
   if(offs[k]>displayed && ons[k]>=bin_lo && ons[k]<=bin_hi)
    expected_attack=expected_attack|(32'd1<<keys[k]);
  end
  if(body!==expected || attack!==expected_attack)
   $fatal(1,"bank=%h score=%0d row=%0d body=%h want=%h attack=%h want=%h",base,displayed,r,body,expected,attack,expected_attack);
  checks=checks+1;
 end
 y=191;repeat(2)step;if(body!==0 || attack!==0)$fatal(1,"roll leaked above lane");
 y=400;repeat(2)step;if(body!==0 || attack!==0)$fatal(1,"roll leaked into key separator");
end endtask
initial begin
 ons[0]=0;offs[0]=160;keys[0]=0;
 ons[1]=80;offs[1]=400;keys[1]=3;
 ons[2]=80;offs[2]=800;keys[2]=7;
 ons[3]=240;offs[3]=480;keys[3]=0;
 ons[4]=1200;offs[4]=1240;keys[4]=5;
 ons[5]=4000;offs[5]=8000;keys[5]=31;
 ons[6]=24;offs[6]=32;keys[6]=12;
 repeat(5)step;rst_n=1;step;
 for(bank=0;bank<4;bank=bank+1)begin
  base=7'h29+bank*12;new_score;
  load(0,0,1);load(24,12,1);load(32,12,0);load(80,3,1);load(80,7,1);
  load(160,0,0);load(240,0,1);load(400,3,0);load(480,0,0);load(800,7,0);
  load(1200,5,1);load(1240,5,0);load(4000,31,1);load(8000,31,0);
  play;refresh;check_picture;
  for(t=0;t<500;t=t+1)ms;
  refresh;check_picture;
  // Pause freezes score, bars, and release boundaries despite wall ticks.
  pause=1;before_pause=score_time;repeat(20)ms;
  refresh;check_picture;
  if(score_time!=before_pause)$fatal(1,"pause advanced score");pause=0;
  for(t=500;t<4500;t=t+1)ms;
  refresh;check_picture; // Long held note must reach above the preview top.
  stop=1;step;stop=0;repeat(3)step;
  if(visible || body!==0 || attack!==0)$fatal(1,"stop retained old bitmap");
  play;refresh;check_picture; // restart uses original score and original spans
 end
 // Follow waiting: graphics use the same frozen score as the scheduler.
 new_score;base=7'h29;follow=1;
 load(80,0,1);load(160,0,0);load(240,7,1);load(400,7,0);play;
 for(t=0;t<120;t=t+1)ms;
 if(score_time!=80)$fatal(1,"follow did not wait at note onset");
 refresh;y=398;repeat(2)step;
 if(!body[0] || !attack[0])$fatal(1,"waiting note not on judgment row");
 y=378;repeat(2)step;if(!attack[7])$fatal(1,"next follow note hidden behind Note Off");
 repeat(30)ms;refresh;
 if(displayed!=80)$fatal(1,"follow graphics moved during wait");
 hit=1;step;hit=0;repeat(8)step;repeat(50)ms;refresh;
 if(displayed<=80)$fatal(1,"correct physical-step did not resume score");
 // Full 16384-event upload and repeated overlapping same-key voices.
 new_score;follow=0;ready=0;
 for(i=0;i<8192;i=i+1)load(100,31,1);
 for(i=0;i<8192;i=i+1)load(200,31,0);
 if(count!=16384 || error)$fatal(1,"maximum capacity changed");
 play;refresh;y=379;repeat(2)step;
 if(body!==32'h80000000)$fatal(1,"max-score repeated voices lost span");
 y=386;repeat(2)step;
 if(attack!==32'h80000000)$fatal(1,"max-score onset absent");
 // Clear/reload never exposes stale framebuffer contents.
 new_score;load(500,2,1);load(600,2,0);play;refresh;
 y=379;repeat(2)step;if(body!==0)$fatal(1,"old score leaked after clear");
 $display("PASS: %0d row masks, four calibrated banks, chords/retriggers/durations/long holds, NoteOff lookahead, pause/follow, restart/clear, 16384 events",checks);
 $finish;
end
initial begin #100000000;$fatal(1,"piano roll watchdog");end
endmodule
