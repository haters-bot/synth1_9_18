function signed [15:0] plot_gain;
 input signed [15:0] value;
 input [1:0] gain;
 reg signed [18:0] scaled;
 begin
  scaled=$signed({{3{value[15]}},value})<<<gain;
  plot_gain=scaled>32767 ? 16'sd32767 : scaled< -32768 ? -16'sd32768 : scaled[15:0];
 end
endfunction
