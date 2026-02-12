#!/bin/bash
set -e

echo "===== Installation et configuration de Loki ====="

# Création des dossiers requis
sudo mkdir -p /var/loki/{index,cache,compactor}
sudo mkdir -p /etc/loki
sudo chown -R root:root /var/loki

# Télécharger Loki (version cohérente avec la vôtre : 3.1.0)
cd /tmp
wget -O loki.tar.gz https://github.com/grafana/loki/releases/download/v3.1.0/loki-linux-amd64.zip
unzip loki.tar.gz
sudo mv loki-linux-amd64 /usr/local/bin/loki
sudo chmod +x /usr/local/bin/loki

# Créer le fichier d’environnement pour la clé Azure
sudo tee /etc/loki/env > /dev/null << 'EOF'
storage_account_key=REPLACE_WITH_YOUR_REAL_KEY
EOF

# Déployer votre configuration Loki existante
sudo tee /etc/loki/local-config.yaml > /dev/null << 'EOF'
$(cat /etc/loki/local-config.yaml)
EOF

# Créer le service systemd
sudo tee /etc/systemd/system/loki.service > /dev/null << 'EOF'
[Unit]
Description=Loki Service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/local-config.yaml -config.expand-env=true
Restart=always
EnvironmentFile=/etc/loki/env

[Install]
WantedBy=multi-user.target
EOF

# Démarrer Loki
sudo systemctl daemon-reexec
sudo systemctl enable loki
sudo systemctl restart loki

echo "Loki installé et démarré."
echo "Vérification :"
sudo systemctl status loki --no-pager
