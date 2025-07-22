# versions.tf
# Terraform version and provider requirements for Azure Network Performance Monitoring

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
    
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
    
    application_insights {
      disable_generated_rule = false
    }
  }
}

# Configure the Random Provider for unique resource naming
provider "random" {}