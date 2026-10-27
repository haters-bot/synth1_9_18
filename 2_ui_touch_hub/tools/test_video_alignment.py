"""Check output pixel/sync alignment across the complete renderer pipeline.

Uses independently known solid pixels in both the old base and new FX layers;
varies sync and DEN every clock so a one-pixel latency error cannot settle away.
"""
from datetime import datetime
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
MS=Path('D:/altera/modelsim_ase/win32aloem')


def main():
    out=ROOT/'impl'/('video_alignment_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    source=(ROOT/'rtl/ui_vector_engine/ui_top_renderer.v').read_text()
    ports=source[source.index('module ui_top_renderer'):source.index(');')]
    live={'clk','rst_n','in_hsync','in_vsync','in_den','in_pixel_x','in_pixel_y'}
    connections=[]
    for match in re.finditer(r'input\s+wire\s*(?:signed\s*)?(\[\d+:\d+\])?\s*([^\n]+)',ports):
        width,names=match.groups()
        for name in names.split('//')[0].rstrip(' ,\r').split(','):
            name=name.strip()
            if name:
                value=name if name in live else (width.split(':')[0][1:]+"'d0" if width else "1'b0")
                # Explicit sized zero avoids signed/truncation surprises.
                if name not in live and width:
                    msb,lsb=map(int,re.findall(r'\d+',width));value=f"{msb-lsb+1}'d0"
                connections.append(f'.{name}({value})')
    connections += ['.out_hsync(out_hsync)','.out_vsync(out_vsync)',
                    '.out_den(out_den)','.out_pixel_data(rgb)']
    tb='''`timescale 1ns/1ps
module tb_video_alignment;
reg clk=0,rst_n=0,in_hsync=0,in_vsync=0,in_den=0;
reg [13:0] in_pixel_x=0,in_pixel_y=0;
wire out_hsync,out_vsync,out_den;
wire [23:0] rgb;
reg [6:0] hs=0,vs=0,de=0;
reg [23:0] colors[0:6];
reg [23:0] expected_pixel=24'h101318;
integer cycle=0,checks=0,i,n;
reg checking=1;
integer px[0:19],py[0:19],k;
reg [23:0] stationary[0:19];
always #8 clk=~clk;
ui_top_renderer dut(CONNECTIONS);
always @(posedge clk) begin
    if(!rst_n) begin
        hs=0;vs=0;de=0;cycle=0;
        for(i=0;i<7;i=i+1) colors[i]=0;
    end else begin
        hs={hs[5:0],in_hsync};vs={vs[5:0],in_vsync};de={de[5:0],in_den};
        for(i=6;i>0;i=i-1) colors[i]=colors[i-1];
        colors[0]=in_den ? expected_pixel : 24'd0;
        cycle=cycle+1;
        #1;
        if(checking && cycle>10) begin
            if({out_hsync,out_vsync,out_den} !== {hs[6],vs[6],de[6]})
                $fatal(1,"Sync delay differs from seven clocks at cycle %0d",cycle);
            if(rgb !== colors[6])
                $fatal(1,"Compositor pixel alignment at cycle %0d: actual=%h expected=%h",cycle,rgb,colors[6]);
            checks=checks+1;
        end
    end
end
initial begin
    repeat(8) @(negedge clk);rst_n=1;
    for(n=0;n<2048;n=n+1) begin
        @(negedge clk);
        in_hsync=(n%3)==0;in_vsync=(n%7)<3;in_den=(n%5)!=0;
        case(n%10)
            0: begin in_pixel_x=0;in_pixel_y=0;expected_pixel=24'h151D29;end
            1: begin in_pixel_x=420;in_pixel_y=368;expected_pixel=24'h384256;end
            2: begin in_pixel_x=780;in_pixel_y=693;expected_pixel=24'h384256;end
            3: begin in_pixel_x=425;in_pixel_y=405;expected_pixel=24'h181C24;end
            4: begin in_pixel_x=0;in_pixel_y=200;expected_pixel=24'h101318;end
            5: begin in_pixel_x=36;in_pixel_y=450;expected_pixel=24'h2A3140;end
            6: begin in_pixel_x=37;in_pixel_y=450;expected_pixel=24'h0B0E14;end
            7: begin in_pixel_x=24;in_pixel_y=200;expected_pixel=24'h2A3140;end
            8: begin in_pixel_x=23;in_pixel_y=200;expected_pixel=24'h101318;end
            9: begin in_pixel_x=36;in_pixel_y=450;expected_pixel=24'h2A3140;end
        endcase
    end
    // Stationary output is an independent latency oracle: leave each input
    // fixed long enough to settle, then demand the same pixel when inputs
    // jump on every clock. Covers old panels, four-stage ENV, FX and LFO.
    @(negedge clk);checking=0;in_den=1;
    px[0]=36;py[0]=450;px[1]=37;py[1]=450;
    px[2]=390;py[2]=450;px[3]=391;py[3]=450;
    px[4]=200;py[4]=22;px[5]=200;py[5]=26;
    px[6]=950;py[6]=268;px[7]=951;py[7]=278;
    px[8]=36;py[8]=60;px[9]=40;py[9]=60;
    px[10]=126;py[10]=385;px[11]=140;py[11]=385;
    px[12]=36;py[12]=120;px[13]=37;py[13]=120;
    px[14]=824;py[14]=408;px[15]=825;py[15]=409;
    px[16]=780;py[16]=693;px[17]=425;py[17]=405;
    px[18]=24;py[18]=200;px[19]=23;py[19]=200;
    for(k=0;k<20;k=k+1) begin
        in_pixel_x=px[k];in_pixel_y=py[k];
        repeat(24) @(negedge clk);
        if((^rgb)===1'bx) $fatal(1,"Unknown stationary pixel %0d",k);
        stationary[k]=rgb;
    end
    expected_pixel=stationary[19];
    repeat(12) @(negedge clk);checking=1;
    for(n=0;n<4096;n=n+1) begin
        @(negedge clk);k=(n*7)%20;
        in_pixel_x=px[k];in_pixel_y=py[k];expected_pixel=stationary[k];
        in_hsync=(n%3)==0;in_vsync=(n%7)<3;in_den=(n%5)!=0;
    end
    @(negedge clk);
    if(checks<6000) $fatal(1,"Incomplete video checks");
    $display("PASS: %0d continuous compositor pixel, HSYNC, VSYNC and DEN alignment checks",checks);
    $finish;
end
endmodule
'''.replace('CONNECTIONS',',\n'.join(connections))
    (out/'tb_video_alignment.v').write_text(tb)
    def run(args,name):
        with (out/name).open('w') as stream:
            subprocess.run([str(a) for a in args],cwd=out,stdout=stream,stderr=subprocess.STDOUT,check=True,timeout=120)
    run([MS/'vlib.exe','work'],'vlib.log')
    files=[ROOT/e.attrib['path'] for e in ET.parse(ROOT/'2_ui_touch_hub.gprj').findall('.//File') if e.attrib['path'].endswith('.v')]
    run([MS/'vlog.exe','-sv','+incdir+'+str(ROOT/'rtl/ui_vector_engine'),*files,'tb_video_alignment.v'],'compile.log')
    run([MS/'vsim.exe','-c','-l','simulation.log','tb_video_alignment','-do','onerror {quit -code 1}; run -all; quit -f'],'vsim.log')
    log=(out/'simulation.log').read_text(errors='replace')
    if 'PASS:' not in log or '** Fatal:' in log or '** Error:' in log:
        raise RuntimeError(f'Alignment check failed: {out}')
    print(next(line for line in log.splitlines() if 'PASS:' in line));print(out)


if __name__=='__main__':main()
