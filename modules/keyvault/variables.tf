variable "prefix" {}
variable "location" {}
variable "resource_group_name" {}
variable "tenant_id" {}
variable "tags" {
  type = map(string)
}
variable "storage_account_key" {
  sensitive = true
}