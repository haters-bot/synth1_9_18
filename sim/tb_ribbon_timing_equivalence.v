`timescale 1ns/1ps
// 与优化前的处理器逐事件对照；允许处理延迟增加，要求握手顺序和数据相同。
module tb_ribbon_timing_equivalence #(parameter REVERSED=1);
    reg clk=0,rst_n=0,valid=0,ready_out=0;
    reg [2:0] channel=0;
    reg signed [23:0] data=0;
    wire ready_new,ready_ref,valid_new,valid_ref,on_new,on_ref;
    wire [2:0] source_new,source_ref;
    wire [14:0] pitch_new,pitch_ref;
    wire [6:0] velocity_new,velocity_ref;
    reg [25:0] queue_new [0:19999], queue_ref [0:19999];
    integer count_new=0,count_ref=0,compared=0,cycle=0,i,j;
    reg [31:0] rng=32'h1837ac41;
    always #10 clk=~clk;
    ribbon_pitch_processor #(.CHANNEL_COUNT(4), .CALIBRATED_REVERSED(REVERSED)) dut (
        .clk(clk),.rst_n(rst_n),.sample_valid(valid),.sample_channel(channel),.sample_data(data),.sample_ready(ready_new),
        .event_valid(valid_new),.event_ready(ready_out),.event_on(on_new),.event_source(source_new),.event_pitch_q8(pitch_new),.event_velocity(velocity_new));
    ribbon_pitch_processor_reference #(.CHANNEL_COUNT(4), .CALIBRATED_REVERSED(REVERSED)) ref_dut (
        .clk(clk),.rst_n(rst_n),.sample_valid(valid),.sample_channel(channel),.sample_data(data),.sample_ready(ready_ref),
        .event_valid(valid_ref),.event_ready(ready_out),.event_on(on_ref),.event_source(source_ref),.event_pitch_q8(pitch_ref),.event_velocity(velocity_ref));
    always @(posedge clk) if (rst_n) begin
        if (valid_new && ready_out) begin
            queue_new[count_new]={on_new,source_new,pitch_new,velocity_new}; count_new=count_new+1;
        end
        if (valid_ref && ready_out) begin
            queue_ref[count_ref]={on_ref,source_ref,pitch_ref,velocity_ref}; count_ref=count_ref+1;
        end
        while (compared<count_new && compared<count_ref) begin
            if (queue_new[compared] !== queue_ref[compared])
                $fatal(1,"event %0d mismatch new=%h ref=%h",compared,queue_new[compared],queue_ref[compared]);
            compared=compared+1;
        end
    end
    always @(negedge clk) if (rst_n) begin
        cycle=cycle+1;
        // 大幅变化背压，覆盖请求保持、跨通道和异常样本。
        ready_out <= (cycle % 71 >= 19);
    end
    task send;
      input [2:0] c; input signed [23:0] v;
      begin
        @(negedge clk); valid=0;
        while (!(ready_new && ready_ref)) @(negedge clk);
        channel=c; data=v; valid=1;
        @(negedge clk); valid=0;
      end
    endtask
    initial begin
      #100 rst_n=1;
      // 包含负值、满量程、闸门迟滞和两种映射模式边界。
      for (i=0;i<160;i=i+1) for(j=0;j<4;j=j+1) begin
        case (i % 16)
          0,1,2,3: send(j,24'sd0);
          4,5,6,7: send(j,24'sd3000000);
          8: send(j,24'sh7fffff);
          9: send(j,24'sh800000);
          10: send(j,24'sd922747);
          11: send(j,24'sd503316);
          default: begin rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};send(j,$signed(rng[23:0])); end
        endcase
      end
      repeat(400) @(negedge clk);
      if (compared<20 || count_new!=count_ref || compared!=count_new)
        $fatal(1,"missing output: compared=%0d new=%0d ref=%0d",compared,count_new,count_ref);
      $display("PASS ribbon equivalence reversed=%0d samples=640 events=%0d",REVERSED,compared);
      $finish;
    end
    initial begin #5000000;$fatal(1,"timeout");end
endmodule
