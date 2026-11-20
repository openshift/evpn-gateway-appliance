"""Focused tests for dashboard PromQL compilation, the frr-k8s metric catalog and alert rules."""
import copy
import json
import os
import sys
import tempfile
import unittest

import yaml

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import check_dashboards  # noqa: E402

DASHBOARD = {
    "templating": {"list": [
        {"name": "job", "type": "query", "query": "label_values(frrk8s_scrape_success, job)"},
        {"name": "instance", "type": "query",
         "query": {"query": 'label_values(frrk8s_scrape_success{job=~"$job"}, instance)'}},
    ]},
    "panels": [{"panels": [
        {"targets": [{"expr": 'rate(frrk8s_bgp_updates_total{job=~"$job", instance=~"${instance}"}'
                               '[$__rate_interval])'}]},
        {"panels": [{"targets": [{"expr": "frrk8s_bgp_session_up offset $__interval"}]}]},
    ]}],
}


class CheckDashboardsTest(unittest.TestCase):
    def check(self, dashboard):
        with tempfile.NamedTemporaryFile("w", suffix=".json") as f:
            json.dump(dashboard, f)
            f.flush()
            return check_dashboards.check_dashboard(f.name)

    def test_nested_panels_and_variables_pass(self):
        self.assertEqual(self.check(DASHBOARD), "4 PromQL expressions OK")

    def test_invalid_promql_fails(self):
        for location in ("panel", "variable"):
            with self.subTest(location=location):
                dashboard = copy.deepcopy(DASHBOARD)
                invalid = "rate(frrk8s_bgp_updates_total)"  # rate requires a range vector
                if location == "panel":
                    dashboard["panels"][0]["panels"][1]["panels"][0]["targets"][0]["expr"] = invalid
                else:
                    dashboard["templating"]["list"][1]["query"]["query"] = f"label_values({invalid}, instance)"
                with self.assertRaisesRegex(ValueError, "invalid PromQL"):
                    self.check(dashboard)

    def test_unknown_frrk8s_name_fails(self):
        for location in ("panel", "variable", "rules"):
            with self.subTest(location=location):
                dashboard = copy.deepcopy(DASHBOARD)
                unknown = "frrk8s_made_up"
                with self.assertRaisesRegex(ValueError, unknown):
                    if location == "panel":
                        dashboard["panels"][0]["panels"][0]["targets"][0]["expr"] = unknown
                        self.check(dashboard)
                    elif location == "variable":
                        dashboard["templating"]["list"][0]["query"] = f"label_values({unknown}, job)"
                        self.check(dashboard)
                    else:
                        with tempfile.NamedTemporaryFile("w", suffix=".yaml") as f:
                            f.write(f"groups: [{{name: test, rules: [{{alert: Test, expr: {unknown} == 0}}]}}]\n")
                            f.flush()
                            check_dashboards.check_alerts(f.name, {}, set())

    def test_cloudwatch_target_without_metric_fails(self):
        dashboard = copy.deepcopy(DASHBOARD)
        dashboard["panels"][0]["panels"][0]["targets"] = [{"namespace": "AWS/DX", "statistic": "Minimum", "period": "300"}]
        with self.assertRaisesRegex(ValueError, "metricName"):
            self.check(dashboard)


class CheckAlertsTest(unittest.TestCase):
    with open(os.path.join(check_dashboards.HERE, "grafana", "aws-transport-alerts.yaml")) as f:
        ALERTS = yaml.safe_load(f)
    RULE = ALERTS["groups"][0]["rules"][0]
    DASHBOARDS = {"ega-aws-transport": {1, 2, 3}}

    def check(self, change=None, sections=None):
        alerts = copy.deepcopy(self.ALERTS)
        if change:
            change(alerts["groups"][0]["rules"][0])
        with tempfile.NamedTemporaryFile("w", suffix=".yaml") as f:
            yaml.safe_dump(alerts, f)
            f.flush()
            names = [r["title"] for r in self.ALERTS["groups"][0]["rules"]]
            return check_dashboards.check_alerts(f.name, self.DASHBOARDS, set(names) if sections is None else sections)

    def test_broken_alerts_fail(self):
        cases = {
            "runbook_url": lambda r: r["annotations"].update(runbook_url="https://example.com/x"),
            "panel": lambda r: r.update(panelId=99),
            "condition": lambda r: r.update(condition="A"),
            "earlier query": lambda r: r["data"][2]["model"].update(expression="$D < 1"),
            "metricName": lambda r: r["data"][0]["model"].pop("metricName"),
            "noDataState": lambda r: r.update(noDataState="Missing"),
        }
        for message, change in cases.items():
            with self.subTest(message), self.assertRaisesRegex(ValueError, message):
                self.check(change)
        with self.assertRaisesRegex(ValueError, "section"):
            self.check(sections=set())


if __name__ == "__main__":
    unittest.main()
