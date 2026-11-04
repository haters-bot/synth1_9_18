`timescale 1ns/1ps
module tb_performance_scheduler;
    parameter integer CAPACITY=8;
    reg clk=0,rst_n=0,tick_1ms=0,clear_events=0,event_push=0;
    reg [31:0] event_time_ms=0;
    reg [6:0] event_note=0,event_velocity=0;
    reg event_on=0,start=0,stop=0,pause=0;
    wire running,event_valid,event_on_out,done,load_error;
    wire [6:0] event_note_out,event_velocity_out;
    wire [31:0] song_time_ms;
    wire [$clog2(CAPACITY+1)-1:0] loaded_events;
    performance_event_scheduler #(.MAX_EVENTS(CAPACITY)) dut(
      .event_ready(1'b1),.follow_mode(1'b0),.follow_step(1'b0),.clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.clear_events(clear_events),
      .event_push(event_push),.event_time_ms(event_time_ms),.event_note(event_note),
      .event_velocity(event_velocity),.event_on(event_on),.start(start),.stop(stop),
      .pause(pause),.running(running),.event_valid(event_valid),.event_on_out(event_on_out),
      .event_note_out(event_note_out),.event_velocity_out(event_velocity_out),
      .song_time_ms(song_time_ms),.done(done),.loaded_events(loaded_events),.load_error(load_error));
    always #5 clk=~clk;

    task push;
      input [31:0] t; input [6:0] n,v; input on;
      begin
        @(negedge clk); event_time_ms=t;event_note=n;event_velocity=v;event_on=on;event_push=1;
        @(negedge clk); event_push=0;
      end
    endtask
    task tick;
      begin @(negedge clk);tick_1ms=1;@(negedge clk);tick_1ms=0; end
    endtask

    integer seen=0,expected_count=0,done_seen=0,i,old_seen;
    reg [46:0] expected [0:CAPACITY-1];
    always @(negedge clk) begin
      if(event_valid) begin
        if(seen>=expected_count) $fatal(1,"unexpected event %0d",seen);
        if({event_note_out,event_velocity_out,event_on_out} !== expected[seen][14:0])
          $fatal(1,"event %0d mismatch",seen);
        if(song_time_ms < expected[seen][46:15]) $fatal(1,"event fired early");
        seen=seen+1;
      end
      if(done) done_seen=done_seen+1;
    end
    task add;
      input [31:0] t; input [6:0] n,v; input on;
      begin
        expected[expected_count]={t,n,v,on};expected_count=expected_count+1;
        push(t,n,v,on);
      end
    endtask
    task play;
      begin @(negedge clk);start=1;@(negedge clk);start=0; end
    endtask
    task clear;
      begin
        @(negedge clk);clear_events=1;@(negedge clk);clear_events=0;
        seen=0;expected_count=0;done_seen=0;
      end
    endtask
    task drain;
      integer limit;
      begin
        limit=0;
        while(running && limit<CAPACITY*5+20) begin @(posedge clk);#1;limit=limit+1;end
        @(posedge clk);#1;
        if(running || seen!=expected_count || done_seen!=1)
          $fatal(1,"drain failed: running=%b seen=%0d expected=%0d done=%0d",running,seen,expected_count,done_seen);
      end
    endtask
    initial begin
      #10000000;$fatal(1,"watchdog");
    end

    initial begin
      repeat(3)@(negedge clk);rst_n=1;
      clear();play();repeat(5)@(negedge clk);
      if(running || done_seen) $fatal(1,"empty playback");
      add(0,60,100,1);add(5,60,0,0);add(5,64,80,1);add(8,64,0,0);
      if(loaded_events!=4) $fatal(1,"event count mismatch");
      play();
      repeat(10)@(negedge clk);
      repeat(4)tick();
      if(seen!=1) $fatal(1,"first due event missing");
      pause=1;repeat(6)tick();
      if(song_time_ms!=4 || seen!=1) $fatal(1,"pause advanced playback");
      pause=0;
      repeat(4)tick();
      drain();
      // Restart must not use the stale synchronous RAM output at the old pointer.
      seen=0;done_seen=0;play();repeat(8)tick();drain();
      // Fill to exact capacity and reject the extra record without wrapping.
      clear();
      for(i=0;i<CAPACITY;i=i+1)add(0,21+(i%88),i%128,i%2);
      push(0,127,127,1);
      if(loaded_events!=CAPACITY || !load_error) $fatal(1,"capacity overflow not reported");
      play();repeat(8)@(negedge clk);
      if(running || seen)$fatal(1,"Truncated song was allowed to play");
      clear();
      if(load_error)$fatal(1,"Clear did not release failed import");
      for(i=0;i<CAPACITY;i=i+1)add(0,21+(i%88),i%128,i%2);
      pause=1;play();repeat(8)@(negedge clk);
      if(seen || song_time_ms) $fatal(1,"paused start emitted an event");
      // Loading/clearing during playback cannot corrupt the stored song.
      push(0,127,127,1);
      clear_events=1;@(negedge clk);clear_events=0;
      if(loaded_events!=CAPACITY) $fatal(1,"clear while running");
      pause=0;drain();
      if(!load_error)$fatal(1,"Write during playback did not report failure");
      clear();
      for(i=0;i<CAPACITY;i=i+1)add(0,21+(i%88),i%128,i%2);
      // Stop invalidates a prefetched record; replay begins from record zero.
      seen=0;done_seen=0;pause=1;play();repeat(8)@(negedge clk);
      stop=1;@(negedge clk);stop=0;
      pause=0;repeat(8)@(negedge clk);
      if(running || seen || song_time_ms) $fatal(1,"stop leaked event");
      play();drain();
      // Clear wins over a simultaneous push.
      clear();event_push=1;clear_events=1;
      @(negedge clk);event_push=0;clear_events=0;
      if(loaded_events) $fatal(1,"clear/push priority");
      add(0,72,90,1);play();drain();
      // Reset invalidates old RAM contents without resetting the RAM itself.
      rst_n=0;repeat(3)@(negedge clk);rst_n=1;
      clear();play();repeat(6)@(negedge clk);
      if(loaded_events || running || seen) $fatal(1,"reset replayed stale RAM");
      $display("PASS: performance scheduler capacity=%0d, timing/pause/replay/full/stop/clear/reset",CAPACITY);
      $finish;
    end
endmodule
