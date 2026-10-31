"""Verify the audio WTB1 bank and import its count/hash, without changing audio.

WTB1 contains no names. Keep honest numbered table IDs; never infer names from
the waveform. Re-run this after replacing the bank on the audio board's SD card.
"""
from pathlib import Path
import argparse,hashlib,json,struct
ROOT=Path(__file__).resolve().parents[1]
def import_catalog(path):
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
 (ROOT/'rtl/ui_vector_engine/wavetable_catalog.vh').write_text('// Generated from audio WAVEBANK.WTB; no names in WTB1.\n'
  f'// SHA256 {sha}\n`ifndef UI_WAVETABLE_CATALOG_VH\n`define UI_WAVETABLE_CATALOG_VH\n`define UI_WAVETABLE_COUNT {count}\n`endif\n')
 (ROOT/'doc/WAVETABLE_CATALOG_2026-10-31.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'count':count,'sha256':sha,'names_in_file':False}))
 return metadata
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('bank',type=Path);import_catalog(p.parse_args().bank)
