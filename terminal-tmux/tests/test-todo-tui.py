#!/usr/bin/env python3

from pathlib import Path
import runpy
import sys
import tempfile
from types import ModuleType, SimpleNamespace
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
complete_two_factor = module["complete_two_factor"]
ensure_pyicloud_runtime = module["ensure_pyicloud_runtime"]
needs_two_factor_code = module["needs_two_factor_code"]
visual_login = module["visual_login"]

assert display_width("abc") == 3
assert display_width("工作") == 4
assert display_width("a工") == 3
assert display_width(truncate("这是一个很长的标题", 7)) <= 7

# A virtualenv's Python normally resolves to the same underlying system binary.
# todo must still re-exec through the venv so its site-packages become active.
with tempfile.TemporaryDirectory() as temp_dir:
    venv_root = Path(temp_dir) / "pyicloud"
    venv_bin = venv_root / "bin"
    venv_bin.mkdir(parents=True)
    icloud_cli = venv_bin / "icloud"
    icloud_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    venv_python = venv_bin / "python"
    venv_python.symlink_to(sys.executable)
    with (
        patch.object(sys, "prefix", str(Path(temp_dir) / "system")),
        patch("os.execv", side_effect=RuntimeError("exec requested")) as execv,
    ):
        try:
            ensure_pyicloud_runtime(str(icloud_cli))
        except RuntimeError as error:
            assert str(error) == "exec requested"
        else:
            raise AssertionError("todo did not switch to the pyicloud virtualenv")
    expected_runtime = icloud_cli.resolve().with_name("python")
    assert execv.call_args.args[0] == str(expected_runtime)
    assert execv.call_args.args[1][0] == str(expected_runtime)

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


class FakeTwoFactorAPI:
    security_key_names = []
    fido2_devices = []
    two_factor_delivery_method = "trusted_device"
    two_factor_delivery_notice = None

    def __init__(self, valid_code="123456"):
        self.valid_code = valid_code
        self.request_count = 0
        self.validated_codes = []

    def request_2fa_code(self):
        self.request_count += 1
        return True

    def validate_2fa_code(self, code):
        self.validated_codes.append(code)
        return code == self.valid_code


# PyiCloudService already sends the initial code while authenticating the
# password. The TUI must prompt for that code without sending a second request.
login_app = FakeLoginApp(["123456"])
two_factor_api = FakeTwoFactorAPI()
assert complete_two_factor(login_app, two_factor_api) is True
assert two_factor_api.request_count == 0
assert two_factor_api.validated_codes == ["123456"]
assert "验证码已发送到受信任设备" in login_app.prompts[0][1]["instruction"]

# A resend happens only when the user explicitly enters R.
login_app = FakeLoginApp(["R", "654321"])
two_factor_api = FakeTwoFactorAPI(valid_code="654321")
assert complete_two_factor(login_app, two_factor_api) is True
assert two_factor_api.request_count == 1
assert two_factor_api.validated_codes == ["654321"]

# Apple can omit the HSA version even though the fresh browser session is
# untrusted and a code was sent. That state must still enter the 2FA prompt.
assert needs_two_factor_code(
    SimpleNamespace(requires_2fa=False, is_trusted_session=False),
    requires_2sa=False,
) is True
assert needs_two_factor_code(
    SimpleNamespace(requires_2fa=False, is_trusted_session=True),
    requires_2sa=False,
) is False
assert needs_two_factor_code(
    SimpleNamespace(requires_2fa=False, is_trusted_session=False),
    requires_2sa=True,
) is False

# Exercise the complete visual-login branch for the exact Apple response that
# sent a code but omitted the flag pyicloud normally exposes as requires_2fa.
class FakeUntrustedAPI(FakeTwoFactorAPI):
    account_name = "user@example.com"
    requires_2fa = False
    requires_2sa = False

    def __init__(self):
        super().__init__()
        self.is_trusted_session = False
        self.trust_count = 0

    def validate_2fa_code(self, code):
        valid = super().validate_2fa_code(code)
        if valid:
            self.is_trusted_session = True
        return valid

    def trust_session(self):
        self.trust_count += 1
        return False


untrusted_api = FakeUntrustedAPI()
login_app = FakeLoginApp(["user@example.com", "password", "123456"])
fake_pyicloud = ModuleType("pyicloud")
fake_pyicloud.PyiCloudService = lambda **_kwargs: untrusted_api
fake_exceptions = ModuleType("pyicloud.exceptions")
fake_exceptions.PyiCloudFailedLoginException = type(
    "PyiCloudFailedLoginException", (Exception,), {}
)
visual_globals = visual_login.__globals__
original_remember_account = visual_globals["remember_account"]
try:
    visual_globals["remember_account"] = lambda *_args: None
    with patch.dict(
        sys.modules,
        {"pyicloud": fake_pyicloud, "pyicloud.exceptions": fake_exceptions},
    ):
        assert visual_login(login_app, None, Path("/tmp/session")) == "user@example.com"
finally:
    visual_globals["remember_account"] = original_remember_account
assert [prompt[0][0] for prompt in login_app.prompts] == ["Apple ID", "密码", "验证码"]
assert untrusted_api.trust_count == 0

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
