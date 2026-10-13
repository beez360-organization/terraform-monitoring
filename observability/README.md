# Observabilité Beez360 — stack Azure-native

Azure Managed Grafana en lecture sur Azure Monitor (métriques, Log Analytics,
Application Insights) des subscriptions Beez360, avec :
- routage central des alertes (action group) ;
- alerte Azure Service Health ;
- 5 dashboards versionnés.

Pourquoi elle remplace les VM Prometheus/Loki : [../docs/REVIEW_MONITORING_2026-10.md](../docs/REVIEW_MONITORING_2026-10.md).
Elle tourne **en parallèle** de l'ancienne stack (racine du repo, autre clé
d'état) jusqu'au décommissionnement.

## Contenu

| Fichier | Rôle |
|---|---|
| `main.tf` | RG, Grafana (SKU Essential par défaut, identité managée, SSO Entra), `Monitoring Reader` sur chaque subscription, rôles Grafana par groupe Entra, action group `beez360-ops-ag`, alerte Service Health |
| `dashboards/generate.py` | **Source** des dashboards → génère `dashboards/*.json` |
| `scripts/publish-dashboards.sh` | Publie les JSON dans le dossier « Beez360 » (`az grafana`, auth Entra) |
| `.github/workflows/observability.yaml` | fmt/validate, vérifie que les JSON sont à jour, plan, apply + publication (environnement `observability`) |

## Déployer

```bash
cp terraform.tfvars.example terraform.tfvars    # identifiants seulement
export TF_VAR_alert_webhook_url='<webhook Teams>' # jamais dans git
tofu init && tofu apply
scripts/publish-dashboards.sh "$(tofu output -raw grafana_name)"
```

L'identité qui applique doit pouvoir attribuer des rôles (*Owner* ou *User
Access Administrator*) sur les subscriptions surveillées.

## Modifier un dashboard

1. Éditer `dashboards/generate.py`, puis `python3 -I dashboards/generate.py`.
2. Committer le `.py` **et** les `.json` : la CI échoue si les JSON ne sont
   pas régénérés.
3. Un dashboard prototypé dans l'UI Grafana se reporte dans `generate.py`.
   Sinon, la publication suivante l'écrase.

## Brancher les alertes des plateformes

Le module plateforme crée les alertes (`enable_alerts = true` sur les types
prod). Pour les router ici, mettre `alert_action_group_id` dans
`platforms/<tier>/tier.hcl` (repo envs) à la valeur de
`tofu output ops_action_group_id`.
