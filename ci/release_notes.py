"""Бележки към версията за Firebase App Distribution от assets/whats_new.json
(същият текст, който тестерите виждат в камбанката на приложението)."""
import json
import pathlib
import sys

build = sys.argv[1] if len(sys.argv) > 1 else ""
notes = json.loads((pathlib.Path(__file__).parent.parent / "assets/whats_new.json").read_text(encoding="utf-8"))
lines = [f"Тестова версия {build} · {notes.get('date', '')}".strip(" ·"), "", "ДОБАВЕНО"]
lines += [f"• {a}" for a in notes.get("added", [])]
lines += ["", "КАКВО ДА ТЕСТВАТЕ"]
lines += [f"{i}. {t}" for i, t in enumerate(notes.get("test", []), 1)]
print("\n".join(lines))
