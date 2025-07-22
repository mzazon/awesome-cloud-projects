# Infrastructure as Code for Supply Chain Carbon Tracking with AI Agents

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Supply Chain Carbon Tracking with AI Agents".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Bicep language)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with appropriate permissions:
  - Contributor access to create AI Foundry projects
  - Contributor access to create Sustainability Manager instances
  - Contributor access to create Service Bus namespaces
  - Contributor access to create Function Apps and related resources
- Understanding of AI agent concepts, carbon accounting principles, and supply chain management
- Access to sample supply chain data sources (APIs or files) for testing
- Estimated cost: $150-300 for a complete implementation and testing cycle

## Quick Start

### Using Bicep
```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-carbon-tracking \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentName=demo

# Monitor deployment progress
az deployment group show \
    --resource-group rg-carbon-tracking \
    --name main \
    --query properties.provisioningState
```

### Using Terraform
```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
az group show --name rg-carbon-tracking-$(date +%s | tail -c 4)
```

## Architecture Overview

This IaC deploys the following Azure resources:

- **Azure AI Foundry Project**: Foundation for AI agent development and deployment
- **Azure Sustainability Manager Environment**: Power Platform environment for carbon emissions management
- **Azure Service Bus Namespace**: Event-driven messaging for carbon data processing
- **Azure Function App**: Serverless compute for data processing and integration
- **Azure Storage Account**: Required for Function App operations
- **Supporting Resources**: Resource groups, IAM roles, and networking components

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default Value | Required |
|-----------|-------------|---------------|----------|
| `location` | Azure region for resource deployment | `eastus` | Yes |
| `environmentName` | Environment identifier for resource naming | `demo` | Yes |
| `aiFoundryProjectName` | Name for AI Foundry project | Auto-generated | No |
| `serviceBusNamespaceName` | Name for Service Bus namespace | Auto-generated | No |
| `functionAppName` | Name for Function App | Auto-generated | No |
| `storageAccountName` | Name for storage account | Auto-generated | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `location` | Azure region for deployment | `string` | `"eastus"` | Yes |
| `environment` | Environment name for resources | `string` | `"demo"` | Yes |
| `resource_group_name` | Resource group name | `string` | Auto-generated | No |
| `ai_foundry_project_name` | AI Foundry project name | `string` | Auto-generated | No |
| `service_bus_namespace_name` | Service Bus namespace name | `string` | Auto-generated | No |
| `function_app_name` | Function App name | `string` | Auto-generated | No |
| `storage_account_name` | Storage account name | `string` | Auto-generated | No |

## Post-Deployment Configuration

After successful deployment, complete these additional setup steps:

1. **Configure AI Agents**: Deploy agent configurations through Azure AI Foundry portal
2. **Set up Sustainability Manager**: Configure carbon accounting rules and data sources
3. **Deploy Function Code**: Upload carbon processing functions to the Function App
4. **Configure Data Sources**: Connect supply chain data sources to the collection agents
5. **Set up Monitoring**: Configure alerts and dashboards for carbon tracking

## Validation

### Verify Resource Deployment
```bash
# Check resource group
az group show --name rg-carbon-tracking-demo

# Verify AI Foundry project
az ml workspace show \
    --name aif-carbon-demo \
    --resource-group rg-carbon-tracking-demo

# Check Service Bus namespace
az servicebus namespace show \
    --name sb-carbon-demo \
    --resource-group rg-carbon-tracking-demo

# Verify Function App
az functionapp show \
    --name func-carbon-demo \
    --resource-group rg-carbon-tracking-demo
```

### Test Service Bus Messaging
```bash
# Send test message to carbon data queue
az servicebus queue send \
    --name carbon-data-queue \
    --namespace-name sb-carbon-demo \
    --resource-group rg-carbon-tracking-demo \
    --body '{"facility_id":"FAC001","source":"transportation","co2_eq_tonnes":25.5}'

# Check message processing
az servicebus queue show \
    --name carbon-data-queue \
    --namespace-name sb-carbon-demo \
    --resource-group rg-carbon-tracking-demo \
    --query messageCount
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-carbon-tracking-demo \
    --yes \
    --no-wait
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name rg-carbon-tracking-demo
```

## Customization

### Scaling Configuration

For production environments, consider these modifications:

1. **Service Bus Scaling**: Upgrade to Premium tier for higher throughput
2. **Function App Scaling**: Configure dedicated App Service Plan for consistent performance
3. **Storage Account**: Use Premium storage for better performance
4. **AI Foundry**: Configure dedicated compute instances for agent workloads

### Security Hardening

1. **Network Security**: Implement virtual network integration and private endpoints
2. **Identity Management**: Use managed identities for all service-to-service authentication
3. **Data Encryption**: Enable encryption at rest and in transit for all data stores
4. **Access Control**: Implement role-based access control (RBAC) for all resources

### Cost Optimization

1. **Function App**: Use consumption plan for variable workloads
2. **Storage Account**: Implement lifecycle management policies
3. **Service Bus**: Use Standard tier for development/testing environments
4. **AI Foundry**: Configure auto-scaling policies based on usage patterns

## Monitoring and Observability

### Key Metrics to Monitor

- **Carbon Data Processing Rate**: Messages processed per minute
- **Agent Performance**: Response times and success rates
- **Function App Metrics**: Execution duration and error rates
- **Service Bus Metrics**: Queue depth and message throughput
- **Sustainability Manager**: Data ingestion rates and reporting accuracy

### Recommended Alerts

```bash
# Create alert for high carbon emissions
az monitor metrics alert create \
    --name "High Carbon Emissions Alert" \
    --resource-group rg-carbon-tracking-demo \
    --scopes "/subscriptions/{subscription-id}/resourceGroups/rg-carbon-tracking-demo" \
    --condition "avg Custom.CarbonEmissions > 400" \
    --description "Alert when carbon emissions exceed threshold"
```

## Troubleshooting

### Common Issues

1. **AI Foundry Project Creation Fails**
   - Verify Machine Learning Services provider is registered
   - Check regional availability of AI Foundry services
   - Ensure sufficient quota for compute resources

2. **Service Bus Connection Issues**
   - Verify connection string configuration
   - Check firewall rules and network access
   - Validate authentication credentials

3. **Function App Deployment Failures**
   - Check storage account accessibility
   - Verify Azure Functions runtime version compatibility
   - Review application settings configuration

4. **Sustainability Manager Integration Issues**
   - Verify Power Platform environment provisioning
   - Check data connector permissions
   - Validate API endpoint configurations

### Diagnostic Commands

```bash
# Check resource provider registration
az provider show --namespace Microsoft.MachineLearningServices
az provider show --namespace Microsoft.ServiceBus
az provider show --namespace Microsoft.Web

# View deployment logs
az deployment group show \
    --resource-group rg-carbon-tracking-demo \
    --name main \
    --query properties.error

# Check Function App logs
az functionapp log tail \
    --name func-carbon-demo \
    --resource-group rg-carbon-tracking-demo
```

## Support

For issues with this infrastructure code, refer to:

1. **Original Recipe Documentation**: Review the complete recipe for context and manual deployment steps
2. **Azure Documentation**: [Azure AI Foundry Agent Service](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/overview)
3. **Azure Support**: [Azure Sustainability Manager](https://learn.microsoft.com/en-us/industry/sustainability/sustainability-manager-overview)
4. **Community Support**: [Azure Community Forums](https://techcommunity.microsoft.com/t5/azure/ct-p/Azure)

## Contributing

To contribute improvements to this IaC:

1. Follow Azure naming conventions and best practices
2. Test all changes in a development environment
3. Update documentation for any new parameters or resources
4. Ensure security best practices are maintained
5. Validate cost implications of changes

## License

This infrastructure code is provided as-is under the same terms as the original recipe. Use responsibly and ensure compliance with your organization's policies and Azure terms of service.