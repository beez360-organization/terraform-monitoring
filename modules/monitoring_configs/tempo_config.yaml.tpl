server:
  http_listen_port: 3200

storage:
  trace:
    backend: azureblob
    azureblob:
      container: "tempo-traces"
      account_name: "${storage_account_name}"
      account_key: "${storage_account_key}"


  index:
    prefix: "tempo_index_"
    period: 24h
    store: azureblob
    azureblob:
      container: "tempo-index"
      account_name: "${storage_account_name}"
      account_key: "${storage_account_key}"


sampling:
  default_strategy:
    probabilistic:
      sampling_rate: 0.05
