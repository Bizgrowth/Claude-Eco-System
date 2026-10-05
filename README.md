# Claude Command Center

Mobile-first, installable (PWA) daily launch dashboard: priorities, to-dos, GitHub project status, and a Claude product playbook (Chat vs Cowork vs Code vs add-ons) with SOPs.

## Go live (one-time, ~5 min)
1. GitHub repo → Settings → Pages → deploy from branch (root).
2. Actions tab → run **Refresh dashboard data** once (it then runs every ~20 min).
3. For private repos / other repos in the org: add a repo secret `GH_READ_TOKEN` (fine-grained token, read-only: Contents/Metadata, Issues, Pull requests).
4. Open the Pages URL on your phone → Add to Home Screen.

## Customize
- Links, org name, stale thresholds, priority labels: `data/config.json`
- Playbook rules/SOPs: arrays at the top of the script in `index.html`
- Label GitHub issues `priority` to surface them on Today.

Priorities and to-dos are stored on the device (More → Copy backup to move them).
