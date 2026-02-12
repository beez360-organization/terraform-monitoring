#cloud-config
package_update: true
package_upgrade: true

packages:
  - wget
  - curl
  - unzip
  - fuse
  - lsof
  - liblua5.1-0
  - lua-cjson
  - apt-transport-https
  - ca-certificates


write_files:
  # =========================
  # ENV BLOBFUSE
  # =========================
  - path: /etc/blobfuse/env
    permissions: "0600"
    content: |
      STORAGE_ACCOUNT_NAME=__STORAGE_ACCOUNT_NAME__
      STORAGE_ACCOUNT_KEY=__STORAGE_ACCOUNT_KEY__

  # =========================
  # LOKI CONFIG
  # =========================
  - path: /etc/loki/local-config.yaml
    permissions: "0644"
    content: |
      auth_enabled: false
      server:
        http_listen_port: 3100
        http_listen_address: 0.0.0.0
      ingester:
        lifecycler:
          ring:
            kvstore:
              store: inmemory
            replication_factor: 1
        chunk_idle_period: 5m
        max_chunk_age: 1h
      schema_config:
        configs:
          - from: 2020-10-24
            store: boltdb-shipper
            object_store: azure
            schema: v11
            index:
              prefix: index_
              period: 24h
      storage_config:
        boltdb_shipper:
          active_index_directory: /var/loki/index
          cache_location: /var/loki/cache
        azure:
          container_name: "loki-logs"
          account_name: "beez360storage"
          account_key: "__STORAGE_ACCOUNT_KEY__"
      limits_config:
        ingestion_rate_mb: 10
        ingestion_burst_size_mb: 15
        allow_structured_metadata: false
      compactor:
        working_directory: /var/loki/compactor
        retention_enabled: true
        retention_delete_delay: 0s
        retention_delete_worker_count: 10
        shared_store: azure
  # =========================
  # BLOBFUSE CONFIGS POUR LES 8 CONTENEURS
  # =========================
  - path: /etc/blobfuse-insights-logs-appserviceauditlogs.cfg
    permissions: "0600"
    content: |
      accountName __STORAGE_ACCOUNT_NAME__
      accountKey __STORAGE_ACCOUNT_KEY__
      containerName insights-logs-appserviceauditlogs

  - path: /etc/blobfuse-insights-logs-appserviceconsolelogs.cfg
    permissions: "0600"
    content: |
      accountName __STORAGE_ACCOUNT_NAME__
      accountKey __STORAGE_ACCOUNT_KEY__
      containerName insights-logs-appserviceconsolelogs

  - path: /etc/blobfuse-insights-logs-appservicehttplogs.cfg
    permissions: "0600"
    content: |
      accountName __STORAGE_ACCOUNT_NAME__
      accountKey __STORAGE_ACCOUNT_KEY__
      containerName insights-logs-appservicehttplogs

  - path: /etc/blobfuse-insights-logs-appserviceplatformlogs.cfg
    permissions: "0600"
    content: |
      accountName __STORAGE_ACCOUNT_NAME__
      accountKey __STORAGE_ACCOUNT_KEY__
      containerName insights-logs-appserviceplatformlogs

  - path: /etc/insights-logs-postgresqllogs.cfg
    permissions: "0600"
    content: |
      accountName __STORAGE_ACCOUNT_NAME__
      accountKey __STORAGE_ACCOUNT_KEY__
      containerName insights-logs-postgresqllogs

  - path: /etc/insights-logs-postgresqlflexsessions.cfg
    permissions: "0600"
    content: |
      accountName __STORAGE_ACCOUNT_NAME__
      accountKey __STORAGE_ACCOUNT_KEY__
      containerName insights-logs-postgresqlflexsessions

  - path: /etc/insights-logs-postgresqlflextablestats.cfg
    permissions: "0600"
    content: |
      accountName __STORAGE_ACCOUNT_NAME__
      accountKey __STORAGE_ACCOUNT_KEY__
      containerName insights-logs-postgresqlflextablestats

  - path: /etc/insights-logs-postgresqlflexdatabasexacts.cfg
    permissions: "0600"
    content: |
      accountName __STORAGE_ACCOUNT_NAME__
      accountKey __STORAGE_ACCOUNT_KEY__
      containerName insights-logs-postgresqlflexdatabasexacts

  - path: /etc/loki/env
    permissions: "0600"
    content: |
      STORAGE_ACCOUNT_KEY=__STORAGE_ACCOUNT_KEY__

  - path: /etc/systemd/system/loki.service
    permissions: "0644"
    content: |
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

  # =========================
  # BLOBFUSE MOUNT SCRIPT
  # =========================
  - path: /etc/blobfuse-mount.sh
    permissions: "0755"
    content: |
      #!/bin/bash

      declare -A mounts=(
        [insights-logs-appserviceauditlogs]="/mnt/insights-logs-appserviceauditlogs:/etc/blobfuse-insights-logs-appserviceauditlogs.cfg"
        [insights-logs-appserviceconsolelogs]="/mnt/insights-logs-appserviceconsolelogs:/etc/blobfuse-insights-logs-appserviceconsolelogs.cfg"
        [insights-logs-appservicehttplogs]="/mnt/insights-logs-appservicehttplogs:/etc/blobfuse-insights-logs-appservicehttplogs.cfg"
        [insights-logs-appserviceplatformlogs]="/mnt/insights-logs-appserviceplatformlogs:/etc/blobfuse-insights-logs-appserviceplatformlogs.cfg"

        [insights-logs-postgresqllogs]="/mnt/pgsql-logs:/etc/insights-logs-postgresqllogs.cfg"
        [insights-logs-postgresqlflexsessions]="/mnt/pgsql-flexsessions:/etc/insights-logs-postgresqlflexsessions.cfg"
        [insights-logs-postgresqlflextablestats]="/mnt/pgsql-flextablestats:/etc/insights-logs-postgresqlflextablestats.cfg"
        [insights-logs-postgresqlflexdatabasexacts]="/mnt/pgsql-flexdatabasexacts:/etc/insights-logs-postgresqlflexdatabasexacts.cfg"
      )

      echo "$(date): Arrêt de td-agent-bit"
      systemctl stop fluent-bit

      for container in "${!mounts[@]}"; do
        IFS=":" read -r mount_point config_file <<< "${mounts[$container]}"

        mkdir -p "$mount_point"

        if mountpoint -q "$mount_point"; then
          echo "$(date): Démontage lazy de $mount_point"
          umount -l "$mount_point"
        fi

        echo "$(date): Montage $container sur $mount_point"
        blobfuse "$mount_point" \
          --config-file="$config_file" \
          --tmp-path=/mnt/blobfuse_tmp \
          --use-attr-cache=false \
          --log-level=LOG_DEBUG
      done

      echo "$(date): Redémarrage de td-agent-bit"
      systemctl start fluent-bit

  # =========================
  # CLEAN LOGS SCRIPT
  # =========================
  - path: /etc/clean-old-logs.sh
    permissions: "0755"
    content: |
      #!/bin/bash
      days=10
      for d in /mnt/insights-logs-appservice*; do
        echo "$(date): Nettoyage dans $d"
        find "$d" -type f -name '*.json' -mtime +"$days" -delete
      done

  # =========================
  # FLUENT BIT CONFIGURATION
  # =========================
  - path: /etc/td-agent-bit/td-agent-bit.conf
    permissions: "0644"
    content: |
      [SERVICE]
          Flush        2
          Daemon       Off
          Log_Level    debug
          Parsers_File parsers.conf
          Workers      2

      [INPUT]
          Name   tail
          Path   /mnt/insights-logs-appserviceauditlogs/ResourceId=/SUBSCRIPTIONS/*/RESOURCEGROUPS/*/PROVIDERS/MICROSOFT.WEB/SITES/*/y=*/m=*/d=*/h=*/m=*/PT1H.json
          Tag    azure.webapp.auditlogs
          Parser json
          Read_from_Head True
          Refresh_Interval 30
          Rotate_Wait 10
          Skip_Long_Lines On

      [INPUT]
          Name   tail
          Path   /mnt/insights-logs-appserviceconsolelogs/resourceId=/SUBSCRIPTIONS/*/RESOURCEGROUPS/*/PROVIDERS/MICROSOFT.WEB/SITES/*/y=*/m=*/d=*/h=*/m=*/PT1H.json
          Tag    azure.webapp.consolelogs
          Parser json
          Read_from_Head True
          Refresh_Interval 30
          Rotate_Wait 10
          Skip_Long_Lines On

      [INPUT]
          Name   tail
          Path   /mnt/insights-logs-appservicehttplogs/resourceId=/SUBSCRIPTIONS/*/RESOURCEGROUPS/*/PROVIDERS/MICROSOFT.WEB/SITES/*/y=*/m=*/d=*/h=*/m=*/PT1H.json
          Tag    azure.webapp.httplogs
          Parser json
          Read_from_Head True
          Refresh_Interval 30
          Rotate_Wait 10
          Skip_Long_Lines On

      [INPUT]
          Name   tail
          Path   /mnt/insights-logs-appserviceplatformlogs/resourceId=/SUBSCRIPTIONS/*/RESOURCEGROUPS/*/PROVIDERS/MICROSOFT.WEB/SITES/*/y=*/m=*/d=*/h=*/m=*/PT1H.json
          Tag    azure.webapp.platformlogs
          Parser json
          Read_from_Head True
          Refresh_Interval 30
          Rotate_Wait 10
          Skip_Long_Lines On

      [INPUT]
          Name   tail
          Path   /mnt/insights-logs-postgresqlflextablestats/resourceId=*/SUBSCRIPTIONS/*/RESOURCEGROUPS/*/PROVIDERS/MICROSOFT.DBFORPOSTGRESQL/FLEXIBLESERVERS/BEEZ360-FRC-FRANCHISEE-PARIS-DEV-PSQL/y=*/m=*/d=*/h=*/m=*/PT1H.json
          Tag    pg.flextablestats
          Parser json
          Read_from_Head True
          Refresh_Interval 30
          Rotate_Wait 10
          Skip_Long_Lines On

      [INPUT]
          Name   tail
          Path   /mnt/insights-logs-postgresqlflexdatabasexacts/resourceId=*/SUBSCRIPTIONS/*/RESOURCEGROUPS/*/PROVIDERS/MICROSOFT.DBFORPOSTGRESQL/FLEXIBLESERVERS/BEEZ360-FRC-FRANCHISEE-PARIS-DEV-PSQL/y=*/m=*/d=*/h=*/m=*/PT1H.json
          Tag    pg.flexdatabasexacts
          Parser json
          Read_from_Head True
          Refresh_Interval 30
          Rotate_Wait 10
          Skip_Long_Lines On

      [INPUT]
          Name   tail
          Path   /mnt/insights-logs-postgresqlflexsessions/resourceId=*/SUBSCRIPTIONS/*/RESOURCEGROUPS/*/PROVIDERS/MICROSOFT.DBFORPOSTGRESQL/FLEXIBLESERVERS/BEEZ360-FRC-FRANCHISEE-PARIS-DEV-PSQL/y=*/m=*/d=*/h=*/m=*/PT1H.json
          Tag    pg.flexsessions
          Parser json
          Read_from_Head True
          Refresh_Interval 30
          Rotate_Wait 10
          Skip_Long_Lines On

      [INPUT]
          Name   tail
          Path   /mnt/insights-logs-postgresqllogs/resourceId=*/SUBSCRIPTIONS/*/RESOURCEGROUPS/*/PROVIDERS/MICROSOFT.DBFORPOSTGRESQL/FLEXIBLESERVERS/BEEZ360-FRC-FRANCHISEE-PARIS-DEV-PSQL/y=*/m=*/d=*/h=*/m=*/PT1H.json
          Tag    pg.logs
          Parser json
          Read_from_Head True
          Refresh_Interval 30
          Rotate_Wait 10
          Skip_Long_Lines On

      [FILTER]
          Name         lua
          Match        azure.webapp.*
          Script       /etc/td-agent-bit/extract_json.lua
          Call         extract_json

      [FILTER]
          Name         lua
          Match        pg.*
          Script       /etc/td-agent-bit/extract_json.lua
          Call         extract_json

      [FILTER]
          Name modify
          Match *
          Rename service service

      [FILTER]
          Name    modify
          Match   azure.webapp.*
          Set     job azure-webapp

      [FILTER]
          Name    modify
          Match   pg.*
          Set     service postgres

      [FILTER]
          Name    modify
          Match   pg.*
          Set     job azure-postgresql

      [FILTER]
          Name    modify
          Match   azure.webapp.*
          Set     service azure-webapp

      [OUTPUT]
          Name        loki
          Match       azure.webapp.*
          Host        __VM_LOGS_IP__
          Port        3100
          Label_keys  $job,$service,$resourceId

  - path: /etc/td-agent-bit/extract_json.lua
    permissions: "0644"
    content: |
      package.cpath = package.cpath .. ";/usr/lib/x86_64-linux-gnu/lua/5.1/?.so"
      local cjson = require "cjson"

      local function parse_iso8601(time_str)
          local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)%.?(%d*)Z"
          local year, month, day, hour, min, sec, ms = time_str:match(pattern)
          if not year then return nil end
          local t = os.time{
              year = tonumber(year),
              month = tonumber(month),
              day = tonumber(day),
              hour = tonumber(hour),
              min = tonumber(min),
              sec = tonumber(sec)
          }
          if ms and #ms > 0 then
              ms = tonumber(string.sub(ms .. "000", 1, 3))
              return t + ms / 1000
          else
              return t
          end
      end

      local function short_resource_name(resourceId)
          if not resourceId then return "unknown" end
          return resourceId:match(".*/SITES/([^/]+)$") or "unknown"
      end

      function extract_json(tag, timestamp, record)
          local log_json = record
          local ok = true
          if not ok or not log_json then
              return 1, timestamp, record
          end

          if log_json.time then
              local new_ts = parse_iso8601(log_json.time)
              if new_ts then
                  timestamp = new_ts
              end
          end

          local resource_id = log_json.resourceId or log_json.ResourceId or nil

          local service = "unknown"
          if resource_id then
              if resource_id:find("SITES/.+-API-WEBAPP") then
                  service = "api"
              elseif resource_id:find("SITES/.+-CLICKANDCOLLECT-WEBAPP") then
                  service = "clickandcollect"
              elseif resource_id:find("SITES/.+-BACKOFFICE-WEBAPP") then
                  service = "backoffice"
              end
              record["resourceId"] = resource_id
          end

          local level = (log_json.level or "info"):lower()
          local time_str = log_json.time or os.date("!%Y-%m-%dT%H:%M:%SZ", timestamp)
          local message = log_json.resultDescription or ""
          message = message:gsub("\27%[[0-9;]*m", "")

          if #message > 300 then
              message = message:sub(1, 300) .. "..."
          end

          local formatted_msg = string.format("%s [%s] %s", time_str, level:upper(), message)

          record["service"] = service
          record["level"] = level
          record["message"] = message
          record["time"] = time_str
          record["formatted_log"] = formatted_msg
          record["short_resource"] = short_resource_name(resource_id)
          record["service_detected"] = service

          return 1, timestamp, record
      end

  - path: /etc/td-agent-bit/parsers.conf
    permissions: "0644"
    content: |
      [PARSER]
          Name   apache
          Format regex
          Regex  ^(?<host>[^ ]*) [^ ]* (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")?$
          Time_Key time
          Time_Format %d/%b/%Y:%H:%M:%S %z

      [PARSER]
          Name   apache2
          Format regex
          Regex  ^(?<host>[^ ]*) [^ ]* (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^ ]*) +\S*)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>.*)")?$
          Time_Key time
          Time_Format %d/%b/%Y:%H:%M:%S %z

      [PARSER]
          Name   apache_error
          Format regex
          Regex  ^\[[^ ]* (?<time>[^\]]*)\] \[(?<level>[^\]]*)\](?: \[pid (?<pid>[^\]]*)\])?( \[client (?<client>[^\]]*)\])? (?<message>.*)$

      [PARSER]
          Name   nginx
          Format regex
          Regex ^(?<remote>[^ ]*) (?<host>[^ ]*) (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")
          Time_Key time
          Time_Format %d/%b/%Y:%H:%M:%S %z

      [PARSER]
          Name        k8s-nginx-ingress
          Format      regex
          Regex       ^(?<host>[^ ]*) - (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*) "(?<referer>[^\"]*)" "(?<agent>[^\"]*)" (?<request_length>[^ ]*) (?<request_time>[^ ]*) \[(?<proxy_upstream_name>[^ ]*)\] (\[(?<proxy_alternative_upstream_name>[^ ]*)\] )?(?<upstream_addr>[^ ]*) (?<upstream_response_length>[^ ]*) (?<upstream_response_time>[^ ]*) (?<upstream_status>[^ ]*) (?<reg_id>[^ ]*).*$ 
          Time_Key    time
          Time_Format %d/%b/%Y:%H:%M:%S %z

      [PARSER]
          Name        json
          Format      json
          Time_Key    time
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z
          Time_Keep   On

      [PARSER]
          Name        nested_json
          Format      json
          Time_Key    time
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z

      [PARSER]
          Name         docker
          Format       json
          Time_Key     time
          Time_Format  %Y-%m-%dT%H:%M:%S.%L
          Time_Keep    On

      [PARSER]
          Name        docker-daemon
          Format      regex
          Regex       time="(?<time>[^ ]*)" level=(?<level>[^ ]*) msg="(?<message>.*)"

      [PARSER]
          Name        syslog-rfc5424
          Format      regex
          Regex       <(?<pri>[0-9]+)>(?<time>[^ ]* [^ ]* [^ ]*) (?<host>[^ ]*) (?<app_name>[^ ]*) (?<procid>[^ ]*) (?<msgid>[^ ]*) (?<message>.*)
          Time_Key    time
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z

      [PARSER]
          Name        syslog-rfc3164
          Format      regex
          Regex       ^(?<time>[A-Z][a-z]{2} [ 0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}) (?<host>[^ ]*) (?<app_name>[^:]*): (?<message>.*)
          Time_Key    time
          Time_Format %b %d %H:%M:%S

      [PARSER]
          Name        syslog-rfc3164-local
          Format      regex
          Regex       ^(?<time>[A-Z][a-z]{2} [ 0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}) (?<host>[^ ]*) (?<message>.*)
          Time_Key    time
          Time_Format %b %d %H:%M:%S

      [PARSER]
          Name        mongodb
          Format      json
          Time_Key    timestamp
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z

      [PARSER]
          Name        envoy
          Format      json
          Time_Key    timestamp
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z

      [PARSER]
          Name        cri
          Format      regex
          Regex       ^(?<time>[0-9-]+T[0-9:.]+Z) (?<stream>stdout|stderr) (?<logtag>F|P) (?<message>.*)
          Time_Key    time
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z

      [PARSER]
          Name        kube-custom
          Format      regex
          Regex       ^(?<time>[0-9T:.Z]+) (?<stream>stdout|stderr) (?<logtag>F|P) (?<message>.*)
          Time_Key    time
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z

      [PARSER]
          Name        postgres
          Format      regex
          Regex       ^(?<time>[^ ]*) \[(?<pid>[0-9]+)\]: (?<level>[^:]+): (?<message>.*)$
          Time_Key    time
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z


      

runcmd:
  # =========================
  # Repo Microsoft + Blobfuse
  # =========================
  - wget https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
  - dpkg -i /tmp/packages-microsoft-prod.deb
  - apt-get update
  - apt-get install -y blobfuse

  # Dossier temporaire blobfuse
  - mkdir -p /mnt/blobfuse_tmp
  - chmod 777 /mnt/blobfuse_tmp


  # =========================
  # Installation Loki
  # =========================
  - apt-get install -y unzip
  - wget https://github.com/grafana/loki/releases/download/v2.9.1/loki-linux-amd64.zip -O /tmp/loki.zip
  - unzip /tmp/loki.zip -d /tmp
  - chmod +x /tmp/loki-linux-amd64
  - mv /tmp/loki-linux-amd64 /usr/local/bin/loki

  - mkdir -p /etc/loki /var/loki/{index,cache,compactor}
  - chown -R azureuser:azureuser /var/loki

  - systemctl daemon-reload
  - systemctl enable loki
  - systemctl start loki

  # =========================
  # Optimisation kernel
  # =========================
  - echo "vm.swappiness=10" >> /etc/sysctl.conf
  - echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  - sysctl -p

  # =========================
  # Installation Fluent Bit
  # =========================
  - curl -fsSL https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh
  - mkdir -p /etc/systemd/system/fluent-bit.service.d
  - echo "[Service]" > /etc/systemd/system/fluent-bit.service.d/override.conf
  - echo "ExecStart=" >> /etc/systemd/system/fluent-bit.service.d/override.conf
  - echo "ExecStart=/opt/fluent-bit/bin/fluent-bit -c /etc/td-agent-bit/td-agent-bit.conf" >> /etc/systemd/system/fluent-bit.service.d/override.conf
  - systemctl daemon-reload

  - systemctl enable fluent-bit
  - systemctl restart fluent-bit
    # Exécuter montage blobfuse
  - chmod +x /etc/blobfuse-mount.sh

  - /etc/blobfuse-mount.sh

  # =========================
  # Cron montages automatiques
  # =========================
  - echo "*/5 * * * * root flock -n /tmp/blobfuse.lock /etc/blobfuse-mount.sh >> /var/log/blobfuse-mount.log 2>&1" > /etc/cron.d/blobfuse-mount
  - echo "0 3 * * * root flock -n /tmp/clean.lock /etc/clean-old-logs.sh >> /var/log/clean-old-logs.log 2>&1" > /etc/cron.d/clean-old-logs
