#!/usr/bin/env python3

from pathlib import Path
import runpy


root = Path(__file__).resolve().parent.parent
source = root / "bin" / "todo"
module = runpy.run_path(str(source))

display_width = module["display_width"]
truncate = module["truncate"]
DemoClient = module["DemoClient"]
TodoApp = module["TodoApp"]

assert display_width("abc") == 3
assert display_width("工作") == 4
assert display_width("a工") == 3
assert display_width(truncate("这是一个很长的标题", 7)) <= 7

client = DemoClient()
snapshot = client.snapshot()
assert [item["name"] for item in snapshot["lists"]] == ["工作", "个人", "购物"]

created = client.request(
    {
        "action": "create",
        "list_id": "personal",
        "title": "新任务",
        "notes": "测试",
        "due": None,
        "priority": 0,
    }
)
assert created["ok"] is True
task = next(item for item in client.tasks if item["title"] == "新任务")
client.request({"action": "update", "id": task["id"], "list_id": "work", "title": "已移动"})
assert task["list_id"] == "work"
client.request({"action": "complete", "id": task["id"], "completed": True})
assert task["completed"] is True
client.request({"action": "delete", "id": task["id"]})
assert all(item["id"] != task["id"] for item in client.tasks)

assert TodoApp.SMART_VIEWS == (
    ("today", "今天"),
    ("scheduled", "已计划"),
    ("all", "全部"),
    ("completed", "已完成"),
)
text = source.read_text(encoding="utf-8")
for glyph in "╭╮╰╯│─":
    assert glyph in text
assert "curses.COLOR_MAGENTA" in text
assert "curses.ALL_MOUSE_EVENTS" in text

print("todo TUI tests passed")
