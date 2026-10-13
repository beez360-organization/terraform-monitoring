#!/usr/bin/env python3
"""Generate the Beez360 Grafana dashboards (Azure Monitor data source).

Source of truth for the dashboards in this folder: edit this file, then run
    python3 -I observability/dashboards/generate.py
and commit the regenerated *.json. scripts/publish-dashboards.sh pushes them.

Every dashboard is platform-agnostic: it is driven by variables
    ds (Azure Monitor data source) → sub (subscription) → platform (resource group)
and finds the platform's resources by the naming convention of the platform
module ({prefix}-api-webapp, -backend-asp, -psql, …). It therefore works for the
legacy stacks (beez360/, otacos/, bigm-burger/) and for every platforms/ unit.
"""

import json
import pathlib

OUT = pathlib.Path(__file__).resolve().parent
DS = {"type": "grafana-azure-monitor-datasource", "uid": "${ds}"}
RG_SCOPE = "/subscriptions/$sub/resourceGroups/$platform"

NS_SITE = "microsoft.web/sites"
NS_PLAN = "microsoft.web/serverfarms"
NS_PG = "microsoft.dbforpostgresql/flexibleservers"
NS_REDIS = "microsoft.cache/redis"

APPS = [("api", "API"), ("backoffice", "Backoffice"), ("clickcollect", "Click & Collect")]


# ─── Variables ──────────────────────────────────────────────────────────────
def v_ds():
    return {"name": "ds", "label": "Data source", "type": "datasource",
            "query": "grafana-azure-monitor-datasource", "hide": 0, "refresh": 1,
            "current": {}, "options": []}


def v_sub(multi=False):
    return {"name": "sub", "label": "Subscription", "type": "query", "datasource": DS,
            "query": {"queryType": "Azure Subscriptions", "refId": "A"},
            "refresh": 1, "hide": 0, "multi": multi, "includeAll": multi, "current": {},
            "options": [], "sort": 1}


def v_platform():
    return {"name": "platform", "label": "Platform", "type": "query", "datasource": DS,
            "query": {"queryType": "Azure Resource Groups", "subscription": "$sub", "refId": "A"},
            "regex": "/^(beez360-[a-z0-9-]+-rg)$/", "refresh": 1, "hide": 0, "sort": 1,
            "current": {}, "options": []}


def v_resource(name, label, namespace, suffix, hide=2):
    return {"name": name, "label": label, "type": "query", "datasource": DS,
            "query": {"queryType": "Azure Resource Names", "subscription": "$sub",
                      "resourceGroup": "$platform", "namespace": namespace, "refId": "A"},
            "regex": f"/^(.*{suffix})$/", "refresh": 2, "hide": hide, "current": {},
            "options": []}


def v_text(name, label, default=""):
    return {"name": name, "label": label, "type": "textbox", "query": default,
            "current": {"text": default, "value": default}, "hide": 0}


def site_vars():
    return [v_resource("api", "API", NS_SITE, "-api-webapp"),
            v_resource("backoffice", "Backoffice", NS_SITE, "-backoffice-webapp"),
            v_resource("clickcollect", "Click & Collect", NS_SITE, "-clickandcollect-webapp")]


# ─── Targets ────────────────────────────────────────────────────────────────
def metric(ref, namespace, resource_var, name, agg, legend=None, dims=None):
    return {
        "refId": ref, "datasource": DS, "queryType": "Azure Monitor", "subscription": "$sub",
        "azureMonitor": {
            "resources": [{"subscription": "$sub", "resourceGroup": "$platform",
                           "metricNamespace": namespace, "resourceName": f"${resource_var}"}],
            "metricNamespace": namespace, "metricName": name, "aggregation": agg,
            "timeGrain": "auto", "allowedTimeGrainsMs": [], "dimensionFilters": dims or [],
            "alias": legend or "",
        },
    }


def kql(ref, query, fmt="time_series"):
    return {"refId": ref, "datasource": DS, "queryType": "Azure Log Analytics",
            "azureLogAnalytics": {"query": query.strip(), "resources": [RG_SCOPE],
                                  "resultFormat": fmt, "dashboardTime": False}}


def arg(ref, query):
    return {"refId": ref, "datasource": DS, "queryType": "Azure Resource Graph",
            "subscriptions": ["$sub"],
            "azureResourceGraph": {"query": query.strip(), "resultFormat": "table"}}


# ─── Panels ─────────────────────────────────────────────────────────────────
class Layout:
    """Left-to-right, top-to-bottom placement on Grafana's 24-column grid."""

    def __init__(self):
        self.x, self.y, self.row_h, self.next_id, self.panels = 0, 0, 0, 1, []

    def _place(self, w, h):
        if self.x + w > 24:
            self.x, self.y, self.row_h = 0, self.y + self.row_h, 0
        pos = {"x": self.x, "y": self.y, "w": w, "h": h}
        self.x += w
        self.row_h = max(self.row_h, h)
        return pos

    def row(self, title):
        if self.x:
            self.x, self.y, self.row_h = 0, self.y + self.row_h, 0
        self.panels.append({"id": self.next_id, "type": "row", "title": title, "collapsed": False,
                            "gridPos": {"x": 0, "y": self.y, "w": 24, "h": 1}, "panels": []})
        self.next_id += 1
        self.y += 1

    def add(self, panel, w, h):
        panel["id"] = self.next_id
        panel["gridPos"] = self._place(w, h)
        panel.setdefault("datasource", DS)
        self.next_id += 1
        self.panels.append(panel)


def thresholds(*steps):
    """steps: (value, color) pairs; first value is ignored (base)."""
    return {"mode": "absolute",
            "steps": [{"value": None if i == 0 else v, "color": c} for i, (v, c) in enumerate(steps)]}


def stat(title, targets, unit="short", th=None, desc="", reduce="sum", decimals=None):
    defaults = {"unit": unit, "thresholds": th or thresholds((None, "green")), "color": {"mode": "thresholds"}}
    if decimals is not None:
        defaults["decimals"] = decimals
    return {"type": "stat", "title": title, "description": desc, "targets": targets,
            "fieldConfig": {"defaults": defaults, "overrides": []},
            "options": {"reduceOptions": {"calcs": [reduce], "fields": "", "values": False},
                        "colorMode": "background", "graphMode": "area", "textMode": "value",
                        "justifyMode": "center", "orientation": "auto"}}


def ts(title, targets, unit="short", desc="", stack=False, th=None, draw="line"):
    custom = {"drawStyle": draw, "lineWidth": 2, "fillOpacity": 12, "showPoints": "never",
              "spanNulls": True, "stacking": {"mode": "normal" if stack else "none", "group": "A"}}
    defaults = {"unit": unit, "custom": custom, "color": {"mode": "palette-classic"}}
    if th:
        defaults["thresholds"] = th
        custom["thresholdsStyle"] = {"mode": "line+area"}
    return {"type": "timeseries", "title": title, "description": desc, "targets": targets,
            "fieldConfig": {"defaults": defaults, "overrides": []},
            "options": {"legend": {"displayMode": "table", "placement": "bottom",
                                   "calcs": ["mean", "max", "lastNotNull"]},
                        "tooltip": {"mode": "multi", "sort": "desc"}}}


def gauge(title, targets, unit="percent", th=None, desc=""):
    return {"type": "gauge", "title": title, "description": desc, "targets": targets,
            "fieldConfig": {"defaults": {"unit": unit, "min": 0, "max": 100,
                                         "thresholds": th or thresholds((None, "green"), (70, "orange"), (85, "red"))},
                            "overrides": []},
            "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                        "showThresholdMarkers": True}}


def table(title, targets, desc="", overrides=None):
    return {"type": "table", "title": title, "description": desc, "targets": targets,
            "fieldConfig": {"defaults": {"custom": {"filterable": True, "cellOptions": {"type": "auto"}}},
                            "overrides": overrides or []},
            "options": {"showHeader": True, "cellHeight": "sm", "footer": {"show": False}}}


def logs(title, targets, desc=""):
    return {"type": "logs", "title": title, "description": desc, "targets": targets,
            "options": {"showTime": True, "wrapLogMessage": True, "sortOrder": "Descending",
                        "enableLogDetails": True, "dedupStrategy": "none"}}


def pie(title, targets, desc=""):
    return {"type": "piechart", "title": title, "description": desc, "targets": targets,
            "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": True},
                        "pieType": "donut", "legend": {"displayMode": "table", "placement": "right",
                                                       "values": ["value", "percent"]}}}


def color_override(field, mode):
    return {"matcher": {"id": "byName", "options": field},
            "properties": [{"id": "custom.cellOptions", "value": {"type": mode}}]}


# ─── Dashboard envelope ─────────────────────────────────────────────────────
def dashboard(uid, title, desc, variables, layout, refresh="5m", time_from="now-6h"):
    return {
        "uid": uid, "title": title, "description": desc, "tags": ["beez360"],
        "editable": True, "graphTooltip": 1, "schemaVersion": 39, "version": 1,
        "time": {"from": time_from, "to": "now"}, "refresh": refresh, "timezone": "browser",
        "templating": {"list": variables},
        "links": [{"title": "Beez360", "type": "dashboards", "tags": ["beez360"], "asDropdown": True,
                   "includeVars": True, "keepTime": True}],
        "annotations": {"list": []},
        "panels": layout.panels,
    }


# ─── 1. Platform overview ───────────────────────────────────────────────────
def platform_overview():
    L = Layout()
    red_5xx = thresholds((None, "green"), (1, "orange"), (10, "red"))
    L.row("Santé — période sélectionnée")
    L.add(stat("API · requêtes", [metric("A", NS_SITE, "api", "Requests", "Total")]), 4, 4)
    L.add(stat("API · erreurs 5xx", [metric("A", NS_SITE, "api", "Http5xx", "Total")], th=red_5xx), 4, 4)
    L.add(stat("API · temps de réponse moyen", [metric("A", NS_SITE, "api", "HttpResponseTime", "Average")],
               unit="s", reduce="mean", decimals=2,
               th=thresholds((None, "green"), (1, "orange"), (2, "red"))), 4, 4)
    L.add(stat("API · health check", [metric("A", NS_SITE, "api", "HealthCheckStatus", "Average")],
               unit="percent", reduce="lastNotNull",
               th=thresholds((None, "red"), (99, "orange"), (100, "green")),
               desc="100 % = toutes les instances répondent au health check"), 4, 4)
    L.add(stat("Backoffice · erreurs 5xx", [metric("A", NS_SITE, "backoffice", "Http5xx", "Total")], th=red_5xx), 4, 4)
    L.add(stat("Click & Collect · erreurs 5xx", [metric("A", NS_SITE, "clickcollect", "Http5xx", "Total")], th=red_5xx), 4, 4)

    L.row("Trafic & erreurs par application")
    L.add(ts("Requêtes", [metric(r, NS_SITE, v, "Requests", "Total", label) for r, (v, label) in zip("ABC", APPS)]), 8, 8)
    L.add(ts("Erreurs HTTP 5xx", [metric(r, NS_SITE, v, "Http5xx", "Total", label) for r, (v, label) in zip("ABC", APPS)],
             draw="bars"), 8, 8)
    L.add(ts("Erreurs HTTP 4xx", [metric(r, NS_SITE, v, "Http4xx", "Total", label) for r, (v, label) in zip("ABC", APPS)],
             draw="bars"), 8, 8)
    L.add(ts("Temps de réponse moyen", [metric(r, NS_SITE, v, "HttpResponseTime", "Average", label)
                                         for r, (v, label) in zip("ABC", APPS)], unit="s",
             th=thresholds((None, "transparent"), (2, "red"))), 12, 8)
    L.add(ts("Mémoire (working set)", [metric(r, NS_SITE, v, "MemoryWorkingSet", "Average", label)
                                        for r, (v, label) in zip("ABC", APPS)], unit="bytes"), 12, 8)

    L.row("Capacité — App Service Plans")
    plans = [("backendplan", "Plan backend"), ("frontendplan", "Plan frontend")]
    pct = thresholds((None, "transparent"), (85, "red"))
    L.add(ts("CPU %", [metric(r, NS_PLAN, v, "CpuPercentage", "Average", label) for r, (v, label) in zip("AB", plans)],
             unit="percent", th=pct), 8, 8)
    L.add(ts("Mémoire %", [metric(r, NS_PLAN, v, "MemoryPercentage", "Average", label) for r, (v, label) in zip("AB", plans)],
             unit="percent", th=pct), 8, 8)
    L.add(ts("File d'attente HTTP", [metric(r, NS_PLAN, v, "HttpQueueLength", "Average", label)
                                      for r, (v, label) in zip("AB", plans)],
             desc="Une file > 0 durable = instances saturées (scale up/out)"), 8, 8)

    L.row("PostgreSQL")
    L.add(gauge("Stockage utilisé", [metric("A", NS_PG, "psql", "storage_percent", "Maximum")]), 4, 7)
    L.add(gauge("CPU", [metric("A", NS_PG, "psql", "cpu_percent", "Average")]), 4, 7)
    L.add(gauge("Mémoire", [metric("A", NS_PG, "psql", "memory_percent", "Average")]), 4, 7)
    L.add(ts("Connexions", [metric("A", NS_PG, "psql", "active_connections", "Average", "actives"),
                            metric("B", NS_PG, "psql", "connections_failed", "Total", "échouées")]), 12, 7)

    L.row("Redis (plateformes mutualisées)")
    L.add(ts("Mémoire utilisée %", [metric("A", NS_REDIS, "redis", "usedmemorypercentage", "Maximum")],
             unit="percent", th=pct), 8, 7)
    L.add(ts("Charge serveur %", [metric("A", NS_REDIS, "redis", "serverLoad", "Maximum")], unit="percent", th=pct), 8, 7)
    L.add(ts("Cache hits / misses", [metric("A", NS_REDIS, "redis", "cachehits", "Total", "hits"),
                                     metric("B", NS_REDIS, "redis", "cachemisses", "Total", "misses")]), 8, 7)

    variables = [v_ds(), v_sub(), v_platform(), *site_vars(),
                 v_resource("backendplan", "Plan backend", NS_PLAN, "-backend-asp"),
                 v_resource("frontendplan", "Plan frontend", NS_PLAN, "-frontend-asp"),
                 v_resource("psql", "PostgreSQL", NS_PG, "-psql"),
                 v_resource("redis", "Redis", NS_REDIS, "-redis")]
    return dashboard("beez360-platform-overview", "Beez360 · Vue plateforme",
                     "Santé, trafic, capacité et données d'une plateforme (métriques Azure Monitor).",
                     variables, L)


# ─── 2. API performance (Application Insights, workspace-based) ─────────────
def api_performance():
    L = Layout()
    L.row("Indicateurs clés (Application Insights)")
    L.add(stat("Requêtes", [kql("A", "AppRequests | where $__timeFilter(TimeGenerated) | summarize Requests = count()", "table")],
               reduce="lastNotNull"), 6, 4)
    L.add(stat("Taux d'échec", [kql("A", """
AppRequests | where $__timeFilter(TimeGenerated)
| summarize FailureRate = 100.0 * countif(Success == false) / count()""", "table")],
               unit="percent", reduce="lastNotNull", decimals=2,
               th=thresholds((None, "green"), (1, "orange"), (5, "red"))), 6, 4)
    L.add(stat("Latence P95", [kql("A", """
AppRequests | where $__timeFilter(TimeGenerated)
| summarize P95 = percentile(DurationMs, 95)""", "table")],
               unit="ms", reduce="lastNotNull", th=thresholds((None, "green"), (800, "orange"), (2000, "red"))), 6, 4)
    L.add(stat("Exceptions", [kql("A", "AppExceptions | where $__timeFilter(TimeGenerated) | summarize Exceptions = count()", "table")],
               reduce="lastNotNull", th=thresholds((None, "green"), (1, "orange"), (50, "red"))), 6, 4)

    L.row("Requêtes")
    L.add(ts("Requêtes par classe de statut", [kql("A", """
AppRequests | where $__timeFilter(TimeGenerated)
| extend Status = case(toint(ResultCode) >= 500, "5xx", toint(ResultCode) >= 400, "4xx", "2xx/3xx")
| summarize Requests = count() by bin(TimeGenerated, $__interval), Status
| order by TimeGenerated asc""")], stack=True, draw="bars"), 12, 8)
    L.add(ts("Latence P50 / P95 / P99", [kql("A", """
AppRequests | where $__timeFilter(TimeGenerated)
| summarize P50 = percentile(DurationMs, 50), P95 = percentile(DurationMs, 95), P99 = percentile(DurationMs, 99)
    by bin(TimeGenerated, $__interval)
| order by TimeGenerated asc""")], unit="ms"), 12, 8)
    L.add(table("Opérations les plus lentes (P95)", [kql("A", """
AppRequests | where $__timeFilter(TimeGenerated)
| summarize Requests = count(), P95_ms = round(percentile(DurationMs, 95), 0), Failures = countif(Success == false)
    by Operation = OperationName, Application = AppRoleName
| top 15 by P95_ms desc""", "table")]), 12, 9)
    L.add(table("Opérations en échec", [kql("A", """
AppRequests | where $__timeFilter(TimeGenerated) and Success == false
| summarize Failures = count(), LastSeen = max(TimeGenerated) by Operation = OperationName, ResultCode, Application = AppRoleName
| top 15 by Failures desc""", "table")]), 12, 9)

    L.row("Exceptions & dépendances")
    L.add(ts("Exceptions par type", [kql("A", """
AppExceptions | where $__timeFilter(TimeGenerated)
| summarize Exceptions = count() by bin(TimeGenerated, $__interval), ExceptionType
| order by TimeGenerated asc""")], stack=True, draw="bars"), 12, 8)
    L.add(table("Top exceptions", [kql("A", """
AppExceptions | where $__timeFilter(TimeGenerated)
| summarize Count = count(), LastSeen = max(TimeGenerated), Message = take_any(OuterMessage)
    by ProblemId, Application = AppRoleName
| top 15 by Count desc""", "table")]), 12, 8)
    L.add(ts("Dépendances en échec (DB, APIs externes…)", [kql("A", """
AppDependencies | where $__timeFilter(TimeGenerated) and Success == false
| summarize Failures = count() by bin(TimeGenerated, $__interval), Target
| order by TimeGenerated asc""")], draw="bars", stack=True), 12, 8)
    L.add(table("Dépendances les plus lentes", [kql("A", """
AppDependencies | where $__timeFilter(TimeGenerated)
| summarize Calls = count(), P95_ms = round(percentile(DurationMs, 95), 0), Failures = countif(Success == false)
    by Type = DependencyType, Target
| top 15 by P95_ms desc""", "table")]), 12, 8)

    return dashboard("beez360-api-performance", "Beez360 · Performance applicative",
                     "Requêtes, latence, exceptions et dépendances (Application Insights via Log Analytics, "
                     "requêtes à l'échelle du resource group de la plateforme).",
                     [v_ds(), v_sub(), v_platform()], L)


# ─── 3. Logs & HTTP ─────────────────────────────────────────────────────────
def logs_dashboard():
    L = Layout()
    app_name = "extend App = tostring(split(_ResourceId, '/')[-1])"
    L.row("HTTP (diagnostics App Service)")
    L.add(ts("Statuts HTTP par application", [kql("A", f"""
AppServiceHTTPLogs | where $__timeFilter(TimeGenerated)
| {app_name}
| extend Status = strcat(App, " · ", tostring(ScStatus / 100), "xx")
| summarize Requests = count() by bin(TimeGenerated, $__interval), Status
| order by TimeGenerated asc""")], stack=True, draw="bars"), 24, 8)
    L.add(table("URLs en erreur 5xx", [kql("A", f"""
AppServiceHTTPLogs | where $__timeFilter(TimeGenerated) and ScStatus >= 500
| {app_name}
| summarize Errors = count(), LastSeen = max(TimeGenerated) by App, CsMethod, CsUriStem, ScStatus
| top 20 by Errors desc""", "table")]), 12, 9)
    L.add(table("URLs les plus lentes (P95)", [kql("A", f"""
AppServiceHTTPLogs | where $__timeFilter(TimeGenerated)
| {app_name}
| summarize Requests = count(), P95_ms = percentile(TimeTaken, 95) by App, CsMethod, CsUriStem
| where Requests > 5
| top 20 by P95_ms desc""", "table")]), 12, 9)

    L.row("Logs applicatifs (console des conteneurs)")
    L.add(ts("Lignes d'erreur par application", [kql("A", f"""
AppServiceConsoleLogs | where $__timeFilter(TimeGenerated)
| where Level =~ "Error" or ResultDescription has_any ("error", "exception", "fatal")
| {app_name}
| summarize Errors = count() by bin(TimeGenerated, $__interval), App
| order by TimeGenerated asc""")], draw="bars", stack=True), 24, 7)
    L.add(logs("Console — recherche « $search »", [kql("A", f"""
AppServiceConsoleLogs | where $__timeFilter(TimeGenerated)
| where ResultDescription contains "$search"
| {app_name}
| project TimeGenerated, App, Level, Message = ResultDescription
| order by TimeGenerated desc
| take 500""", "logs")],
                desc="Filtrer avec la variable « Recherche » (texte libre, sensible à la casse)."), 24, 12)

    L.row("Plateforme App Service & PostgreSQL")
    L.add(table("Événements conteneurs (démarrage, pull d'image, crash)", [kql("A", f"""
AppServicePlatformLogs | where $__timeFilter(TimeGenerated)
| {app_name}
| project TimeGenerated, App, Level, Message
| order by TimeGenerated desc
| take 200""", "table")]), 12, 10)
    L.add(table("PostgreSQL — erreurs", [kql("A", """
AzureDiagnostics | where $__timeFilter(TimeGenerated)
| where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL" and Category == "PostgreSQLLogs"
| where Message has_any ("ERROR", "FATAL", "PANIC")
| project TimeGenerated, Server = Resource, Message
| order by TimeGenerated desc
| take 200""", "table")]), 12, 10)

    return dashboard("beez360-logs", "Beez360 · Logs & HTTP",
                     "Logs HTTP, console des conteneurs, événements plateforme et erreurs PostgreSQL "
                     "(diagnostics → Log Analytics de la plateforme).",
                     [v_ds(), v_sub(), v_platform(), v_text("search", "Recherche", "")], L, time_from="now-3h")


# ─── 4. PostgreSQL deep dive ────────────────────────────────────────────────
def postgres():
    L = Layout()

    def m(ref, name, agg, legend=None):
        return metric(ref, NS_PG, "psql", name, agg, legend)

    L.row("Disponibilité & saturation")
    L.add(stat("Base joignable", [m("A", "is_db_alive", "Minimum")], reduce="min",
               th=thresholds((None, "red"), (1, "green")), desc="1 = la base répond"), 4, 5)
    L.add(gauge("CPU", [m("A", "cpu_percent", "Average")]), 5, 5)
    L.add(gauge("Mémoire", [m("A", "memory_percent", "Average")]), 5, 5)
    L.add(gauge("Stockage", [m("A", "storage_percent", "Maximum")]), 5, 5)
    L.add(stat("Connexions échouées", [m("A", "connections_failed", "Total")],
               th=thresholds((None, "green"), (1, "orange"), (20, "red"))), 5, 5)

    L.row("Charge")
    pct = thresholds((None, "transparent"), (85, "red"))
    L.add(ts("CPU / mémoire %", [m("A", "cpu_percent", "Average", "CPU"), m("B", "memory_percent", "Average", "mémoire")],
             unit="percent", th=pct), 12, 8)
    L.add(ts("Connexions", [m("A", "active_connections", "Average", "actives"),
                            m("B", "connections_succeeded", "Total", "réussies"),
                            m("C", "connections_failed", "Total", "échouées")]), 12, 8)
    L.add(ts("IOPS lecture / écriture", [m("A", "read_iops", "Average", "lecture"), m("B", "write_iops", "Average", "écriture")],
             unit="iops"), 8, 8)
    L.add(ts("File d'attente disque", [m("A", "disk_queue_depth", "Average")],
             desc="Durablement > 1 : stockage sous-dimensionné (IOPS)"), 8, 8)
    L.add(ts("Réseau", [m("A", "network_bytes_ingress", "Total", "entrant"), m("B", "network_bytes_egress", "Total", "sortant")],
             unit="bytes"), 8, 8)

    L.row("Stockage")
    L.add(ts("Stockage utilisé", [m("A", "storage_used", "Maximum", "données"),
                                  m("B", "txlogs_storage_used", "Maximum", "journaux de transactions")],
             unit="bytes"), 12, 8)
    L.add(ts("Transaction IDs consommés", [m("A", "maximum_used_transactionIDs", "Maximum")],
             desc="Approche de 2^31 = risque de wraparound : VACUUM nécessaire"), 12, 8)

    return dashboard("beez360-postgresql", "Beez360 · PostgreSQL",
                     "Disponibilité, saturation, connexions, IO et stockage du serveur PostgreSQL Flexible d'une plateforme.",
                     [v_ds(), v_sub(), v_platform(), v_resource("psql", "Serveur", NS_PG, "-psql", hide=0)], L)


# ─── 5. Fleet (all platforms, Azure Resource Graph) ─────────────────────────
def fleet():
    L = Layout()
    beez_rg = "resourceGroup startswith 'beez360-'"
    L.row("Parc")
    L.add(stat("Plateformes", [arg("A", """
resourcecontainers
| where type == 'microsoft.resources/subscriptions/resourcegroups' and name startswith 'beez360-' and name endswith '-rg'
| where name !contains 'tfstate' and name !contains 'observability'
| summarize Platforms = count()""")], reduce="lastNotNull"), 6, 4)
    L.add(stat("Web apps", [arg("A", f"resources | where type =~ 'microsoft.web/sites' and {beez_rg} | summarize Apps = count()")],
               reduce="lastNotNull"), 6, 4)
    L.add(stat("Web apps arrêtées", [arg("A", f"""
resources | where type =~ 'microsoft.web/sites' and {beez_rg}
| where tostring(properties.state) != 'Running' | summarize Stopped = count()""")],
               reduce="lastNotNull", th=thresholds((None, "green"), (1, "red"))), 6, 4)
    L.add(stat("Alertes actives", [arg("A", """
alertsmanagementresources
| where type =~ 'microsoft.alertsmanagement/alerts'
| where tostring(properties.essentials.monitorCondition) == 'Fired'
| where tostring(properties.essentials.targetResourceGroup) startswith 'beez360-'
| summarize Fired = count()""")], reduce="lastNotNull", th=thresholds((None, "green"), (1, "red"))), 6, 4)

    L.add(table("Inventaire des plateformes", [arg("A", """
resourcecontainers
| where type == 'microsoft.resources/subscriptions/resourcegroups' and name startswith 'beez360-' and name endswith '-rg'
| project Platform = name, Type = tostring(tags.PlatformType), Tier = tostring(tags.Tier),
          Environment = tostring(tags.Environment), Country = tostring(tags.Country),
          CostCenter = tostring(tags.CostCenter), Region = location, subscriptionId
| order by Type asc, Platform asc""")]), 24, 9)

    L.row("Alertes & posture")
    L.add(table("Alertes déclenchées", [arg("A", """
alertsmanagementresources
| where type =~ 'microsoft.alertsmanagement/alerts'
| where tostring(properties.essentials.monitorCondition) == 'Fired'
| where tostring(properties.essentials.targetResourceGroup) startswith 'beez360-'
| project Started = todatetime(properties.essentials.startDateTime), Severity = tostring(properties.essentials.severity),
          Alert = name, Platform = tostring(properties.essentials.targetResourceGroup),
          Resource = tostring(split(tostring(properties.essentials.targetResource), '/')[-1])
| order by Started desc""")]), 24, 8)
    L.add(table("Exposition réseau des services de données", [arg("A", f"""
resources
| where {beez_rg}
| where type in~ ('microsoft.keyvault/vaults', 'microsoft.storage/storageaccounts',
                  'microsoft.containerregistry/registries', 'microsoft.dbforpostgresql/flexibleservers',
                  'microsoft.cache/redis')
| extend PublicAccess = coalesce(tostring(properties.publicNetworkAccess), tostring(properties.network.publicNetworkAccess))
| extend PrivateEndpoints = array_length(properties.privateEndpointConnections)
| project Platform = resourceGroup, Service = tostring(split(type, '/')[1]), Name = name, PublicAccess, PrivateEndpoints
| order by Platform asc, Service asc""")],
                desc="« Enabled » sans private endpoint sur une plateforme prod = à corriger."), 24, 9)

    L.row("Données")
    L.add(table("Serveurs PostgreSQL", [arg("A", f"""
resources
| where type =~ 'microsoft.dbforpostgresql/flexibleservers' and {beez_rg}
| project Platform = resourceGroup, Server = name, Version = tostring(properties.version), Sku = tostring(sku.name),
          HA = tostring(properties.highAvailability.mode), StorageGB = toint(properties.storage.storageSizeGB),
          GeoBackup = tostring(properties.backup.geoRedundantBackup), BackupDays = toint(properties.backup.backupRetentionDays),
          State = tostring(properties.state)
| order by Platform asc""")]), 24, 8)
    L.add(pie("Ressources par type", [arg("A", f"""
resources | where {beez_rg}
| summarize Count = count() by Type = tostring(split(type, '/')[1])
| order by Count desc""")]), 12, 9)
    L.add(pie("Plateformes par type", [arg("A", """
resourcecontainers
| where type == 'microsoft.resources/subscriptions/resourcegroups' and name startswith 'beez360-' and name endswith '-rg'
| summarize Count = count() by Type = coalesce(tostring(tags.PlatformType), 'legacy')""")]), 12, 9)

    return dashboard("beez360-fleet", "Beez360 · Parc des plateformes",
                     "Vue transverse de toutes les plateformes (prod, non-prod, legacy) via Azure Resource Graph : "
                     "inventaire, alertes actives, exposition réseau, bases de données.",
                     [v_ds(), v_sub(multi=True)], L, refresh="15m", time_from="now-24h")


def main():
    for build in (fleet, platform_overview, api_performance, logs_dashboard, postgres):
        d = build()
        path = OUT / f"{d['uid']}.json"
        path.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"wrote {path.name} ({len(d['panels'])} panels)")


if __name__ == "__main__":
    main()
