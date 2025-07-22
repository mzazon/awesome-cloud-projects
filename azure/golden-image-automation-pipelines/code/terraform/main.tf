# Get current client configuration
data "azurerm_client_config" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name != "" ? var.resource_group_name : "rg-${var.project_name}-${random_string.suffix.result}"
  location = var.location

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Create hub virtual network for DNS resolver
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-${random_string.suffix.result}"
  address_space       = var.hub_vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    VNetType    = "hub"
  })
}

# Create inbound subnet for DNS resolver
resource "azurerm_subnet" "resolver_inbound" {
  name                 = "resolver-inbound-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.resolver_inbound_subnet_address_prefix]

  # Delegation for DNS resolver
  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Create outbound subnet for DNS resolver
resource "azurerm_subnet" "resolver_outbound" {
  name                 = "resolver-outbound-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.resolver_outbound_subnet_address_prefix]

  # Delegation for DNS resolver
  delegation {
    name = "Microsoft.Network.dnsResolvers"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Create Azure Private DNS Resolver
resource "azurerm_private_dns_resolver" "main" {
  name                = "pdns-resolver-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  virtual_network_id  = azurerm_virtual_network.hub.id

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Create inbound endpoint for DNS resolver
resource "azurerm_private_dns_resolver_inbound_endpoint" "main" {
  name                    = "inbound-endpoint"
  private_dns_resolver_id = azurerm_private_dns_resolver.main.id
  location                = azurerm_resource_group.main.location
  
  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                   = azurerm_subnet.resolver_inbound.id
  }

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Create outbound endpoint for DNS resolver
resource "azurerm_private_dns_resolver_outbound_endpoint" "main" {
  name                    = "outbound-endpoint"
  private_dns_resolver_id = azurerm_private_dns_resolver.main.id
  location                = azurerm_resource_group.main.location
  subnet_id               = azurerm_subnet.resolver_outbound.id

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Create DNS forwarding ruleset
resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "main" {
  name                                       = "corporate-ruleset"
  resource_group_name                        = azurerm_resource_group.main.name
  location                                   = azurerm_resource_group.main.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.main.id]

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Create DNS forwarding rules (if provided)
resource "azurerm_private_dns_resolver_forwarding_rule" "rules" {
  for_each = { for rule in var.dns_forwarding_rules : rule.name => rule }

  name                      = each.value.name
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.main.id
  domain_name               = each.value.domain
  enabled                   = true

  dynamic "target_dns_servers" {
    for_each = each.value.target_servers
    content {
      ip_address = target_dns_servers.value
      port       = 53
    }
  }
}

# Create build virtual network
resource "azurerm_virtual_network" "build" {
  name                = "vnet-build-${random_string.suffix.result}"
  address_space       = var.build_vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    VNetType    = "build"
  })
}

# Create build subnet
resource "azurerm_subnet" "build" {
  name                 = "build-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.build.name
  address_prefixes     = [var.build_subnet_address_prefix]
}

# Create virtual network peering from build to hub
resource "azurerm_virtual_network_peering" "build_to_hub" {
  name                      = "build-to-hub"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.build.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}

# Create virtual network peering from hub to build
resource "azurerm_virtual_network_peering" "hub_to_build" {
  name                      = "hub-to-build"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.build.id
  allow_virtual_network_access = true
  allow_forwarded_traffic   = true
  allow_gateway_transit     = false
  use_remote_gateways       = false
}

# Link DNS forwarding ruleset to build virtual network
resource "azurerm_private_dns_resolver_virtual_network_link" "build_vnet_link" {
  name                      = "build-vnet-link"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.main.id
  virtual_network_id        = azurerm_virtual_network.build.id
}

# Create Azure Compute Gallery
resource "azurerm_shared_image_gallery" "main" {
  name                = "gallery${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  description         = var.compute_gallery_description

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Create gallery image definition
resource "azurerm_shared_image" "ubuntu_hardened" {
  name                = "ubuntu-server-hardened"
  gallery_name        = azurerm_shared_image_gallery.main.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  
  identifier {
    publisher = var.gallery_image_definition_publisher
    offer     = var.gallery_image_definition_offer
    sku       = var.gallery_image_definition_sku
  }

  description = var.gallery_image_definition_description

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    ImageType   = "hardened-ubuntu"
  })
}

# Create user-assigned managed identity for VM Image Builder
resource "azurerm_user_assigned_identity" "image_builder" {
  name                = "id-image-builder-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "vm-image-builder"
  })
}

# Assign Virtual Machine Contributor role to managed identity
resource "azurerm_role_assignment" "vm_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.image_builder.principal_id
}

# Assign Storage Account Contributor role to managed identity
resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.image_builder.principal_id
}

# Assign Network Contributor role to managed identity
resource "azurerm_role_assignment" "network_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.image_builder.principal_id
}

# Create custom role for Compute Gallery access
resource "azurerm_role_definition" "image_builder_gallery" {
  name        = "Image Builder Gallery Role ${random_string.suffix.result}"
  scope       = azurerm_resource_group.main.id
  description = "Custom role for VM Image Builder to access Compute Gallery"

  permissions {
    actions = [
      "Microsoft.Compute/galleries/read",
      "Microsoft.Compute/galleries/images/read",
      "Microsoft.Compute/galleries/images/versions/read",
      "Microsoft.Compute/galleries/images/versions/write",
      "Microsoft.Compute/images/read",
      "Microsoft.Compute/images/write",
      "Microsoft.Compute/images/delete"
    ]
    not_actions = []
  }

  assignable_scopes = [
    azurerm_resource_group.main.id
  ]
}

# Assign custom gallery role to managed identity
resource "azurerm_role_assignment" "gallery_custom" {
  scope              = azurerm_resource_group.main.id
  role_definition_id = azurerm_role_definition.image_builder_gallery.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.image_builder.principal_id
}

# Generate image customization scripts
locals {
  # Default customization scripts
  default_scripts = [
    {
      name        = "UpdateSystem"
      script_type = "Shell"
      inline = [
        "sudo apt-get update -y",
        "sudo apt-get upgrade -y",
        "sudo apt-get install -y curl wget unzip"
      ]
    }
  ]

  # Security hardening script
  security_script = var.enable_security_hardening ? [{
    name        = "InstallSecurity"
    script_type = "Shell"
    inline = [
      "sudo apt-get install -y fail2ban ufw",
      "sudo ufw --force enable",
      "sudo systemctl enable fail2ban",
      "sudo systemctl start fail2ban"
    ]
  }] : []

  # Monitoring tools script
  monitoring_script = var.enable_monitoring_tools ? [{
    name        = "InstallMonitoring"
    script_type = "Shell"
    inline = [
      "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash",
      "wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb",
      "sudo dpkg -i packages-microsoft-prod.deb",
      "sudo apt-get update",
      "sudo apt-get install -y azure-cli"
    ]
  }] : []

  # Compliance configuration script
  compliance_script = var.enable_compliance_configuration ? [{
    name        = "ConfigureCompliance"
    script_type = "Shell"
    inline = [
      "sudo mkdir -p /etc/corporate",
      "echo 'Golden Image Build Date: $(date)' | sudo tee /etc/corporate/build-info.txt",
      "sudo chmod 644 /etc/corporate/build-info.txt"
    ]
  }] : []

  # Combine all scripts
  all_scripts = concat(
    local.default_scripts,
    local.security_script,
    local.monitoring_script,
    local.compliance_script,
    var.custom_image_scripts
  )

  # Determine replication regions (use current region if none specified)
  replication_regions = length(var.replication_regions) > 0 ? var.replication_regions : [var.location]
}

# Create VM Image Builder template
resource "azurerm_image" "template" {
  name                = "template-ubuntu-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Purpose     = "image-template"
  })
}

# Create the VM Image Builder template configuration using local file
resource "local_file" "image_template" {
  filename = "${path.module}/image-template.json"
  content = jsonencode({
    type       = "Microsoft.VirtualMachineImages/imageTemplates"
    apiVersion = "2022-02-14"
    location   = var.location
    dependsOn  = []
    tags = merge(var.tags, {
      Environment = var.environment
      Project     = var.project_name
      Purpose     = "golden-image"
    })
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        "${azurerm_user_assigned_identity.image_builder.id}" = {}
      }
    }
    properties = {
      buildTimeoutInMinutes = var.vm_image_builder_build_timeout
      vmProfile = {
        vmSize      = var.vm_image_builder_vm_size
        osDiskSizeGB = var.vm_image_builder_os_disk_size
        vnetConfig = {
          subnetId = azurerm_subnet.build.id
        }
      }
      source = {
        type      = "PlatformImage"
        publisher = var.source_image_publisher
        offer     = var.source_image_offer
        sku       = var.source_image_sku
        version   = var.source_image_version
      }
      customize = [
        for script in local.all_scripts : {
          type   = script.script_type
          name   = script.name
          inline = script.inline
        }
      ]
      distribute = [
        {
          type         = "SharedImage"
          galleryImageId = azurerm_shared_image.ubuntu_hardened.id
          runOutputName  = "ubuntu-hardened-image"
          replicationRegions = local.replication_regions
          storageAccountType = var.storage_account_type
        }
      ]
    }
  })

  depends_on = [
    azurerm_role_assignment.vm_contributor,
    azurerm_role_assignment.storage_contributor,
    azurerm_role_assignment.network_contributor,
    azurerm_role_assignment.gallery_custom
  ]
}

# Create Azure DevOps pipeline configuration
resource "local_file" "azure_pipelines" {
  filename = "${path.module}/azure-pipelines.yml"
  content = templatefile("${path.module}/azure-pipelines.yml.tpl", {
    resource_group_name   = azurerm_resource_group.main.name
    location             = var.location
    image_template_name  = "template-ubuntu-${random_string.suffix.result}"
    project_name         = var.project_name
    environment          = var.environment
  })
}

# Create the pipeline template file
resource "local_file" "pipeline_template" {
  filename = "${path.module}/azure-pipelines.yml.tpl"
  content = <<-EOT
trigger:
  branches:
    include:
    - main
  paths:
    include:
    - image-templates/*

pool:
  vmImage: 'ubuntu-latest'

variables:
  resourceGroup: '$${resource_group_name}'
  location: '$${location}'
  imageTemplateName: '$${image_template_name}'
  projectName: '$${project_name}'
  environment: '$${environment}'

stages:
- stage: ValidateTemplate
  displayName: 'Validate Image Template'
  jobs:
  - job: ValidateJob
    displayName: 'Validate'
    steps:
    - task: AzureCLI@2
      displayName: 'Validate Template Syntax'
      inputs:
        azureSubscription: 'Azure Service Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az deployment group validate \
            --resource-group $$(resourceGroup) \
            --template-file image-template.json \
            --parameters imageTemplateName=$$(imageTemplateName)

- stage: BuildImage
  displayName: 'Build Golden Image'
  dependsOn: ValidateTemplate
  condition: succeeded()
  jobs:
  - job: BuildJob
    displayName: 'Build'
    timeoutInMinutes: 120
    steps:
    - task: AzureCLI@2
      displayName: 'Deploy Image Template'
      inputs:
        azureSubscription: 'Azure Service Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az deployment group create \
            --resource-group $$(resourceGroup) \
            --template-file image-template.json \
            --parameters imageTemplateName=$$(imageTemplateName)

    - task: AzureCLI@2
      displayName: 'Start Image Build'
      inputs:
        azureSubscription: 'Azure Service Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az image builder run \
            --name $$(imageTemplateName) \
            --resource-group $$(resourceGroup)

    - task: AzureCLI@2
      displayName: 'Monitor Build Progress'
      inputs:
        azureSubscription: 'Azure Service Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          while true; do
            BUILD_STATUS=$$(az image builder show \
              --name $$(imageTemplateName) \
              --resource-group $$(resourceGroup) \
              --query properties.lastRunStatus.runState \
              --output tsv)
            
            echo "Build status: $$BUILD_STATUS"
            
            if [ "$$BUILD_STATUS" == "Succeeded" ]; then
              echo "Image build completed successfully"
              break
            elif [ "$$BUILD_STATUS" == "Failed" ]; then
              echo "Image build failed"
              exit 1
            fi
            
            sleep 60
          done

- stage: PublishImage
  displayName: 'Publish Image Version'
  dependsOn: BuildImage
  condition: succeeded()
  jobs:
  - job: PublishJob
    displayName: 'Publish'
    steps:
    - task: AzureCLI@2
      displayName: 'Tag Image Version'
      inputs:
        azureSubscription: 'Azure Service Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          VERSION=$$(date +%Y%m%d.%H%M%S)
          echo "Publishing image version: $$VERSION"
          # Additional tagging or metadata operations can be added here
EOT
}