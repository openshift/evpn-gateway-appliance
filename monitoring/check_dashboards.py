#!/usr/bin/env python3
"""Check Grafana dashboards: required variables, datasource, job/instance scope, unique panel IDs, PromQL."""
import json
import os
import re
import subprocess
import sys

# Every frrk8s_* or up selector must start with the dashboard's job/instance filter. Mark that filter, then
# blank all quoted strings so label values cannot look like metric names.
SCOPE = '{job=~"$job", instance=~"$instance"'
STRING = re.compile(r"""("|')(?:\\.|(?!\1)[^\\])*\1|`[^`]*`""")
UNSCOPED = re.compile(r"\b(frrk8s_\w+|up)\b(?!\{SCOPED)")


def panels(items):
    for panel in items:
        yield panel
        yield from panels(panel.get("panels", []))  # collapsed rows nest their panels


def datasource_ok(item):
    source = item.get("datasource")
    return isinstance(source, dict) and source.get("uid") == "${datasource}"


def check(path):
    with open(path) as f:
        dashboard = json.load(f)
    variables = {v["name"]: v for v in dashboard.get("templating", {}).get("list", [])}
    source = variables.get("datasource", {})
    if (source.get("type"), source.get("query")) != ("datasource", "prometheus") or not all(
            name in variables and datasource_ok(variables[name]) for name in ("job", "instance")):
        raise ValueError("needs a Prometheus datasource variable and job and instance variables that query it")
    ids, rules = set(), []
    for panel in panels(dashboard["panels"]):
        pid = panel["id"]
        if pid in ids:
            raise ValueError(f"duplicate panel id {pid}")
        ids.add(pid)
        targets = panel.get("targets", [])
        # Targets inherit the panel's datasource; an explicit target datasource must also be the variable.
        if targets and not all(map(datasource_ok, [panel, *(t for t in targets if "datasource" in t)])):
            raise ValueError(f"panel {pid}: datasource must be ${{datasource}}")
        for target in targets:
            expr = target["expr"]
            if m := UNSCOPED.search(STRING.sub('""', expr.replace(SCOPE, "{SCOPED"))):
                raise ValueError(f'panel {pid}: {m[1]} lacks {{job=~"$job", instance=~"$instance"}}')
            for var, value in (("$job", ".*"), ("$instance", ".*"), ("$__rate_interval", "1m")):
                expr = expr.replace(var, value)
            rules.append({"record": f"panel_{pid}_{target['refId']}", "expr": expr})
    # Compile all queries in one stable promtool call, as recording rules read from stdin.
    result = subprocess.run([os.environ.get("PROMTOOL", "promtool"), "check", "rules"], capture_output=True, text=True,
                            input=json.dumps({"groups": [{"name": "dashboard", "rules": rules}]}))
    if result.returncode:
        raise ValueError(f"invalid PromQL:\n{result.stdout}{result.stderr}")
    print(f"{path}: {len(rules)} queries OK")


for path in sys.argv[1:]:
    try:
        check(path)
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f"{path}: {error}")
