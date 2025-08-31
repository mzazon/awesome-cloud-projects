# Outputs for Azure resource organization with resource groups and tags
# This file provides key information about created resources for verification,
# integration, and cost management reporting

# Resource Group Outputs
output "resource_groups" {
  description = "Information about all created resource groups including names, locations, and tags"
  value = {
    development = {
      name     = azurerm_resource_group.development.name
      id       = azurerm_resource_group.development.id
      location = azurerm_resource_group.development.location
      tags     = azurerm_resource_group.development.tags
    }
    production = {
      name     = azurerm_resource_group.production.name
      id       = azurerm_resource_group.production.id
      location = azurerm_resource_group.production.location
      tags     = azurerm_resource_group.production.tags
    }
    shared = {
      name     = azurerm_resource_group.shared.name
      id       = azurerm_resource_group.shared.id
      location = azurerm_resource_group.shared.location
      tags     = azurerm_resource_group.shared.tags
    }
  }
}

# Storage Account Outputs
output "storage_accounts" {
  description = "Information about created storage accounts including endpoints and access details"
  value = {
    development = {
      name                = azurerm_storage_account.development.name
      id                  = azurerm_storage_account.development.id
      resource_group_name = azurerm_storage_account.development.resource_group_name
      primary_endpoint    = azurerm_storage_account.development.primary_blob_endpoint
      replication_type    = azurerm_storage_account.development.account_replication_type
      tags                = azurerm_storage_account.development.tags
    }
    production = {
      name                = azurerm_storage_account.production.name
      id                  = azurerm_storage_account.production.id
      resource_group_name = azurerm_storage_account.production.resource_group_name
      primary_endpoint    = azurerm_storage_account.production.primary_blob_endpoint
      replication_type    = azurerm_storage_account.production.account_replication_type
      tags                = azurerm_storage_account.production.tags
    }
  }
  sensitive = false
}

# App Service Plan Outputs
output "app_service_plans" {
  description = "Information about created App Service Plans including SKU and capacity details"
  value = {
    development = {
      name                = azurerm_service_plan.development.name
      id                  = azurerm_service_plan.development.id
      resource_group_name = azurerm_service_plan.development.resource_group_name
      sku_name            = azurerm_service_plan.development.sku_name
      os_type             = azurerm_service_plan.development.os_type
      tags                = azurerm_service_plan.development.tags
    }
    production = {
      name                = azurerm_service_plan.production.name
      id                  = azurerm_service_plan.production.id
      resource_group_name = azurerm_service_plan.production.resource_group_name
      sku_name            = azurerm_service_plan.production.sku_name
      os_type             = azurerm_service_plan.production.os_type
      tags                = azurerm_service_plan.production.tags
    }
  }
}

# Shared Infrastructure Outputs
output "shared_infrastructure" {
  description = "Information about shared infrastructure resources"
  value = {
    virtual_network = {
      name                = azurerm_virtual_network.shared.name
      id                  = azurerm_virtual_network.shared.id
      resource_group_name = azurerm_virtual_network.shared.resource_group_name
      address_space       = azurerm_virtual_network.shared.address_space
      subnets             = azurerm_virtual_network.shared.subnet
      tags                = azurerm_virtual_network.shared.tags
    }
  }
}

# Cost Management and Governance Outputs
output "cost_allocation_tags" {
  description = "Summary of tags used for cost allocation and governance across all environments"
  value = {
    environments = {
      development = {
        environment = "development"
        department  = var.department
        costcenter  = var.cost_center_dev  
        owner       = var.owner_dev
      }
      production = {
        environment = "production"
        department  = var.department
        costcenter  = var.cost_center_prod
        owner       = var.owner_prod
        sla         = var.enable_production_compliance ? var.sla_tier : null
        compliance  = var.enable_production_compliance ? var.compliance_framework : null
      }
      shared = {
        environment = "shared"
        department  = "platform"
        costcenter  = var.cost_center_shared
        owner       = var.owner_shared
        scope       = "multi-environment"
      }
    }
    project_metadata = {
      project     = var.project_name
      managedBy   = var.managed_by
      automation  = "enabled"
    }
  }
}

# Resource Naming Convention Outputs
output "naming_convention" {
  description = "Naming convention used for resources to ensure consistency"
  value = {
    resource_suffix     = local.resource_suffix
    resource_group_format = "${local.resource_group_prefix}-{environment}-${local.resource_suffix}"
    storage_format      = "${local.storage_prefix}{environment}${local.resource_suffix}"
    app_service_format  = "${local.app_service_prefix}-{environment}-${local.resource_suffix}"
  }
}

# Subscription and Location Information
output "deployment_info" {
  description = "Information about the deployment location and subscription"
  value = {
    subscription_id = data.azurerm_client_config.current.subscription_id
    tenant_id       = data.azurerm_client_config.current.tenant_id
    location        = var.location
    deployment_time = timestamp()
  }
}

# Tag Inheritance Verification
output "tag_inheritance_verification" {
  description = "Verification data for Azure Cost Management tag inheritance and cost allocation"
  value = {
    resource_groups_with_tags = {
      for rg_key, rg_info in {
        development = azurerm_resource_group.development
        production  = azurerm_resource_group.production
        shared      = azurerm_resource_group.shared
      } : rg_key => {
        name = rg_info.name
        cost_center = lookup(rg_info.tags, "costcenter", "not-set")
        environment = lookup(rg_info.tags, "environment", "not-set")
        department  = lookup(rg_info.tags, "department", "not-set")
        owner       = lookup(rg_info.tags, "owner", "not-set")
      }
    }
    resources_with_specific_tags = {
      storage_accounts = {
        development = {
          name = azurerm_storage_account.development.name
          tier = lookup(azurerm_storage_account.development.tags, "tier", "not-set")
          dataclass = lookup(azurerm_storage_account.development.tags, "dataclass", "not-set")
        }
        production = {
          name = azurerm_storage_account.production.name
          tier = lookup(azurerm_storage_account.production.tags, "tier", "not-set")
          dataclass = lookup(azurerm_storage_account.production.tags, "dataclass", "not-set")
          encryption = lookup(azurerm_storage_account.production.tags, "encryption", "not-set")
        }
      }
      app_service_plans = {
        development = {
          name = azurerm_service_plan.development.name
          tier = lookup(azurerm_service_plan.development.tags, "tier", "not-set")
          workload = lookup(azurerm_service_plan.development.tags, "workload", "not-set")
        }
        production = {
          name = azurerm_service_plan.production.name
          tier = lookup(azurerm_service_plan.production.tags, "tier", "not-set")
          workload = lookup(azurerm_service_plan.production.tags, "workload", "not-set")
          monitoring = lookup(azurerm_service_plan.production.tags, "monitoring", "not-set")
        }
      }
    }
  }
}

# Azure CLI Commands for Validation (as output for reference)
output "validation_commands" {
  description = "Azure CLI commands for validating the deployed infrastructure and tags"
  value = {
    list_resource_groups = "az group list --query \"[?contains(name, '${local.resource_suffix}')].{Name:name, Location:location, Tags:tags}\" --output table"
    query_by_environment = "az resource list --tag environment=development --query \"[].{Name:name, Type:type, ResourceGroup:resourceGroup}\" --output table"
    query_by_cost_center = "az resource list --tag costcenter=${var.cost_center_dev} --query \"[].{Name:name, Type:type, CostCenter:tags.costcenter}\" --output table"
    cost_allocation_report = "az resource list --query \"[?tags.costcenter != null].{Name:name, Environment:tags.environment, CostCenter:tags.costcenter, Department:tags.department}\" --output table"
  }
}