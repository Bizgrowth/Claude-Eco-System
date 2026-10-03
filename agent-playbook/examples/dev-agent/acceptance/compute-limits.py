#!/usr/bin/env python3
"""Compute maxTurns, cost cap and time target from your acceptance results.

Formulas (from acceptance/README.md):
  maxTurns per role = ceil(1.5 x highest turn count seen for that role in the SUCCESSFUL full runs)
  cost cap          = 2 x median cost of the successful full runs (same currency/unit you entered)
  time target       = keep "about 2 hours" only if every successful run met it, else the measured
                      maximum rounded up to the next 15 minutes

Guardrails: needs at least 2 successful runs; excludes failed runs; any role that hit its turn limit
is reported as a LOWER BOUND and --apply is refused until you raise that cap and re-run.

Usage:
  python3 acceptance/compute-limits.py results.json            # report only (changes nothing)
  python3 acceptance/compute-limits.py results.json --apply    # write maxTurns into .claude/agents/*.md

Exit codes: 0 ok, 1 bad input, 2 not enough trustworthy data (or apply refused).
Input format: see acceptance/limits-input-template.json
"""
import argparse
import datetime
import json
import math
import re
import statistics
import sys
from pathlib import Path

ROLES = ["researcher", "designer", "builder", "reviewer"]
TURN_MULT = 1.5
COST_MULT = 2.0
TIME_TARGET_MIN = 120
INTERVENTION_TARGET = 3  # target is fewer than 3 per run


class InputError(Exception):
    pass


class NotTrustworthy(Exception):
    pass


def _num(value, name, run_id, integer=False, allow_zero=False):
    ok_type = isinstance(value, int) if integer else isinstance(value, (int, float))
    if isinstance(value, bool) or not ok_type:
        raise InputError(f"run {run_id}: '{name}' must be {'a whole number' if integer else 'a number'} (got {value!r}); fill in every field")
    if value < 0 or (value == 0 and not allow_zero):
        raise InputError(f"run {run_id}: '{name}' must be {'zero or more' if allow_zero else 'greater than zero'} (got {value})")
    return value


def load_runs(path):
    try:
        data = json.loads(Path(path).read_text())
    except FileNotFoundError:
        raise InputError(f"file not found: {path}")
    except json.JSONDecodeError as exc:
        raise InputError(f"invalid JSON in {path}: {exc}")
    runs = data.get("runs") if isinstance(data, dict) else None
    if not isinstance(runs, list) or not runs:
        raise InputError("'runs' must be a non-empty list")

    clean = []
    for i, r in enumerate(runs, start=1):
        if not isinstance(r, dict):
            raise InputError(f"run #{i} must be an object")
        rid = r.get("brief") or f"#{i}"
        if not isinstance(r.get("passed"), bool):
            raise InputError(f"run {rid}: 'passed' must be true or false")
        item = {"brief": str(rid), "passed": r["passed"]}
        if r["passed"]:  # failed runs need not carry complete numbers; they are excluded
            item["cost"] = _num(r.get("cost"), "cost", rid)
            item["minutes"] = _num(r.get("minutes"), "minutes", rid)
            item["interventions"] = _num(r.get("interventions"), "interventions", rid, integer=True, allow_zero=True)
            turns = r.get("turns")
            if not isinstance(turns, dict):
                raise InputError(f"run {rid}: 'turns' must list {', '.join(ROLES)}")
            item["turns"] = {role: _num(turns.get(role), f"turns.{role}", rid, integer=True) for role in ROLES}
            hit = r.get("hit_cap", [])
            if not isinstance(hit, list) or any(h not in ROLES for h in hit):
                raise InputError(f"run {rid}: 'hit_cap' must be a list drawn from {ROLES}")
            item["hit_cap"] = hit
        clean.append(item)
    return clean


def compute(runs):
    good = [r for r in runs if r["passed"]]
    failed = [r for r in runs if not r["passed"]]
    if len(good) < 2:
        raise NotTrustworthy(
            f"need at least 2 successful full runs to set limits, have {len(good)}. "
            "Fix the failing brief(s) and re-run before setting limits."
        )

    turns = {role: math.ceil(TURN_MULT * max(r["turns"][role] for r in good)) for role in ROLES}
    lower_bound = sorted({role for r in good for role in r["hit_cap"]})
    cost_cap = round(COST_MULT * statistics.median(r["cost"] for r in good), 2)
    slowest = max(r["minutes"] for r in good)
    if slowest <= TIME_TARGET_MIN:
        time_target, time_note = TIME_TARGET_MIN, "every successful run finished within about 2 hours, so the target stands"
    else:
        time_target = math.ceil(slowest / 15) * 15
        time_note = f"slowest successful run took {slowest:g} min, so 'about 2 hours' is NOT supported; use the measured figure"
    over = [r["brief"] for r in good if r["interventions"] >= INTERVENTION_TARGET]
    return {
        "good": good, "failed": failed, "turns": turns, "lower_bound": lower_bound,
        "cost_cap": cost_cap, "time_target": time_target, "time_note": time_note,
        "interventions_over": over,
    }


def current_max_turns(agents_dir, role):
    text = (Path(agents_dir) / f"{role}.md").read_text()
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None
    mm = re.search(r"^maxTurns:\s*(\d+)\s*$", m.group(1), re.M)
    return int(mm.group(1)) if mm else None


def report(result, agents_dir):
    lines = []
    ids = ", ".join(r["brief"] for r in result["good"])
    lines.append(f"Based on successful runs: {ids}")
    if result["failed"]:
        lines.append("Excluded failed runs: " + ", ".join(r["brief"] for r in result["failed"]) + "  (fix these before client use)")
    lines.append("")
    lines.append(f"{'Role':<12}{'Current':>9}{'Recommended':>13}  Note")
    for role in ROLES:
        try:
            cur = current_max_turns(agents_dir, role)
        except FileNotFoundError:
            cur = None
        note = "LOWER BOUND: hit its cap; raise cap and re-run first" if role in result["lower_bound"] else ""
        lines.append(f"{role:<12}{(cur if cur is not None else '-'):>9}{result['turns'][role]:>13}  {note}")
    lines.append("")
    lines.append(f"Per-run cost cap : {result['cost_cap']:.2f} (same unit you entered; = {COST_MULT:g} x median of successful runs)")
    lines.append(f"Time target      : {result['time_target']} minutes ({result['time_note']})")
    if result["interventions_over"]:
        lines.append(f"WARNING: interventions at or above the target of fewer than {INTERVENTION_TARGET} in run(s): "
                     + ", ".join(result["interventions_over"]) + ". The agent is not yet autonomous enough.")
    if result["lower_bound"]:
        lines.append("")
        lines.append("NOT SAFE TO APPLY: " + ", ".join(result["lower_bound"]) +
                     " hit the turn limit, so the true need is unknown. Raise that cap, re-run the brief, and recompute.")
    return "\n".join(lines)


def apply_limits(result, agents_dir, record_path, source):
    if result["lower_bound"]:
        raise NotTrustworthy("refusing to apply: " + ", ".join(result["lower_bound"]) + " hit the turn limit (lower bound only)")
    agents_dir = Path(agents_dir)
    plan = {}
    for role in ROLES:  # validate everything first so we never half-apply
        path = agents_dir / f"{role}.md"
        if not path.exists():
            raise InputError(f"agent file not found: {path}")
        text = path.read_text()
        m = re.match(r"(---\n)(.*?)(\n---\n)", text, re.S)
        if not m or not re.search(r"^maxTurns:\s*\d+\s*$", m.group(2), re.M):
            raise InputError(f"{path} has no 'maxTurns: <number>' line in its frontmatter")
        new_front = re.sub(r"^maxTurns:\s*\d+\s*$", f"maxTurns: {result['turns'][role]}", m.group(2), count=1, flags=re.M)
        plan[path] = m.group(1) + new_front + m.group(3) + text[m.end():]
    for path, new_text in plan.items():
        path.write_text(new_text)

    rows = "\n".join(f"| {role} | {result['turns'][role]} |" for role in ROLES)
    Path(record_path).write_text(
        f"# Limits record\n\nGenerated {datetime.date.today().isoformat()} by compute-limits.py from `{source}`.\n"
        f"Successful runs used: {', '.join(r['brief'] for r in result['good'])}\n\n"
        f"| Role | maxTurns |\n|---|---|\n{rows}\n\n"
        f"- Per-run cost cap: {result['cost_cap']:.2f} (same unit as entered; set this as your spend alert)\n"
        f"- Time target: {result['time_target']} minutes. {result['time_note']}\n"
    )


def main(argv=None):
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description="Compute agent limits from acceptance results.")
    ap.add_argument("results", help="JSON file of per-run figures (see limits-input-template.json)")
    ap.add_argument("--apply", action="store_true", help="write maxTurns into the agent files")
    ap.add_argument("--agents-dir", default=str(here.parent / ".claude" / "agents"))
    ap.add_argument("--record", default=str(here / "limits-record.md"))
    args = ap.parse_args(argv)

    try:
        runs = load_runs(args.results)
        result = compute(runs)
        print(report(result, args.agents_dir))
        if args.apply:
            apply_limits(result, args.agents_dir, args.record, args.results)
            print(f"\nApplied maxTurns to {args.agents_dir}; record written to {args.record}")
            print("Next: set the cost cap as a spend alert, update SPEC.md, and re-run both hook test suites.")
        else:
            print("\n(report only; nothing was changed. Add --apply to write maxTurns.)")
        return 0
    except InputError as exc:
        print(f"INPUT ERROR: {exc}", file=sys.stderr)
        return 1
    except NotTrustworthy as exc:
        print(f"\nSTOP: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
