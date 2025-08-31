# Terraform configuration block specifying required providers and versions
terraform {
  required_version = ">= 1.5"

  required_providers {
    # Azure Resource Manager provider for managing Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }

    # Random provider for generating unique resource names and values
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider with required features
provider "azurerm" {
  features {
    # Ensure complete deletion of resources during terraform destroy
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    # Configure storage account behavior
    storage {
      prevent_blob_public_access_on_storage_account = true
    }

    # Configure cognitive services behavior
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}