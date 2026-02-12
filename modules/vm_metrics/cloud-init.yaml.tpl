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

write_files:
  # Grafana environment variables
  - path: /etc/grafana/env
    permissions: '0600'
    content: |
      GRAFANA_URL=__GRAFANA_URL__
      ADMIN_PASSWORD=admin

  # Prometheus installation script
  - path: /usr/local/bin/install_prometheus.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      PROM_VERSION="2.49.0"
      PROM_DIR="/usr/local/bin"
      useradd --no-create-home --shell /bin/false prometheus || true
      mkdir -p /etc/prometheus /var/lib/prometheus
      chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
      wget https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz -O /tmp/prometheus.tar.gz
      tar xzf /tmp/prometheus.tar.gz -C /tmp/
      cp /tmp/prometheus-${PROM_VERSION}.linux-amd64/prometheus ${PROM_DIR}/
      cp /tmp/prometheus-${PROM_VERSION}.linux-amd64/promtool ${PROM_DIR}/
      chmod +x ${PROM_DIR}/prometheus ${PROM_DIR}/promtool
      chown prometheus:prometheus ${PROM_DIR}/prometheus ${PROM_DIR}/promtool

  # Grafana installation script
  - path: /usr/local/bin/install_grafana.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      GRAF_VERSION="12.3.2"
      wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /usr/share/keyrings/grafana.gpg > /dev/null
      echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
      apt-get update
      apt-get install -y grafana=${GRAF_VERSION}
      systemctl daemon-reload
      systemctl enable grafana-server
      systemctl start grafana-server


  # Promitor start script
  - path: /usr/local/bin/start_promitor.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      docker rm -f promitor-scraper || true
      docker run -d --name promitor-scraper -p 8080:8080 \
        -v /config/:/config/ \
        ghcr.io/tomkerkhove/promitor-agent-scraper:2.6.0

  # Dashboards import script
  - path: /usr/local/bin/import_dashboards.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      source /etc/grafana/env
      DASHBOARDS_DIR="/etc/grafana/dashboards"
      api_key=$(cat /etc/grafana/api_key)
      until curl -s $GRAFANA_URL/api/health | jq -e '.database=="ok"' > /dev/null; do
        echo "Waiting for Grafana to be ready..."
        sleep 5
      done
      for dashboard_file in "$DASHBOARDS_DIR"/*.json; do
        echo "Importing dashboard $dashboard_file ..."
        DASH_JSON=$(jq -c '.' "$dashboard_file")
        curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $api_key" \
          -d "{\"dashboard\":$DASH_JSON,\"overwrite\":true}"
      done

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
        --storage.tsdb.path=/var/lib/prometheus \
        --web.listen-address=:9090
      [Install]
      WantedBy=multi-user.target

  # Grafana dashboards import systemd
  - path: /etc/systemd/system/grafana-import.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Import Grafana Dashboards
      After=grafana-server.service
      Wants=grafana-server.service
      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/import_dashboards.sh
      RemainAfterExit=yes
      [Install]
      WantedBy=multi-user.target

  # Prometheus config
  - path: /etc/prometheus/prometheus.yml
    content: |
      global:
        scrape_interval: 15s
      scrape_configs:
        - job_name: 'node_exporter'
          static_configs:
            - targets: ['__PROM_NODE_EXPORTER__']
        - job_name: 'promitor'
          static_configs:
            - targets: ['__PROM_PROMITOR__']
  - path: /etc/grafana/provisioning/dashboards/default.yaml
    permissions: '0644'
    content: |
      apiVersion: 1
      providers:
        - name: default
          orgId: 1
          folder: ""
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards

  # Promitor metrics declaration (Azure)
  - path: /config/metrics-declaration.yaml
    content: |
      version: v1
      azureMetadata:
        tenantId: "4577d937-9ed0-46b9-a6ca-17f02fa7984b"
        subscriptionId: "7df6c09e-5b30-41d7-8bf2-d39b61f07de3"
        resourceGroupName: "beez360-frc-franchisee-paris-dev-rg"
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

runcmd:
  - mkdir -p /etc/grafana/dashboards
  - wget -O /etc/grafana/dashboards/loki-dashboard.json https://raw.githubusercontent.com/grafana/loki/main/production/helm/loki-stack/templates/grafana/dashboards/loki-dashboard.json
  - wget -O /etc/grafana/dashboards/tempo-dashboard.json https://raw.githubusercontent.com/grafana/tempo/main/production/helm/tempo/templates/grafana/dashboards/tempo-dashboard.json
  - /usr/local/bin/install_grafana.sh
  - systemctl enable --now grafana-server
  - mkdir -p /var/lib/grafana/dashboards
  - curl -fsSL -o /var/lib/grafana/dashboards/api-dashboard.json https://raw.githubusercontent.com/beez360-organization/terraform-monitoring/main/dashboards/api-dashboard.json
  - curl -fsSL -o /var/lib/grafana/dashboards/backoffice.json https://raw.githubusercontent.com/beez360-organization/terraform-monitoring/main/dashboards/backoffice.json
  - curl -fsSL -o /var/lib/grafana/dashboards/c_c.json https://raw.githubusercontent.com/beez360-organization/terraform-monitoring/main/dashboards/c_c.json
  - curl -fsSL -o /var/lib/grafana/dashboards/global-informations.json https://raw.githubusercontent.com/beez360-organization/terraform-monitoring/main/dashboards/global-informations.json
  - curl -fsSL -o /var/lib/grafana/dashboards/postgres.json https://raw.githubusercontent.com/beez360-organization/terraform-monitoring/main/dashboards/postgres.json

  - systemctl restart grafana-server
  - |
    until curl -s __GRAFANA_URL__/api/health | jq -e '.database=="ok"' > /dev/null; do
      echo "Waiting for Grafana..."
      sleep 5
    done
  - |
    api_key=$(curl -s -X POST __GRAFANA_URL__/api/auth/keys \
      -u admin:${ADMIN_PASSWORD} \
      -H "Content-Type: application/json" \
      -d '{"name":"terraform-import","role":"Admin","secondsToLive":86400}' | jq -r '.key')
    echo $api_key > /etc/grafana/api_key
  - systemctl enable --now grafana-import.service
  - |
    curl -s -X POST __GRAFANA_URL__/api/datasources \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $api_key" \
      -d '{
        "name":"Prometheus",
        "type":"prometheus",
        "url":"http://__PROM_URL__:9090",
        "access":"proxy",
        "basicAuth":false
      }'
  - |
    curl -s -X POST __GRAFANA_URL__/api/datasources \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $api_key" \
      -d '{
        "name":"Loki",
        "type":"loki",
        "url": "__LOKI_URL__",
        "access":"proxy",
        "basicAuth":false
      }'
