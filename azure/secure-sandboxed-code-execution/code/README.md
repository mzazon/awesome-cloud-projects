# Infrastructure as Code for Secure Sandboxed Code Execution with Dynamic Sessions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Sandboxed Code Execution with Dynamic Sessions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.62.0 or higher installed and configured
- Azure subscription with appropriate permissions for:
  - Azure Container Apps
  - Azure Event Grid
  - Azure Key Vault
  - Azure Monitor
  - Azure Functions
  - Azure Storage
- Container Apps extension for Azure CLI (auto-installs when needed)
- For Terraform: Terraform v1.0+ installed
- For Bicep: Bicep CLI installed (included with Azure CLI v2.20.0+)
- Appropriate Azure RBAC permissions for resource creation and management

## Architecture Overview

This infrastructure deploys a secure code execution platform featuring:

- **Azure Container Apps Environment** with dynamic session pools for isolated code execution
- **Azure Event Grid** topic and subscriptions for event-driven workflows
- **Azure Functions** for session management and orchestration
- **Azure Key Vault** for secure secrets management
- **Azure Storage Account** for execution results and logging
- **Azure Monitor** with Application Insights for comprehensive observability

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentName=<unique-environment-name>
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure deployment parameters
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `environmentName` | string | `demo` | Environment name for resource naming |
| `maxSessions` | int | `20` | Maximum number of dynamic sessions |
| `readySessions` | int | `5` | Number of warm sessions to maintain |
| `cooldownPeriod` | int | `300` | Session cooldown period in seconds |
| `storageSkuName` | string | `Standard_LRS` | Storage account SKU |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | Required | Name of the resource group |
| `location` | string | `East US` | Azure region for resources |
| `environment_name` | string | `demo` | Environment identifier |
| `max_sessions` | number | `20` | Maximum dynamic sessions |
| `ready_sessions` | number | `5` | Ready session pool size |
| `session_cooldown` | number | `300` | Session cooldown in seconds |

## Deployment Options

### Development Environment

For development and testing purposes:

```bash
# Using Bicep
az deployment group create \
    --resource-group rg-dev-code-execution \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters environmentName=dev \
    --parameters maxSessions=10 \
    --parameters readySessions=2

# Using Terraform
terraform apply -var="environment_name=dev" -var="max_sessions=10"
```

### Production Environment

For production deployments with enhanced security and monitoring:

```bash
# Using Bicep
az deployment group create \
    --resource-group rg-prod-code-execution \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters environmentName=prod \
    --parameters maxSessions=50 \
    --parameters readySessions=10 \
    --parameters storageSkuName=Standard_GRS

# Using Terraform
terraform apply \
    -var="environment_name=prod" \
    -var="max_sessions=50" \
    -var="ready_sessions=10"
```

## Post-Deployment Configuration

After successful deployment, complete these configuration steps:

1. **Configure Function App Code**: Deploy the session management function code to the created Function App
2. **Set up Event Grid Subscription**: The subscription is created but may need additional filtering configuration
3. **Configure Key Vault Secrets**: Add any additional secrets required by your application
4. **Test Session Pool**: Verify dynamic session allocation is working correctly

### Testing the Deployment

```bash
# Test Event Grid topic connectivity
TOPIC_ENDPOINT=$(az eventgrid topic show \
    --name <event-grid-topic-name> \
    --resource-group <resource-group> \
    --query endpoint --output tsv)

# Publish a test event
curl -X POST "${TOPIC_ENDPOINT}/api/events" \
    -H "aeg-sas-key: <topic-key>" \
    -H "Content-Type: application/json" \
    -d '[{
        "id": "test-001",
        "eventType": "Microsoft.EventGrid.ExecuteCode",
        "subject": "code-execution/test",
        "data": {"code": "print(\"Hello World!\")"},
        "eventTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }]'
```

## Security Considerations

This infrastructure implements several security best practices:

- **Network Isolation**: Dynamic sessions have egress disabled by default
- **Managed Identity**: Function App uses managed identity for Azure service authentication
- **Key Vault Integration**: Secrets are stored securely in Azure Key Vault
- **RBAC Permissions**: Least privilege access patterns implemented
- **Encryption**: All data encrypted at rest and in transit

## Monitoring and Observability

The deployment includes comprehensive monitoring:

- **Application Insights**: Detailed application performance monitoring
- **Log Analytics**: Centralized logging for all components
- **Azure Monitor**: Metrics and alerting for infrastructure components
- **Event Grid Metrics**: Event delivery and processing statistics

Access monitoring dashboards:

```bash
# Get Application Insights dashboard URL
az monitor app-insights component show \
    --app <app-insights-name> \
    --resource-group <resource-group> \
    --query appId --output tsv
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name <resource-group-name> --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **Container Apps Extension Missing**:
   ```bash
   az extension add --name containerapp
   ```

2. **Insufficient Permissions**:
   - Ensure your account has Contributor role on the subscription or resource group
   - Verify Key Vault access policies are correctly configured

3. **Session Pool Creation Fails**:
   - Check Container Apps environment is fully provisioned
   - Verify Log Analytics workspace is accessible

4. **Event Grid Subscription Issues**:
   - Confirm Function App endpoint is accessible
   - Check Event Grid topic permissions

### Validation Commands

```bash
# Check Container Apps environment status
az containerapp env show \
    --name <environment-name> \
    --resource-group <resource-group> \
    --query properties.provisioningState

# Verify session pool is ready
az containerapp sessionpool show \
    --name <session-pool-name> \
    --resource-group <resource-group> \
    --query properties.poolManagementEndpoint

# Test Key Vault access
az keyvault secret list \
    --vault-name <key-vault-name> \
    --query "[].name"
```

## Cost Optimization

To optimize costs for this deployment:

1. **Adjust Session Pool Size**: Reduce `readySessions` for development environments
2. **Use Consumption Plans**: Function Apps use consumption pricing by default
3. **Configure Storage Tiers**: Use appropriate storage tiers for your retention requirements
4. **Monitor Usage**: Use Azure Cost Management to track spending

## Customization

### Adding Additional Languages

To support additional programming languages, modify the session pool configuration:

```bash
# Create additional session pool for Node.js
az containerapp sessionpool create \
    --name pool-nodejs-<suffix> \
    --container-type NodeLTS \
    --environment <environment-name> \
    --resource-group <resource-group>
```

### Custom Function Code

Deploy your custom session management logic:

```bash
# Package and deploy function code
func azure functionapp publish <function-app-name>
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for architecture details
2. Consult Azure Container Apps documentation for dynamic sessions
3. Check Azure Event Grid documentation for event-driven patterns
4. Refer to provider-specific documentation for troubleshooting

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Supported Azure CLI**: v2.62.0+
- **Supported Terraform**: v1.0+
- **Supported Bicep**: Latest (included with Azure CLI v2.20.0+)

## Contributing

When updating this infrastructure code:

1. Test changes in a development environment first
2. Update parameter documentation if adding new variables
3. Ensure cleanup scripts remove all created resources
4. Update this README with any new configuration options