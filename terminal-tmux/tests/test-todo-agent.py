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
worktree = Path(args[args.index("--cd") + 1])
result = Path(args[args.index("--output-last-message") + 1])
prompt = sys.stdin.read()
(worktree / "agent-change.txt").write_text("changed\n", encoding="utf-8")
(worktree / "received-prompt.txt").write_text(prompt, encoding="utf-8")
result.write_text("已修改 agent-change.txt，并完成验证。\n", encoding="utf-8")
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
    assert "已修改 agent-change.txt" in state["comments"][0]["content"]
    worktree = root / "worktrees" / "terminal-tmux" / "task-1"
    assert (worktree / "agent-change.txt").read_text(encoding="utf-8") == "changed\n"
    prompt = (worktree / "received-prompt.txt").read_text(encoding="utf-8")
    assert "修复 bootstrap" in prompt
    assert "保持现有 Node.js" in prompt
    assert "不推送远端" in prompt

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
    retried = run(
        [sys.executable, str(TODO_AGENT), "run", "--once"],
        environment=environment,
    )
    assert "等待审核：失败任务" in retried.stdout
    retry_prompt = (
        root / "worktrees" / "terminal-tmux" / "task-2" / "received-prompt.txt"
    ).read_text(encoding="utf-8")
    assert "请按反馈重试" in retry_prompt

    removed = run(
        [sys.executable, str(TODO_AGENT), "project", "remove", "terminal-tmux"],
        environment=environment,
    )
    assert "已删除项目映射：terminal-tmux" in removed.stdout
    assert "[[projects]]" not in (root / "projects.toml").read_text(encoding="utf-8")

print("todo-agent tests passed")
