"""Generate fixed navigation text rectangles and character ROM (no bitmap assets)."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]

def generate_knob_captions(chars):
    captions=['K01 OSC A WT POS', 'K02 OSC A WARP', 'K03 OSC A PAN', 'K04 OSC A VOLUME', 'K05 OSC A UNISON', 'K06 OSC A DETUNE', 'K07 OSC A BLEND', 'K08 OSC A PHASE', 'K09 ENV ATTACK', 'K10 ENV HOLD', 'K11 ENV DECAY', 'K12 ENV SUSTAIN', 'K13 ENV RELEASE', 'K14 MASTER VOLUME', 'K15 MACRO 1', 'K16 MACRO 2', 'K17 OSC B WT POS', 'K18 OSC B WARP', 'K19 OSC B PAN', 'K20 OSC B VOLUME', 'K21 OSC B UNISON', 'K22 OSC B DETUNE', 'K23 OSC B BLEND', 'K24 OSC B PHASE', 'K25 FLT CUTOFF', 'K26 FLT RES', 'K27 MASTER PAN', 'K28 FLT DRIVE', 'K29 FLT FAT', 'K30 FLT MIX', 'K31 REVERB SIZE', 'K32 DELAY FEEDBACK']
    out=['function [5:0] knob_caption; input [4:0] knob; input [5:0] col; begin case({knob,col})\n']
    for knob,caption in enumerate(captions):
        for col,ch in enumerate(caption[:18]):
            if ch!=' ':out.append(f"11'd{knob*64+col}:knob_caption=6'd{chars.index(ch)};\n")
    out.append('default:knob_caption=0;endcase end endfunction\n')
    (ROOT/'rtl/ui_vector_engine/knob_setting_labels.vh').write_text(''.join(out))


def main():
    chars=json.loads((ROOT/'tools/ui_font_7x10.json').read_text())['characters']
    generate_knob_captions(chars)
    lines=[]
    named={}
    def add(condition,x,y,text,large=False,color='DDE7F4',name=None):
        if name:named[name]=len(lines)
        condition=condition.replace('view','text_view').replace('usb_connected','text_usb_connected').replace('usb_error','text_usb_error').replace('settings_section_id','render_settings_section_id')
        lines.append((condition,x,y,text.replace('/',':'),large,color))
    add('1',44,16,'MENU')
    add('1',136,14,'SYNTHESIZER')
    add('1',344,14,'VISUALIZATION')
    add('1',600,16,'PERFORMANCE')
    add('1',832,16,'SYSTEM')
    add('view!=0 && usb_connected && !usb_error',1056,16,'USB ON',False,'58DDB8')
    add('view!=0 && (!usb_connected || usb_error)',1056,16,'USB OFF',False,'D0A46C')
    add('view==0',1040,14,'MASTER')
    add('view==1',24,56,'PERFORMANCE MONITOR',True)
    add('view==1',800,64,'SIX VIEWS / I2S RETURN',False,'B3C5D8')
    titles=['01 AUDIO OVERVIEW','02 WAVEFORM','03 STEREO L:R XY','04 SPECTRUM','05 SPECTROGRAM','06 LEVELS']
    details=['LEVEL DBFS / 96 KHZ','L CYAN / R AMBER','FINAL PCM / SAME TIME',
             'PEAK 00000','BLUE LOW / RED HIGH','DBFS / PEAK / CREST']
    ready=['metrics_ready','waveform_ready','phase_ready','spectrum_ready','spectrum_ready','metrics_ready']
    for i in range(6):
        x=24+(i%3)*418;y=96+(i//3)*296
        add('view==1',x+20,y+12,titles[i],True)
        live=f'view==1 && audio_link_up && {ready[i]}'
        subtitle=['I2S PCM / LIVE ENERGY','L:R PCM  : 10.67 MS','X LEFT / Y RIGHT',
                  'CENTER 00000 HZ','LOG FREQ / TIME RIGHT','STEREO RMS / PEAK HOLD'][i]
        add(live,x+22,y+56,subtitle,False,'B3C5D8',name='CENTROID' if i==3 else 'WAVE_SPAN' if i==1 else None)
        add('view==1 && !audio_link_up',x+22,y+56,'I2S DISCONNECTED',False,'D5AD78')
        add(f'view==1 && audio_link_up && !{ready[i]}',x+22,y+56,'WAITING FOR PCM',False,'D5AD78')
        add('view==1',x+20,y+238,details[i],False,'C0D0E0',name={2:'STEREO',3:'PEAK_HZ'}.get(i))
    add('view==1',222,630,'TO 00000HZ',False,'C0D0E0',name='SPECTRUM_RANGE')
    live='view==1 && audio_link_up && metrics_ready'
    add(live,238,198,'RMS -00.0',False,'61DED1',name='OV_RMS')
    add(live,238,230,'PK  -00.0',False,'65CDA4',name='OV_PEAK')
    add(live,238,262,'00000 HZ',False,'F5D36A',name='OV_HZ')
    add(live,238,294,'L    R',False,'B3C5D8')
    add(live,882,488,'L -00.0',False,'65CDA4',name='LEVEL_L')
    add(live,882,608,'P -00.0',False,'65CDA4',name='LEVEL_PEAK')
    add(live,882,552,'R -00.0',False,'61DED1',name='LEVEL_RMS')
    add(live,1034,608,'C  00.0',False,'F5D36A',name='LEVEL_CREST')
    add('view==1 && audio_link_up && metrics_ready && metrics_clip!=0',1176,580,'CLIP',False,'E87565')
    add('view==1 && audio_link_up && metrics_ready && metrics_transient!=0',238,318,'ATTACK',False,'F5D36A')
    add('view==2',32,56,'SYSTEM SETTINGS',True)
    for i,title in enumerate(['CONTROLS','DISPLAY','INPUTS','PRESETS']):
        x=[32,336,632,928][i]
        add('view==2',x+24,98,title,False,'E8F0FA')
    add('view==2 && settings_section_id==1',48,144,'ENCODER STEP',True)
    add('view==2 && settings_section_id==1',448,144,'APPLY ALL',False,'61DED1')
    for row in range(8):
        add('view==2 && settings_section_id==1',64,218+row*44,
            'K00                1    2    4    8',name=f'KNOB{row}')
    add('view==2 && settings_section_id==1',64,584,'PREV       PAGE 1:4          NEXT',name='KNOB_PAGE')
    add('view==2 && settings_section_id==1',736,152,'PHYSICAL ENCODERS',True)
    add('view==2 && settings_section_id==1',736,216,'STEP PER DETENT : 1 2 4 8')
    add('view==2 && settings_section_id==1',736,272,'EACH KNOB HAS ITS OWN STEP')
    add('view==2 && settings_section_id==1',736,328,'APPLY ALL USES LAST CHOICE')
    add('view==2 && settings_section_id==1',736,384,'TOUCH DRAG IS UNCHANGED')
    add('view==2 && settings_section_id==1',736,440,'SESSION SETTINGS : DEFAULT 4')
    add('view==2 && settings_section_id==1',736,520,'TOUCH DIAGNOSTICS')
    add('view==2 && settings_section_id==1 && show_diagnostics',904,552,'ON : TAP TO HIDE')
    add('view==2 && settings_section_id==1 && !show_diagnostics',904,552,'OFF : TAP TO SHOW')
    add('view==2 && settings_section_id==2',48,144,'PLOT DISPLAY SCALES',True)
    for row,title in enumerate(['ENERGY GAIN','WAVE GAIN:TIME','PHASE Y:X','SPECTRUM Y:ZOOM','HISTORY COLOR:TIME','METER GAIN']):
        add('view==2 && settings_section_id==2',64,212+row*56,f'{row+1} {title}',name=f'SCALE{row}')
        add('view==2 && settings_section_id==2',400,212+row*56,'Y1 --' if row in (0,5) else 'Y1 X1',name=f'SCALE_VALUE{row}')
        add('view==2 && settings_section_id==2',560,212+row*56,
            'Y-        Y+        X-        X+' if row not in (0,5) else 'Y-        Y+')
    add('view==2 && settings_section_id==2',64,576,'DISPLAY ONLY : MEASUREMENTS UNCHANGED',False,'AFC3D8')
    add('view==2 && settings_section_id==2',64,616,'PLOT FOOTER SHORTCUTS USE THE SAME SETTINGS',False,'61DED1')
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
    add('view==2 && settings_section_id==4',760,296,'PHONE : HC07 UART',False,'D6B989')
    add('view==3',48,72,'WORKSPACE MENU',True)
    for i,(title,detail) in enumerate([('SYNTHESIZER','OSC FILTER ENV FX LFO'),
                                    ('VISUALIZATION','PCM VIEWS / NOTE SLOT'),
                                    ('SYSTEM','CONTROLS AND STATUS')]):
        x=48+i*408
        add('view==3',x+20,208,title,True)
        add('view==3',x+20,384,detail,False,'AFC3D8')
    add('view==3',48,544,'PAGE SWITCHING KEEPS SYNTH SETTINGS',False,'B3C5D8')
    add('view==3',48,576,'AUDIO DATA INPUTS / I2S RETURN',False,'B3C5D8')
    # Page IDs: synth=0, visual=1, performance=2, system=3, menu=4.
    # Remap only the pre-existing system/menu text before adding performance.
    lines=[(condition.replace('view==3','view==4').replace('view==2','view==3'),
            x,y,text,large,color) for condition,x,y,text,large,color in lines]
    add('view==2',32,100,'PERFORMANCE',True)
    add('view==2 && !performance_gateway_up',336,100,'PHONE : DISCONNECTED',False,'D5AD78')
    add('view==2 && performance_gateway_up',336,100,'PHONE : CONNECTED',False,'58DDB8')
    record_labels=['RECORDER READY', 'RECORDER NOT READY', 'RECORDING',
                   'SAVING RECORDING', 'RECORDING SAVED', 'RECORDING LIMIT REACHED',
                   'AUDIO INPUT LOST', 'RECORDING STORAGE ERROR', 'RECORDER BUSY / RETRY',
                   'MIDI QUEUE OVERFLOW', 'SCORE LOAD ERROR : RETRY']
    add('view==2',800,100,'RECORDER STATUS             ',False,'AFC3D8',name='RECORDER_STATUS')
    add('view==2',32,400,'FOLLOW THE HIGHLIGHTED KEYS',False,'AFC3D8')
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
    status_rom=[0]*512
    for status,text in enumerate(record_labels):
        for col,ch in enumerate(text.replace('/',':')):
            if ch!=' ':status_rom[status*32+col]=chars.index(ch)
    out.append('reg [5:0] recorder_char_rom[0:511];\ninitial begin\n')
    for address,value in enumerate(status_rom):
        out.append(f"recorder_char_rom[{address}]=6'd{value};\n")
    out.append('end\n')
    (ROOT/'rtl/ui_vector_engine/navigation_labels.vh').write_text(''.join(out))
    print(f'{len(lines)} navigation text rectangles generated')
if __name__=='__main__':main()
