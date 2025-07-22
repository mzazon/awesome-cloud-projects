# Infrastructure as Code for Comprehensive Container Monitoring with Azure Container Storage and Managed Prometheus

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Comprehensive Container Monitoring with Azure Container Storage and Managed Prometheus".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with contributor-level permissions
- Basic understanding of container orchestration and monitoring concepts
- For Bicep: Azure CLI with Bicep extension installed
- For Terraform: Terraform v1.5+ installed
- Appropriate permissions for creating:
  - Azure Container Apps and environments
  - Azure Monitor workspaces
  - Azure Managed Grafana instances
  - Azure Storage accounts
  - Log Analytics workspaces

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to Bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-stateful-monitoring \
    --template-file main.bicep \
    --parameters location=eastus \
                 environment=demo

# Monitor deployment progress
az deployment group show \
    --resource-group rg-stateful-monitoring \
    --name main
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az containerapp list --resource-group rg-stateful-monitoring --output table
```

## Architecture Overview

This IaC deployment creates:

- **Azure Container Apps Environment** with monitoring enabled
- **Azure Monitor Workspace** for Prometheus metrics storage
- **Azure Managed Grafana** instance for visualization
- **Azure Storage Account** for persistent container storage
- **Log Analytics Workspace** for centralized logging
- **Stateful PostgreSQL application** with persistent volumes
- **Monitoring sidecar containers** for enhanced observability
- **Prometheus recording rules** for custom metrics
- **Alert rules** for proactive monitoring

## Configuration Options

### Bicep Parameters

```bicep
@description('Azure region for deployment')
param location string = 'eastus'

@description('Environment name (dev, staging, prod)')
param environment string = 'demo'

@description('Resource name prefix')
param resourcePrefix string = 'stateful-monitoring'

@description('Container Apps minimum replicas')
param minReplicas int = 1

@description('Container Apps maximum replicas')
param maxReplicas int = 3

@description('Enable high availability')
param enableHA bool = false
```

### Terraform Variables

```hcl
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-stateful-monitoring"
}

variable "location" {
  description = "Azure region for deployment"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo"
  }
}

variable "container_cpu" {
  description = "CPU allocation for containers"
  type        = number
  default     = 1.0
}

variable "container_memory" {
  description = "Memory allocation for containers"
  type        = string
  default     = "2.0Gi"
}
```

## Monitoring Configuration

### Prometheus Metrics

The deployment automatically configures collection of:
- Container CPU and memory usage
- Storage pool utilization
- Disk I/O performance metrics
- Application-specific metrics
- Custom recording rules for efficiency calculations

### Grafana Dashboards

Pre-configured dashboards include:
- Container resource utilization
- Storage performance metrics
- Application health indicators
- Alert status and history

### Alert Rules

Automated alerts for:
- High CPU usage (>80%)
- Storage pool capacity warnings (>85%)
- Disk read latency issues (>100ms)
- Container restart rate anomalies
- Persistent volume read-only errors

## Validation Steps

After deployment, verify the infrastructure:

```bash
# Check Container Apps environment
az containerapp env show \
    --name cae-stateful-monitoring \
    --resource-group rg-stateful-monitoring

# Verify Prometheus workspace
az monitor account list \
    --resource-group rg-stateful-monitoring \
    --output table

# Test Grafana access
az grafana show \
    --name grafana-stateful-monitoring \
    --resource-group rg-stateful-monitoring \
    --query "properties.endpoint"

# Check storage account
az storage account show \
    --name ststatefulmonitoring \
    --resource-group rg-stateful-monitoring \
    --query "provisioningState"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-stateful-monitoring \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-stateful-monitoring
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name rg-stateful-monitoring
```

## Customization

### Storage Configuration

Modify storage performance and capacity:

```bicep
// In main.bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  properties: {
    accessTier: 'Hot'        // Change to 'Cool' for cost optimization
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
  sku: {
    name: 'Premium_LRS'      // Change to 'Standard_LRS' for cost savings
  }
}
```

### Monitoring Retention

Adjust log retention periods:

```hcl
# In terraform/main.tf
resource "azurerm_log_analytics_workspace" "main" {
  retention_in_days = 30     # Change to 90 or 365 for longer retention
  daily_quota_gb    = 10     # Adjust based on log volume
}
```

### Application Scaling

Configure auto-scaling parameters:

```bash
# In scripts/deploy.sh
az containerapp create \
    --min-replicas 2 \        # Increase for higher availability
    --max-replicas 10 \       # Increase for higher scale
    --cpu 2.0 \               # Adjust based on workload
    --memory 4.0Gi            # Adjust based on requirements
```

## Cost Optimization

### Development Environment

For cost-effective development deployments:

```bicep
param environment string = 'dev'
param enableHA bool = false
param minReplicas int = 0        // Allow scaling to zero
param storageAccountType string = 'Standard_LRS'
```

### Production Environment

For production deployments with high availability:

```bicep
param environment string = 'prod'
param enableHA bool = true
param minReplicas int = 2        // Ensure availability
param storageAccountType string = 'Premium_LRS'
```

## Troubleshooting

### Common Issues

1. **Resource naming conflicts**: Ensure unique resource names by modifying the `resourcePrefix` parameter
2. **Insufficient permissions**: Verify Azure CLI is logged in with appropriate permissions
3. **Region availability**: Some Azure services may not be available in all regions
4. **Quota limits**: Check Azure subscription limits for Container Apps and storage

### Diagnostic Commands

```bash
# Check deployment status
az deployment group list \
    --resource-group rg-stateful-monitoring \
    --output table

# View Container Apps logs
az containerapp logs show \
    --name ca-stateful-app \
    --resource-group rg-stateful-monitoring \
    --follow

# Check Prometheus metrics
az monitor prometheus query \
    --workspace-id /subscriptions/{subscription}/resourceGroups/rg-stateful-monitoring/providers/Microsoft.Monitor/accounts/amw-prometheus \
    --query "up"
```

## Security Considerations

### Network Security

- Container Apps environment uses internal networking by default
- Storage account requires HTTPS-only access
- Grafana instance configured with Azure AD authentication

### Access Control

- Managed identities used for service-to-service authentication
- Least privilege principles applied to all resource permissions
- Storage account access keys managed through Azure Key Vault integration

### Monitoring Security

- All metrics and logs encrypted at rest
- Network traffic encrypted in transit
- Alert rules configured for security-related events

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for context
2. Review Azure Container Apps documentation: https://docs.microsoft.com/en-us/azure/container-apps/
3. Consult Azure Monitor documentation: https://docs.microsoft.com/en-us/azure/azure-monitor/
4. Reference Azure Managed Prometheus guide: https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-overview

## Additional Resources

- [Azure Container Apps monitoring](https://docs.microsoft.com/en-us/azure/container-apps/monitor)
- [Azure Managed Prometheus overview](https://docs.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-overview)
- [Azure Container Storage documentation](https://docs.microsoft.com/en-us/azure/container-storage/)
- [Azure Managed Grafana guide](https://docs.microsoft.com/en-us/azure/managed-grafana/)