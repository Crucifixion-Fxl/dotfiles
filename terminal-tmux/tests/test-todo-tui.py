#!/usr/bin/env python3

from pathlib import Path
import runpy
from types import SimpleNamespace
from unittest.mock import patch


root = Path(__file__).resolve().parent.parent
source = root / "bin" / "todo"
module = runpy.run_path(str(source))

display_width = module["display_width"]
truncate = module["truncate"]
DemoClient = module["DemoClient"]
PyiCloudClient = module["PyiCloudClient"]
TodoApp = module["TodoApp"]
authenticated_account = module["authenticated_account"]

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


class FakePyiCloudClient(PyiCloudClient):
    def __init__(self):
        super().__init__("/fake/icloud", "user@example.com")
        self.commands = []

    def _run(self, *arguments):
        self.commands.append(arguments)
        if arguments == ("sync-cursor",):
            return {"sync_cursor": "cursor-1"}
        if arguments == ("lists",):
            return [{"id": "List/WORK", "title": "工作"}]
        if arguments[:2] == ("list", "--include-completed"):
            return [
                {
                    "id": "Reminder/A",
                    "list_id": "List/WORK",
                    "title": "检查服务器",
                    "desc": "生产环境",
                    "due_date": "2026-08-02T09:00:00+08:00",
                    "all_day": False,
                    "priority": 1,
                    "completed": False,
                    "deleted": False,
                }
            ]
        if arguments[0] == "changes":
            return []
        if arguments[0] == "delete":
            return {"reminder_id": arguments[1], "deleted": True}
        row = {
            "id": "Reminder/A",
            "list_id": "List/WORK",
            "title": "检查服务器",
            "desc": "生产环境",
            "due_date": None,
            "all_day": False,
            "priority": 0,
            "completed": arguments[0] == "set-status",
        }
        return row


pyicloud = FakePyiCloudClient()
pyicloud_snapshot = pyicloud.snapshot()
assert pyicloud_snapshot["lists"] == [{"id": "List/WORK", "name": "工作"}]
assert pyicloud_snapshot["tasks"][0]["notes"] == "生产环境"
assert pyicloud.commands[:3] == [
    ("sync-cursor",),
    ("lists",),
    ("list", "--include-completed", "--limit", "10000"),
]
pyicloud.snapshot()
assert pyicloud.commands[-1] == (
    "changes",
    "--since",
    "cursor-1",
    "--limit",
    "10000",
)
pyicloud.request(
    {
        "action": "update",
        "id": "Reminder/A",
        "list_id": "List/WORK",
        "title": "检查生产服务器",
        "notes": "",
        "due": "",
        "all_day": False,
        "priority": 0,
    }
)
assert pyicloud.commands[-1][-1] == "--clear-due-date"
pyicloud.request({"action": "complete", "id": "Reminder/A", "completed": False})
assert pyicloud.commands[-1] == (
    "set-status",
    "Reminder/A",
    "--not-completed",
)

with patch.object(
    module["subprocess"],
    "run",
    return_value=SimpleNamespace(returncode=0, stdout="[]", stderr=""),
) as subprocess_run:
    assert PyiCloudClient(
        "/fake/icloud",
        "user@example.com",
        Path("/server/state/pyicloud"),
    )._run("lists") == []
    assert subprocess_run.call_args.args[0] == [
        "/fake/icloud",
        "reminders",
        "lists",
        "--username",
        "user@example.com",
        "--session-dir",
        "/server/state/pyicloud",
        "--format",
        "json",
    ]

auth_globals = authenticated_account.__globals__
original_runner = auth_globals["run_icloud_json"]
try:
    auth_globals["run_icloud_json"] = lambda *_args, **_kwargs: {
        "authenticated": True,
        "account_name": "user@example.com",
    }
    assert authenticated_account(
        "/fake/icloud",
        "user@example.com",
        Path("/server/state/pyicloud"),
    ) == "user@example.com"
    auth_globals["run_icloud_json"] = lambda *_args, **_kwargs: {
        "authenticated": False,
        "accounts": [],
    }
    assert authenticated_account(
        "/fake/icloud",
        "user@example.com",
        Path("/server/state/pyicloud"),
    ) is None
finally:
    auth_globals["run_icloud_json"] = original_runner

assert TodoApp.SMART_VIEWS == (
    ("today", "今天"),
    ("scheduled", "已计划"),
    ("all", "全部"),
    ("completed", "已完成"),
)

# The pyicloud snapshot is already in Reminders order. Filtering a list must
# not apply a second due-date/title sort.
app = TodoApp.__new__(TodoApp)
app.lists = [{"id": "work", "name": "工作"}]
app.tasks = [
    {
        "id": "last-due",
        "list_id": "work",
        "title": "Z task",
        "due": "2026-08-02T09:00:00+08:00",
        "completed": False,
    },
    {
        "id": "first-due",
        "list_id": "work",
        "title": "A task",
        "due": "2026-08-01T09:00:00+08:00",
        "completed": False,
    },
    {
        "id": "no-due",
        "list_id": "work",
        "title": "Middle task",
        "due": None,
        "completed": False,
    },
]
app.selected_view = len(TodoApp.SMART_VIEWS)
app.filter_text = ""
assert [task["id"] for task in app.current_tasks()] == [
    "last-due",
    "first-due",
    "no-due",
]
app.filter_text = "task"
assert [task["id"] for task in app.current_tasks()] == [
    "last-due",
    "first-due",
    "no-due",
]

text = source.read_text(encoding="utf-8")
for glyph in "╭╮╰╯│─":
    assert glyph in text
assert "curses.COLOR_MAGENTA" in text
assert "curses.init_pair(BORDER, curses.COLOR_GREEN, -1)" in text
assert "return curses.color_pair(BORDER) | curses.A_BOLD" in text
assert "return curses.color_pair(BORDER)" in text
assert "curses.ALL_MOUSE_EVENTS" in text
assert "def visual_login(" in text
assert "secret=True" in text
assert "正在检查服务器上的 iCloud 登录状态" in text
assert 'Path.home() / ".local" / "state" / "pyicloud"' in text

print("todo TUI tests passed")
