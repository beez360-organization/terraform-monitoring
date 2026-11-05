# Revue monitoring Beez360 — octobre 2026

> Remplace la décision « self-hosted LGTM durci » de [HARDENING.md](../HARDENING.md).
> La nouvelle stack est dans [`observability/`](../observability) ; l'ancienne
> (racine du repo) continue de tourner jusqu'au décommissionnement.

## 1. Ce qui existe

```
App Service ──diag (configuré à la main)──▶ Event Hub Standard ──▶ Fluent Bit ─┐
                                                                               ▼
Azure Monitor ◀── Promitor (scrape 1 RG) ── VM metrics (B2s, IP publique)   VM logs-traces (B2s, IP publique)
                   Prometheus 2.49 + Alertmanager + Grafana (SQLite)          Loki + Tempo (Blob)
```

| Composant | Constat |
|---|---|
| 2 VM `Standard_B2s` Ubuntu, IP publiques, cloud-init | Tout est installé à la main par script (Prometheus 2.49, Promitor 2.6, Loki, Tempo, Grafana apt). Pas de mise à jour automatique, pas de sauvegarde Grafana (SQLite sur disque), pas de HA. `vm_size` et l'image sont codés en dur malgré les variables. |
| Event Hub Standard + Fluent Bit + Loki | Les logs App Service n'arrivent dans l'Event Hub que via des diagnostic settings **créés à la main** : le module plateforme envoie les logs vers **Log Analytics**, pas vers l'Event Hub. Pour toute nouvelle plateforme, Loki reste vide. |
| Promitor | Scrape **un seul** resource group (`beez360-frc-franchisee-paris-dev-rg`). Les autres plateformes ne sont pas surveillées. |
| Tempo | Aucune application n'envoie de traces OTLP vers lui ; les traces existent déjà dans Application Insights. |
| Dashboards (5) | Noms de ressources et subscription **en dur** (`franchisee-paris-dev`), aucune variable : inutilisables pour une autre plateforme. Mélangent Prometheus et Loki. |
| Alerting | Règles Prometheus + Alertmanager, webhook optionnel : si la VM tombe, plus aucune alerte. |
| Réseau | VNet `10.0.0.0/16` : **chevauche la plage réservée aux hubs** du nouveau modèle plateforme → ne jamais l'appairer. |
| `terragrunt-monitoring` | Stub non fonctionnel (`inputs = {}`, backend en conflit avec celui du module). |

Le durcissement précédent (secrets en Key Vault, ports VNet-only, identités
managées) était utile, mais il traite les symptômes. Le problème de fond est
architectural.

## 2. Verdict : ce n'est ni la bonne façon de faire, ni la plus économique

1. **Double collecte.** Les plateformes envoient déjà métriques, logs et
   traces à Azure Monitor / Log Analytics / Application Insights (payé à
   l'ingestion). La stack VM recollecte les mêmes données (Promitor, Event Hub,
   Loki) pour les stocker une deuxième fois.
2. **Ne passe pas à l'échelle du modèle plateforme.** Chaque nouvelle
   plateforme demanderait de modifier Promitor, les diagnostic settings Event
   Hub et les dashboards à la main.
3. **Coût d'exploitation.** 2 VM à patcher, des binaires à mettre à jour, une
   sauvegarde à inventer, une exposition publique à gérer. Pour une équipe
   plateforme réduite, c'est du temps qui n'apporte pas de valeur produit.
4. **L'alerting dépend de la VM** qu'il est censé surveiller.

## 3. Cible : Azure-native, Grafana en lecture seule

```
Plateformes ──▶ Azure Monitor metrics (gratuit) ─┐
            ──▶ Log Analytics (diag, déjà payé) ─┼──▶ Azure Managed Grafana (identité managée, SSO Entra ID)
            ──▶ Application Insights (déjà payé) ┘
            ──▶ Alertes Azure Monitor (par plateforme) ──▶ Action group ops (Teams / e-mail)
Azure Service Health ─────────────────────────────────────▶ Action group ops
```

- **Grafana ne collecte rien**, il interroge Azure Monitor avec son identité
  managée (`Monitoring Reader` sur chaque subscription). Une nouvelle
  plateforme apparaît automatiquement dans les dashboards.
- **L'alerting est dans Azure Monitor**, à côté des ressources (module
  plateforme, `enable_alerts`) : 5xx, latence, health check, CPU/mémoire des
  plans, PostgreSQL (CPU, mémoire, stockage, connexions), Redis. Il fonctionne
  même si Grafana est indisponible. S'y ajoute une alerte **Service Health**
  (incidents Azure en France Central).
- **Dashboards as code** : `observability/dashboards/generate.py` génère les
  JSON ; la CI vérifie qu'ils sont à jour et les publie (`az grafana`, auth
  Entra, aucune clé d'API).

### Coûts mensuels estimés

Estimations en France Central : **à confirmer avec la calculatrice Azure**.
La page tarifaire officielle de Managed Grafana n'affiche pas les montants et
les sources tierces divergent.

| Option | Postes | Ordre de grandeur |
|---|---|---|
| **Actuel** (VM) | 2 × B2s + disques + 2 IP publiques + Event Hub Standard (1 TU) + stockage + KV | **≈ 110–140 €/mois** + ~1 j/mois d'exploitation, et la donnée est stockée en double |
| **Cible — Grafana Essential** (défaut) | Pas de frais d'instance ; ~6 $/utilisateur actif/mois (selon des sources tierces) ; alertes métriques ≈ 0,10 $/règle/mois (~16 règles par plateforme) ; Service Health gratuit | **≈ 30–50 €/mois** pour ~5 utilisateurs et une dizaine de plateformes |
| Cible — Grafana Standard X1 | + frais d'instance (≈ 50–70 $/mois selon les sources) ; SLA 99,9 %, private endpoint, SMTP/reporting | ≈ 80–120 €/mois |
| Grafana Cloud (free tier) | 0 € jusqu'à 3 utilisateurs, mais accès à Azure par **secret** de service principal depuis un SaaS externe | Écarté : pas d'identité managée, données de requête hors Azure |

Limites d'**Essential** : 20 dashboards et 5 data sources max, pas
d'alerting ni de reporting Grafana, pas de SLA, et c'était encore une
« preview » sur la page de prix. Ça convient ici, puisque l'alerting est dans
Azure Monitor. Passer en `grafana_sku = "Standard"` quand un SLA ou un accès
privé devient nécessaire.

**Leviers d'économie supplémentaires** (déjà câblés dans le module) :
- plafond d'ingestion Log Analytics en non-prod (`log_analytics_daily_quota_gb` = 1 Go en dev, 2 Go en tst) ;
- rétention de 30 j hors prod.

**Option** : passer `AppServiceHTTPLogs` en plan de table *Basic* (ingestion
moins chère, requêtes limitées).

## 4. Bonnes pratiques appliquées

| Domaine | Avant | Après |
|---|---|---|
| Collecte | Promitor + Event Hub + Fluent Bit (copies) | Lecture directe des sources Azure, aucune copie |
| Couverture | 1 resource group en dur | Toutes les subscriptions déclarées, toutes les plateformes (legacy incluses) |
| Identité | MI VM + SAS Event Hub + mot de passe admin Grafana | MI Grafana (`Monitoring Reader`), SSO Entra ID par groupes (Admin / Editor / Viewer), `api_key_enabled = false` |
| Alerting | Alertmanager sur la VM | Alertes Azure Monitor par plateforme + Service Health + action group central |
| Exposition | VM avec IP publiques, HTTP:80 | Service managé HTTPS, aucun port à ouvrir |
| Dashboards | JSON exportés à la main, en dur | Générés par code, variables plateforme, publiés par la CI, vérifiés à jour |
| Exploitation | Patching, upgrades, sauvegardes manuels | Aucun serveur |

## 5. Dashboards (dossier « Beez360 »)

Ils fonctionnent tous pour n'importe quelle plateforme : variables
`Subscription → Platform`, et ressources retrouvées par la convention de
nommage du module.

| Dashboard | Contenu |
|---|---|
| **Parc des plateformes** | Toutes les plateformes (Resource Graph, multi-subscription) : inventaire par type/tier/pays/centre de coût, web apps arrêtées, **alertes actives**, **exposition réseau** des services de données (accès public / private endpoints), serveurs PostgreSQL (version, SKU, HA, géo-backup, rétention), répartition par type. |
| **Vue plateforme** | Santé (requêtes, 5xx, latence, health check) par app ; trafic 2xx/4xx/5xx ; latence ; mémoire ; CPU / mémoire / file HTTP des plans ; PostgreSQL (CPU, mémoire, stockage, connexions) ; Redis (mémoire, charge, hit/miss). |
| **Performance applicative** | Application Insights : taux d'échec, P50/P95/P99, opérations les plus lentes et en échec, exceptions par type et top exceptions, dépendances lentes et en échec. |
| **Logs & HTTP** | Statuts HTTP par app, URLs en 5xx, URLs les plus lentes, erreurs console, recherche plein texte, événements conteneurs (pull d'image, crash : catégorie `AppServicePlatformLogs` ajoutée au module), erreurs PostgreSQL. |
| **PostgreSQL** | Disponibilité, CPU/mémoire/stockage, connexions réussies/échouées, IOPS, file d'attente disque, réseau, journaux de transactions, consommation des transaction IDs (risque de wraparound). |

Les anciens dashboards (Prometheus/Loki) restent dans `dashboards/` pour la
stack legacy.

**Non testé** : les JSON ont été vérifiés structurellement (grille, IDs, JSON
valide), mais pas encore importés dans un Grafana réel. Au premier
déploiement, vérifier chaque panneau ; un nom de métrique ou une colonne KQL
peut demander un ajustement dans `generate.py`.

## 6. Migration (sans coupure)

1. **Déployer `observability/`** : renseigner `terraform.tfvars` à partir de
   `terraform.tfvars.example`, et les secrets `ALERT_WEBHOOK_URL`. L'identité
   CI doit être *Owner* ou *User Access Administrator* sur les subscriptions
   surveillées, pour attribuer `Monitoring Reader` à Grafana.
2. Vérifier les 5 dashboards sur une plateforme legacy (ex.
   `beez360-frc-otacos-prd-rg`) et sur `dev`.
3. **Activer les alertes** :
   - nouvelles plateformes : déjà actif via les types `prod-*` ;
   - pour tout router vers l'action group central, mettre
     `alert_action_group_id = <ops_action_group_id>` dans `tier.hcl` → `_common/platform.hcl`.
4. Faire tourner les deux stacks en parallèle **2 à 4 semaines**.
5. **Décommissionner l'ancienne stack** :
   - supprimer les diagnostic settings App Service → Event Hub créés à la main ;
   - `tofu destroy` à la racine du repo (le Key Vault reste en soft-delete 90 j, purge protection) ;
   - archiver `terragrunt-monitoring`.
