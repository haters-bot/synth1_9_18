"""产生独立分数Hermite参考向量，固定随机种子，写入忽略目录tmp。"""
from pathlib import Path
from fractions import Fraction
import random
from lfo_v2_protocol import PRESETS

def main():
    rng=random.Random(728)
    curves=list(PRESETS)+[(0,)*7,(127,)*7,(0,127,0,127,0,127,0),(127,0,127,0,127,0,127),(3,5,127,12,74,1,82)]
    curves += [tuple(rng.randrange(128) for _ in range(7)) for _ in range(24)]
    nodes=[]; values=[]
    for p in curves:
        for stepped in (False,True):
            nodes.append((int(stepped)<<49)|sum(v<<(7*n) for n,v in enumerate(p)))
            for phase in range(385):
                s=min(phase//64,5); t=Fraction(phase-s*64,64)
                if phase==384: y=Fraction(p[6])
                elif stepped: y=Fraction(p[s])
                else:
                    def mm(x,y): return (1 if x>0 else -1)*min(abs(x),abs(y)) if x*y>0 else 0
                    dm=p[s+1]-p[s]
                    m0=mm(p[s]-p[s-1],dm) if s else 0
                    m1=mm(dm,p[s+2]-p[s+1]) if s<5 else 0
                    y=(2*t**3-3*t**2+1)*p[s]+(t**3-2*t**2+t)*m0+(-2*t**3+3*t**2)*p[s+1]+(t**3-t**2)*m1
                values.append(max(0,min(8128,int(y*64))))
    dest=Path(__file__).resolve().parents[1]/'tmp'; dest.mkdir(exist_ok=True)
    (dest/'lfo_v2_nodes.hex').write_text(''.join(f'{v:013x}\n' for v in nodes),encoding='ascii')
    (dest/'lfo_v2_expected.hex').write_text(''.join(f'{v:04x}\n' for v in values),encoding='ascii')
    print(f'{len(nodes)} curves, {len(values)} exact Q6 vectors, seed=728')
if __name__=='__main__': main()
