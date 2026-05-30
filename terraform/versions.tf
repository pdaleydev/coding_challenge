terraform {
  required_version = ">= 1.5"

    required_providers {
      azurerm = {
        source  = "hashicorp/azurerm"
        version = "~> 3.110"
      }
    }

    backend "azurerm" {
      resource_group_name  = "azure-terraform-states"           # resource group holding the storage account
      storage_account_name = "pdaleyterraformstates"         # the storage account you manually created
      container_name       = "tfstate"              # the blob container inside that account
      key                  = "hlwrld-dev.tfstate"   # filename for this project's state file
    }
}