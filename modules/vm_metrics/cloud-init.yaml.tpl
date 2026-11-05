#cloud-config
package_update: true
package_upgrade: true
packages:
  - docker.io
  - wget
  - curl
  - tar
  - jq
  - apt-transport-https
  - software-properties-common
  - unzip
  - gnupg
  - lsb-release

# Resilience: format (once) and mount the Premium SSD data disk at /data.
# overwrite:false → Prometheus TSDB + Grafana DB survive VM recreation.
fs_setup:
  - device: /dev/disk/azure/scsi1/lun0
    filesystem: ext4
    label: datadisk
    overwrite: false
mounts:
  - ["/dev/disk/azure/scsi1/lun0", "/data", "ext4", "defaults,nofail", "0", "2"]

write_files:
  # Grafana environment variables
  - path: /etc/grafana/env
    permissions: '0600'
    content: |
      GRAFANA_URL=${GRAFANA_URL}
      ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

  # Force the Grafana admin password (otherwise it stays admin/admin)
  - path: /etc/systemd/system/grafana-server.service.d/override.conf
    permissions: '0644'
    content: |
      [Service]
      Environment=GF_SECURITY_ADMIN_USER=admin
      Environment=GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      Environment=GF_PATHS_DATA=/data/grafana

  # Prometheus installation script
  - path: /usr/local/bin/install_prometheus.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e

      PROM_VERSION="2.49.0"

      useradd --no-create-home --shell /bin/false prometheus || true

      mkdir -p /etc/prometheus /data/prometheus

      cd /tmp

      wget https://github.com/prometheus/prometheus/releases/download/v2.49.0/prometheus-2.49.0.linux-amd64.tar.gz

      tar xzf prometheus-2.49.0.linux-amd64.tar.gz

      cp prometheus-2.49.0.linux-amd64/prometheus /usr/local/bin/
      cp prometheus-2.49.0.linux-amd64/promtool /usr/local/bin/

      chmod +x /usr/local/bin/prometheus /usr/local/bin/promtool

      chown prometheus:prometheus /data/prometheus

  # Grafana installation script
  - path: /usr/local/bin/install_grafana.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /usr/share/keyrings/grafana.gpg > /dev/null
      echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
      apt-get update
      apt-get install -y grafana
      systemctl daemon-reload
      systemctl enable grafana-server
      systemctl start grafana-server

  # Promitor start script
  - path: /usr/local/bin/start_promitor.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      docker pull ghcr.io/tomkerkhove/promitor-agent-scraper:2.6.0
      docker rm -f promitor-scraper || true
      docker run -d --name promitor-scraper -p 8080:8080 \
        -v /config/:/config/ \
        ghcr.io/tomkerkhove/promitor-agent-scraper:2.6.0



  # Promitor systemd
  - path: /etc/systemd/system/promitor.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Promitor Agent Scraper
      After=docker.service
      Requires=docker.service
      [Service]
      Restart=always
      ExecStart=/usr/local/bin/start_promitor.sh
      [Install]
      WantedBy=multi-user.target

  # Prometheus systemd
  - path: /etc/systemd/system/prometheus.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Prometheus
      Wants=network-online.target
      After=network-online.target
      [Service]
      User=prometheus
      Group=prometheus
      Type=simple
      ExecStart=/usr/local/bin/prometheus \
        --config.file=/etc/prometheus/prometheus.yml \
        --storage.tsdb.path=/data/prometheus \
        --web.listen-address=:9090
      [Install]
      WantedBy=multi-user.target


  # Prometheus config
  - path: /etc/prometheus/prometheus.yml
    content: |
      global:
        scrape_interval: 15s
      rule_files:
        - /etc/prometheus/rules/*.yml
      alerting:
        alertmanagers:
          - static_configs:
              - targets: ['localhost:9093']
      scrape_configs:
        - job_name: 'node_exporter'
          static_configs:
            - targets: ['${PROM_NODE_EXPORTER}']
        - job_name: 'promitor'
          static_configs:
            - targets: ['${PROM_PROMITOR}']

  # Prometheus alert rules (starter set on Promitor/Azure-Monitor metrics)
  - path: /etc/prometheus/rules/beez360.yml
    content: |
      groups:
        - name: beez360-platform
          rules:
            - alert: PromitorScraperDown
              expr: up{job="promitor"} == 0
              for: 5m
              labels:
                severity: critical
              annotations:
                summary: "Promitor scraper is down"
                description: "Azure Monitor metrics are not being collected (job=promitor down for 5m)."
            - alert: AppServiceHttp5xx
              expr: sum(increase(appservice_http_5xx[5m])) > 5
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "App Service 5xx errors rising"
                description: "More than 5 HTTP 5xx in the last 5 minutes across the web apps."
            - alert: PostgresHighConnections
              expr: max(postgresql_active_connections) > 80
              for: 10m
              labels:
                severity: warning
              annotations:
                summary: "PostgreSQL active connections high"
                description: "Active connections above 80 for 10m — check pool/leaks."
            - alert: AppPlanHighCpu
              expr: max(appplan_cpu_percentage) > 85
              for: 10m
              labels:
                severity: warning
              annotations:
                summary: "App Service Plan CPU high"
                description: "App Service Plan CPU above 85% for 10m — consider scaling."

  # Alertmanager config (templatefile guards the receiver: bare = no delivery)
  - path: /etc/alertmanager/alertmanager.yml
    content: |
      route:
        receiver: beez360
        group_by: ['alertname']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 4h
      receivers:
        - name: beez360
%{ if ALERT_WEBHOOK_URL != "" ~}
          webhook_configs:
            - url: '${ALERT_WEBHOOK_URL}'
              send_resolved: true
%{ endif ~}

  # Alertmanager systemd unit
  - path: /etc/systemd/system/alertmanager.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Alertmanager
      Wants=network-online.target
      After=network-online.target
      [Service]
      Type=simple
      ExecStart=/usr/local/bin/alertmanager \
        --config.file=/etc/alertmanager/alertmanager.yml \
        --storage.path=/data/alertmanager \
        --web.listen-address=:9093
      Restart=always
      [Install]
      WantedBy=multi-user.target

  # Alertmanager install script
  - path: /usr/local/bin/install_alertmanager.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      AM_VERSION="0.27.0"
      cd /tmp
      wget -q https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
      tar xzf alertmanager-0.27.0.linux-amd64.tar.gz
      cp alertmanager-0.27.0.linux-amd64/alertmanager /usr/local/bin/
      chmod +x /usr/local/bin/alertmanager


  - path: /etc/grafana/provisioning/datasources/default.yaml
    permissions: '0644'
    content: |
      apiVersion: 1
      datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: ${PROM_URL}
        isDefault: true

      - name: Loki
        type: loki
        access: proxy
        url: ${LOKI_URL}


  # Promitor metrics declaration (Azure)
  - path: /config/metrics-declaration.yaml
    content: |
      version: v1
      azureMetadata:
        tenantId: "${TENANT_ID}"
        subscriptionId: "${SUBSCRIPTION_ID}"
        resourceGroupName: "${MONITORED_RG}"
      metricDefaults:
        aggregation:
          interval: 00:01:00
        scraping:
          schedule: "*/1 * * * *"
      metrics:
        # WEB APPS
        - name: appservice_cpu_time
          description: CPU time consumed by Web Apps
          resourceType: WebApp
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: CpuTime
            aggregation:
              type: Total
          resources:
            - webAppName: beez360-frc-franchisee-paris-dev-api-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-backoffice-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-clickandcollect-webapp
        - name: appservice_request_count
          description: Total number of requests
          resourceType: WebApp
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: Requests
            aggregation:
              type: Total
          resources:
            - webAppName: beez360-frc-franchisee-paris-dev-api-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-backoffice-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-clickandcollect-webapp
        - name: appservice_memory_working_set
          description: Average memory working set
          resourceType: WebApp
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: MemoryWorkingSet
            aggregation:
              type: Average
          resources:
            - webAppName: beez360-frc-franchisee-paris-dev-api-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-backoffice-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-clickandcollect-webapp
        - name: appservice_bytes_received
          description: Total bytes received
          resourceType: WebApp
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: BytesReceived
            aggregation:
              type: Total
          resources:
            - webAppName: beez360-frc-franchisee-paris-dev-api-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-backoffice-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-clickandcollect-webapp
        - name: appservice_bytes_sent
          description: Total bytes sent
          resourceType: WebApp
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: BytesSent
            aggregation:
              type: Total
          resources:
            - webAppName: beez360-frc-franchisee-paris-dev-api-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-backoffice-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-clickandcollect-webapp
        - name: appservice_http_5xx
          description: Total HTTP 5xx errors
          resourceType: WebApp
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: Http5xx
            aggregation:
              type: Total
          resources:
            - webAppName: beez360-frc-franchisee-paris-dev-api-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-backoffice-webapp
            - webAppName: beez360-frc-franchisee-paris-dev-clickandcollect-webapp

        # APP SERVICE PLANS
        - name: appplan_memory_percentage
          description: Average memory usage of App Plans
          resourceType: AppPlan
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: MemoryPercentage
            aggregation:
              type: Average
          resources:
            - appPlanName: beez360-frc-franchisee-paris-dev-frontend-asp
            - appPlanName: beez360-frc-franchisee-paris-dev-backend-asp
        - name: appplan_cpu_percentage
          description: Average CPU usage
          resourceType: AppPlan
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: CpuPercentage
            aggregation:
              type: Average
          resources:
            - appPlanName: beez360-frc-franchisee-paris-dev-frontend-asp
            - appPlanName: beez360-frc-franchisee-paris-dev-backend-asp
        - name: appplan_disk_queue_length
          description: Disk queue length
          resourceType: AppPlan
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: DiskQueueLength
            aggregation:
              type: Average
          resources:
            - appPlanName: beez360-frc-franchisee-paris-dev-frontend-asp
            - appPlanName: beez360-frc-franchisee-paris-dev-backend-asp

        # POSTGRESQL FLEXIBLE
        - name: postgresql_cpu_percent
          description: Average CPU percent
          resourceType: PostgreSql
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: cpu_percent
            aggregation:
              type: Average
          resources:
            - serverName: beez360-frc-franchisee-paris-dev-psql
              type: Flexible
        - name: postgresql_storage_used
          description: Storage used
          resourceType: PostgreSql
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: storage_used
            aggregation:
              type: Average
          resources:
            - serverName: beez360-frc-franchisee-paris-dev-psql
              type: Flexible
        - name: postgresql_active_connections
          description: Active connections
          resourceType: PostgreSql
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: active_connections
            aggregation:
              type: Average
          resources:
            - serverName: beez360-frc-franchisee-paris-dev-psql
              type: Flexible
        - name: postgresql_io_consumption
          description: I/O consumption percent
          resourceType: PostgreSql
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: io_consumption_percent
            aggregation:
              type: Average
          resources:
            - serverName: beez360-frc-franchisee-paris-dev-psql
              type: Flexible

        # STORAGE ACCOUNT
        - name: storage_used_capacity
          description: Total used capacity
          resourceType: StorageAccount
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: UsedCapacity
            aggregation:
              type: Total
          resources:
            - accountName: beez360frcfranchiseepari
        - name: storage_ingress
          description: Total ingress
          resourceType: StorageAccount
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: Ingress
            aggregation:
              type: Total
          resources:
            - accountName: beez360frcfranchiseepari
        - name: storage_egress
          description: Total egress
          resourceType: StorageAccount
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: Egress
            aggregation:
              type: Total
          resources:
            - accountName: beez360frcfranchiseepari
        - name: storage_transactions
          description: Total transactions
          resourceType: StorageAccount
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: Transactions
            aggregation:
              type: Total
          resources:
            - accountName: beez360frcfranchiseepari

        # KEY VAULT
        - name: keyvault_service_api_hit
          description: Total API hits
          resourceType: KeyVault
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: ServiceApiHit
            aggregation:
              type: Total
          resources:
            - vaultName: beez360frcfranchiseepari
        - name: keyvault_throttled_requests
          description: Total throttled requests
          resourceType: KeyVault
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: ThrottledRequests
            aggregation:
              type: Total
          resources:
            - vaultName: beez360frcfranchiseepari

        # CONTAINER REGISTRY
        - name: acr_pull_count
          description: Total pull count
          resourceType: ContainerRegistry
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: PullCount
            aggregation:
              type: Total
          resources:
            - registryName: beez360frcfranchiseeparisdevacr
        - name: acr_push_count
          description: Total push count
          resourceType: ContainerRegistry
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: PushCount
            aggregation:
              type: Total
          resources:
            - registryName: beez360frcfranchiseeparisdevacr
        - name: acr_used_capacity
          description: Average used capacity
          resourceType: ContainerRegistry
          scraping:
            schedule: "*/1 * * * *"
          azureMetricConfiguration:
            metricName: UsedCapacity
            aggregation:
              type: Average
          resources:
            - registryName: beez360frcfranchiseeparisdevacr

  # Promitor runtime config
  - path: /config/runtime.yaml
    content: |
      server:
        httpPort: 8080
      authentication:
        mode: SystemAssignedManagedIdentity
      metricsConfiguration:
        absolutePath: /config/metrics-declaration.yaml
      telemetry:
        applicationInsights:
          isEnabled: false
        containerLogs:
          isEnabled: true
          verbosity: Debug
        defaultVerbosity: Debug
      metricSinks:
        prometheusScrapingEndpoint:
          metricUnavailableValue: NaN
          enableMetricTimestamps: true
          baseUriPath: /metrics
          labels:
            transformation: None

  - path: /etc/nginx/conf.d/99-hardening.conf
    permissions: '0644'
    content: |
      server_names_hash_bucket_size 128;
      server_names_hash_max_size 512;
  
  - path: /etc/nginx/sites-available/grafana
    permissions: '0644'
    content: |
      server {
          listen 80;
          server_name beez360-dashboard.francecentral.cloudapp.azure.com;

          location / {
              proxy_pass http://127.0.0.1:3000;

              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
          }
      }

runcmd:
  - systemctl enable --now docker

  # Data dirs on the mounted /data disk (resilience). Grafana dir is opened
  # temporarily so its first start can write, then tightened below.
  - mkdir -p /data/prometheus /data/alertmanager /etc/prometheus/rules /etc/alertmanager
  - mkdir -p /data/grafana && chmod 0777 /data/grafana
  - mkdir -p /etc/grafana/dashboards /var/lib/grafana/dashboards

  - useradd --no-create-home --shell /bin/false prometheus || true
  - mkdir -p /etc/prometheus
  - chown -R prometheus:prometheus /etc/prometheus /data/prometheus
  - /usr/local/bin/install_prometheus.sh
  - /usr/local/bin/install_alertmanager.sh
  - |
    cat <<EOF > /etc/systemd/system/prometheus.service
    [Unit]
    Description=Prometheus
    Wants=network-online.target
    After=network-online.target

    [Service]
    User=prometheus
    Group=prometheus
    Type=simple
    ExecStart=/usr/local/bin/prometheus \
      --config.file=/etc/prometheus/prometheus.yml \
      --storage.tsdb.path=/data/prometheus \
      --web.listen-address=:9090

    [Install]
    WantedBy=multi-user.target
    EOF

  - systemctl daemon-reexec

  - systemctl daemon-reload 
  - systemctl enable prometheus || true
  - systemctl start prometheus || true
  - systemctl enable alertmanager || true
  - systemctl start alertmanager || true
  - /usr/local/bin/install_grafana.sh
  - systemctl enable --now grafana-server
  - chown -R grafana:grafana /var/lib/grafana/dashboards /data/grafana

  - systemctl enable --now promitor.service || true
  - systemctl daemon-reload
  - systemctl restart grafana-server || true

  - |
      until curl -s ${GRAFANA_URL}/api/health | jq -e '.database=="ok"' > /dev/null; do
        echo "Waiting for Grafana..."
        sleep 5
      done

  - |
      api_key=$(curl -s -X POST ${GRAFANA_URL}/api/auth/keys \
        -u admin:${GRAFANA_ADMIN_PASSWORD} \
        -H "Content-Type: application/json" \
        -d '{"name":"terraform-import","role":"Admin","secondsToLive":86400}' | jq -r '.key')
      echo $api_key > /etc/grafana/api_key

  - systemctl enable --now grafana-import.service || true

  # Datasources are provisioned declaratively via
  # /etc/grafana/provisioning/datasources/default.yaml (PROM_URL / LOKI_URL).
  # The old API-based creation was removed: it duplicated provisioning and
  # built malformed URLs (http://http://...:9090:9090).

  # =========================
  # NGINX setup
  # =========================
  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
  - rm -f /etc/nginx/sites-enabled/default || true

  - ln -sf /etc/nginx/sites-available/grafana /etc/nginx/sites-enabled/grafana

  - nginx -t
  - systemctl enable nginx
  - systemctl restart nginx || true