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
  - jq
  - software-properties-common
  - gnupg
  - kafkacat

write_files:


  # =========================
  # Loki config
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
          account_name: "__STORAGE_ACCOUNT_NAME__"
          account_key: "__STORAGE_ACCOUNT_KEY__"

      limits_config:
        ingestion_rate_mb: 10
        ingestion_burst_size_mb: 15
        allow_structured_metadata: false

      compactor:
        working_directory: /var/loki/compactor
        retention_enabled: true
        shared_store: azure

  # =========================
  # Loki ENV 
  # =========================
  - path: /etc/loki/env
    permissions: "0600"
    content: |
      STORAGE_ACCOUNT_KEY=__STORAGE_ACCOUNT_KEY__

  # =========================
  # Loki systemd
  # =========================
  - path: /etc/systemd/system/loki.service
    permissions: "0644"
    content: |
      [Unit]
      Description=Loki
      After=network-online.target

      [Service]
      ExecStart=/usr/local/bin/loki -config.file=/etc/loki/local-config.yaml -config.expand-env=true
      Restart=always
      EnvironmentFile=/etc/loki/env
      LimitNOFILE=65536

      [Install]
      WantedBy=multi-user.target

  # =========================
  # Fluent Bit config (FULL)
  # =========================
  - path: /etc/fluent-bit/fluent-bit.conf
    permissions: "0644"
    content: |
      [SERVICE]
          Flush 2
          Daemon Off
          Log_Level info
          Parsers_File parsers.conf
          Workers 2

      [INPUT]
          Name kafka
          Tag eventhub.logs
          Brokers evh-beez360-monitoring-dev.servicebus.windows.net:9093
          Topics logs-appservice
          Group_Id fluentbit-eventhub
          Format json
          rdkafka.security.protocol SASL_SSL
          rdkafka.sasl.mechanisms PLAIN
          rdkafka.sasl.username $ConnectionString
          rdkafka.sasl.password __EVENTHUB_SAS__
          rdkafka.enable.ssl.certificate.verification false
          rdkafka.auto.offset.reset earliest

      [FILTER]
          Name lua
          Match eventhub.logs
          script /etc/fluent-bit/split.lua
          call split_records

      [OUTPUT]
          Name loki
          Match *
          Host __VM_LOGS_IP__
          Port 3100
          Labels job=eventhub
          Line_Format json

  # =========================
  # Lua parser FULL (ton original logique gardée)
  # =========================
  - path: /etc/fluent-bit/split.lua
    permissions: "0644"
    content: |
      local cjson = require "cjson"

      function split_records(tag, timestamp, record)
          local new_records = {}

          if not record["payload"] or not record["payload"]["records"] then
              record["error"] = "missing payload.records"
              return 1, timestamp, record
          end

          if type(record["payload"]["records"]) ~= "table" then
              record["error"] = "payload.records is not a table"
              return 1, timestamp, record
          end

          for _, r in ipairs(record["payload"]["records"]) do
              local nr = {}
              nr["time"] = r["time"] or record["time"] or os.time()

              local category = r["category"] or "-"
              nr["category"] = category
              nr["level"] = (r["level"] or "info"):lower()

              local message = "-"
              local email = "-"
              local status = 0

              if r["properties"] then
                  local ok, props = pcall(cjson.decode, r["properties"])
                  if ok and props then
                      if props.CsUsername and props.CsUsername ~= "" then
                          email = props.CsUsername
                      end

                      status = tonumber(props.ScStatus or 0)

                      local method = props.CsMethod or "-"
                      local path = props.CsUriStem or "-"
                      local duration = props.TimeTaken or 0

                      if path:find("logstream") then
                          goto continue
                      end

                      if method ~= "-" and path ~= "-" then
                          message = string.format("%s %s → %s (%sms)", method, path, status, duration)
                      end
                  else
                      message = "ERROR parsing properties JSON"
                  end
              end

              nr["message"] = message
              nr["email"] = email
              nr["status"] = status

              table.insert(new_records, nr)

              ::continue::
          end

          return 2, timestamp, new_records
      end

runcmd:

  # kafkacat

  # Loki install
  - wget -O /tmp/loki.zip https://github.com/grafana/loki/releases/download/v2.9.1/loki-linux-amd64.zip
  - unzip -o /tmp/loki.zip -d /tmp
  - mv /tmp/loki-linux-amd64 /usr/local/bin/loki
  - chmod +x /usr/local/bin/loki

  # dirs
  - mkdir -p /etc/loki /var/loki/index /var/loki/cache /var/loki/compactor
  - chown -R azureuser:azureuser /var/loki

  # systemd
  - systemctl daemon-reload
  - systemctl enable loki
  - systemctl start loki || true

  # Fluent-bit install
  - curl -fsSL https://packages.fluentbit.io/fluentbit.key | gpg --dearmor -o /usr/share/keyrings/fluentbit.gpg
  - echo "deb [signed-by=/usr/share/keyrings/fluentbit.gpg] https://packages.fluentbit.io/ubuntu/jammy jammy main" > /etc/apt/sources.list.d/fluent-bit.list

  - apt-get update
  - DEBIAN_FRONTEND=noninteractive apt-get install -y fluent-bit
  - systemctl daemon-reload
  - systemctl enable fluent-bit
  - systemctl restart fluent-bit || true

  # sys tuning
  - echo "vm.swappiness=10" >> /etc/sysctl.conf
  - echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  - sysctl -p || true