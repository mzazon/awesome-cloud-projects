# Infrastructure as Code for Environmental Impact Dashboards with Azure Sustainability Manager and Power BI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Environmental Impact Dashboards with Azure Sustainability Manager and Power BI".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (JSON/ARM template transpiled)
- **Terraform**: Multi-cloud infrastructure as code using Azure Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login`)
- Appropriate Azure subscription with permissions to create resources:
  - Resource Groups
  - Storage Accounts
  - Function Apps
  - Data Factory
  - Logic Apps
  - Application Insights
  - Key Vault
  - Log Analytics Workspace
- Power BI Pro license or Premium Per User (PPU) license
- Microsoft Cloud for Sustainability license (required for Sustainability Manager)
- Basic understanding of sustainability metrics and carbon accounting

## Quick Start

### Using Bicep
```bash
cd bicep/

# Deploy with default parameters
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters @parameters.json

# Deploy with custom parameters
az deployment group create \
    --resource-group myResourceGroup \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentName=production \
    --parameters uniqueSuffix=abc123
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh

# View deployment status
az group show --name rg-sustainability-* --query "properties.provisioningState"
```

## Architecture Overview

This solution deploys:

1. **Data Collection Infrastructure**:
   - Azure Storage Account for sustainability data
   - Azure Data Factory for data ingestion
   - Storage containers for organized data lake

2. **Processing Layer**:
   - Azure Functions for emissions calculations
   - Logic Apps for automated workflows
   - Custom emissions calculation engine

3. **Monitoring & Analytics**:
   - Log Analytics Workspace for centralized logging
   - Application Insights for telemetry
   - Key Vault for secure credential management

4. **Integration Points**:
   - Power BI workspace configuration
   - Microsoft Cloud for Sustainability integration
   - Automated data refresh capabilities

## Configuration

### Bicep Parameters

Key parameters in `parameters.json`:
- `location`: Azure region for resource deployment
- `environmentName`: Environment tag (dev, test, prod)
- `uniqueSuffix`: Suffix for globally unique resource names
- `powerBiWorkspaceName`: Name for Power BI workspace
- `enableMonitoring`: Toggle for monitoring resources

### Terraform Variables

Key variables in `variables.tf`:
- `location`: Azure region
- `resource_group_name`: Resource group name
- `environment`: Environment designation
- `unique_suffix`: Random suffix for resource names
- `power_bi_workspace`: Power BI workspace name

### Environment Variables

The deployment scripts use these environment variables:
```bash
export RESOURCE_GROUP="rg-sustainability-${RANDOM_SUFFIX}"
export LOCATION="eastus"
export POWERBI_WORKSPACE="sustainability-workspace"
export STORAGE_ACCOUNT="stsustain${RANDOM_SUFFIX}"
```

## Deployment Process

### Pre-deployment Steps

1. **Azure Login**: Ensure you're logged into Azure CLI
2. **Subscription Selection**: Set the correct Azure subscription
3. **Resource Group**: Create or select target resource group
4. **Power BI Setup**: Prepare Power BI workspace and licensing

### Post-deployment Configuration

1. **Microsoft Cloud for Sustainability**: Manual configuration required through M365 admin center
2. **Power BI Data Sources**: Configure data source connections
3. **Sustainability Manager**: Set up data collection sources
4. **Dashboard Creation**: Build Power BI dashboards using sustainability data

## Monitoring and Maintenance

### Health Checks

Monitor these key metrics:
- Function App execution success rates
- Data Factory pipeline success
- Storage account data ingestion
- Logic App workflow execution
- Application Insights telemetry

### Automated Monitoring

The solution includes:
- Application Insights for performance monitoring
- Log Analytics for centralized logging
- Azure Monitor alerts for processing failures
- Custom metrics for sustainability data quality

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete --name myResourceGroup --yes --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
cd scripts/
./destroy.sh
```

### Manual Cleanup Required

Some resources require manual cleanup:
- **Power BI Workspace**: Delete from Power BI Service portal
- **Microsoft Cloud for Sustainability**: Remove configuration from M365 admin center
- **Azure Active Directory**: Clean up any service principals created

## Cost Considerations

### Estimated Monthly Costs

- **Storage Account**: $10-50 (depends on data volume)
- **Function App**: $5-20 (consumption plan)
- **Data Factory**: $20-100 (depends on pipeline runs)
- **Logic Apps**: $10-30 (depends on workflow executions)
- **Application Insights**: $5-25 (depends on telemetry volume)
- **Key Vault**: $1-5 (basic operations)
- **Log Analytics**: $10-50 (depends on log volume)

**Total Estimated Range**: $61-280/month

### Cost Optimization

- Use consumption-based pricing for serverless components
- Implement data retention policies
- Monitor usage patterns and adjust accordingly
- Consider Azure Reserved Instances for predictable workloads

## Security Considerations

### Implemented Security Measures

- **Key Vault**: Secure credential management
- **Managed Identity**: Service-to-service authentication
- **Network Security**: Private endpoints where applicable
- **Data Encryption**: At rest and in transit
- **Access Control**: Role-based access controls (RBAC)

### Security Best Practices

1. **Principle of Least Privilege**: Grant minimal required permissions
2. **Network Isolation**: Use private endpoints for sensitive data
3. **Data Classification**: Classify sustainability data appropriately
4. **Regular Security Reviews**: Monitor access patterns and permissions
5. **Compliance**: Ensure adherence to relevant regulations (GDPR, etc.)

## Troubleshooting

### Common Issues

1. **Power BI Connection Failures**:
   - Verify Power BI license assignment
   - Check service principal permissions
   - Validate Key Vault access policies

2. **Data Factory Pipeline Failures**:
   - Review pipeline run history
   - Check source data availability
   - Verify linked service connections

3. **Function App Errors**:
   - Monitor Application Insights for exceptions
   - Check function app configuration
   - Verify storage account connectivity

### Debugging Resources

- **Application Insights**: Performance and exception monitoring
- **Log Analytics**: Centralized logging and querying
- **Azure Monitor**: Infrastructure and application metrics
- **Function App Logs**: Real-time function execution logs

## Support and Documentation

### Microsoft Documentation

- [Microsoft Cloud for Sustainability](https://docs.microsoft.com/en-us/industry/sustainability/)
- [Power BI Sustainability Templates](https://docs.microsoft.com/en-us/power-bi/connect-data/service-connect-to-sustainability)
- [Azure Sustainability Best Practices](https://docs.microsoft.com/en-us/azure/architecture/framework/sustainability/)

### Additional Resources

- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure Cost Management](https://docs.microsoft.com/en-us/azure/cost-management-billing/)
- [Azure Monitor Best Practices](https://docs.microsoft.com/en-us/azure/azure-monitor/best-practices)

## Contributing

For issues with this infrastructure code, refer to the original recipe documentation or submit feedback through the appropriate channels.

## License

This infrastructure code is provided as-is for educational and implementation purposes. Ensure compliance with your organization's policies and Microsoft's licensing terms.