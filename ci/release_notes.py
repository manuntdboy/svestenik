"""Бележки към версията за Firebase App Distribution от assets/whats_new.json
(същият текст, който тестерите виждат в камбанката на приложението)."""
import json
import pathlib
import sys

build = sys.argv[1] if len(sys.argv) > 1 else ""
creator = "--creator" in sys.argv
notes = json.loads((pathlib.Path(__file__).parent.parent / "assets/whats_new.json").read_text(encoding="utf-8"))
title = "Тестова версия"
lines = [f"{title} {build} · {notes.get('date', '')}".strip(" ·"), "", "ДОБАВЕНО"]
lines += [f"• {a}" for a in (notes.get("creator", []) if creator else []) + notes.get("added", [])]
lines += ["", "КАКВО ДА ТЕСТВАТЕ"]
lines += [f"{i}. {t}" for i, t in enumerate((notes.get("creator_test", []) if creator else []) + notes.get("test", []), 1)]
print("\n".join(lines))
