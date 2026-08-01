#!/usr/bin/env python3

"""End-to-end contract tests for the Todoist Codex dispatcher."""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import sqlite3
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
TODO_AGENT = ROOT / "bin" / "todo-agent"


def write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def run(
    command: list[str],
    *,
    environment: dict[str, str],
    cwd: Path | None = None,
    expected: int = 0,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=environment,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    assert result.returncode == expected, (
        command,
        result.returncode,
        result.stdout,
        result.stderr,
    )
    return result


def wait_until(predicate, timeout: float, interval: float = 0.05) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return predicate()


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    home = root / "home"
    repository = root / "repository"
    home.mkdir()
    repository.mkdir()
    state_path = root / "todoist.json"
    td_path = root / "td"
    codex_path = root / "codex"

    state_path.write_text(
        json.dumps(
            {
                "projects": [{"id": "project-1", "name": "terminal-tmux"}],
                "labels": [{"id": "label-bug", "name": "bug"}],
                "tasks": [
                    {
                        "id": "task-1",
                        "projectId": "project-1",
                        "content": "修复 bootstrap",
                        "description": "保持现有 Node.js",
                        "labels": ["bug", "codex-ready"],
                    },
                    {
                        "id": "task-parallel-2",
                        "projectId": "project-1",
                        "content": "并行任务二",
                        "description": "验证无并发上限",
                        "labels": ["codex-ready"],
                    },
                    {
                        "id": "task-parallel-3",
                        "projectId": "project-1",
                        "content": "并行任务三",
                        "description": "验证无并发上限",
                        "labels": ["codex-ready"],
                    },
                ],
                "comments": [],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    write_executable(
        td_path,
        r'''#!/usr/bin/env python3
import json
import fcntl
import os
from pathlib import Path
import sys

path = Path(os.environ["FAKE_TODOIST_STATE"])
lock = path.with_suffix(".lock").open("w", encoding="utf-8")
fcntl.flock(lock, fcntl.LOCK_EX)
state = json.loads(path.read_text(encoding="utf-8"))
args = sys.argv[1:]

def save():
    path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")

def option(name, default=None):
    if name not in args:
        return default
    return args[args.index(name) + 1]

if args[:2] == ["auth", "status"]:
    print(json.dumps({"email": "agent@example.com"}))
elif args[:2] == ["project", "list"]:
    print(json.dumps({"results": state["projects"], "nextCursor": None}))
elif args[:2] == ["label", "list"]:
    print(json.dumps({"results": state["labels"], "nextCursor": None}))
elif args[:2] == ["label", "create"]:
    label = {"id": f"label-{len(state['labels']) + 1}", "name": option("--name")}
    state["labels"].append(label)
    save()
    print(json.dumps(label))
elif args[:2] == ["task", "list"]:
    project_id = option("--project", "").removeprefix("id:")
    label = option("--label")
    tasks = [
        task for task in state["tasks"]
        if task["projectId"] == project_id and (not label or label in task["labels"])
    ]
    print(json.dumps({"results": tasks, "nextCursor": None}, ensure_ascii=False))
elif args[:2] == ["task", "view"]:
    task_id = args[2].removeprefix("id:")
    task = next(task for task in state["tasks"] if task["id"] == task_id)
    print(json.dumps(task, ensure_ascii=False))
elif args[:2] == ["task", "update"]:
    task_id = args[2].removeprefix("id:")
    task = next(task for task in state["tasks"] if task["id"] == task_id)
    task["labels"] = option("--labels", "").split(",") if option("--labels") else []
    save()
    print(json.dumps(task, ensure_ascii=False))
elif args[:2] == ["comment", "list"]:
    task_id = args[2].removeprefix("id:")
    rows = [comment for comment in state["comments"] if comment["taskId"] == task_id]
    print(json.dumps({"results": rows, "nextCursor": None}, ensure_ascii=False))
elif args[:2] == ["comment", "add"]:
    task_id = args[2].removeprefix("id:")
    comment = {
        "id": f"comment-{len(state['comments']) + 1}",
        "taskId": task_id,
        "content": sys.stdin.read(),
    }
    state["comments"].append(comment)
    save()
    print(json.dumps(comment, ensure_ascii=False))
else:
    print(f"unsupported fake td command: {args}", file=sys.stderr)
    raise SystemExit(2)
''',
    )

    write_executable(
        codex_path,
        r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time

args = sys.argv[1:]
assert args[args.index("-a") + 1] == "never"
assert args[args.index("-c") + 1] == "sandbox_workspace_write.network_access=true"
assert args[args.index("--sandbox") + 1] == "workspace-write"
worktree = Path(args[args.index("--cd") + 1])
result = Path(args[args.index("--output-last-message") + 1])
prompt = sys.stdin.read()
(worktree / "agent-change.txt").write_text("changed\n", encoding="utf-8")
(worktree / "received-prompt.txt").write_text(prompt, encoding="utf-8")
if os.environ.get("FAKE_CODEX_UNSTRUCTURED"):
    result.write_text("已修改 agent-change.txt，并完成验证。\n", encoding="utf-8")
else:
    result.write_text(
        "## 1. 任务是什么\n\n"
        "修复 bootstrap。\n\n"
        "## 2. 做了哪些工作\n\n"
        "已修改 agent-change.txt，并完成验证。\n\n"
        "## 3. 怎么做的\n\n"
        "在任务专用 worktree 中修改文件并检查结果。\n\n"
        "## 4. 最终结论是什么\n\n"
        "任务已完成，验证通过。\n",
        encoding="utf-8",
    )
control_value = os.environ.get("FAKE_CODEX_CONTROL_DIR")
if control_value:
    control_dir = Path(control_value)
    control_dir.mkdir(parents=True, exist_ok=True)
    (control_dir / f"{worktree.name}.started").write_text("started\n", encoding="utf-8")
    if worktree.name == os.environ.get("FAKE_CODEX_BLOCK_TASK"):
        deadline = time.monotonic() + 20
        while not (control_dir / f"{worktree.name}.release").exists():
            if time.monotonic() >= deadline:
                print("fake codex release timed out", file=sys.stderr)
                raise SystemExit(9)
            time.sleep(0.05)
expected_parallel = int(os.environ.get("FAKE_CODEX_EXPECTED_PARALLEL", "0"))
if expected_parallel:
    parallel_dir = Path(os.environ["FAKE_CODEX_PARALLEL_DIR"])
    parallel_dir.mkdir(parents=True, exist_ok=True)
    (parallel_dir / worktree.name).write_text("started\n", encoding="utf-8")
    deadline = time.monotonic() + 10
    while len(list(parallel_dir.iterdir())) < expected_parallel:
        if time.monotonic() >= deadline:
            print("fake codex agents did not run concurrently", file=sys.stderr)
            raise SystemExit(8)
        time.sleep(0.05)
print(json.dumps({"type": "thread.started", "thread_id": "thread-test"}))
exit_code = int(os.environ.get("FAKE_CODEX_EXIT", "0"))
if exit_code:
    print("fake codex failed", file=sys.stderr)
raise SystemExit(exit_code)
''',
    )

    environment = os.environ.copy()
    environment.update(
        {
            "HOME": str(home),
            "TODOIST_CLI": str(td_path),
            "CODEX_CLI": str(codex_path),
            "FAKE_TODOIST_STATE": str(state_path),
            "TODOIST_CODEX_CONFIG": str(root / "projects.toml"),
            "TODOIST_CODEX_STATE_DIR": str(root / "state"),
            "TODOIST_CODEX_WORKTREE_DIR": str(root / "worktrees"),
        }
    )

    run(["git", "init", "-b", "main"], environment=environment, cwd=repository)
    run(["git", "config", "user.name", "Test User"], environment=environment, cwd=repository)
    run(
        ["git", "config", "user.email", "test@example.com"],
        environment=environment,
        cwd=repository,
    )
    (repository / "README.md").write_text("test\n", encoding="utf-8")
    run(["git", "add", "README.md"], environment=environment, cwd=repository)
    run(["git", "commit", "-m", "initial"], environment=environment, cwd=repository)

    registered = run(
        [
            sys.executable,
            str(TODO_AGENT),
            "project",
            "add",
            "--todoist-project",
            "terminal-tmux",
            "--max-agents",
            "1",
        ],
        environment=environment,
        cwd=repository,
    )
    assert "已注册项目：terminal-tmux" in registered.stdout
    config = (root / "projects.toml").read_text(encoding="utf-8")
    assert 'todoist_project_id = "project-1"' in config
    assert f'repository = "{repository.resolve()}"' in config
    assert 'base_branch = "main"' in config
    assert "max_agents" not in config
    assert stat.S_IMODE((root / "projects.toml").stat().st_mode) == 0o600

    # Configs written by the first dispatcher version remain readable, but the
    # legacy cap is ignored and disappears the next time the config is saved.
    (root / "projects.toml").write_text(
        config.replace("enabled = true", "max_agents = 1\nenabled = true"),
        encoding="utf-8",
    )

    state = json.loads(state_path.read_text(encoding="utf-8"))
    assert {label["name"] for label in state["labels"]} >= {
        "codex-ready",
        "codex-running",
        "codex-review",
        "codex-failed",
    }

    listed = run(
        [sys.executable, str(TODO_AGENT), "project", "list"],
        environment=environment,
    )
    assert "terminal-tmux\tproject-1" in listed.stdout
    assert "max=" not in listed.stdout

    dry_run = run(
        [sys.executable, str(TODO_AGENT), "run", "--once", "--dry-run"],
        environment=environment,
    )
    assert "将执行：修复 bootstrap" in dry_run.stdout
    assert "将执行：并行任务二" in dry_run.stdout
    assert "将执行：并行任务三" in dry_run.stdout
    state = json.loads(state_path.read_text(encoding="utf-8"))
    assert state["tasks"][0]["labels"] == ["bug", "codex-ready"]

    parallel_environment = environment.copy()
    parallel_environment["FAKE_CODEX_EXPECTED_PARALLEL"] = "3"
    parallel_environment["FAKE_CODEX_PARALLEL_DIR"] = str(root / "parallel")
    completed = run(
        [sys.executable, str(TODO_AGENT), "run", "--once"],
        environment=parallel_environment,
    )
    assert "等待审核：修复 bootstrap" in completed.stdout
    state = json.loads(state_path.read_text(encoding="utf-8"))
    assert state["tasks"][0]["labels"] == ["bug", "codex-review"]
    assert all("codex-review" in task["labels"] for task in state["tasks"])
    assert len(list((root / "parallel").iterdir())) == 3
    comment = state["comments"][0]["content"]
    headings = [
        "## 1. 任务是什么",
        "## 2. 做了哪些工作",
        "## 3. 怎么做的",
        "## 4. 最终结论是什么",
    ]
    heading_positions = [comment.index(heading) for heading in headings]
    assert heading_positions == sorted(heading_positions)
    assert "已修改 agent-change.txt" in comment
    assert "## 执行信息" in comment
    assert comment.index("## 执行信息") > heading_positions[-1]
    worktree = root / "worktrees" / "terminal-tmux" / "task-1"
    assert (worktree / "agent-change.txt").read_text(encoding="utf-8") == "changed\n"
    prompt = (worktree / "received-prompt.txt").read_text(encoding="utf-8")
    assert "修复 bootstrap" in prompt
    assert "保持现有 Node.js" in prompt
    assert "不推送远端" in prompt
    assert "最终回答必须简洁" in prompt
    for heading in headings:
        assert heading in prompt

    task_run_root = root / "state" / "runs" / "task-1"
    assert task_run_root.is_dir()
    run(
        ["git", "show-ref", "--verify", "refs/heads/codex/terminal-tmux/task-1"],
        environment=environment,
        cwd=repository,
    )
    state["tasks"][0]["checked"] = True
    state_path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
    cleaned = run(
        [sys.executable, str(TODO_AGENT), "run", "--once"],
        environment=environment,
    )
    assert "已清理完成任务：task-1" in cleaned.stdout
    assert not worktree.exists()
    assert not task_run_root.exists()
    run(
        ["git", "show-ref", "--verify", "refs/heads/codex/terminal-tmux/task-1"],
        environment=environment,
        cwd=repository,
        expected=128,
    )
    with sqlite3.connect(root / "state" / "state.db") as connection:
        assert connection.execute(
            "SELECT 1 FROM runs WHERE task_id = ?", ("task-1",)
        ).fetchone() is None

    state["tasks"].append(
        {
            "id": "task-2",
            "projectId": "project-1",
            "content": "失败任务",
            "description": "验证失败状态",
            "labels": ["codex-ready"],
        }
    )
    state["tasks"].append(
        {
            "id": "task-interrupted",
            "projectId": "project-1",
            "content": "中断任务",
            "description": "验证恢复",
            "labels": ["codex-running"],
        }
    )
    state_path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
    with sqlite3.connect(root / "state" / "state.db") as connection:
        connection.execute(
            """
            INSERT INTO runs (
                task_id, project_id, project_name, status, branch, worktree,
                run_dir, attempts, started_at
            ) VALUES (?, ?, ?, 'running', ?, ?, ?, 1, ?)
            """,
            (
                "task-interrupted",
                "project-1",
                "terminal-tmux",
                "codex/terminal-tmux/task-interrupted",
                str(root / "worktrees" / "terminal-tmux" / "task-interrupted"),
                str(root / "state" / "runs" / "task-interrupted" / "old"),
                "2026-08-01T00:00:00+00:00",
            ),
        )
    failed_environment = environment.copy()
    failed_environment["FAKE_CODEX_EXIT"] = "7"
    failed = run(
        [sys.executable, str(TODO_AGENT), "run", "--once"],
        environment=failed_environment,
        expected=1,
    )
    assert "执行失败：失败任务" in failed.stderr
    state = json.loads(state_path.read_text(encoding="utf-8"))
    task_2 = next(task for task in state["tasks"] if task["id"] == "task-2")
    assert task_2["labels"] == ["codex-failed"]
    interrupted = next(
        task for task in state["tasks"] if task["id"] == "task-interrupted"
    )
    assert interrupted["labels"] == ["codex-failed"]
    assert any(
        "上一次执行被意外中断" in comment["content"]
        for comment in state["comments"]
        if comment["taskId"] == "task-interrupted"
    )
    assert "fake codex failed" in state["comments"][-1]["content"]

    task_2["labels"] = ["codex-ready"]
    state["comments"].append(
        {"id": "feedback", "taskId": "task-2", "content": "请按反馈重试"}
    )
    state_path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
    retry_environment = environment.copy()
    retry_environment["FAKE_CODEX_UNSTRUCTURED"] = "1"
    retried = run(
        [sys.executable, str(TODO_AGENT), "run", "--once"],
        environment=retry_environment,
    )
    assert "等待审核：失败任务" in retried.stdout
    retry_prompt = (
        root / "worktrees" / "terminal-tmux" / "task-2" / "received-prompt.txt"
    ).read_text(encoding="utf-8")
    assert "请按反馈重试" in retry_prompt
    state = json.loads(state_path.read_text(encoding="utf-8"))
    retry_comment = next(
        comment["content"]
        for comment in reversed(state["comments"])
        if comment["taskId"] == "task-2"
    )
    retry_heading_positions = [retry_comment.index(heading) for heading in headings]
    assert retry_heading_positions == sorted(retry_heading_positions)
    assert "## 执行信息" in retry_comment

    state["tasks"].append(
        {
            "id": "task-live-1",
            "projectId": "project-1",
            "content": "长时间运行任务",
            "description": "保持运行以验证持续扫描",
            "labels": ["codex-ready"],
        }
    )
    state_path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
    control_dir = root / "live-control"
    watch_environment = environment.copy()
    watch_environment["FAKE_CODEX_CONTROL_DIR"] = str(control_dir)
    watch_environment["FAKE_CODEX_BLOCK_TASK"] = "task-live-1"
    watcher = subprocess.Popen(
        [sys.executable, str(TODO_AGENT), "watch", "--interval", "5"],
        env=watch_environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    try:
        assert wait_until(lambda: (control_dir / "task-live-1.started").exists(), 5)
        locked = run(
            [sys.executable, str(TODO_AGENT), "run", "--once", "--dry-run"],
            environment=environment,
            expected=1,
        )
        assert "另一个 todo-agent 正在运行" in locked.stderr
        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["tasks"].append(
            {
                "id": "task-live-2",
                "projectId": "project-1",
                "content": "运行期间新增任务",
                "description": "必须在第一个任务结束前启动",
                "labels": ["codex-ready"],
            }
        )
        state_path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
        assert wait_until(
            lambda: (control_dir / "task-live-2.started").exists(), 7
        ), "watcher did not start a newly-ready task while another task was running"

        dynamic_repository = root / "dynamic-repository"
        dynamic_repository.mkdir()
        run(
            ["git", "init", "-b", "main"],
            environment=environment,
            cwd=dynamic_repository,
        )
        run(
            ["git", "config", "user.name", "Test User"],
            environment=environment,
            cwd=dynamic_repository,
        )
        run(
            ["git", "config", "user.email", "test@example.com"],
            environment=environment,
            cwd=dynamic_repository,
        )
        (dynamic_repository / "README.md").write_text("dynamic\n", encoding="utf-8")
        run(["git", "add", "README.md"], environment=environment, cwd=dynamic_repository)
        run(
            ["git", "commit", "-m", "initial"],
            environment=environment,
            cwd=dynamic_repository,
        )

        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["projects"].append({"id": "project-live-2", "name": "dynamic-project"})
        state_path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
        registered_dynamic = run(
            [
                sys.executable,
                str(TODO_AGENT),
                "project",
                "add",
                "--todoist-project",
                "dynamic-project",
            ],
            environment=environment,
            cwd=dynamic_repository,
        )
        assert "已注册项目：dynamic-project" in registered_dynamic.stdout

        state = json.loads(state_path.read_text(encoding="utf-8"))
        state["tasks"].append(
            {
                "id": "task-live-project-2",
                "projectId": "project-live-2",
                "content": "监听期间注册的新项目任务",
                "description": "无需重启 watcher 就必须领取",
                "labels": ["codex-ready"],
            }
        )
        state_path.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
        assert wait_until(
            lambda: (control_dir / "task-live-project-2.started").exists(), 7
        ), "watcher did not reload projects registered after it started"
    finally:
        control_dir.mkdir(parents=True, exist_ok=True)
        (control_dir / "task-live-1.release").write_text("release\n", encoding="utf-8")
        wait_until(
            lambda: all(
                "codex-running" not in task["labels"]
                for task in json.loads(state_path.read_text(encoding="utf-8"))["tasks"]
            ),
            12,
        )
        watcher.terminate()
        try:
            watcher.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            watcher.kill()
            watcher.communicate()

    removed_dynamic = run(
        [sys.executable, str(TODO_AGENT), "project", "remove", "dynamic-project"],
        environment=environment,
    )
    assert "已删除项目映射：dynamic-project" in removed_dynamic.stdout
    removed = run(
        [sys.executable, str(TODO_AGENT), "project", "remove", "terminal-tmux"],
        environment=environment,
    )
    assert "已删除项目映射：terminal-tmux" in removed.stdout
    assert "[[projects]]" not in (root / "projects.toml").read_text(encoding="utf-8")

print("todo-agent tests passed")
