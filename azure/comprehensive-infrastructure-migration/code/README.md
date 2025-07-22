# Infrastructure as Code for Comprehensive Infrastructure Migration with Resource Mover and Update Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Comprehensive Infrastructure Migration with Resource Mover and Update Manager".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates an integrated migration workflow that includes:

- Azure Resource Mover collections for orchestrated cross-region migration
- Azure Update Manager configurations for automated patch management
- Azure Workbooks for comprehensive migration monitoring
- Log Analytics workspace for centralized logging and analytics
- Source region infrastructure (VMs, networks, storage) for migration testing
- Target region resource groups and configurations

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions:
  - Resource Mover Contributor
  - Update Manager Contributor
  - Virtual Machine Contributor
  - Network Contributor
  - Log Analytics Contributor
- Two Azure regions configured for migration (source and target)
- PowerShell 7.0+ (for Bicep deployment scripts)
- Terraform v1.5+ (for Terraform implementation)

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to Bicep directory
cd bicep/

# Review and customize parameters
cp parameters.example.json parameters.json
# Edit parameters.json with your specific values

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-migration-demo \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group rg-migration-demo \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="source_region=eastus" \
    -var="target_region=westus2" \
    -var="resource_group_name=rg-migration-demo"

# Apply the configuration
terraform apply \
    -var="source_region=eastus" \
    -var="target_region=westus2" \
    -var="resource_group_name=rg-migration-demo"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export SOURCE_REGION="eastus"
export TARGET_REGION="westus2"
export RESOURCE_GROUP_PREFIX="rg-migration"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment status
az resource list --resource-group ${RESOURCE_GROUP_PREFIX}-demo --output table
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| sourceRegion | Azure region for source infrastructure | eastus | Yes |
| targetRegion | Azure region for migration target | westus2 | Yes |
| resourceGroupName | Name for source resource group | rg-migration-demo | Yes |
| vmSize | Size for test virtual machines | Standard_B2s | No |
| adminUsername | VM administrator username | azureuser | No |
| enableMonitoring | Enable Azure Monitor integration | true | No |
| maintenanceWindowStartTime | Update maintenance window start | 03:00:00 | No |

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| source_region | Source Azure region | string | "eastus" |
| target_region | Target Azure region | string | "westus2" |
| resource_group_name | Resource group name prefix | string | "rg-migration" |
| vm_size | Virtual machine size | string | "Standard_B2s" |
| admin_username | VM administrator username | string | "azureuser" |
| enable_monitoring | Enable monitoring features | bool | true |
| tags | Resource tags | map(string) | {} |

## Post-Deployment Steps

After successful deployment, complete these additional configuration steps:

### 1. Configure Migration Dependencies

```bash
# Add resources to move collection
az resource-mover move-resource create \
    --resource-group $SOURCE_RG \
    --move-collection-name $MOVE_COLLECTION_NAME \
    --name vm-source-test \
    --source-id $VM_RESOURCE_ID \
    --target-resource-group $TARGET_RG
```

### 2. Validate Migration Readiness

```bash
# Validate move collection
az resource-mover move-collection validate \
    --resource-group $SOURCE_RG \
    --move-collection-name $MOVE_COLLECTION_NAME

# Check validation status
az resource-mover move-collection show \
    --resource-group $SOURCE_RG \
    --move-collection-name $MOVE_COLLECTION_NAME \
    --query provisioningState
```

### 3. Execute Migration Workflow

```bash
# Prepare resources for migration
az resource-mover move-resource prepare \
    --resource-group $SOURCE_RG \
    --move-collection-name $MOVE_COLLECTION_NAME \
    --move-resource-name vm-source-test

# Initiate migration
az resource-mover move-resource initiate-move \
    --resource-group $SOURCE_RG \
    --move-collection-name $MOVE_COLLECTION_NAME \
    --move-resource-name vm-source-test

# Commit migration (makes it permanent)
az resource-mover move-resource commit \
    --resource-group $SOURCE_RG \
    --move-collection-name $MOVE_COLLECTION_NAME \
    --move-resource-name vm-source-test
```

### 4. Apply Update Management

```bash
# Assign maintenance configuration to migrated VM
az maintenance assignment create \
    --resource-group $TARGET_RG \
    --assignment-name migration-maintenance \
    --maintenance-configuration-id $MAINTENANCE_CONFIG_ID \
    --resource-id $MIGRATED_VM_ID
```

## Monitoring and Validation

### Access Migration Dashboard

1. Navigate to Azure portal
2. Go to Azure Monitor > Workbooks
3. Open "Infrastructure Migration Monitoring" workbook
4. Review migration metrics and compliance status

### Verify Resource Migration

```bash
# Check source region resources
az resource list \
    --resource-group $SOURCE_RG \
    --query "[].{Name:name, Type:type, Location:location}" \
    --output table

# Check target region resources
az resource list \
    --resource-group $TARGET_RG \
    --query "[].{Name:name, Type:type, Location:location}" \
    --output table
```

### Validate Update Management

```bash
# Check maintenance configuration
az maintenance configuration show \
    --resource-group $TARGET_RG \
    --name $MAINTENANCE_CONFIG_NAME \
    --query "{Name:name, State:provisioningState, Scope:maintenanceScope}"

# Verify VM patch compliance
az vm run-command invoke \
    --resource-group $TARGET_RG \
    --name vm-source-test \
    --command-id RunShellScript \
    --scripts "sudo apt list --upgradable"
```

## Troubleshooting

### Common Issues

**Migration Validation Failures**
- Verify target region has sufficient quota
- Check for naming conflicts in target region
- Ensure all dependencies are included in move collection

**Update Manager Configuration Issues**
- Verify VM has Azure Monitor agent installed
- Check maintenance configuration schedule format
- Ensure proper IAM permissions for Update Manager

**Monitoring Dashboard Problems**
- Verify Log Analytics workspace is properly configured
- Check workbook template deployment status
- Ensure data is flowing to Log Analytics

### Debug Commands

```bash
# Check Resource Mover operation logs
az monitor activity-log list \
    --resource-group $SOURCE_RG \
    --start-time 2024-01-01T00:00:00Z \
    --query "[?contains(operationName.value, 'Microsoft.Migrate')]"

# Verify Update Manager agent status
az vm extension show \
    --resource-group $TARGET_RG \
    --vm-name vm-source-test \
    --name AzureMonitorLinuxAgent \
    --query "{Name:name, State:provisioningState, Version:typeHandlerVersion}"

# Check Log Analytics workspace health
az monitor log-analytics workspace show \
    --resource-group $SOURCE_RG \
    --workspace-name $LOG_WORKSPACE_NAME \
    --query "{Name:name, State:provisioningState, RetentionDays:retentionInDays}"
```

## Cleanup

### Using Bicep

```bash
# Delete the deployment
az deployment group delete \
    --resource-group rg-migration-demo \
    --name main

# Delete resource groups
az group delete --name rg-migration-demo --yes --no-wait
az group delete --name rg-migration-demo-target --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="source_region=eastus" \
    -var="target_region=westus2" \
    -var="resource_group_name=rg-migration-demo"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
az group list --query "[?starts_with(name, 'rg-migration')]" --output table
```

## Security Considerations

### Identity and Access Management

- Use managed identities for resource authentication
- Apply principle of least privilege for service principals
- Enable Azure RBAC for fine-grained access control

### Network Security

- Configure network security groups with minimal required access
- Use private endpoints for secure service communication
- Enable Azure DDoS Protection for public-facing resources

### Data Protection

- Enable encryption at rest for all storage resources
- Use Azure Key Vault for certificate and secret management
- Configure audit logging for compliance requirements

## Cost Optimization

### Resource Sizing

- Use appropriate VM sizes for workload requirements
- Configure auto-shutdown for development environments
- Implement Azure Cost Management budgets and alerts

### Monitoring Costs

```bash
# Check current month costs
az consumption usage list \
    --start-date 2024-01-01 \
    --end-date 2024-01-31 \
    --query "[?contains(instanceName, 'migration')]"

# Set up cost alerts
az consumption budget create \
    --resource-group rg-migration-demo \
    --budget-name migration-budget \
    --amount 100 \
    --time-grain Monthly \
    --start-date 2024-01-01 \
    --end-date 2024-12-31
```

## Customization

### Extending the Solution

1. **Multi-region Migration**: Modify templates to support multiple target regions
2. **Application-aware Migration**: Add Application Insights integration
3. **Compliance Integration**: Include Azure Policy assignments
4. **Disaster Recovery**: Add Azure Site Recovery configuration

### Template Modifications

- Update `bicep/main.bicep` for Bicep customizations
- Modify `terraform/main.tf` for Terraform changes
- Edit `scripts/deploy.sh` for bash script enhancements

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Resource Mover [documentation](https://docs.microsoft.com/en-us/azure/resource-mover/)
3. Consult Azure Update Manager [best practices](https://docs.microsoft.com/en-us/azure/update-manager/)
4. Reference Azure Workbooks [troubleshooting guide](https://docs.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-troubleshoot)

## Additional Resources

- [Azure Resource Mover Overview](https://docs.microsoft.com/en-us/azure/resource-mover/overview)
- [Azure Update Manager Documentation](https://docs.microsoft.com/en-us/azure/update-manager/)
- [Azure Workbooks Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)