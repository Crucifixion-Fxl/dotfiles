# Todoist CLI exploration gaps

- Browser OAuth (`td auth login`) is not suitable as the only first-run path in
  a headless container because it opens a browser and relies on an OS credential
  manager. The TUI therefore offers a masked API Token input while still reusing
  an existing official CLI login when one is available.
- The CLI has no incremental-change cursor command. The TUI performs a complete
  three-command snapshot every 30 seconds and also supports manual refresh.
- Todoist exposes completed tasks for an API date range of at most three months;
  the TUI's “已完成” view intentionally represents the latest 89 days, not the
  account's unlimited completion history.
- Real read/write requests were not sent because they require the user's private
  Todoist token. Command construction, JSON parsing, auth fallback, token file
  permissions, and CRUD state mapping are covered with a fake `td` backend.
