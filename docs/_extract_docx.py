import re
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

W_NS = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
path = Path(r"d:\Downloads\rozd4_hikora (1).docx")
out_path = Path(__file__).parent / "_rozd4_text.txt"

with zipfile.ZipFile(path) as z:
    xml = z.read("word/document.xml")

root = ET.fromstring(xml)
lines = []
for p in root.iter(f"{W_NS}p"):
    parts = []
    for node in p.iter():
        if node.tag == f"{W_NS}t" and node.text:
            parts.append(node.text)
        if node.tag == f"{W_NS}t" and node.tail:
            parts.append(node.tail)
    line = "".join(parts).strip()
    if line:
        lines.append(line)

out_path.write_text("\n".join(lines), encoding="utf-8")
print(f"Wrote {len(lines)} lines to {out_path}")
