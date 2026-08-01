#!/usr/bin/env python3

import json
import os
from pathlib import Path
import runpy
import stat
import tempfile
from types import SimpleNamespace
from unittest.mock import patch


root = Path(__file__).resolve().parent.parent
source = root / "bin" / "todo"
module = runpy.run_path(str(source))

display_width = module["display_width"]
truncate = module["truncate"]
DemoClient = module["DemoClient"]
TodoError = module["TodoError"]
TodoistClient = module["TodoistClient"]
TodoApp = module["TodoApp"]
authenticated_account = module["authenticated_account"]
load_saved_token = module["load_saved_token"]
run_td_json = module["run_td_json"]
save_token = module["save_token"]
visual_login = module["visual_login"]

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


class FakeTodoistClient(TodoistClient):
    def __init__(self):
        super().__init__("/fake/td", "secret-token")
        self.commands = []

    @staticmethod
    def task_row(**overrides):
        row = {
            "id": "task-1",
            "projectId": "project-work",
            "content": "检查服务器",
            "description": "生产环境",
            "priority": 4,
            "due": {"datetime": "2026-08-02T09:00:00+08:00"},
            "checked": False,
        }
        row.update(overrides)
        return row

    def _run_json(self, *arguments, input_text=None):
        self.commands.append(("json", arguments, input_text))
        if arguments[:2] == ("project", "list"):
            return {"results": [{"id": "project-work", "name": "工作"}], "nextCursor": None}
        if arguments[:2] == ("task", "list"):
            return {"results": [self.task_row()], "nextCursor": None}
        if arguments[:2] == ("completed", "list"):
            return {
                "results": [
                    self.task_row(
                        id="task-done",
                        content="已完成任务",
                        description="",
                        priority=1,
                        due={"date": "2026-08-01"},
                    )
                ],
                "nextCursor": None,
            }
        if arguments[:2] == ("task", "add"):
            return self.task_row(
                id="task-created",
                content=arguments[2],
                description=input_text or "",
                priority=3,
                due=None,
            )
        if arguments[:2] == ("task", "update"):
            return self.task_row(
                content=arguments[arguments.index("--content") + 1],
                description=input_text or "",
                priority=1,
                due=None,
            )
        raise AssertionError(arguments)

    def _run(self, *arguments, input_text=None):
        self.commands.append(("run", arguments, input_text))


todoist = FakeTodoistClient()
todoist_snapshot = todoist.snapshot()
assert todoist_snapshot["lists"] == [{"id": "project-work", "name": "工作"}]
assert todoist_snapshot["tasks"][0]["notes"] == "生产环境"
assert todoist_snapshot["tasks"][0]["priority"] == 1
assert todoist_snapshot["tasks"][1]["completed"] is True
assert todoist_snapshot["tasks"][1]["all_day"] is True
assert [command[1][:2] for command in todoist.commands[:3]] == [
    ("project", "list"),
    ("task", "list"),
    ("completed", "list"),
]
completed_command = todoist.commands[2][1]
assert completed_command[-2:] == ("--json", "--full")
assert "--since" in completed_command and "--until" in completed_command

created = todoist.request(
    {
        "action": "create",
        "list_id": "project-work",
        "title": "新任务",
        "notes": "来自 stdin",
        "due": "",
        "all_day": False,
        "priority": 5,
    }
)
assert created["task"]["id"] == "task-created"
create_command = todoist.commands[-1]
assert create_command[1][:3] == ("task", "add", "新任务")
assert create_command[1][create_command[1].index("--priority") + 1] == "p2"
assert create_command[2] == "来自 stdin"

todoist.request(
    {
        "action": "update",
        "id": "task-1",
        "list_id": "project-personal",
        "title": "检查生产服务器",
        "notes": "",
        "due": "",
        "all_day": False,
        "priority": 0,
    }
)
update_command, move_command = todoist.commands[-2:]
assert "--no-due" in update_command[1]
assert update_command[2] == ""
assert move_command[1] == (
    "task",
    "move",
    "id:task-1",
    "--project",
    "id:project-personal",
    "--no-section",
    "--no-parent",
)
todoist.request({"action": "complete", "id": "task-1", "completed": True})
assert todoist.commands[-1][1] == ("task", "complete", "id:task-1")
todoist.request({"action": "complete", "id": "task-1", "completed": False})
assert todoist.commands[-1][1] == ("task", "uncomplete", "id:task-1")
todoist.request({"action": "delete", "id": "task-1"})
assert todoist.commands[-1][1] == ("task", "delete", "id:task-1", "--yes")

# Tokens are passed only through the child environment, never in argv.
with patch.object(
    module["subprocess"],
    "run",
    return_value=SimpleNamespace(
        returncode=0,
        stdout=json.dumps({"email": "user@example.com"}),
        stderr="",
    ),
) as subprocess_run:
    assert run_td_json("/fake/td", ("auth", "status", "--json"), "secret-token") == {
        "email": "user@example.com"
    }
    call = subprocess_run.call_args
    assert call.args[0] == ["/fake/td", "auth", "status", "--json"]
    assert "secret-token" not in call.args[0]
    assert call.kwargs["env"]["TODOIST_API_TOKEN"] == "secret-token"

with tempfile.TemporaryDirectory() as temp_dir:
    token_path = Path(temp_dir) / "state" / "token"
    save_token(token_path, "secret-token")
    assert load_saved_token(token_path) == "secret-token"
    assert stat.S_IMODE(token_path.stat().st_mode) == 0o600
    assert stat.S_IMODE(token_path.parent.stat().st_mode) == 0o700


class FakeLoginApp:
    def __init__(self, responses):
        self.responses = iter(responses)
        self.prompts = []
        self.notices = []

    def prompt_input(self, *args, **kwargs):
        self.prompts.append((args, kwargs))
        return next(self.responses)

    def show_notice(self, *args, **kwargs):
        self.notices.append((args, kwargs))


with tempfile.TemporaryDirectory() as temp_dir:
    login_app = FakeLoginApp(["valid-token"])
    token_path = Path(temp_dir) / "token"
    visual_globals = visual_login.__globals__
    original_auth = visual_globals["authenticated_account"]
    try:
        visual_globals["authenticated_account"] = lambda *_args: {
            "email": "user@example.com"
        }
        login = visual_login(login_app, "/fake/td", token_path)
    finally:
        visual_globals["authenticated_account"] = original_auth
    assert login == ("valid-token", {"email": "user@example.com"})
    assert load_saved_token(token_path) == "valid-token"
    assert login_app.prompts[0][1]["secret"] is True
    assert "设置 → 集成 → 开发者" in login_app.prompts[0][1]["instruction"]

auth_globals = authenticated_account.__globals__
original_runner = auth_globals["run_td_json"]
try:
    auth_globals["run_td_json"] = lambda *_args, **_kwargs: {
        "id": "user-1",
        "email": "user@example.com",
    }
    assert authenticated_account("/fake/td", "token")["email"] == "user@example.com"
    auth_globals["run_td_json"] = lambda *_args, **_kwargs: {}
    try:
        authenticated_account("/fake/td", "token")
    except TodoError:
        pass
    else:
        raise AssertionError("invalid auth status must be rejected")
finally:
    auth_globals["run_td_json"] = original_runner

assert TodoApp.SMART_VIEWS == (
    ("today", "今天"),
    ("scheduled", "已计划"),
    ("all", "全部"),
    ("completed", "已完成"),
)

# Filtering keeps the order returned by Todoist.
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
assert "正在检查服务器上的 Todoist 登录状态" in text
assert 'Path.home() / ".local" / "state" / "todoist-cli" / "token"' in text
assert "pyicloud" not in text.casefold()
assert "iCloud" not in text

print("todo TUI tests passed")
