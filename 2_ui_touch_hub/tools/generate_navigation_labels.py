"""Generate fixed navigation text rectangles and character ROM (no bitmap assets)."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]

def main():
    chars=json.loads((ROOT/'tools/ui_font_7x10.json').read_text())['characters']
    lines=[]
    named={}
    def add(condition,x,y,text,large=False,color='DDE7F4',name=None):
        if name:named[name]=len(lines)
        condition=condition.replace('view','text_view').replace('usb_connected','text_usb_connected').replace('usb_error','text_usb_error')
        lines.append((condition,x,y,text.replace('/',':'),large,color))
    add('1',44,16,'MENU')
    add('1',136,14,'SYNTHESIZER')
    add('1',344,14,'VISUALIZATION')
    add('1',616,16,'SYSTEM')
    add('usb_connected && !usb_error',840,16,'USB CONNECTED',False,'58DDB8')
    add('!usb_connected || usb_error',840,16,'USB OFFLINE',False,'D0A46C')
    add('view==0',1040,14,'MASTER')
    add('view!=0',1056,16,'UI TOUCH HUB')
    add('view==1',24,56,'PERFORMANCE MONITOR',True)
    add('view==1',800,64,'SIX VIEWS / I2S RETURN',False,'B3C5D8')
    titles=['01 AUDIO OVERVIEW','02 WAVEFORM','03 STEREO PHASE','04 SPECTRUM','05 SPECTROGRAM','06 LEVELS']
    details=['LEVEL DBFS / 96 KHZ','10.7 MS / AUTO TRIGGER','CORR +000 / BAL +000',
             'PEAK 00000 HZ','BLUE LOW / RED HIGH','P R DBFS / C CREST DB']
    ready=['metrics_ready','waveform_ready','phase_ready','spectrum_ready','spectrum_ready','metrics_ready']
    for i in range(6):
        x=24+(i%3)*418;y=96+(i//3)*296
        add('view==1',x+20,y+12,titles[i],True)
        live=f'view==1 && audio_link_up && {ready[i]}'
        subtitle=['I2S PCM / LIVE ENERGY','LEFT PCM / ZERO CROSS','L X / R Y / PCM',
                  'CENTER 00000 HZ','LOG FREQ / TIME RIGHT','PEAK / RMS / CREST'][i]
        add(live,x+22,y+56,subtitle,False,'B3C5D8',name='CENTROID' if i==3 else None)
        add('view==1 && !audio_link_up',x+22,y+56,'I2S DISCONNECTED',False,'D5AD78')
        add(f'view==1 && audio_link_up && !{ready[i]}',x+22,y+56,'WAITING FOR PCM',False,'D5AD78')
        add('view==1',x+20,y+248,details[i],False,'C0D0E0',name={2:'STEREO',3:'PEAK_HZ'}.get(i))
    live='view==1 && audio_link_up && metrics_ready'
    add(live,238,198,'RMS -00.0',False,'61DED1',name='OV_RMS')
    add(live,238,230,'PK  -00.0',False,'65CDA4',name='OV_PEAK')
    add(live,238,262,'00000 HZ',False,'F5D36A',name='OV_HZ')
    add(live,238,294,'L    R',False,'B3C5D8')
    add(live,882,488,'P -00.0',False,'65CDA4',name='LEVEL_PEAK')
    add(live,882,528,'R -00.0',False,'61DED1',name='LEVEL_RMS')
    add(live,882,568,'C  00.0',False,'F5D36A',name='LEVEL_CREST')
    add('view==1 && audio_link_up && metrics_ready && metrics_clip!=0',882,608,'CLIP',False,'E87565')
    add('view==1 && audio_link_up && metrics_ready && metrics_transient!=0',238,318,'ATTACK',False,'F5D36A')
    add('view==2',32,56,'SYSTEM SETTINGS',True)
    for i,title in enumerate(['CONTROLS','DISPLAY','INPUTS','ABOUT']):
        x=[32,336,632,928][i]
        add('view==2',x+24,98,title,False,'E8F0FA')
    add('view==2 && settings_section_id==1',48,136,'CONTROLS',True)
    add('view==2 && settings_section_id==1',48,184,'MACROS : AUDIO MAPPING NOT CONNECTED',False,'AFC3D8')
    for i in range(4):
        y=248+i*64
        add('view==2 && settings_section_id==1',64,y,f'MACRO {i+1}')
        add('view==2 && settings_section_id==1',264,y,'-',True)
        add('view==2 && settings_section_id==1',600,y,'+',True)
    add('view==2 && settings_section_id==1',48,528,'AUDIO MAPPING NOT CONNECTED',False,'D6B989')
    add('view==2 && settings_section_id==1',48,560,'VALUES KEPT WHEN CHANGING PAGES',False,'AFC3D8')
    add('view==2 && settings_section_id==1',736,136,'DEVICE STATUS',True)
    add('view==2 && settings_section_id==1 && usb_connected && !usb_error',736,192,'TOUCH USB: CONNECTED',False,'58DDB8')
    add('view==2 && settings_section_id==1 && (!usb_connected || usb_error)',736,192,'TOUCH USB: OFFLINE / ERROR',False,'D0A46C')
    add('view==2 && settings_section_id==1',736,232,'VIDEO : 1280 X 720 / 50 MHZ')
    add('view==2 && settings_section_id==1',736,264,'REFRESH : 40.4 HZ')
    add('view==2 && settings_section_id==1',736,304,'FIRMWARE : R17 NAV / SIX SLOTS')
    add('view==2 && settings_section_id==1',736,344,'AUDIO INPUT : I2S RETURN',False,'B3C5D8')
    add('view==2 && settings_section_id==1',736,384,'NOTE INPUT : NOT CONNECTED',False,'D6B989')
    add('view==2 && settings_section_id==1',736,424,'DEPLOYMENT : SRAM')
    add('view==2 && settings_section_id==1',736,480,'TOUCH DIAGNOSTICS')
    add('view==2 && settings_section_id==1 && show_diagnostics',904,544,'ON : TAP TO HIDE')
    add('view==2 && settings_section_id==1 && !show_diagnostics',904,544,'OFF : TAP TO SHOW')
    add('view==2 && settings_section_id==2',64,152,'DISPLAY INFO',True)
    add('view==2 && settings_section_id==2',64,224,'OUTPUT : 1280 X 720')
    add('view==2 && settings_section_id==2',64,272,'PIXEL CLOCK : 50 MHZ')
    add('view==2 && settings_section_id==2',64,320,'REFRESH : 40.4 HZ')
    add('view==2 && settings_section_id==2',64,392,'DISPLAY MODE IS FIXED BY THE FPGA',False,'AFC3D8')
    add('view==2 && settings_section_id==2',64,432,'NO BRIGHTNESS CONTROL IS CONNECTED',False,'D6B989')
    add('view==2 && settings_section_id==2',760,216,'DISPLAY INTERFACE',True)
    add('view==2 && settings_section_id==2',760,296,'VIDEO MODE IS SET BY FPGA')
    add('view==2 && settings_section_id==2',760,344,'FUTURE OPTIONS SLOT')
    add('view==2 && settings_section_id==3',64,152,'INPUT STATUS',True)
    add('view==2 && settings_section_id==3 && usb_connected && !usb_error',64,224,'TOUCH USB : CONNECTED',False,'58DDB8')
    add('view==2 && settings_section_id==3 && (!usb_connected || usb_error)',64,224,'TOUCH USB : OFFLINE / ERROR',False,'D0A46C')
    add('view==2 && settings_section_id==3',64,272,'AUDIO PCM : I2S RETURN',False,'B3C5D8')
    add('view==2 && settings_section_id==3',64,320,'NOTE EVENTS : NOT CONNECTED',False,'D6B989')
    add('view==2 && settings_section_id==3',64,368,'MIDI UART : PARAMETER CONTROL')
    add('view==2 && settings_section_id==3',760,216,'DATA CONNECTIONS',True)
    add('view==2 && settings_section_id==3',760,296,'AUDIO PCM : I2S RETURN')
    add('view==2 && settings_section_id==3',760,344,'NOTE EVENTS : RESERVED PORT')
    add('view==2 && settings_section_id==4',64,152,'UI TOUCH HUB',True)
    add('view==2 && settings_section_id==4',64,224,'FIRMWARE : R17 NAV / SIX SLOTS')
    add('view==2 && settings_section_id==4',64,272,'CURRENT DEPLOYMENT : SRAM')
    add('view==2 && settings_section_id==4',64,320,'CONFIGURATION FLASH NOT CHANGED',False,'AFC3D8')
    add('view==2 && settings_section_id==4',64,392,'SETTINGS ITEMS CAN BE ADDED BY ID',False,'AFC3D8')
    add('view==2 && settings_section_id==4',760,216,'EXPANSION INTERFACE',True)
    add('view==2 && settings_section_id==4',760,296,'ADD A SECTION ID AND LABEL')
    add('view==2 && settings_section_id==4',760,344,'CONNECT ITS STATE AND TOUCH')
    add('view==2 && settings_section_id==4',760,392,'NO UNUSED SETTINGS ARE EXPOSED',False,'D6B989')
    add('view==3',48,72,'WORKSPACE MENU',True)
    for i,(title,detail) in enumerate([('SYNTHESIZER','OSC FILTER ENV FX LFO'),
                                    ('VISUALIZATION','PCM VIEWS / NOTE SLOT'),
                                    ('SYSTEM','CONTROLS AND STATUS')]):
        x=48+i*408
        add('view==3',x+20,208,title,True)
        add('view==3',x+20,384,detail,False,'AFC3D8')
    add('view==3',48,544,'PAGE SWITCHING KEEPS SYNTH SETTINGS',False,'B3C5D8')
    add('view==3',48,576,'AUDIO DATA INPUTS / I2S RETURN',False,'B3C5D8')
    # Parallel one-hot rectangle decode. A serial chain of 97 if-assignments
    # made view -> glyph-coordinate timing unnecessarily deep.
    count=len(lines)
    assert count<=128, count
    out=['// Generated by tools/generate_navigation_labels.py. Parallel hit planes.\n',
         f'wire [{count-1}:0] nav_text_hit;\n']
    for name,index in named.items():out.append(f"localparam [6:0] NAV_{name}=7'd{index};\n")
    fields={'id':7,'col':6,'rx':4,'ry':5,'color':24}
    for field,width in fields.items():
        for bit in range(width):out.append(f'wire [{count-1}:0] nav_{field}_b{bit};\n')
    out+= [f'wire [{count-1}:0] nav_large_hit;\n',
           'reg [6:0] text_id; reg [5:0] text_col; reg [3:0] text_rx; reg [4:0] text_ry; reg text_large;\n',
           'reg text_valid; reg [23:0] text_color;\n']
    for i,(condition,x,y,text,large,color) in enumerate(lines):
        advance=16
        assert x+len(text)*advance<=1280, (text,x)
        out.append(f"wire [10:0] nav_dx_{i}=in_x[10:0]-11'd{x}; wire [4:0] nav_dy_{i}=in_y[4:0]-5'd{y%32};\n")
        out.append(f"assign nav_text_hit[{i}]=({condition}) && in_x>={x} && in_x<{x+len(text)*advance} && in_y>={y} && in_y<{y+(22 if large else 16)};\n")
        out.append(f"assign nav_large_hit[{i}]=nav_text_hit[{i}] & 1'b{int(large)};\n")
        for bit in range(7):out.append(f"assign nav_id_b{bit}[{i}]=nav_text_hit[{i}] & 1'b{(i>>bit)&1};\n")
        for bit in range(6):out.append(f"assign nav_col_b{bit}[{i}]=nav_text_hit[{i}] & nav_dx_{i}[{bit+4}];\n")
        for bit in range(4):out.append(f"assign nav_rx_b{bit}[{i}]=nav_text_hit[{i}] & nav_dx_{i}[{bit}];\n")
        for bit in range(5):out.append(f"assign nav_ry_b{bit}[{i}]=nav_text_hit[{i}] & nav_dy_{i}[{bit}];\n")
        rgb=int(color,16)
        for bit in range(24):out.append(f"assign nav_color_b{bit}[{i}]=nav_text_hit[{i}] & 1'b{(rgb>>bit)&1};\n")
    out.append('always @* begin\n')
    for field,width in fields.items():
        target='text_color' if field=='color' else 'text_'+field
        out.append(target+'={' + ','.join(f'|nav_{field}_b{bit}' for bit in reversed(range(width))) + '};\n')
    out.append('text_large=|nav_large_hit;text_valid=|nav_text_hit;\nend\n')
    out+=['function [5:0] navigation_char; input [6:0] line; input [5:0] col; begin\ncase({line,col})\n']
    for i,(_,_,_,text,_,_) in enumerate(lines):
        for j,ch in enumerate(text):
            if ch!=' ':out.append(f"13'd{i*64+j}:navigation_char=6'd{chars.index(ch)};\n")
    out.append("default:navigation_char=0;endcase end endfunction\n")
    # A synchronous ROM replaces the large combinational character decoder.
    # Keep the function above as an independent regression reference.
    rom = [0] * 8192
    for i,(_,_,_,text,_,_) in enumerate(lines):
        for j,ch in enumerate(text):
            if ch!=' ':rom[i*64+j]=chars.index(ch)
    # Gowin 1.9.11 limits elaboration loops to 2000 iterations. Emit the
    # complete constant image directly instead of an 8192-iteration HDL loop.
    out.append('reg [5:0] navigation_char_rom[0:8191];\ninitial begin\n')
    for address,value in enumerate(rom):
        out.append(f"navigation_char_rom[{address}]=6'd{value};\n")
    out.append('end\n')
    (ROOT/'rtl/ui_vector_engine/navigation_labels.vh').write_text(''.join(out))
    print(f'{len(lines)} navigation text rectangles generated')
if __name__=='__main__':main()
