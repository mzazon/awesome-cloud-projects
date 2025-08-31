# Azure Communication Services Monitoring Infrastructure
# Provider version requirements and configuration

terraform {
  required_version = ">= 1.9"
  
  required_providers {
    # Azure Resource Manager provider for core Azure resources
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.37"
    }
    
    # Random provider for generating unique resource names
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Azure Provider with enhanced features
provider "azurerm" {
  # Enhanced features block for resource management
  features {
    # Resource group management features
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    # Log Analytics workspace features
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
    
    # Application Insights features  
    application_insights {
      disable_generated_rule = false
    }
  }
  
  # Enhanced resource provider registration for Communication Services
  resource_provider_registrations = "extended"
}

# Random provider configuration (no special configuration needed)
provider "random" {}