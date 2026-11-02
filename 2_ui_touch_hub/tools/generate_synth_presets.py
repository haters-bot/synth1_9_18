"""Generate UI ROM from the owner's pinned upstream Python preset library.

Never import the GUI or consult a moving worktree. Only literal constant
assignments and make_synth_preset are evaluated from the fixed Git object.
"""
from pathlib import Path
import ast
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = 'f0da2279eba79c3b368248718f96033f0cc8f9b6'
# Same authoritative bank order as static_cc_slots.vh. Wave slots use UI enums.
SLOT_CCS = [48,10,36,21,23,22,87,88,20,39,91,46,
            37,29,31,30,89,90,28,41,92,47,42,43,44,45,
            24,25,26,27,32,33,34,35,53,52,54,55,56,57,
            38,40,49,50,51,58,59,60,61,62,63,64,65,66,67,68,
            69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86]
GLOBAL_KEYS = ['pan','filter_mode','filter_cutoff','filter_resonance','filter_mix',
               'master_level','vibrato_enabled','vibrato_rate','vibrato_depth',
               'portamento_enabled','portamento_time','effect_mode',
               'delay_time','delay_feedback','delay_mix','reverb_size','reverb_decay','reverb_mix',
               'distortion_enabled','distortion_type','distortion_drive','distortion_tone','distortion_mix',
               'chorus_enabled','chorus_rate','chorus_depth','chorus_delay','chorus_feedback','chorus_mix',
               'phaser_enabled','phaser_rate','phaser_depth','phaser_center','phaser_feedback','phaser_mix',
               'compressor_enabled','compressor_threshold','compressor_ratio','compressor_attack',
               'compressor_release','compressor_makeup','compressor_mix']
OSC_KEYS = ['enabled','waveform','warp_mode','warp_amount','wavetable_index','wt_position',
            'detune','phase','rand','unison','level','pan','attack','decay','sustain','release']
# Presentation-only translations: parameter values always come from Git.
TITLES = ['SYNTH PIANO','SOLO BOWED STRINGS','WARM ANALOG BRASS','RETRO STRING MACHINE',
          'CLASSIC PWM LEAD','WIDE SUPERSAW','ROUND SUB BASS','ACID 303',
          'BRIGHT PLUCK','CRYSTAL ELECTRIC PIANO','TRANSISTOR ORGAN','WIDE ANALOG PAD',
          'SAMPLED GRAND PIANO']
DETAILS = ['SD BANK 08 : DECAYING PIANO', 'SD BANK 09 : EXPRESSIVE STRINGS',
           'WARM FILTERED DUAL OSCILLATORS', 'VINTAGE ENSEMBLE TEXTURE',
           'PULSE WIDTH LEAD', '7 UNISON MEMBERS : REDUCED POLYPHONY',
           'SOLID LOW FREQUENCY FOUNDATION','SD BANK 00 : RESONANT ACID BASS',
           'FAST ATTACK : BRIGHT PLUCK','CLEAR BELL LIKE KEYS',
           'CLASSIC ORGAN TONE','5 UNISON MEMBERS : REDUCED POLYPHONY',
           'SD10 BODY + SD11 BRIGHT ATTACK']
CATEGORIES = ['ACOUSTIC','CLASSIC','LEAD','BASS','KEYS','ATMOSPHERE']

def reference_data():
    raw = subprocess.check_output(['git','show',REFERENCE+':tools/midi_uart_sender.py'],cwd=ROOT)
    tree = ast.parse(raw.decode('utf-8'))
    namespace = {}
    for node in tree.body:
        if isinstance(node,ast.FunctionDef) and node.name=='make_synth_preset':
            exec(compile(ast.Module([node],type_ignores=[]),'pinned_reference','exec'),namespace)
        elif isinstance(node,ast.Assign):
            names=[t.id for t in node.targets if isinstance(t,ast.Name)]
            if names and (names[0].isupper()):
                try:
                    value=ast.literal_eval(node.value)
                except (ValueError,TypeError):
                    if names[0]!='SYNTH_PRESETS': continue
                    value=eval(compile(ast.Expression(node.value),'pinned_presets','eval'),namespace)
                for name in names: namespace[name]=value
    return raw,namespace

def expanded_rows(ns):
    rows=[]
    extension=json.loads((ROOT/'tools/sampled_piano_preset.json').read_text(encoding='utf-8'))
    presets=list(ns['SYNTH_PRESETS'].items())+[(extension['name'],extension['full'])]
    for name,preset in presets:
        by_cc={}
        for key,value in preset['controls'].items():
            if isinstance(value,bool): value=127 if value else 0
            if isinstance(value,str):
                table={'filter_mode':'FILTER_MODE_VALUES','effect_mode':'EFFECT_MODE_VALUES',
                       'distortion_type':'DISTORTION_TYPE_VALUES'}[key]
                value=ns[table][value]
            constant=key.upper().replace('_ENABLED','_ENABLE')+'_CC'
            by_cc[ns[constant]]=value
        for osc,values in preset['oscillators'].items():
            ccmap=ns['OSC_'+osc+'_CC']
            for key,value in values.items():
                if key=='enabled': value=127 if value else 0
                if key=='waveform': value=ns['WAVEFORM_VALUES'][value]
                if key=='warp_mode': value=ns['WARP_MODE_VALUES'][value]
                by_cc[ccmap['enable' if key=='enabled' else key]]=value
        assert set(by_cc)==set(SLOT_CCS) and len(by_cc)==74
        assert all(isinstance(v,int) and 0<=v<=127 for v in by_cc.values())
        assert 1<=by_cc[23]<=8 and 1<=by_cc[31]<=8
        values=[by_cc[cc] for cc in SLOT_CCS]
        for slot in (3,13): values[slot]={0:0,96:1,64:2,32:3,127:4}[values[slot]]
        sequence=[]
        for key in GLOBAL_KEYS:
            cc=ns[key.upper().replace('_ENABLED','_ENABLE')+'_CC'];sequence.append(cc)
        for osc in ('A','B'):
            sequence.extend(ns['OSC_'+osc+'_CC']['enable' if k=='enabled' else k] for k in OSC_KEYS)
        assert len(sequence)==74 and len(set(sequence))==74
        rows.append({'name':name,'description':preset['description'],'full':preset,
                     'ui_values':values,'cc_values':by_cc,'cc_sequence':sequence})
    assert len(rows)==13
    return rows

def main():
    raw,ns=reference_data(); rows=expanded_rows(ns)
    out=['// Generated by generate_synth_presets.py; do not hand edit.\n',
         '// Reference '+REFERENCE+'; SHA256 '+hashlib.sha256(raw).hexdigest()+'\n',
         'function [517:0] synth_preset_bank; input [3:0] index; begin case(index)\n']
    for n,row in enumerate(rows):
        bits=sum(v<<(7*i) for i,v in enumerate(row['ui_values']))
        out.append(f"4'd{n}:synth_preset_bank=518'h{bits:0130X}; // {TITLES[n]}\n")
    out.append("default:synth_preset_bank=518'd0;endcase end endfunction\n")
    out.append('function [6:0] synth_preset_send_slot; input [6:0] index; begin case(index)\n')
    for n,cc in enumerate(rows[0]['cc_sequence']):
        out.append(f"7'd{n}:synth_preset_send_slot=7'd{SLOT_CCS.index(cc)}; // CC{cc}\n")
    out.append("default:synth_preset_send_slot=0;endcase end endfunction\n")
    (ROOT/'rtl/ui_vector_engine/synth_presets.vh').write_text(''.join(out),encoding='utf-8')
    catalog={'reference_commit':REFERENCE,'reference_sha256':hashlib.sha256(raw).hexdigest(),
             'extension_file':'tools/sampled_piano_preset.json',
             'extension_sha256':hashlib.sha256((ROOT/'tools/sampled_piano_preset.json').read_bytes()).hexdigest(),
             'slot_ccs':SLOT_CCS,'categories':CATEGORIES,'rows':rows}
    (ROOT/'tools/synth_presets_reference.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    chars=json.loads((ROOT/'tools/ui_font_7x10.json').read_text())['characters']
    texts=CATEGORIES+TITLES+DETAILS+['SELECT A SOUND','APPLYING : NOTE PRIORITY',
          'READY','REAPPLY','BACK','CUSTOM : RESERVED',
          'CUSTOM SAVE AND DELETE ARE NOT IMPLEMENTED',
          '13 FACTORY SOUNDS : COMPLETE PARAMETER RECALL',
          'SD SOUNDS REQUIRE THE AUDIO BOARD WAVE BANK',
          'QUEUED : LATEST SELECTION']
    names=['SELECT','APPLYING','READY','REAPPLY','BACK','CUSTOM','NOTICE','FOOTER','SD','QUEUED']
    text_rom=['// Generated presentation text; factory data is in synth_presets.vh.\n',
              f'localparam PRESET_TITLE_BASE=6, PRESET_DETAIL_BASE={6+len(rows)};\n']
    for i,name in enumerate(names):text_rom.append(f'localparam PRESET_TEXT_{name}={6+2*len(rows)+i};\n')
    text_rom += [
              'function [287:0] synth_preset_text; input [5:0] index; begin case(index)\n']
    for index,t in enumerate(texts):
        assert len(t)<=48,t
        bits=sum(chars.index(ch)<<(6*(47-i)) for i,ch in enumerate(t))
        text_rom.append(f"6'd{index}:synth_preset_text=288'h{bits:072X}; // {t}\n")
    text_rom.append('default:synth_preset_text=0;endcase end endfunction\n')
    (ROOT/'rtl/ui_vector_engine/synth_preset_text.vh').write_text(''.join(text_rom),encoding='utf-8')
    # Reserved, versioned custom snapshot interchange contract. No user slots
    # are enabled in hardware and this creates no save/delete functionality.
    limits={3:(0,4),13:(0,4),4:(1,8),14:(1,8),22:(0,4),
            40:(0,11),41:(0,11),42:(0,11),43:(0,11),44:(0,3),46:(0,2)}
    fields=[]
    for i,cc in enumerate(SLOT_CCS):
        lo,hi=limits.get(i,(0,127))
        field={'type':'integer','minimum':lo,'maximum':hi,'description':f'static slot {i}, audio CC{cc}'}
        if i in (2,12,45,50,56,62,69,72):field['enum']=[0,127]
        fields.append(field)
    schema={'$schema':'https://json-schema.org/draft/2020-12/schema',
            'title':'Reserved UI synth snapshot v1','type':'object','additionalProperties':False,
            'required':['schema_version','name','description','values'],
            'properties':{'schema_version':{'const':1},'name':{'type':'string','minLength':1,'maxLength':64},
              'description':{'type':'string','maxLength':160},
              'values':{'type':'array','prefixItems':fields,'items':False,'minItems':74,'maxItems':74}}}
    (ROOT/'doc/SYNTH_CUSTOM_PRESET_SCHEMA_V1.json').write_text(json.dumps(schema,indent=2)+'\n',encoding='utf-8')
    print('PASS: 12 unchanged upstream presets + sampled piano / 962 CC values; pinned base '+REFERENCE)

if __name__=='__main__': main()
