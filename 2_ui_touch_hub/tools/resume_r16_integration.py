"""Resume the checked migration after its initially unmatched compositor anchor."""
from pathlib import Path
import integrate_fx_lfo as migration
s=Path(migration.__file__).read_text()
start=s.index("    patch(top,'        end else if (hit_curve_hint)")
exec(compile('if True:\n'+s[start:],migration.__file__,'exec'),dict(vars(migration),top='rtl/ui_vector_engine/ui_top_renderer.v'))
