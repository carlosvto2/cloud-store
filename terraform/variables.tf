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

variable "ingress_namespace" {
  type        = string
  default     = "ingress-basic"
  description = "Namespace where the Ingress Controller Infrastructure will be deployed"
}

variable "use_custom_acr" {
  type        = bool
  default     = false
  description = "Specify if the images must come from a private ACR"
}

# -----------------------------------------------------------------------------
# NGINX Ingress Controller - Image configuration in ACR
# -----------------------------------------------------------------------------

# Controller
variable "controller_image" {
  type        = string
  default     = "ingress-nginx/controller"
  description = "Ingress Controller Image route in ACR"
}

variable "controller_tag" {
  type        = string
  default     = "v1.0.4"
  description = "Ingress Controller image Tag/Version"
}

# Webhook Patch (Admission Webhooks)
variable "patch_image" {
  type        = string
  default     = "ingress-nginx/kube-webhook-certgen"
  description = "Webhook patch Image route in ACR"
}

variable "patch_tag" {
  type        = string
  default     = "v1.1.1"
  description = "Webhook patch image Tag/Version"
}

# Default Backend
variable "defaultbackend_image" {
  type        = string
  default     = "defaultbackend-amd64"
  description = "Default backend Image route in ACR"
}

variable "defaultbackend_tag" {
  type        = string
  default     = "1.5"
  description = "Default backendimage Tag/Version"
}