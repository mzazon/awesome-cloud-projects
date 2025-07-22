# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    
    virtual_machine_scale_set {
      roll_instances_when_required = true
    }
    
    application_gateway {
      # Enable Application Gateway WAF logging
      rule_set_type    = "OWASP"
      rule_set_version = "3.2"
    }
  }
}

# Configure the Random Provider
provider "random" {
  # No specific configuration required
}