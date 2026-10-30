"""触屏LFO V2目标定义、Q7.6参考模型及7位安全SysEx编码。"""
RATES_HZ = (0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0)
PRESETS = ((0,42,85,127,85,42,0), (0,21,42,64,85,106,127), (127,127,127,0,0,0,0))
TARGET_NAMES = (
    "Macro 1", "Macro 2", "Macro 3", "Macro 4", "Master Level",
    "OSC A Unison", "OSC A Detune", "OSC A Blend", "OSC A Phase", "OSC A Rand",
    "OSC A WT Position", "OSC A Warp Amount", "OSC A Pan", "OSC A Level",
    "OSC B Unison", "OSC B Detune", "OSC B Blend", "OSC B Phase", "OSC B Rand",
    "OSC B WT Position", "OSC B Warp Amount", "OSC B Pan", "OSC B Level",
    "Filter Cutoff", "Filter Resonance", "Filter Pan", "Filter Drive", "Filter Fat", "Filter Mix",
    "ENV1 Attack", "ENV1 Hold", "ENV1 Decay", "ENV1 Sustain", "ENV1 Release",
    "Delay Feedback", "Delay Left Time", "Delay Right Time", "Delay Filter Freq", "Delay Filter Q", "Delay Mix",
    "Reverb Size", "Reverb Decay", "Reverb Low Cut", "Reverb High Cut", "Reverb Spin", "Reverb Depth", "Reverb Mix",
    "EQ Low Freq", "EQ Low Q", "EQ Low Gain", "EQ High Freq", "EQ High Q", "EQ High Gain",
)
# 单声道Delay的Left对应现有Time，Right预留。无对应的目标不伪造音频效果。
TARGET_CCS = {4:48,6:22,8:87,9:88,10:20,11:39,12:91,13:46,
              15:30,17:89,18:90,19:28,20:41,21:92,22:47,
              23:43,24:44,28:45,34:53,35:52,39:54,40:55,41:56,46:57}

def sysex(parameter_id, value):
    if not 0 <= parameter_id <= 127 or not 0 <= value <= 0x3FFF:
        raise ValueError("SysEx ID必须为7位，value必须为14位")
    return bytes((0xF0,0x7D,parameter_id,value>>7,value&127,0xF7))

def pack_route(source, depth):
    if not 0 <= source <= 3 or not -127 <= depth <= 127:
        raise ValueError("source=0..3，depth=-127..127")
    return (source<<8)|(depth&255)

def minmod(a,b):
    if not a or not b or (a<0)!=(b<0): return 0
    return a if abs(a)<abs(b) else b

def value_q6(points, phase, stepped=False):
    """0..384档，整数Horner，最终向下截断；与UI RTL的Q6语义一致。"""
    if len(points)!=7 or any(not 0<=p<=127 for p in points) or not 0<=phase<=384:
        raise ValueError("需要7个0..127节点，phase=0..384")
    if phase==384: return points[6]<<6
    s,t=divmod(phase,64); y=points[s]
    if stepped: return y<<6
    dm=points[s+1]-y
    m0=minmod(y-points[s-1],dm) if s else 0
    m1=minmod(dm,points[s+2]-points[s+1]) if s<5 else 0
    c1,c2,c3=m0,3*dm-2*m0-m1,-2*dm+m0+m1
    raw=(((c3*t+(c2<<6))*t+(c1<<12))*t+(y<<18))>>12
    return max(0,min(8128,raw))

def modulate(base, source, depth, wave):
    return max(0,min(127,base+((depth*wave)>>7))) if source else base

def configuration_fields(curves,modes,routes):
    if len(curves)!=3 or len(modes)!=3 or len(routes)!=53:
        raise ValueError("V2固定3个LFO、53个目标")
    result={}
    for bank,points in enumerate(curves):
        if len(points)!=7 or any(not 0<=p<=127 for p in points):
            raise ValueError("每条曲线需要7个7位节点")
        for n,point in enumerate(points): result[48+bank*7+n]=point
        rate,stepped,once=modes[bank]
        if not 0<=rate<=7: raise ValueError("速率档位=0..7")
        result[69+bank]=rate|(int(stepped)<<3)|(int(once)<<4)
    for idx,(source,depth) in enumerate(routes): result[73+idx]=pack_route(source,depth)
    return result
