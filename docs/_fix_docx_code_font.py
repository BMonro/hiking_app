"""Increase font size for code blocks in rozdim 4 docx."""
from pathlib import Path

from docx import Document
from docx.shared import Pt

# Main text is usually 14 pt; code was often 9–10 pt — raise for readability.
CODE_FONT_PT = 12
CODE_FONTS = {"Consolas", "Courier New", "Courier", "Lucida Console", "Cascadia Mono"}

# Heuristic: paragraphs that look like source code (no Consolas style set).
CODE_MARKERS = (
    "await ",
    "async ",
    "Future<",
    "final ",
    "return ",
    "redirect:",
    "query =",
    "Stream<",
    "OAuthProvider",
    "body: {",
    "functions.invoke",
)


def looks_like_code(text: str) -> bool:
    t = text.strip()
    if len(t) < 12:
        return False
    if any(m in t for m in CODE_MARKERS):
        return True
    if t.startswith(("}", "{", ");", "});")):
        return True
    return False


def patch_docx(path: Path, out: Path | None = None) -> tuple[int, int]:
    doc = Document(str(path))
    runs_changed = 0
    paras_changed = 0

    for para in doc.paragraphs:
        para_touched = False
        full = para.text
        use_heuristic = looks_like_code(full)

        for run in para.runs:
            if not run.text.strip():
                continue
            name = (run.font.name or "").strip()
            size = run.font.size
            size_pt = size.pt if size is not None else None

            is_code_font = name in CODE_FONTS
            is_small = size_pt is not None and size_pt < CODE_FONT_PT
            is_code = is_code_font or (use_heuristic and (is_small or size_pt is None))

            if is_code:
                run.font.name = name or "Consolas"
                run.font.size = Pt(CODE_FONT_PT)
                runs_changed += 1
                para_touched = True

        if para_touched:
            paras_changed += 1

    target = out or path
    doc.save(str(target))
    return runs_changed, paras_changed


if __name__ == "__main__":
    src = Path(r"d:\Downloads\rozd4_hikora (5).docx")
    if not src.exists():
        src = Path(r"d:\Downloads\rozd4_hikora_vypravleno.docx")
    out = src.with_name(src.stem + "_code12pt.docx")
    n_runs, n_paras = patch_docx(src, out)
    print(f"Source: {src}")
    print(f"Saved:  {out}")
    print(f"Runs: {n_runs}, paragraphs: {n_paras}, code font: {CODE_FONT_PT} pt")
