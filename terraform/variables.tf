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

variable "azure_client_id" {
  type        = string
  description = "App ID / Client ID of the Azure Service Principal"
}

variable "azure_client_secret" {
  type        = string
  description = "Client Secret of the Azure Service Principal"
}

variable "azure_devops_pat" {
  type        = string
  description = "Personal Access Token of Azure DevOps with read access to the repo"
  sensitive   = true
}

variable "azure_client_object_id" {
  type    = string
  default = "6ae11d01-6d46-4001-8c55-c2e3796c710c"
}