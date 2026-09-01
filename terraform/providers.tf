terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kustomization = {
      source  = "kbst/kustomization"
      version = ">= 0.9.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "game-infra-tfstate-rg"
    storage_account_name = "gametfstatestorage2026"
    container_name       = "tfstate"
    key                  = "game-api.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

provider "kustomization" {
  kubeconfig_raw = azurerm_kubernetes_cluster.aks.kube_config_raw
}