"""One-shot checked migration for the R16 ENV geometry (retained for audit)."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def change(name, pairs):
    p = ROOT/name
    s = p.read_text(encoding='utf-8')
    for a,b in pairs:
        if a not in s:
            raise RuntimeError(f'Missing migration anchor: {name}: {a}')
        s = s.replace(a,b)
    p.write_text(s, encoding='utf-8')

if __name__ == '__main__':
    change('rtl/ui_vector_engine/params.vh', [
        ('ENV_PANEL_X1          14\'d780', 'ENV_PANEL_X1          14\'d402'),
        ('ENV_WIN_X1            14\'d768', 'ENV_WIN_X1            14\'d390'),
        ("16'd20+(({9'd0,v}*16'd130)", "16'd10+(({9'd0,v}*16'd65)"),
        ("({9'd0,v}*16'd60)", "({9'd0,v}*16'd30)"),
        ("16'd24+(({9'd0,v}*16'd160)", "16'd12+(({9'd0,v}*16'd80)"),
    ])
    change('rtl/ui_vector_engine/env_panel_renderer.v', [("len_s = 14'd120", "len_s = 14'd60")])
    p=ROOT/'rtl/ui_vector_engine/knob_vector_unit.v'
    s=p.read_text(); start=s.index('// Envelope 1 (Attack'); end=s.index('// Master FX & Voicing',start)
    block=s[start:end]
    for old,new in [(100,64),(230,130),(360,196),(490,262),(620,328)]:
        for a,b in [(old-30,new-30),(old,new),(old+30,new+30)]:
            block=block.replace(f"14'd{a}",f"14'd{b}")
    s=s[:start]+block+s[end:];p.write_text(s)
    p=ROOT/'rtl/touch_intake/touch_event_router.v';s=p.read_text()
    start=s.index('// Envelope 1\n',s.index('// --- ROW 3'));end=s.index('// Master FX',start)
    block=s[start:end]
    for old,new in [(100,64),(230,130),(360,196),(490,262),(620,328)]:
        block=block.replace(f"14'd{old}",f"14'd{new}")
    # Narrow the lower row hit cells to prevent overlap between adjacent knobs.
    block=block.replace('dy_r3)',"dy_r3) && s0_tx >= 14'd34 && s0_tx <= 14'd358")
    s=s[:start]+block+s[end:]
    # The dedicated FX controller owns the entire middle column.
    s=s.replace("if (s0_tx >= 14'd796 && s0_tx <= 14'd1256 &&", "if (s0_tx >= 14'd420 && s0_tx <= 14'd1256 &&")
    # Use non-overlapping cells for the five ENV knobs rather than the old 84px boxes.
    import re
    for center in [64,130,196,262,328]:
        s=s.replace(f"is_knob_x_hit(s0_tx, 14'd{center}, dy_r3)",
                    f"(s0_tx >= 14'd{center-30} && s0_tx <= 14'd{center+30})")
    p.write_text(s)
    change('rtl/touch_intake/curve_touch_editor.v', [
        ("10'd156+la0", "10'd96+la0"),
        ("130:reciprocal=18'd64528;60:reciprocal=18'd139810;", "65:reciprocal=19'd129056;30:reciprocal=19'd279620;"),
        ("160:reciprocal=18'd52429", "80:reciprocal=19'd104858"),
        ("reg [17:0] reciprocal", "reg [18:0] reciprocal"),
        ("pixel_value(p0,130)","pixel_value(p0,65)"),
        ("pixel_value(p1,60)","pixel_value(p1,30)"),
        ("pixel_value(p2,160)","pixel_value(p2,80)"),
        ("pixel_value(p4,160)","pixel_value(p4,80)"),
        ("base_a*18'd130", "base_a*18'd65"),
        ("base_h*18'd60", "base_h*18'd30"),
        ("base_d*18'd160", "base_d*18'd80"),
        ("base_r*18'd160", "base_r*18'd80"),
    ])
