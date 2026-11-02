"""Append two phase-aligned piano tables to an existing WTB1 without replacing it.

Input is a permitted University of Iowa Steinway B recording, not a Serum table.
Each table is 256 periodic frames of 256 signed little-endian 16-bit samples.
The existing ten table payloads are copied byte-for-byte. No audio RTL changes.
"""
from pathlib import Path
import argparse, hashlib, json, math, struct, wave
import numpy as np
from scipy.signal import correlate, find_peaks

SOURCE_URL='https://theremin.music.uiowa.edu/sound%20files/MIS/Piano_Other/piano/Piano.mf.C4.aiff'
PERMISSION_URL='https://theremin.music.uiowa.edu/MIS.html'
SOURCE_SHA256='1a7d8ddea94a3639fa58d79ebcc0b09b170b9c324811d2b705f97e278fdefac2'

def read_aiff(path):
 b=path.read_bytes();assert b[:4]==b'FORM' and b[8:12]==b'AIFF'
 at=12;comm=None;audio=None
 while at+8<=len(b):
  name=b[at:at+4];size=int.from_bytes(b[at+4:at+8],'big');chunk=b[at+8:at+8+size]
  if name==b'COMM':comm=chunk
  if name==b'SSND':audio=chunk
  at+=8+size+(size&1)
 assert comm is not None and audio is not None
 channels,frames,bits=struct.unpack_from('>hIh',comm)
 exponent=int.from_bytes(comm[8:10],'big');mantissa=int.from_bytes(comm[10:18],'big')
 rate=math.ldexp(mantissa,(exponent&0x7fff)-16383-63)
 assert bits==16 and channels in (1,2) and 40000<rate<100000
 offset=int.from_bytes(audio[:4],'big');raw=audio[8+offset:]
 samples=np.frombuffer(raw,dtype='>i2').reshape(-1,channels).astype(np.float64)/32768
 assert len(samples)==frames
 # Retain the first microphone rather than averaging potentially delayed mics.
 return samples[:,0],float(rate),channels

def estimate_pitch(samples,rate,onset):
 x=samples[onset+int(.12*rate):onset+int(.50*rate)];x=x-np.mean(x)
 ac=correlate(x,x,mode='full',method='fft')[len(x)-1:]
 lo=int(rate/280);hi=int(rate/245);lag=lo+np.argmax(ac[lo:hi+1])
 a,b,c=ac[lag-1:lag+2];lag=lag+.5*(a-c)/(a-2*b+c)
 return rate/lag

def extract(samples,rate,onset,f0,times,attack=False):
 count=int(round(12*rate/f0));h=np.arange(1,61)
 phase=np.arange(256)/256;basis=np.exp(2j*np.pi*h[:,None]*phase)
 frames=[];energies=[]
 for seconds in times:
  start=onset+int(seconds*rate);seg=samples[start:start+count]
  assert len(seg)==count
  seg=seg-np.mean(seg);win=np.hanning(count)
  t=(start-onset+np.arange(count))/rate
  coeff=2*(np.exp(-2j*np.pi*h[:,None]*f0*t)*(seg*win)[None,:]).sum(axis=1)/win.sum()
  # All frames share fundamental phase before frame interpolation.
  coeff*=np.exp(-1j*h*np.angle(coeff[0]))
  if attack:coeff*=np.minimum(1.0,(h/4.0)**2)
  frame=np.real(coeff@basis);frame-=frame.mean()
  frames.append(frame);energies.append(float(np.sqrt(np.mean(frame**2))))
 frames=np.asarray(frames);peak=float(abs(frames).max());assert peak>1e-5
 pcm=np.rint(frames*(.90/peak)*32767).astype('<i2')
 assert pcm.shape==(256,256) and np.isfinite(frames).all()
 return pcm,{'unscaled_peak':peak,'rms_min':min(energies),'rms_max':max(energies),'normalized_peak':int(abs(pcm.astype(np.int32)).max())}

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--base',type=Path,required=True);p.add_argument('--sample',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True)
 a=p.parse_args();a.output_dir.mkdir(parents=True,exist_ok=True)
 old=a.base.read_bytes()
 assert old[:6]==b'WTB1\x01\x0a' and len(old)==32+10*131072
 assert old[6:12]==b'\x00\x01\x00\x01\x10\x01' and not any(old[12:32])
 assert hashlib.sha256(a.sample.read_bytes()).hexdigest()==SOURCE_SHA256,'Source recording does not match the attributed file'
 sample,rate,channels=read_aiff(a.sample)
 power=np.convolve(sample**2,np.ones(128)/128,mode='same')
 onset=int(np.flatnonzero(power>power.max()*0.012)[0]);f0=estimate_pitch(sample,rate,onset)
 assert 245<f0<280,('Unexpected source pitch',f0)
 body,binfo=extract(sample,rate,onset,f0,np.geomspace(.025,1.5,256))
 attack,ainfo=extract(sample,rate,onset,f0,np.linspace(.001,.10,256),True)
 header=bytearray(old[:32]);header[5]=12
 result=bytes(header)+old[32:]+body.tobytes()+attack.tobytes()
 target=a.output_dir/'WAVEBANK.WTB';assert not target.exists(),'Never overwrite a delivered bank'
 target.write_bytes(result)
 assert result[32:32+10*131072]==old[32:]
 for name,pcm in [('PianoBody',body),('PianoAttack',attack)]:
  with wave.open(str(a.output_dir/(name+'.wav')),'wb') as w:
   w.setnchannels(1);w.setsampwidth(2);w.setframerate(44100);w.writeframes(pcm.tobytes())
 metadata={'format':'WTB1','table_count':12,'bytes':len(result),'sha256':hashlib.sha256(result).hexdigest(),
 'base_sha256':hashlib.sha256(old).hexdigest(),'original_tables_0_to_9_unchanged':True,
 'source':{'url':SOURCE_URL,'permission_url':PERMISSION_URL,'attribution':'University of Iowa Electronic Music Studios / Lawrence Fritts; Steinway and Sons Model B',
 'sha256':hashlib.sha256(a.sample.read_bytes()).hexdigest(),'sample_rate':rate,'channels':channels,'selected_microphone':0,'estimated_f0_hz':f0,'onset_sample':onset},
 'extraction':{'method':'Hann-windowed 12-cycle synchronous harmonic analysis; common fundamental phase; 60 harmonics; zero DC',
 'body_times_seconds':[.025,1.5],'attack_times_seconds':[.001,.10],'frame_axis':'brightness/timbre axis; NOT automatic per-note time playback',
 'limitations':'Periodic sample-derived synthesis; does not reproduce full multi-key/velocity piano sampling or nonperiodic hammer/resonance'},
 'new_tables':[{'index':10,'name':'Sampled Piano Body',**binfo},{'index':11,'name':'Sampled Piano Bright Attack',**ainfo}]}
 (a.output_dir/'bank_manifest.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'path':str(target),'bytes':len(result),'f0_hz':f0,'old_tables_preserved':True,'sha256':metadata['sha256']},indent=2),flush=True)

if __name__=='__main__':main()
