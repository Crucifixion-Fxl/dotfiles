# Todoist CLI learning notes

Explored on 2026-08-01 against the official Todoist CLI 3.1.2 source and built
CLI help output.

## Sources

- CLI landing page: https://www.todoist.com/cli
- Official repository: https://github.com/Doist/todoist-cli
- Todoist API v1 reference: https://developer.todoist.com/api/v1/

## Installation and authentication

- Package: `@doist/todoist-cli`; executable: `td`.
- Version 3.1.2 declares Node.js `>=24` and npm `>=11`.
- Interactive OAuth uses `td auth login` and the OS credential store.
- Headless Linux can use `TODOIST_API_TOKEN`; the environment variable takes
  precedence over stored credentials. `todo` uses this route so the token is
  never passed in argv.
- `td auth status --json` validates a token and returns the account id, email,
  full name, authentication mode, and credential source.

## JSON and CRUD contract used by the TUI

- Projects: `td project list --all --json --full`.
- Active tasks: `td task list --all --json --full`.
- Completed tasks: `td completed list --all --since DATE --until DATE --json --full`.
- Paginated list commands return `{ "results": [...], "nextCursor": ... }`.
- Create: `td task add TITLE --project id:ID --stdin --priority pN --json`.
- Update: `td task update id:ID --content TITLE --stdin --priority pN --json`.
- Move: `td task move id:ID --project id:PROJECT --no-section --no-parent`.
- Complete/reopen: `td task complete id:ID` / `td task uncomplete id:ID`.
- Delete: `td task delete id:ID --yes`.
- Descriptions are sent on stdin, including an empty string, so they do not
  leak through process arguments and can be cleared reliably.

## Data mapping

- Todoist `projectId`, `content`, and `description` map to the TUI's list id,
  title, and notes.
- `due.datetime` is a timed task; `due.date` is an all-day task.
- Todoist API priorities `4/3/2/1` map to the TUI's high/medium/low/none values.
- The completed-task API accepts a date range of at most three months. The TUI
  requests the most recent 89 days through tomorrow.

## Experiments performed

- Cloned the official repository at commit
  `8a8849da4d9a9b63488a6e4fa83d39113da234f5`.
- Installed its locked dependencies, built the TypeScript project, and ran the
  real help output for auth, project, task, and completed-task commands.
- Confirmed `td --version` reports `3.1.2` and inspected the command source for
  JSON pagination, completed-task date handling, and authentication precedence.
