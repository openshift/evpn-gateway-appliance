#!/usr/bin/env python3
"""Compile dashboard PromQL, check panel IDs, CloudWatch panel queries and frr-k8s metric names,
and check alert rules: Grafana rule metadata and queries, and that every alert links its own
runbooks.md section."""
import json
import os
import re
import subprocess
import sys

import yaml  # PyYAML; Dockerfile.ci gets it with ansible-core and yamllint

HERE = os.path.dirname(os.path.abspath(__file__))
FRRK8S = re.compile(r"\bfrrk8s_\w+")
RUNBOOKS = "https://github.com/openshift/evpn-gateway-appliance/blob/main/monitoring/runbooks.md#"
CLOUDWATCH_FIELDS = ("namespace", "metricName", "statistic", "period")


def check_names(text, where):
    with open(os.path.join(HERE, "frrk8s-metrics.txt")) as f:
        known = {line.strip() for line in f if line.strip() and not line.startswith("#")}
    if unknown := sorted(set(FRRK8S.findall(text)) - known):
        raise ValueError(f"{where}: unknown frr-k8s series {', '.join(unknown)} (see frrk8s-metrics.txt)")


def panels(items):
    for panel in items:
        yield panel
        yield from panels(panel.get("panels", []))  # collapsed rows nest their panels


def expressions(dashboard):
    for panel in panels(dashboard.get("panels", [])):
        for target in panel.get("targets", []):
            if "expr" in target:
                yield target["expr"]
            elif target.get("datasource", {}).get("type") != "__expr__" and (
                    missing := [field for field in CLOUDWATCH_FIELDS if not target.get(field)]):
                raise ValueError(f"panel {panel.get('id')}: CloudWatch target has no {', '.join(missing)}")
    for variable in dashboard.get("templating", {}).get("list", []):
        if variable.get("type") != "query":
            continue
        query = variable.get("query", "")
        if isinstance(query, dict):
            query = query.get("query", "")  # CloudWatch variable queries have no PromQL
        if query:
            # Grafana's label_values(selector, label) wraps a Prometheus series selector.
            match = re.fullmatch(r"label_values\((.*),\s*\w+\)", query, re.DOTALL)
            yield match[1] if match else query


def check_dashboard(path):
    with open(path) as f:
        dashboard = json.load(f)
    rules = []
    for index, expr in enumerate(expressions(dashboard)):
        check_names(expr, f"query {index}")
        for name, value in (("job", ".*"), ("instance", ".*"), ("__rate_interval", "1m"), ("__interval", "1m")):
            expr = expr.replace(f"${name}", value).replace(f"${{{name}}}", value)
        rules.append({"record": f"query_{index}", "expr": expr})
    if rules:
        # Compile all expressions as recording rules in one promtool call, via stdin.
        result = subprocess.run([os.environ.get("PROMTOOL", "promtool"), "check", "rules"], capture_output=True,
                                text=True, input=json.dumps({"groups": [{"name": "dashboard", "rules": rules}]}))
        if result.returncode:
            raise ValueError(f"invalid PromQL:\n{result.stdout}{result.stderr}")
    return f"{len(rules)} PromQL expressions OK"


def check_alerts(path, dashboards, sections):
    """Check every alert in a Prometheus rule file or Grafana alert file; return the alert names."""
    with open(path) as f:
        text = f.read()
    check_names(text, "rules")
    names = []
    for group in (yaml.safe_load(text) or {}).get("groups", []):
        for rule in group.get("rules", []):
            if "record" in rule:
                continue
            name = rule.get("alert") or rule.get("title")
            if not name:
                raise ValueError("alert rule without alert or title")
            if rule.get("annotations", {}).get("runbook_url") != RUNBOOKS + name.lower() or name not in sections:
                raise ValueError(f"{name}: runbook_url must be {RUNBOOKS}{name.lower()} with a '## {name}' section")
            if "title" in rule:
                check_grafana_rule(name, rule, dashboards)
            names.append(name)
    return names


def check_grafana_rule(name, rule, dashboards):
    if rule.get("noDataState") not in ("Alerting", "NoData", "OK", "KeepLast") or rule.get(
            "execErrState") not in ("Alerting", "Error", "OK", "KeepLast"):
        raise ValueError(f"{name}: invalid noDataState or execErrState")
    if rule.get("panelId") not in dashboards.get(rule.get("dashboardUid"), ()):
        raise ValueError(f"{name}: dashboardUid and panelId must name a panel in these dashboards")
    seen = []
    for query in rule.get("data", []):
        model = query.get("model", {})
        if query.get("datasourceUid") == "__expr__":
            refs = re.findall(r"\$\{?(\w+)", model.get("expression", "")) if model.get("type") == "math" \
                else [model.get("expression")]
            if bad := [ref for ref in refs if ref not in seen]:
                raise ValueError(f"{name}: {query.get('refId')} reads {bad}, not an earlier query")
        elif missing := [field for field in CLOUDWATCH_FIELDS if not model.get(field)]:
            raise ValueError(f"{name}: query {query.get('refId')} has no {', '.join(missing)}")
        seen.append(query.get("refId"))
    expressions = [q.get("refId") for q in rule.get("data", []) if q.get("datasourceUid") == "__expr__"]
    if rule.get("condition") not in expressions:
        raise ValueError(f"{name}: condition must name an expression query")


def main(paths):
    failed, dashboards, alerts = False, {}, []
    with open(os.path.join(HERE, "runbooks.md")) as f:
        headings = re.findall(r"^## (\S+)$", f.read(), re.M)
    sections = set(headings)
    # Dashboards first, so Grafana alert rules can be checked against their panels.
    for path in sorted(paths, key=lambda p: not p.endswith(".json")):
        try:
            if path.endswith(".json"):
                with open(path) as f:
                    dashboard = json.load(f)
                ids = [p.get("id") for p in panels(dashboard.get("panels", []))]
                dashboards[dashboard.get("uid")] = set(ids)
                if None in ids or len(ids) != len(set(ids)):
                    raise ValueError("every panel needs a unique id")
                summary = check_dashboard(path)
            else:
                names = check_alerts(path, dashboards, sections)
                alerts += names
                summary = f"{len(names)} alerts OK"
            print(f"{path}: {summary}")
        except (OSError, ValueError, KeyError, TypeError, AttributeError, yaml.YAMLError) as error:
            print(f"{path}: {error}", file=sys.stderr)
            failed = True
    if problems := sorted({h for h in headings if headings.count(h) > 1} | (sections - set(alerts))):
        print(f"runbooks.md: sections repeated or without an alert: {', '.join(problems)}", file=sys.stderr)
        failed = True
    return failed


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
