locals {
  normalized_regions = {
    for key, val in var.regions : key => lower(replace(val, " ", "-"))
  }
}
locals {
  storage_account_name = module.storage.storage_account_name
  storage_account_key  = module.storage.primary_access_key
}




