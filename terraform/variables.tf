variable "prefix" {
  type        = string
  default     = "azurestore"
  description = "Prefix to name consistently all the Azure resources"
}

variable "location" {
  type        = string
  default     = "westeurope"
  description = "Azure region"
}