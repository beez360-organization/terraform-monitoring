#!/bin/bash
set -e

echo "===== Installation et configuration de Fluent Bit ====="

# Ajouter le dépôt officiel Fluent Bit
curl https://packages.fluentbit.io/fluentbit.key | sudo gpg --dearmor -o /usr/share/keyrings/fluentbit-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/fluentbit-keyring.gpg] https://packages.fluentbit.io/ubuntu focal main" | \
sudo tee /etc/apt/sources.list.d/fluentbit.list

sudo apt update
sudo apt install -y td-agent-bit

# Créer les points de montage attendus (sécurité)
sudo mkdir -p \
 /mnt/insights-logs-appserviceauditlogs \
 /mnt/insights-logs-appserviceconsolelogs \
 /mnt/insights-logs-appservicehttplogs \
 /mnt/insights-logs-appserviceplatformlogs \
 /mnt/insights-logs-postgresqlflextablestats \
 /mnt/insights-logs-postgresqlflexdatabasexacts \
 /mnt/insights-logs-postgresqlflexsessions \
 /mnt/insights-logs-postgresqllogs

sudo chown -R root:root /mnt/insights-logs-*

# Déployer votre configuration Fluent Bit actuelle
sudo tee /etc/td-agent-bit/td-agent-bit.conf > /dev/null << 'EOF'
$(cat /etc/td-agent-bit/td-agent-bit.conf)
EOF

sudo tee /etc/td-agent-bit/extract_json.lua > /dev/null << 'EOF'
$(cat /etc/td-agent-bit/extract_json.lua)
EOF

sudo tee /etc/td-agent-bit/parsers.conf > /dev/null << 'EOF'
$(cat /etc/td-agent-bit/parsers.conf)
EOF

# Redémarrer Fluent Bit
sudo systemctl daemon-reexec
sudo systemctl enable td-agent-bit
sudo systemctl restart td-agent-bit

echo "Fluent Bit installé et démarré."
echo "Vérification :"
sudo systemctl status td-agent-bit --no-pager
