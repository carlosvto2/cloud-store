terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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