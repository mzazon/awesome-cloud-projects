# Infrastructure as Code for Container Security Scanning with Registry and Defender for Cloud

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Container Security Scanning with Registry and Defender for Cloud".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with Owner or Contributor role
- Microsoft Defender for Cloud subscription (enabled during deployment)
- Basic understanding of container security and Docker concepts
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed

## Cost Estimation

Estimated monthly cost for small workloads:
- Azure Container Registry (Standard tier): ~$5/month
- Microsoft Defender for Containers: ~$7 per vCore/month for AKS clusters
- Log Analytics Workspace: ~$3/month for basic monitoring
- **Total**: ~$15-30/month depending on usage

> **Note**: Microsoft Defender for Containers charges are based on the number of vCores in your AKS clusters and includes free vulnerability scanning for ACR images.

## Quick Start

### Using Bicep (Recommended)

```bash
cd bicep/

# Login to Azure
az login

# Set subscription (if needed)
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-container-security \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters resourcePrefix=contososec

# Verify deployment
az deployment group show \
    --resource-group rg-container-security \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="location=eastus" \
    -var="resource_prefix=contososec"

# Apply the infrastructure
terraform apply \
    -var="location=eastus" \
    -var="resource_prefix=contososec"

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Configure environment variables
export RESOURCE_PREFIX="contososec"
export LOCATION="eastus"

# Deploy infrastructure
./deploy.sh

# Verify deployment
az resource list --resource-group "rg-container-security-${RESOURCE_PREFIX}" --output table
```

## Deployment Components

This IaC deployment creates the following Azure resources:

### Core Infrastructure
- **Resource Group**: Container for all security scanning resources
- **Azure Container Registry**: Standard tier registry with security features
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Azure Kubernetes Service**: Target deployment environment (optional)

### Security Components
- **Microsoft Defender for Containers**: Vulnerability scanning and threat protection
- **Azure Policy Assignments**: Compliance enforcement policies
- **Diagnostic Settings**: Security event logging and monitoring
- **Security Alerts**: Automated notifications for critical vulnerabilities

### Access Control
- **Managed Identity**: Secure authentication for services
- **Role Assignments**: Least privilege access control
- **Service Principal**: CI/CD pipeline integration (optional)

## Configuration Options

### Bicep Parameters

```bicep
param location string = 'eastus'
param resourcePrefix string = 'contosec'
param acrSku string = 'Standard'
param enableDefender bool = true
param enableContentTrust bool = true
param logRetentionDays int = 30
```

### Terraform Variables

```hcl
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "contosec"
}

variable "acr_sku" {
  description = "ACR SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"
}

variable "enable_defender" {
  description = "Enable Microsoft Defender for Containers"
  type        = bool
  default     = true
}
```

### Environment Variables (Bash)

```bash
# Required variables
export RESOURCE_PREFIX="contososec"
export LOCATION="eastus"

# Optional variables
export ACR_SKU="Standard"
export ENABLE_DEFENDER="true"
export LOG_RETENTION_DAYS="30"
```

## Post-Deployment Steps

### 1. Enable Container Scanning

```bash
# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show \
    --name "${RESOURCE_PREFIX}acr" \
    --resource-group "rg-container-security-${RESOURCE_PREFIX}" \
    --query loginServer --output tsv)

# Login to ACR
az acr login --name "${RESOURCE_PREFIX}acr"

# Build and push sample image
az acr build \
    --registry "${RESOURCE_PREFIX}acr" \
    --image sample-app:v1 \
    --file Dockerfile .
```

### 2. Verify Security Scanning

```bash
# Check vulnerability scan results
az security assessment list \
    --query "[?contains(displayName, 'container')].{Name:displayName, Status:status.code}" \
    --output table

# View ACR repository vulnerabilities
az security sub-assessment list \
    --assessed-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-container-security-${RESOURCE_PREFIX}/providers/Microsoft.ContainerRegistry/registries/${RESOURCE_PREFIX}acr"
```

### 3. Configure CI/CD Integration

```bash
# Create service principal for DevOps
az ad sp create-for-rbac \
    --name "sp-${RESOURCE_PREFIX}-devops" \
    --role contributor \
    --scopes "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-container-security-${RESOURCE_PREFIX}"
```

## Validation & Testing

### 1. Verify Resource Deployment

```bash
# Check resource group
az group show \
    --name "rg-container-security-${RESOURCE_PREFIX}" \
    --query properties.provisioningState

# Verify ACR creation
az acr show \
    --name "${RESOURCE_PREFIX}acr" \
    --query "{Name:name, SKU:sku.name, Status:provisioningState}"

# Check Defender for Containers
az security pricing show \
    --name Containers \
    --query pricingTier
```

### 2. Test Security Policies

```bash
# Verify policy assignments
az policy assignment list \
    --resource-group "rg-container-security-${RESOURCE_PREFIX}" \
    --query "[].{Name:displayName, Status:enforcementMode}" \
    --output table

# Test policy compliance
az policy state list \
    --resource-group "rg-container-security-${RESOURCE_PREFIX}" \
    --query "[].{Policy:policyDefinitionName, Compliance:complianceState}" \
    --output table
```

### 3. Monitor Security Events

```bash
# Query security logs
az monitor log-analytics query \
    --workspace "law-security-${RESOURCE_PREFIX}" \
    --analytics-query "SecurityEvent | take 10" \
    --output table

# Check container registry events
az monitor log-analytics query \
    --workspace "law-security-${RESOURCE_PREFIX}" \
    --analytics-query "ContainerRegistryRepositoryEvents | take 10" \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete resource group (removes all resources)
az group delete \
    --name "rg-container-security-${RESOURCE_PREFIX}" \
    --yes \
    --no-wait

# Optionally disable Defender for Containers subscription-wide
az security pricing create \
    --name Containers \
    --tier Free
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="location=eastus" \
    -var="resource_prefix=contososec"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
cd scripts/

# Run cleanup script
./destroy.sh

# Verify resource deletion
az resource list \
    --resource-group "rg-container-security-${RESOURCE_PREFIX}" \
    --output table
```

## Customization

### Adding Custom Policies

To add custom Azure Policy definitions:

1. **Bicep**: Add policy definitions in `main.bicep`
2. **Terraform**: Create policy resources in `main.tf`
3. **Bash**: Add policy creation commands in `deploy.sh`

### Integrating with Existing Infrastructure

Modify the IaC to reference existing resources:

```bicep
// Reference existing Log Analytics workspace
resource existingWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' existing = {
  name: 'existing-workspace-name'
  scope: resourceGroup('existing-resource-group')
}
```

### Advanced Security Configuration

Enable additional security features:

```hcl
# Enable ACR Premium features
resource "azurerm_container_registry" "acr" {
  name                = "${var.resource_prefix}acr"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Premium"
  
  # Enable private endpoints
  public_network_access_enabled = false
  
  # Enable content trust
  trust_policy {
    enabled = true
  }
  
  # Enable quarantine policy
  quarantine_policy {
    enabled = true
  }
}
```

## Monitoring and Alerting

### Built-in Monitoring

The deployment includes:
- Container registry diagnostic settings
- Security event logging
- Vulnerability assessment monitoring
- Policy compliance tracking

### Custom Alerts

Create additional alerts for:
- High-severity vulnerabilities
- Policy violations
- Unusual registry access patterns
- Failed authentication attempts

### Dashboard Integration

Query examples for Azure Monitor dashboards:

```kusto
// Container vulnerability trends
ContainerRegistryRepositoryEvents
| where OperationName == "Push"
| join kind=leftouter (
    SecurityRecommendation
    | where RecommendationDisplayName contains "vulnerabilities"
) on $left.Repository == $right.ResourceId
| summarize VulnerabilityCount = count() by bin(TimeGenerated, 1h)
| render timechart
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your account has Owner or Contributor role
2. **Policy Conflicts**: Check for existing policies that might conflict
3. **Resource Name Conflicts**: Use unique resource prefixes
4. **Region Limitations**: Some features may not be available in all regions

### Debug Commands

```bash
# Check deployment logs
az deployment group show \
    --resource-group "rg-container-security-${RESOURCE_PREFIX}" \
    --name main \
    --query properties.error

# Verify policy assignments
az policy assignment list \
    --disable-scope-strict-match \
    --query "[?resourceGroup=='rg-container-security-${RESOURCE_PREFIX}']"

# Check Defender status
az security pricing list \
    --query "[?name=='Containers']"
```

## Security Best Practices

This deployment follows Azure security best practices:

- **Least Privilege Access**: Minimal required permissions
- **Network Security**: Private endpoints when possible
- **Audit Logging**: Comprehensive security event logging
- **Compliance**: Automated policy enforcement
- **Monitoring**: Continuous security monitoring

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Azure Container Registry documentation
3. Consult Microsoft Defender for Cloud documentation
4. Review Azure Policy documentation
5. Check Azure CLI reference documentation

## Contributing

To contribute improvements to this IaC:

1. Test changes thoroughly in a development environment
2. Follow Azure naming conventions
3. Update documentation for any new parameters
4. Ensure cleanup scripts handle new resources
5. Validate security configurations

## License

This infrastructure code is provided under the same license as the parent recipe repository.