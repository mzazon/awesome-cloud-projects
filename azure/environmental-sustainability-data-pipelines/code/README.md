# Infrastructure as Code for Environmental Sustainability Data Pipelines with Data Factory and Sustainability Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Environmental Sustainability Data Pipelines with Data Factory and Sustainability Manager".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Data Factory
  - Azure Sustainability Manager
  - Azure Monitor
  - Azure Functions
  - Azure Storage
  - Log Analytics Workspace
- Terraform CLI v1.0.0 or later (for Terraform deployment)
- Bash shell environment (Linux, macOS, or Windows Subsystem for Linux)

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-env-data-pipeline \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json

# Monitor deployment status
az deployment group show \
    --resource-group rg-env-data-pipeline \
    --name main
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az datafactory show \
    --resource-group rg-env-data-pipeline \
    --name adf-env-pipeline-* \
    --query "{name:name, state:state}"
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export RESOURCE_GROUP="rg-env-data-pipeline"
export LOCATION="eastus"
export ADMIN_EMAIL="admin@yourcompany.com"
```

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "adminEmail": {
      "value": "admin@yourcompany.com"
    },
    "environmentName": {
      "value": "dev"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location = "eastus"
admin_email = "admin@yourcompany.com"
environment_name = "dev"
```

## Architecture Overview

The IaC deploys the following Azure resources:

- **Azure Data Factory**: Orchestrates environmental data pipelines
- **Azure Storage Account**: Data Lake Gen2 for environmental data storage
- **Azure Functions**: Serverless data transformation and processing
- **Log Analytics Workspace**: Centralized logging and monitoring
- **Azure Monitor**: Alerts and compliance threshold monitoring
- **Action Groups**: Notification system for environmental alerts

## Deployment Details

### Resource Groups

- Primary resource group for all environmental data pipeline resources
- Configured with appropriate tags for cost tracking and governance

### Data Factory Configuration

- Linked services for storage account connectivity
- Datasets for environmental data processing
- Pipelines for automated data ingestion and transformation
- Scheduled triggers for continuous data processing

### Monitoring and Alerting

- Log Analytics workspace for centralized logging
- Azure Monitor alerts for pipeline failures and processing delays
- Action groups for email and SMS notifications
- Diagnostic settings for comprehensive monitoring

### Security Features

- Azure Key Vault integration for secrets management
- Managed identities for secure service-to-service authentication
- Role-based access control (RBAC) for least privilege access
- Network security groups for traffic filtering

## Validation

### Post-Deployment Verification

1. **Verify Data Factory Status**:
   ```bash
   az datafactory show \
       --resource-group rg-env-data-pipeline \
       --name adf-env-pipeline-* \
       --query "{name:name, state:state}"
   ```

2. **Test Pipeline Execution**:
   ```bash
   az datafactory pipeline create-run \
       --resource-group rg-env-data-pipeline \
       --factory-name adf-env-pipeline-* \
       --pipeline-name "EnvironmentalDataPipeline"
   ```

3. **Check Monitoring Configuration**:
   ```bash
   az monitor metrics alert list \
       --resource-group rg-env-data-pipeline \
       --output table
   ```

4. **Verify Function App Deployment**:
   ```bash
   az functionapp show \
       --resource-group rg-env-data-pipeline \
       --name func-env-transform-* \
       --query "{name:name, state:state}"
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-env-data-pipeline \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Customization

### Adding Data Sources

To add new environmental data sources:

1. **Bicep**: Edit `bicep/main.bicep` to add new linked services
2. **Terraform**: Modify `terraform/main.tf` to include additional data connectors
3. **Scripts**: Update `scripts/deploy.sh` with new data source configurations

### Modifying Alert Thresholds

Adjust environmental compliance thresholds in:

- **Bicep**: `bicep/main.bicep` alert rule definitions
- **Terraform**: `terraform/main.tf` monitor alert resources
- **Scripts**: `scripts/deploy.sh` alert configuration commands

### Scaling Configuration

For production environments:

- Increase Data Factory integration runtime capacity
- Configure auto-scaling for Function Apps
- Implement data partitioning strategies
- Enable geo-redundant storage for disaster recovery

## Cost Optimization

### Resource Sizing

- **Data Factory**: Uses consumption-based pricing
- **Functions**: Consumption plan for cost efficiency
- **Storage**: Standard LRS for development, consider ZRS for production
- **Log Analytics**: Pay-as-you-go pricing model

### Monitoring Costs

```bash
# Check current month costs
az consumption usage list \
    --start-date $(date -d "1 month ago" +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d) \
    --resource-group rg-env-data-pipeline
```

## Troubleshooting

### Common Issues

1. **Data Factory Pipeline Failures**:
   - Check linked service connectivity
   - Verify storage account permissions
   - Review activity run logs in Azure Monitor

2. **Function App Deployment Issues**:
   - Ensure proper runtime configuration
   - Check application settings
   - Verify storage account connection string

3. **Monitoring Alerts Not Firing**:
   - Verify alert rule conditions
   - Check action group configuration
   - Confirm metric availability

### Debugging Commands

```bash
# Check Data Factory logs
az monitor activity-log list \
    --resource-group rg-env-data-pipeline \
    --start-time $(date -d "1 hour ago" -u +%Y-%m-%dT%H:%M:%SZ)

# Function App logs
az functionapp log tail \
    --resource-group rg-env-data-pipeline \
    --name func-env-transform-*

# Storage account diagnostics
az storage account show \
    --resource-group rg-env-data-pipeline \
    --name stenvdata* \
    --query "{name:name, provisioningState:provisioningState}"
```

## Security Considerations

### Best Practices Implemented

- **Encryption**: All data encrypted at rest and in transit
- **Access Control**: Role-based access control (RBAC) for all resources
- **Secrets Management**: Azure Key Vault for sensitive configuration
- **Network Security**: Private endpoints for storage access
- **Monitoring**: Comprehensive audit logging enabled

### Security Validation

```bash
# Check RBAC assignments
az role assignment list \
    --resource-group rg-env-data-pipeline \
    --output table

# Verify encryption settings
az storage account encryption show \
    --resource-group rg-env-data-pipeline \
    --name stenvdata*
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for solution context
2. **Azure Documentation**: Check [Azure Data Factory documentation](https://docs.microsoft.com/en-us/azure/data-factory/)
3. **Community Support**: Use Azure community forums for specific issues
4. **Microsoft Support**: Contact Microsoft Support for production issues

## Related Resources

- [Azure Data Factory Best Practices](https://docs.microsoft.com/en-us/azure/data-factory/concepts-best-practices)
- [Azure Sustainability Manager Documentation](https://docs.microsoft.com/en-us/industry/sustainability/overview)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)
- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)

## License

This infrastructure code is provided under the MIT License. See the recipe repository for full license details.