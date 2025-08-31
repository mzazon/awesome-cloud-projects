# Infrastructure as Code for SMS Compliance Automation with Communication Services

This directory contains Infrastructure as Code (IaC) implementations for the recipe "SMS Compliance Automation with Communication Services".

This solution implements automated SMS compliance management using Azure Communication Services' Opt-Out Management API with serverless Azure Functions to create real-time, multi-channel opt-out workflows that ensure regulatory adherence through intelligent automation.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.37.0 or later)
- Azure subscription with appropriate permissions:
  - Contributor role on target resource group
  - Communication Services resource management permissions
  - Azure Functions and Storage Account creation permissions
- Node.js 20.x for Azure Functions runtime
- Basic understanding of SMS compliance regulations (TCPA/CAN-SPAM)
- Estimated cost: $5-10 per month for development/testing workloads

> **Note**: This solution uses Azure Communication Services SMS Opt-Out Management API currently in Public Preview (introduced January 2025).

## Architecture Overview

The solution deploys:
- Azure Communication Services resource with Opt-Out Management API access
- Azure Function App with consumption plan for serverless execution
- Storage Account for Function App hosting and audit table storage
- HTTP-triggered function for processing opt-out requests
- Timer-triggered function for compliance monitoring
- Application Insights for monitoring and logging

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Set deployment parameters
export RESOURCE_GROUP="rg-sms-compliance-$(openssl rand -hex 3)"
export LOCATION="eastus"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure using Bicep
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters location=${LOCATION}

# Get deployment outputs
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="location=eastus" \
    -var="resource_group_name=rg-sms-compliance-$(openssl rand -hex 3)"

# Apply infrastructure changes
terraform apply \
    -var="location=eastus" \
    -var="resource_group_name=rg-sms-compliance-$(openssl rand -hex 3)"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-sms-compliance-$(openssl rand -hex 3)"
export LOCATION="eastus"

# Deploy complete solution
./scripts/deploy.sh

# View deployment information
echo "Check Azure portal for deployed resources in: ${RESOURCE_GROUP}"
```

## Post-Deployment Configuration

### Function Code Deployment

After infrastructure deployment, deploy the function code:

```bash
# Navigate to function source directory (created during deployment)
cd ../functions/

# Deploy functions to Azure
func azure functionapp publish <function-app-name>

# Verify deployment
az functionapp function list \
    --name <function-app-name> \
    --resource-group ${RESOURCE_GROUP}
```

### Testing the Solution

```bash
# Get the HTTP trigger function URL
FUNCTION_URL=$(az functionapp function show \
    --name <function-app-name> \
    --resource-group ${RESOURCE_GROUP} \
    --function-name OptOutProcessor \
    --query "invokeUrlTemplate" \
    --output tsv)

# Test opt-out processing
curl -X POST "${FUNCTION_URL}" \
     -H "Content-Type: application/json" \
     -d '{
       "phoneNumber": "+15551234567",
       "fromNumber": "+18005551234",
       "channel": "web"
     }'
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `resourcePrefix` | Prefix for resource names | `sms-comp` | No |
| `functionAppSku` | Function App pricing tier | `Y1` (Consumption) | No |
| `storageAccountType` | Storage redundancy type | `Standard_LRS` | No |
| `communicationDataLocation` | Data residency location | `United States` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `resource_group_name` | Resource group name | - | Yes |
| `location` | Azure region | `East US` | Yes |
| `resource_prefix` | Resource naming prefix | `smscomp` | No |
| `function_runtime_version` | Functions runtime version | `~4` | No |
| `node_version` | Node.js version | `20` | No |

## Monitoring and Compliance

### Application Insights Integration

The solution includes Application Insights for comprehensive monitoring:

```bash
# View Application Insights data
az monitor app-insights query \
    --app <app-insights-name> \
    --analytics-query "requests | where name contains 'OptOutProcessor'"
```

### Compliance Audit Logs

Audit logs are stored in Azure Table Storage:

```bash
# Query audit table
az storage table query \
    --account-name <storage-account-name> \
    --table-name optoutaudit \
    --select "phoneNumber,action,timestamp,status"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

echo "Resource group deletion initiated: ${RESOURCE_GROUP}"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="location=eastus" \
    -var="resource_group_name=${RESOURCE_GROUP}"

# Clean up Terraform state
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name ${RESOURCE_GROUP}
```

## Customization

### Adding Custom Compliance Rules

Modify the function code to implement custom compliance logic:

1. Edit `OptOutProcessor/index.js` to add validation rules
2. Update timer function for custom monitoring schedules
3. Extend audit logging with additional metadata

### Multi-Channel Integration

Extend the solution for email and web portal opt-outs:

1. Add new HTTP endpoints for different channels
2. Implement channel-specific validation logic
3. Update audit logging to track opt-out sources

### Regional Compliance

Configure for different regulatory requirements:

1. Update Bicep/Terraform parameters for regional deployment
2. Modify function logic for jurisdiction-specific rules
3. Implement region-specific audit requirements

## Security Considerations

### Managed Identity

The solution uses system-assigned managed identity for secure service communication:

- No connection strings stored in application code
- Automatic credential rotation
- Least privilege access to Communication Services

### Data Protection

- All audit data encrypted at rest in Azure Storage
- Communication Services connection secured with TLS
- Function App configured with HTTPS-only access

### Compliance Features

- Immediate opt-out processing for regulatory compliance
- Comprehensive audit logging for regulatory reporting
- Automated monitoring for compliance violations

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check Function App logs
   az functionapp logs tail \
       --name <function-app-name> \
       --resource-group ${RESOURCE_GROUP}
   ```

2. **Communication Services connection errors**:
   ```bash
   # Verify connection string configuration
   az functionapp config appsettings list \
       --name <function-app-name> \
       --resource-group ${RESOURCE_GROUP}
   ```

3. **Opt-out API errors**:
   ```bash
   # Check Communication Services status
   az communication show \
       --name <communication-service-name> \
       --resource-group ${RESOURCE_GROUP}
   ```

### Performance Optimization

- Monitor function execution times in Application Insights
- Optimize batch processing for high-volume opt-out requests
- Consider premium Function App plan for consistent performance

## Cost Optimization

### Resource Sizing

- Consumption plan scales to zero when idle
- Storage account uses locally redundant storage for cost efficiency
- Communication Services charges only for actual SMS usage

### Monitoring Costs

```bash
# View cost analysis
az consumption usage list \
    --start-date 2025-01-01 \
    --end-date 2025-01-31 \
    --scope "/subscriptions/<subscription-id>/resourceGroups/${RESOURCE_GROUP}"
```

## Support

### Documentation References

- [Azure Communication Services SMS Opt-Out Management API](https://learn.microsoft.com/en-us/azure/communication-services/concepts/sms/opt-out-api-concept)
- [Azure Functions Best Practices](https://learn.microsoft.com/en-us/azure/azure-functions/functions-best-practices)
- [Bicep Language Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Azure service health status
3. Consult the original recipe documentation
4. Reference Azure Communication Services documentation

### Contributing

To contribute improvements to this IaC implementation:
1. Test changes in a development environment
2. Follow Azure naming conventions and best practices
3. Update documentation for any parameter changes
4. Ensure security configurations remain compliant