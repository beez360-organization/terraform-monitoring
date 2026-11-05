admin_username = "azureuser"
# admin_password: NEVER set here. Left unset → auto-generated and stored in Key Vault.
# Override only via TF_VAR_admin_password if you must.
logs_traces_subnet_cidr = "10.0.2.0/24"
metrics_subnet_cidr     = "10.0.1.0/24"
prefix                  = "beez360"
resource_group_name     = "rg-monitoring"
storage_account_name    = "beez360storage"
vnet_cidr               = "10.0.0.0/16"
key_vault_name          = "beez360-kv"

# Azure scope Promitor scrapes (identifiers, not secrets).
subscription_id          = "7df6c09e-5b30-41d7-8bf2-d39b61f07de3"
monitored_resource_group = "beez360-frc-franchisee-paris-dev-rg"

# Operator access allowlist (Grafana/SSH/NGINX). Empty = VNet-only (secure default).
# Add office/VPN CIDRs to expose the dashboard, e.g.:
# allowed_ingress_cidrs = ["203.0.113.10/32"]
allowed_ingress_cidrs = []