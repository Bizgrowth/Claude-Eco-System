# Claude Command Center

Mobile-first, installable (PWA) daily launch dashboard: priorities, to-dos, GitHub project status, and a Claude product playbook (Chat vs Cowork vs Code vs add-ons) with SOPs.

## Go live (one-time, ~5 min)
1. GitHub repo → Settings → Pages → deploy from branch (root).
2. Actions tab → run **Refresh dashboard data** once (it then runs every ~20 min).
3. Create a classic token (github.com/settings/tokens) with scopes `repo` and `read:project` (add `project` only if you want write access). Save it as secret `GH_READ_TOKEN` (the workflow reads it from the GitHub environment of that name). The Action writes `github.json` into the private sync repo, never into this publicly hosted one.
4. Open the Pages URL on your phone → Add to Home Screen.
5. On each device: More → GitHub sync → paste the token and the `owner/repo` for sync issues → Save & sync. The token stays in that browser only.

## How sync works
Priorities and to-dos are GitHub Issues in `syncRepo` (set in `data/config.json`, use a private repo) with labels `dash:priority` and `dash:todo`. Checking an item closes the issue; ✕ closes it as not planned. Completed items stay visible for 24 hours. Without a token the lists stay on the device only.

## Customize
- Links, org name, stale thresholds, priority labels: `data/config.json`
- Playbook rules/SOPs: arrays at the top of the script in `index.html`
- Label GitHub issues `priority` to surface them on Today.

