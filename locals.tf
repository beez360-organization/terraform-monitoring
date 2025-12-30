locals {
  normalized_regions = {
    for key, val in var.regions : key => lower(replace(val, " ", "-"))
  }
}

