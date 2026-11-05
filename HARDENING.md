# Durcissement — terraform-monitoring

> ⚠️ **Décision révisée (octobre 2026)** : la stack VM self-hosted ci-dessous est
> remplacée par une stack Azure-native (Managed Grafana + alertes Azure
> Monitor), dans [`observability/`](./observability). Justification, coûts et
> plan de migration : [docs/REVIEW_MONITORING_2026-10.md](./docs/REVIEW_MONITORING_2026-10.md).
> Ce document reste valable pour l'ancienne stack tant qu'elle tourne.

Décision d'archi retenue : **self-hosted LGTM durci**, **service central hors modèle**
(non rattaché à `platforms/`), **on durcit l'existant d'abord**. Ce document liste ce
qui a été corrigé et ce qui reste à faire.

## ✅ Corrigé (cette passe — `tofu validate` OK)

| Domaine | Avant | Après |
|---|---|---|
| **Secrets en git** | mot de passe admin VM en clair dans tfvars (présent dans l'historique git : à considérer comme compromis) ; Grafana `admin/admin` ; tenantId/subscriptionId en dur dans cloud-init | Mots de passe **générés** (`random_password`) et stockés dans **Key Vault** (`vm-admin-password`, `grafana-admin-password`). tenant/sub/RG **paramétrés** (template). `subscription_id` n'a plus de GUID par défaut. |
| **Mot de passe Grafana** | `admin/admin` jamais appliqué (env mort) | `GF_SECURITY_ADMIN_PASSWORD` via drop-in systemd → appliqué réellement. Clé API créée avec le bon mot de passe. |
| **Exposition réseau** | Grafana/Prometheus/Loki/Tempo/SSH/OTLP/Consul en `source = *` (Internet) | **Ports data (Prometheus, Loki, Tempo, OTLP, node_exporter, Promitor) = VNet-only.** Ports opérateur (Grafana 3000, NGINX 80, SSH 22) = `allowed_ingress_cidrs` (défaut **VNet-only**, ouvrir explicitement aux IP bureau/VPN). |
| **Clés vs identités** | Storage account key injecté en cloud-init ; Loki via clé | **Managed Identity** : la VM logs reçoit `Storage Blob Data Contributor`, Loki passe en `use_managed_identity: true`. Plus de clé sur disque. |
| **Event Hub** | `RootManageSharedAccessKey` (full-manage) donné à la VM | SAS **`Listen`-only** dédié, scopé au hub `logs`. |
| **Promitor / Azure Monitor** | MI déclarée mais aucun droit → scraping cassé | Role assignment **`Monitoring Reader`** sur le RG observé pour la MI de la VM metrics. |
| **Key Vault** | `purge_protection = false`, soft-delete 7j | `purge_protection = true`, soft-delete **90j**. |
| **Bug datasources Grafana** | Double provisioning + URL malformée `http://http://…:9090:9090` | Provisioning **déclaratif unique** (fichier), blocs API supprimés. |
| **Fluent Bit → Loki** | via IP publique | via `127.0.0.1` (même VM). |

## ⚠️ Reste à faire (prochaines passes — par priorité)

1. **Alerting** (manque #1) : Alertmanager + règles + notif (Teams/Slack/PagerDuty). Sans ça, personne ne voit les incidents.
2. **SSH par clé** : passer `disable_password_authentication = true` + `admin_ssh_key` (fournir la clé publique de l'équipe). Aujourd'hui : mot de passe fort + SSH restreint, mais pas de clé.
3. **Secrets au boot via KV** : les VMs devraient lire `grafana-admin-password` depuis Key Vault via leur MI au démarrage (aujourd'hui injecté en `custom_data`, qui reste récupérable par un Reader sur la VM).
4. **Egress maîtrisé** : NAT Gateway pour la sortie + suppression des IP publiques des VMs (la sortie par défaut Azure est dépréciée). Façade Grafana via App Gateway + **TLS** (aujourd'hui HTTP:80).
5. **Résilience** : disques de données managés (Premium SSD) pour Prometheus TSDB + index Loki (la variable `data_disk_size_gb` n'est toujours pas câblée) ; aujourd'hui tout est sur le disque OS 32 Go → perte si la VM meurt.
6. **Multi-plateforme** : la `metrics-declaration` Promitor est figée sur `franchisee-paris-dev`. La générer dynamiquement pour scraper toutes les plateformes (multi-subscription prod/nonprod).
7. **terragrunt-monitoring** : stub non-fonctionnel (backend hardcodé dans le module ⇄ `remote_state` Terragrunt ; `inputs = {}`). À refondre si on garde Terragrunt.
8. ✅ **FAIT** — Provider aligné sur **azurerm v4** (`>= 4.0, < 5.0`, main + bootstrap), CI basculée **Terraform → OpenTofu v1.12.0**. Renommage v4 appliqué (`enable_rbac_authorization` → `rbac_authorization_enabled`).
9. **CI** : ajouter fmt/validate + tflint/checkov, et gérer le secret VM hors git.
10. **Backup Grafana** (SQLite sur disque OS).

## Runbook

```bash
# 1. Ouvrir l'accès opérateur (sinon Grafana/SSH = VNet-only)
#    terraform.tfvars :
#    allowed_ingress_cidrs = ["<IP_bureau>/32", "<VPN>/32"]

# 2. Mot de passe VM : ne rien mettre dans tfvars (généré). Override éventuel :
export TF_VAR_admin_password='...'   # sinon auto-généré + stocké en KV

# 3. Récupérer les secrets après apply
az keyvault secret show --vault-name beez360-kv --name grafana-admin-password --query value -o tsv
az keyvault secret show --vault-name beez360-kv --name vm-admin-password    --query value -o tsv
```

> **Note RBAC** : les secrets KV sont créés en data-plane par le déployeur (rôle
> *Key Vault Secrets Officer* accordé dans le module). En cas d'échec « Forbidden »
> au 1ᵉʳ apply (propagation RBAC), relancer l'apply.
