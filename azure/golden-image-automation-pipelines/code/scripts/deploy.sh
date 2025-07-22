#!/bin/bash

# Deploy Azure VM Image Builder with Private DNS Resolver
# This script creates an automated golden image pipeline with hybrid DNS resolution

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check required tools
    for tool in openssl; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-golden-image-${RANDOM_SUFFIX}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Define resource names
    export HUB_VNET_NAME="vnet-hub-${RANDOM_SUFFIX}"
    export BUILD_VNET_NAME="vnet-build-${RANDOM_SUFFIX}"
    export PRIVATE_DNS_RESOLVER_NAME="pdns-resolver-${RANDOM_SUFFIX}"
    export COMPUTE_GALLERY_NAME="gallery${RANDOM_SUFFIX}"
    export IMAGE_TEMPLATE_NAME="template-ubuntu-${RANDOM_SUFFIX}"
    export MANAGED_IDENTITY_NAME="id-image-builder-${RANDOM_SUFFIX}"
    
    log "Environment variables set:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  Subscription ID: ${SUBSCRIPTION_ID}"
    log "  Random Suffix: ${RANDOM_SUFFIX}"
    
    success "Environment variables configured"
}

# Create resource group and register providers
create_resource_group() {
    log "Creating resource group and registering providers..."
    
    # Create resource group
    az group create \
        --name ${RESOURCE_GROUP} \
        --location ${LOCATION} \
        --tags purpose=golden-image-pipeline environment=demo
    
    # Register required resource providers
    log "Registering required resource providers..."
    az provider register --namespace Microsoft.VirtualMachineImages --wait
    az provider register --namespace Microsoft.Network --wait
    az provider register --namespace Microsoft.Compute --wait
    
    success "Resource group created: ${RESOURCE_GROUP}"
    success "Resource providers registered successfully"
}

# Create hub virtual network and Private DNS Resolver
create_hub_network() {
    log "Creating hub virtual network and Private DNS Resolver..."
    
    # Create hub virtual network for DNS resolver
    az network vnet create \
        --name ${HUB_VNET_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --address-prefixes 10.0.0.0/16 \
        --subnet-name resolver-inbound-subnet \
        --subnet-prefixes 10.0.1.0/24
    
    # Create outbound subnet for DNS resolver
    az network vnet subnet create \
        --name resolver-outbound-subnet \
        --resource-group ${RESOURCE_GROUP} \
        --vnet-name ${HUB_VNET_NAME} \
        --address-prefixes 10.0.2.0/24
    
    # Create Azure Private DNS Resolver
    az dns-resolver create \
        --name ${PRIVATE_DNS_RESOLVER_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --vnet ${HUB_VNET_NAME} \
        --location ${LOCATION}
    
    success "Hub virtual network and Private DNS Resolver created"
}

# Configure DNS resolver endpoints
configure_dns_endpoints() {
    log "Configuring DNS resolver endpoints..."
    
    # Get subnet IDs
    INBOUND_SUBNET_ID=$(az network vnet subnet show \
        --name resolver-inbound-subnet \
        --vnet-name ${HUB_VNET_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query id --output tsv)
    
    OUTBOUND_SUBNET_ID=$(az network vnet subnet show \
        --name resolver-outbound-subnet \
        --vnet-name ${HUB_VNET_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query id --output tsv)
    
    # Create inbound endpoint for on-premises to Azure DNS resolution
    az dns-resolver inbound-endpoint create \
        --name "inbound-endpoint" \
        --dns-resolver-name ${PRIVATE_DNS_RESOLVER_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --subnet-id ${INBOUND_SUBNET_ID}
    
    # Create outbound endpoint for Azure to on-premises DNS resolution
    az dns-resolver outbound-endpoint create \
        --name "outbound-endpoint" \
        --dns-resolver-name ${PRIVATE_DNS_RESOLVER_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --subnet-id ${OUTBOUND_SUBNET_ID}
    
    # Get outbound endpoint ID
    OUTBOUND_ENDPOINT_ID=$(az dns-resolver outbound-endpoint show \
        --name "outbound-endpoint" \
        --dns-resolver-name ${PRIVATE_DNS_RESOLVER_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query id --output tsv)
    
    # Create DNS forwarding ruleset for on-premises domains
    az dns-resolver forwarding-ruleset create \
        --name "corporate-ruleset" \
        --resource-group ${RESOURCE_GROUP} \
        --outbound-endpoints ${OUTBOUND_ENDPOINT_ID}
    
    success "DNS resolver endpoints configured successfully"
}

# Create build virtual network with DNS integration
create_build_network() {
    log "Creating build virtual network with DNS integration..."
    
    # Create build virtual network for VM Image Builder
    az network vnet create \
        --name ${BUILD_VNET_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --address-prefixes 10.1.0.0/16 \
        --subnet-name build-subnet \
        --subnet-prefixes 10.1.1.0/24
    
    # Create virtual network peering from build to hub
    az network vnet peering create \
        --name "build-to-hub" \
        --resource-group ${RESOURCE_GROUP} \
        --vnet-name ${BUILD_VNET_NAME} \
        --remote-vnet ${HUB_VNET_NAME} \
        --allow-vnet-access
    
    # Create virtual network peering from hub to build
    az network vnet peering create \
        --name "hub-to-build" \
        --resource-group ${RESOURCE_GROUP} \
        --vnet-name ${HUB_VNET_NAME} \
        --remote-vnet ${BUILD_VNET_NAME} \
        --allow-vnet-access
    
    # Get build virtual network ID
    BUILD_VNET_ID=$(az network vnet show \
        --name ${BUILD_VNET_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query id --output tsv)
    
    # Link DNS forwarding ruleset to build virtual network
    az dns-resolver forwarding-ruleset virtual-network-link create \
        --name "build-vnet-link" \
        --resource-group ${RESOURCE_GROUP} \
        --ruleset-name "corporate-ruleset" \
        --virtual-network-id ${BUILD_VNET_ID}
    
    success "Build virtual network created and linked to DNS resolver"
}

# Create Azure Compute Gallery
create_compute_gallery() {
    log "Creating Azure Compute Gallery for image distribution..."
    
    # Create Azure Compute Gallery for image distribution
    az sig create \
        --gallery-name ${COMPUTE_GALLERY_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --description "Corporate Golden Image Gallery" \
        --tags environment=production purpose=golden-images
    
    # Create image definition for Ubuntu server
    az sig image-definition create \
        --gallery-name ${COMPUTE_GALLERY_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --gallery-image-definition "ubuntu-server-hardened" \
        --publisher "CorporateIT" \
        --offer "UbuntuServer" \
        --sku "20.04-LTS-Hardened" \
        --os-type Linux \
        --os-state generalized \
        --description "Corporate hardened Ubuntu 20.04 LTS server image"
    
    # Create managed identity for VM Image Builder
    az identity create \
        --name ${MANAGED_IDENTITY_NAME} \
        --resource-group ${RESOURCE_GROUP}
    
    success "Compute Gallery and managed identity created"
}

# Configure VM Image Builder permissions
configure_permissions() {
    log "Configuring VM Image Builder permissions..."
    
    # Get managed identity details
    IDENTITY_ID=$(az identity show \
        --name ${MANAGED_IDENTITY_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query id --output tsv)
    
    IDENTITY_PRINCIPAL_ID=$(az identity show \
        --name ${MANAGED_IDENTITY_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query principalId --output tsv)
    
    # Wait for identity to be fully created
    sleep 30
    
    # Assign required permissions to managed identity
    az role assignment create \
        --assignee ${IDENTITY_PRINCIPAL_ID} \
        --role "Virtual Machine Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    
    az role assignment create \
        --assignee ${IDENTITY_PRINCIPAL_ID} \
        --role "Storage Account Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    
    az role assignment create \
        --assignee ${IDENTITY_PRINCIPAL_ID} \
        --role "Network Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    
    # Create custom role for Compute Gallery access
    cat > image-builder-role.json << EOF
{
    "Name": "Image Builder Gallery Role",
    "IsCustom": true,
    "Description": "Custom role for VM Image Builder to access Compute Gallery",
    "Actions": [
        "Microsoft.Compute/galleries/read",
        "Microsoft.Compute/galleries/images/read",
        "Microsoft.Compute/galleries/images/versions/read",
        "Microsoft.Compute/galleries/images/versions/write",
        "Microsoft.Compute/images/read",
        "Microsoft.Compute/images/write",
        "Microsoft.Compute/images/delete"
    ],
    "NotActions": [],
    "AssignableScopes": ["/subscriptions/${SUBSCRIPTION_ID}"]
}
EOF
    
    # Create and assign custom role
    az role definition create --role-definition image-builder-role.json
    
    az role assignment create \
        --assignee ${IDENTITY_PRINCIPAL_ID} \
        --role "Image Builder Gallery Role" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    
    success "VM Image Builder permissions configured"
}

# Create VM Image Builder template
create_image_template() {
    log "Creating VM Image Builder template..."
    
    # Get managed identity ID and subnet ID
    IDENTITY_ID=$(az identity show \
        --name ${MANAGED_IDENTITY_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query id --output tsv)
    
    SUBNET_ID=$(az network vnet subnet show \
        --name build-subnet \
        --vnet-name ${BUILD_VNET_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query id --output tsv)
    
    # Create VM Image Builder template configuration
    cat > image-template.json << EOF
{
    "type": "Microsoft.VirtualMachineImages/imageTemplates",
    "apiVersion": "2022-02-14",
    "location": "${LOCATION}",
    "dependsOn": [],
    "tags": {
        "purpose": "golden-image",
        "environment": "production"
    },
    "identity": {
        "type": "UserAssigned",
        "userAssignedIdentities": {
            "${IDENTITY_ID}": {}
        }
    },
    "properties": {
        "buildTimeoutInMinutes": 80,
        "vmProfile": {
            "vmSize": "Standard_D2s_v3",
            "osDiskSizeGB": 30,
            "vnetConfig": {
                "subnetId": "${SUBNET_ID}"
            }
        },
        "source": {
            "type": "PlatformImage",
            "publisher": "Canonical",
            "offer": "0001-com-ubuntu-server-focal",
            "sku": "20_04-lts-gen2",
            "version": "latest"
        },
        "customize": [
            {
                "type": "Shell",
                "name": "UpdateSystem",
                "inline": [
                    "sudo apt-get update -y",
                    "sudo apt-get upgrade -y",
                    "sudo apt-get install -y curl wget unzip"
                ]
            },
            {
                "type": "Shell",
                "name": "InstallSecurity",
                "inline": [
                    "sudo apt-get install -y fail2ban ufw",
                    "sudo ufw --force enable",
                    "sudo systemctl enable fail2ban",
                    "sudo systemctl start fail2ban"
                ]
            },
            {
                "type": "Shell",
                "name": "InstallMonitoring",
                "inline": [
                    "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash",
                    "wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb",
                    "sudo dpkg -i packages-microsoft-prod.deb",
                    "sudo apt-get update",
                    "sudo apt-get install -y azure-cli"
                ]
            },
            {
                "type": "Shell",
                "name": "ConfigureCompliance",
                "inline": [
                    "sudo mkdir -p /etc/corporate",
                    "echo 'Golden Image Build Date: \$(date)' | sudo tee /etc/corporate/build-info.txt",
                    "sudo chmod 644 /etc/corporate/build-info.txt"
                ]
            }
        ],
        "distribute": [
            {
                "type": "SharedImage",
                "galleryImageId": "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/galleries/${COMPUTE_GALLERY_NAME}/images/ubuntu-server-hardened",
                "runOutputName": "ubuntu-hardened-image",
                "replicationRegions": ["${LOCATION}"],
                "storageAccountType": "Standard_LRS"
            }
        ]
    }
}
EOF
    
    success "VM Image Builder template created"
}

# Deploy and execute image builder template
deploy_image_template() {
    log "Deploying and executing VM Image Builder template..."
    
    # Deploy the image template
    az deployment group create \
        --resource-group ${RESOURCE_GROUP} \
        --template-file image-template.json \
        --parameters imageTemplateName=${IMAGE_TEMPLATE_NAME}
    
    # Start the image build process
    log "Starting image build process..."
    az image builder run \
        --name ${IMAGE_TEMPLATE_NAME} \
        --resource-group ${RESOURCE_GROUP}
    
    # Monitor build progress
    log "Image build started. Monitoring progress..."
    log "Note: This process can take 20-40 minutes to complete."
    
    # Wait for build completion
    local max_attempts=60
    local attempt=0
    
    while [ ${attempt} -lt ${max_attempts} ]; do
        BUILD_STATUS=$(az image builder show \
            --name ${IMAGE_TEMPLATE_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --query properties.lastRunStatus.runState \
            --output tsv 2>/dev/null || echo "Unknown")
        
        log "Build status: ${BUILD_STATUS} (attempt $((attempt + 1))/${max_attempts})"
        
        if [ "${BUILD_STATUS}" == "Succeeded" ]; then
            success "Image build completed successfully"
            break
        elif [ "${BUILD_STATUS}" == "Failed" ]; then
            error "Image build failed"
            return 1
        fi
        
        sleep 60
        attempt=$((attempt + 1))
    done
    
    if [ ${attempt} -eq ${max_attempts} ]; then
        error "Image build monitoring timed out after ${max_attempts} attempts"
        return 1
    fi
}

# Create Azure DevOps pipeline configuration
create_devops_pipeline() {
    log "Creating Azure DevOps pipeline configuration..."
    
    # Create Azure DevOps pipeline YAML configuration
    cat > azure-pipelines.yml << EOF
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
  resourceGroup: '${RESOURCE_GROUP}'
  location: '${LOCATION}'
  imageTemplateName: '${IMAGE_TEMPLATE_NAME}'

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
          az deployment group validate \\
            --resource-group \$(resourceGroup) \\
            --template-file image-template.json \\
            --parameters imageTemplateName=\$(imageTemplateName)

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
          az deployment group create \\
            --resource-group \$(resourceGroup) \\
            --template-file image-template.json \\
            --parameters imageTemplateName=\$(imageTemplateName)

    - task: AzureCLI@2
      displayName: 'Start Image Build'
      inputs:
        azureSubscription: 'Azure Service Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az image builder run \\
            --name \$(imageTemplateName) \\
            --resource-group \$(resourceGroup)

    - task: AzureCLI@2
      displayName: 'Monitor Build Progress'
      inputs:
        azureSubscription: 'Azure Service Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          while true; do
            BUILD_STATUS=\$(az image builder show \\
              --name \$(imageTemplateName) \\
              --resource-group \$(resourceGroup) \\
              --query properties.lastRunStatus.runState \\
              --output tsv)
            
            echo "Build status: \$BUILD_STATUS"
            
            if [ "\$BUILD_STATUS" == "Succeeded" ]; then
              echo "Image build completed successfully"
              break
            elif [ "\$BUILD_STATUS" == "Failed" ]; then
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
          VERSION=\$(date +%Y%m%d.%H%M%S)
          echo "Publishing image version: \$VERSION"
          # Additional tagging or metadata operations can be added here
EOF
    
    success "Azure DevOps pipeline configuration created"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Private DNS Resolver status
    log "Checking Private DNS Resolver status..."
    az dns-resolver show \
        --name ${PRIVATE_DNS_RESOLVER_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query "{Name:name, State:resourceState}" \
        --output table
    
    # Verify DNS endpoints
    log "Verifying DNS endpoints..."
    az dns-resolver inbound-endpoint list \
        --dns-resolver-name ${PRIVATE_DNS_RESOLVER_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query "[].{Name:name, State:provisioningState}" \
        --output table
    
    # Verify image template status
    log "Checking image template status..."
    az image builder show \
        --name ${IMAGE_TEMPLATE_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query "{Name:name, Status:properties.lastRunStatus.runState}" \
        --output table
    
    # Check image version in Compute Gallery
    log "Checking image version in Compute Gallery..."
    az sig image-version list \
        --gallery-name ${COMPUTE_GALLERY_NAME} \
        --gallery-image-definition "ubuntu-server-hardened" \
        --resource-group ${RESOURCE_GROUP} \
        --query "[].{Name:name, State:provisioningState}" \
        --output table
    
    success "Deployment validation completed"
}

# Main execution
main() {
    log "Starting Azure VM Image Builder with Private DNS Resolver deployment..."
    
    # Store deployment info
    export DEPLOYMENT_START_TIME=$(date)
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_hub_network
    configure_dns_endpoints
    create_build_network
    create_compute_gallery
    configure_permissions
    create_image_template
    deploy_image_template
    create_devops_pipeline
    validate_deployment
    
    # Save deployment information
    cat > deployment-info.txt << EOF
Azure VM Image Builder with Private DNS Resolver Deployment
==========================================================

Deployment Time: ${DEPLOYMENT_START_TIME}
Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Subscription ID: ${SUBSCRIPTION_ID}

Resources Created:
- Hub Virtual Network: ${HUB_VNET_NAME}
- Build Virtual Network: ${BUILD_VNET_NAME}
- Private DNS Resolver: ${PRIVATE_DNS_RESOLVER_NAME}
- Compute Gallery: ${COMPUTE_GALLERY_NAME}
- Image Template: ${IMAGE_TEMPLATE_NAME}
- Managed Identity: ${MANAGED_IDENTITY_NAME}

Files Created:
- image-template.json
- azure-pipelines.yml
- image-builder-role.json
- deployment-info.txt

Next Steps:
1. Configure on-premises DNS forwarder rules if needed
2. Test golden image deployment
3. Set up Azure DevOps service connection
4. Import the azure-pipelines.yml into your Azure DevOps project

Cleanup:
To remove all resources, run: ./destroy.sh
EOF
    
    success "Deployment completed successfully!"
    success "Deployment information saved to deployment-info.txt"
    
    log "Summary of created resources:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Hub Virtual Network: ${HUB_VNET_NAME}"
    log "  Build Virtual Network: ${BUILD_VNET_NAME}"
    log "  Private DNS Resolver: ${PRIVATE_DNS_RESOLVER_NAME}"
    log "  Compute Gallery: ${COMPUTE_GALLERY_NAME}"
    log "  Image Template: ${IMAGE_TEMPLATE_NAME}"
    log "  Managed Identity: ${MANAGED_IDENTITY_NAME}"
    
    warning "Note: The image build process may take 20-40 minutes to complete."
    warning "Monitor the build status in the Azure portal or use the validation commands."
}

# Error handling
trap 'error "Script failed on line $LINENO. Check the logs for details."' ERR

# Run main function
main "$@"