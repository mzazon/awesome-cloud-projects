# Terraform and provider version requirements
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    # Enable explicit resource group deletion
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Configure firewall features
    firewall {
      delete_subnet_on_destroy = true
    }
    
    # Configure virtual machine features
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
  }
}