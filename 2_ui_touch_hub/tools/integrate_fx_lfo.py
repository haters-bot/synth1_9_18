"""Checked one-shot R16 integration, retained as an audit of the port migration."""
from pathlib import Path
from generate_mod_targets import TARGETS
ROOT=Path(__file__).resolve().parents[1]
def patch(name,old,new):
    p=ROOT/name;s=p.read_text(encoding='utf-8')
    if old not in s: raise RuntimeError(f'Anchor absent in {name}: {old[:80]}')
    p.write_text(s.replace(old,new),encoding='utf-8')

if __name__=='__main__':
    top='rtl/ui_vector_engine/ui_top_renderer.v'
    patch(top,'    // Observation only; phase/running', '''    // Reserved logical adapter; same clock, one-cycle normalized parameter events.
    input wire external_param_valid,
    input wire [7:0] external_param_id,
    input wire [6:0] external_param_value,
    output wire binding_capture,
    output wire fx_event_valid,
    output wire [7:0] fx_event_id,
    output wire [6:0] fx_event_value,
    output wire route_event_valid,
    output wire [7:0] route_event_target,
    output wire [1:0] route_event_source,
    output wire signed [7:0] route_event_depth,
    // Observation only; phase/running''')
    # Flat snapshot is deliberately independent of physical framing.
    names=['val_macro1','val_macro2','val_macro3','val_macro4','val_master_vol']
    for side in ['a','b']:
        names += [f'val_osc{side}_{n}' for n in ['unison','detune','blend','phase','rand','wt_pos','warp','pan','vol']]
    names += [f'val_flt_{n}' for n in ['cutoff','res','pan','drive','fat','mix']]
    names += [f'val_env_{n}' for n in ['attack','hold','decay','sustain','release']]
    setup='''
    wire [132:0] fx_values;
    wire [8:0] fx_switches;
    wire [105:0] mod_sources;
    wire [423:0] mod_depths;
    wire [370:0] mod_base,mod_preview;
    wire mod_armed,mod_dragging;
    wire [5:0] mod_hover,mod_selected;
    wire [146:0] lfo_all_nodes;
    wire [8:0] lfo_all_rates;
    wire [2:0] lfo_all_steps;
    wire [12:0] lfo_curve_q6;
    wire [8:0] lfo_raster_index=in_pixel_x<832 ? 0 : in_pixel_x>1216 ? 384 : in_pixel_x-832;
    wire hit_fx_strip,hit_mod;
    wire [23:0] fx_strip_rgb,mod_rgb;
'''
    setup+='\n'.join(f'    assign mod_base[{i*7}+:7]={name};' for i,name in enumerate(names))
    setup+='\n    assign mod_base[238+:133]=fx_values;\n'
    setup+='''
    fx_editor_state u_fx_state(.clk(clk),.rst_n(rst_n),
        .touch_valid(ui_touch_valid),.touch_down(ui_touch_down && !binding_capture),
        .touch_x(ui_touch_x),.touch_y(ui_touch_y),
        .external_valid(external_param_valid),.external_id(external_param_id),.external_value(external_param_value),
        .values(fx_values),.switches(fx_switches),
        .event_valid(fx_event_valid),.event_id(fx_event_id),.event_value(fx_event_value));
    lfo_binding_state u_binding(.clk(clk),.rst_n(rst_n),
        .touch_valid(ui_touch_valid),.touch_down(ui_touch_down),.touch_x(ui_touch_x),.touch_y(ui_touch_y),
        .active_tab(lfo_tab),.armed(mod_armed),.dragging(mod_dragging),.capture_active(binding_capture),
        .selected_target(mod_selected),.hover_target(mod_hover),.sources(mod_sources),.depths(mod_depths),
        .event_valid(route_event_valid),.event_target(route_event_target),
        .event_source(route_event_source),.event_depth(route_event_depth));
    modulation_preview u_mod_preview(.clk(clk),.rst_n(rst_n),
        .nodes(lfo_all_nodes),.rates(lfo_all_rates),.stepped(lfo_all_steps),
        .active_tab(lfo_tab),.active_phase(lfo_phase),.raster_index(lfo_raster_index),
        .sources(mod_sources),.depths(mod_depths),.base_values(mod_base),
        .preview_values(mod_preview),.raster_q6(lfo_curve_q6));
    fx_strip_renderer u_fx_strip(.clk(clk),.rst_n(rst_n),.in_x(in_pixel_x),.in_y(in_pixel_y),
        .values(mod_preview[238+:133]),.switches(fx_switches),.out_hit(hit_fx_strip),.out_rgb(fx_strip_rgb));
    modulation_overlay u_mod_overlay(.clk(clk),.rst_n(rst_n),.in_x(in_pixel_x),.in_y(in_pixel_y),
        .sources(mod_sources),.depths(mod_depths),.preview_values(mod_preview),
        .armed(mod_armed),.dragging(mod_dragging),.hover_target(mod_hover),.selected_target(mod_selected),
        .active_tab(lfo_tab),.out_hit(hit_mod),.out_rgb(mod_rgb));
'''
    patch(top,'    // A. Procedural Knobs (32 rotary knobs)',setup+'\n    // A. Procedural Knobs (32 rotary knobs)')
    p=ROOT/top;s=p.read_text();start=s.index('    knob_vector_unit u_knobs');end=s.index('    // B. Procedural',start)
    b=s[start:end]
    import re
    for i,name in enumerate(names):
        b=re.sub(r'(\.'+name+r'\s*\()'+name+r'(\))',rf'\g<1>mod_preview[{i*7}+:7]\2',b)
    s=s[:start]+b+s[end:];p.write_text(s)
    patch(top,'        .phase(lfo_phase), .running(lfo_running)\n',
          '        .all_nodes(lfo_all_nodes),.all_rates(lfo_all_rates),.all_stepped(lfo_all_steps),\n        .phase(lfo_phase), .running(lfo_running)\n')
    patch(top,'.touch_valid(ui_touch_valid), .touch_down(ui_touch_down),',
          '.touch_valid(ui_touch_valid), .touch_down(ui_touch_down && !binding_capture),')
    patch(top,'.phase(lfo_phase), .running(lfo_running), .out_hit(hit_fx)',
          '.curve_q6(lfo_curve_q6), .phase(lfo_phase), .running(lfo_running), .out_hit(hit_fx)')
    # New layers precede all older controls.
    patch(top,'        end else if (hit_curve_hint) begin','        end else if(hit_mod) begin pixel_mux=mod_rgb;\n        end else if(hit_fx_strip) begin pixel_mux=fx_strip_rgb;\n        end else if (hit_curve_hint) begin')
    patch('rtl/ui_vector_engine/lfo_panel_renderer.v','    input wire running,','    input wire running,\n    input wire [12:0] curve_q6,')
    patch('rtl/ui_vector_engine/lfo_panel_renderer.v','    wire [13:0] curve_y = 14\'d543-interpolated[6:0];',
          "    reg [12:0] amplitude0,amplitude1;\n    wire [13:0] curve_y = 14'd543-amplitude1[12:6];")
    patch('rtl/ui_vector_engine/lfo_panel_renderer.v',"wire signed [16:0] curve_y_q6=17'sd34752-interpolated_q6;",
          "wire signed [16:0] curve_y_q6=17'sd34752-$signed({4'd0,amplitude1});")
    patch('rtl/ui_vector_engine/lfo_panel_renderer.v','        x0<=in_x; y0<=in_y;',
          '        amplitude0<=curve_q6;amplitude1<=amplitude0;\n        x0<=in_x; y0<=in_y;')
    # Compact ENV forward geometry and inverse picking use the same new dimensions.
    patch('rtl/ui_vector_engine/curve_hint_renderer.v',"in_x>=36 && in_x<", "in_x>=36 && in_x<") if False else None
    fp='rtl/ui_touch_hub_top.v'
    patch(fp,'    wire ui_touch_valid, ui_touch_down;', '''    wire binding_capture;
    wire fx_event_valid,route_event_valid;
    wire [7:0] fx_event_id,route_event_target;
    wire [6:0] fx_event_value;
    wire [1:0] route_event_source;
    wire signed [7:0] route_event_depth;
    wire ui_touch_valid, ui_touch_down;''')
    patch(fp,'.curve_capture_active(curve_capture)', '.curve_capture_active(curve_capture | binding_capture)')
    # First-contact capture in each editor prevents cross-panel drag leakage.
    patch(fp,'.touch_valid(ui_touch_valid),.touch_down(ui_touch_down),.touch_x(ui_touch_x),.touch_y(ui_touch_y),',
          '.touch_valid(ui_touch_valid),.touch_down(ui_touch_down && !binding_capture),.touch_x(ui_touch_x),.touch_y(ui_touch_y),')
    patch(fp,'    ui_top_renderer u_render (', '''    ui_top_renderer u_render (
        .external_param_valid(spi_param_valid),.external_param_id(spi_param_id),.external_param_value(spi_param_val),
        .binding_capture(binding_capture),
        .fx_event_valid(fx_event_valid),.fx_event_id(fx_event_id),.fx_event_value(fx_event_value),
        .route_event_valid(route_event_valid),.route_event_target(route_event_target),
        .route_event_source(route_event_source),.route_event_depth(route_event_depth),''')
    project='2_ui_touch_hub.gprj'
    mods=['fx_editor_state.v','fx_strip_renderer.v','lfo_smooth_table.v','lfo_binding_state.v','modulation_preview.v','modulation_overlay.v']
    patch(project,'        <File path="rtl/ui_vector_engine/lfo_editor_state.v"',
          ''.join(f'        <File path="rtl/ui_vector_engine/{n}" type="file.verilog" enable="1"/>\n' for n in mods)+'        <File path="rtl/ui_vector_engine/lfo_editor_state.v"')
    preview='tools/render_rtl_preview.py'
    patch(preview,"'lfo_editor_state.v', 'lfo_panel_renderer.v',",', '.join(repr(n) for n in mods)+", 'lfo_editor_state.v', 'lfo_panel_renderer.v',")
    # Independent mathematical reference: cubic Hermite with minmod tangents.
    patch(preview,'integer lfo_x, lfo_segment,', 'integer mm0,mm1,pbefore,pafter,da,db,c1,c2,c3,ref_h;\ninteger lfo_x, lfo_segment,')
    old='''        lfo_expected=dut.lfo_stepped && lfo_fraction!=64 ? lfo_a :
            ((64-lfo_fraction)*lfo_a+lfo_fraction*lfo_b)/64;'''
    new='''        pbefore=lfo_segment==0 ? lfo_a : (dut.lfo_nodes>>((lfo_segment-1)*7))&127;
        pafter=lfo_segment==5 ? lfo_b : (dut.lfo_nodes>>((lfo_segment+2)*7))&127;
        da=lfo_a-pbefore;db=lfo_b-lfo_a;
        mm0=lfo_segment==0 || da*db<=0 ? 0 : da>0 ? (da<db ? da:db) : (da>db ? da:db);
        da=lfo_b-lfo_a;db=pafter-lfo_b;
        mm1=lfo_segment==5 || da*db<=0 ? 0 : da>0 ? (da<db ? da:db) : (da>db ? da:db);
        c1=mm0;c2=3*(lfo_b-lfo_a)-2*mm0-mm1;c3=-2*(lfo_b-lfo_a)+mm0+mm1;
        ref_h=c3*lfo_fraction+c2*64;
        ref_h=(ref_h>>>6)*lfo_fraction+c1*64;
        ref_h=(ref_h>>>6)*lfo_fraction+lfo_a*64;
        if(dut.lfo_stepped && lfo_fraction!=64) ref_h=lfo_a*64;
        lfo_expected=ref_h>>6;'''
    patch(preview,old,new)
    patch(preview,'''        lfo_expected_q2=dut.lfo_stepped && lfo_fraction!=64 ? (543-lfo_a)*4 :
            (543*64-(lfo_a*64+(lfo_b-lfo_a)*lfo_fraction))/16;''',
          '        lfo_expected_q2=(543*64-ref_h)/16;')
