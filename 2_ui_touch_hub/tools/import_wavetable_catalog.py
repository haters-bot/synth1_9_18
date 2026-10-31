"""Verify WTB1 and import its catalog and compact local display preview.

WTB1 contains no names. Keep honest numbered table IDs; never infer names from
the waveform. Re-run this after replacing the bank on the audio board's SD card.
"""
from pathlib import Path
import argparse,hashlib,json,struct
ROOT=Path(__file__).resolve().parents[1]
def import_catalog(path, root=ROOT):
 data=path.read_bytes()
 if len(data)<32 or data[:4]!=b'WTB1' or data[4]!=1:raise ValueError('Not a version1 WTB bank')
 count=data[5];frames,samples=struct.unpack_from('<HH',data,6)
 if not 1<=count<=16 or frames!=256 or samples!=256 or data[10:12]!=b'\x10\x01':raise ValueError('Unsupported WTB dimensions/PCM format')
 if any(data[12:32]) or len(data)!=32+count*131072:raise ValueError('Reserved header/length mismatch')
 sha=hashlib.sha256(data).hexdigest()
 metadata={'format':'WTB1','count':count,'frames_per_table':frames,'samples_per_frame':samples,
  'sample_bits':16,'endian':'little','names_in_file':False,'bytes':len(data),'sha256':sha,'tables':[]}
 for i in range(count):
  payload=data[32+i*131072:32+(i+1)*131072];v=struct.unpack('<65536h',payload)
  metadata['tables'].append({'index':i,'label':f'SD {i:02d}','sha256':hashlib.sha256(payload).hexdigest(),'min':min(v),'max':max(v)})
 # Sixteen evenly spaced source frames, 128 phase samples, signed 8-bit PCM.
 # The renderer interpolates the frame axis. This is a compact LOCAL preview,
 # not SD load status or the post-WARP/post-FX signal from the audio board.
 preview=['// Generated LOCAL preview from WTB1. Do not edit.',f'// Source SHA256 {sha}',
          '// 16 frame anchors (0,17,...,255), 128 phase samples (0,2,...,254).']
 for bank in range(count):
  for frame in range(16):
   for phase in range(128):
    value=struct.unpack_from('<h',data,32+bank*131072+(frame*17*256+phase*2)*2)[0] >> 8
    preview.append(f'preview_rom[{bank*2048+frame*128+phase}]=8\'h{value&255:02X};')
 preview_text='\n'.join(preview)+'\n'
 mapping=['// MIDI 0..127 to 16 local frame anchors, 7-bit interpolation fraction.',
          'function [10:0] preview_mix; input [6:0] position; begin case(position)']
 for position in range(128):
  frame,remainder=divmod(position*15,127)
  mapping.append(f"7'd{position}:preview_mix=11'h{((frame<<7)+(remainder*128//127)):03X};")
 mapping.append("default:preview_mix=0; endcase end endfunction")
 mapping_text='\n'.join(mapping)+'\n'
 metadata['preview']={'kind':'local_source_bank','frames':16,'phase_samples':128,'sample_bits':8,
                      'rom_bytes':count*2048,'frame_interpolation':True,
                      'canonical_lf_sha256':hashlib.sha256(preview_text.encode('ascii')).hexdigest()}
 (root/'rtl/ui_vector_engine/wavetable_catalog.vh').write_text('// Generated from audio WAVEBANK.WTB; no names in WTB1.\n'
  f'// SHA256 {sha}\n`ifndef UI_WAVETABLE_CATALOG_VH\n`define UI_WAVETABLE_CATALOG_VH\n`define UI_WAVETABLE_COUNT {count}\n`endif\n')
 (root/'rtl/ui_vector_engine/wavetable_preview_data.vh').write_text(preview_text,encoding='ascii')
 (root/'rtl/ui_vector_engine/wavetable_preview_map.vh').write_text(mapping_text,encoding='ascii')
 (root/'doc/WAVETABLE_CATALOG_2026-10-31.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'count':count,'sha256':sha,'names_in_file':False}))
 return metadata
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('bank',type=Path);import_catalog(p.parse_args().bank)
