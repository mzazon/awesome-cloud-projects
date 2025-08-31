# Infrastructure as Code for Event-Driven AI Agent Workflows with AI Foundry and Logic Apps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event-Driven AI Agent Workflows with AI Foundry and Logic Apps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions for:
  - Azure AI Foundry (Machine Learning Services)
  - Azure Logic Apps
  - Azure Service Bus
  - Resource Groups
- PowerShell or Bash shell environment
- For Terraform: Terraform CLI installed (>= 1.0)
- For Bicep: Bicep CLI installed (latest version)

> **Note**: Azure AI Foundry Agent Service is currently in preview. Ensure your subscription has access to preview features.

## Cost Estimation

Estimated monthly cost for this solution:
- Azure AI Foundry Hub: ~$50-100/month (varies by usage)
- Azure Service Bus Standard: ~$10-20/month
- Azure Logic Apps Consumption: ~$5-15/month (based on executions)
- **Total estimated cost**: $65-135/month

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy infrastructure
az deployment group create \
    --resource-group rg-ai-workflows \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters uniqueSuffix=$(openssl rand -hex 3)

# Verify deployment
az deployment group show \
    --resource-group rg-ai-workflows \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="location=eastus" -var="unique_suffix=$(openssl rand -hex 3)"

# Deploy infrastructure
terraform apply -var="location=eastus" -var="unique_suffix=$(openssl rand -hex 3)"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export LOCATION="eastus"
export UNIQUE_SUFFIX=$(openssl rand -hex 3)

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
az group show --name "rg-ai-workflows-${UNIQUE_SUFFIX}" --query "properties.provisioningState"
```

## Architecture Overview

This IaC deploys the following Azure resources:

- **Azure AI Foundry Hub**: Central management for AI resources with enterprise governance
- **Azure AI Foundry Project**: Isolated workspace for AI agent development
- **Azure Service Bus Namespace**: Reliable messaging with Standard tier
- **Service Bus Queue**: Point-to-point event processing
- **Service Bus Topic & Subscription**: Publish-subscribe event distribution
- **Azure Logic App**: Serverless workflow orchestration
- **Managed Identity**: Secure authentication between services

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | eastus | Azure region for deployment |
| `uniqueSuffix` | string | [generated] | Unique suffix for resource names |
| `serviceBusSku` | string | Standard | Service Bus pricing tier |
| `aiFoundryPublicNetworkAccess` | string | Enabled | AI Foundry network access setting |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | eastus | Azure region for deployment |
| `unique_suffix` | string | [required] | Unique suffix for resource names |
| `service_bus_sku` | string | Standard | Service Bus pricing tier |
| `tags` | map(string) | {} | Resource tags |

### Environment Variables (Bash Scripts)

| Variable | Required | Description |
|----------|----------|-------------|
| `LOCATION` | Yes | Azure region (e.g., eastus) |
| `UNIQUE_SUFFIX` | Yes | Unique identifier for resources |
| `RESOURCE_GROUP` | No | Custom resource group name |

## Post-Deployment Configuration

After infrastructure deployment, complete these manual steps:

### 1. Configure AI Agent in AI Foundry Portal

```bash
# Get AI Foundry project details
az ml workspace show \
    --name "aiproject-workflows-${UNIQUE_SUFFIX}" \
    --resource-group "rg-ai-workflows-${UNIQUE_SUFFIX}" \
    --query "discovery_url"
```

Navigate to [Azure AI Foundry](https://ai.azure.com) to:
- Create BusinessEventProcessor agent
- Configure GPT-4o model
- Enable Grounding with Bing Search
- Set up Azure Logic Apps integration
- Configure system instructions for event processing

### 2. Update Logic App Service Bus Connection

```bash
# Get Service Bus connection string
az servicebus namespace authorization-rule keys list \
    --name RootManageSharedAccessKey \
    --namespace-name "sb-workflows-${UNIQUE_SUFFIX}" \
    --resource-group "rg-ai-workflows-${UNIQUE_SUFFIX}" \
    --query "primaryConnectionString"
```

Update the Logic App's Service Bus connection in the Azure portal with this connection string.

### 3. Test the Solution

```bash
# Send test message to verify end-to-end functionality
az servicebus message send \
    --namespace-name "sb-workflows-${UNIQUE_SUFFIX}" \
    --queue-name "event-processing-queue" \
    --body '{
        "eventType": "support-request",
        "content": "Customer reporting login issues",
        "metadata": {
            "customerId": "CUST-12345",
            "priority": "high"
        }
    }'
```

## Monitoring and Troubleshooting

### Check Resource Status

```bash
# Verify all resources are running
az resource list \
    --resource-group "rg-ai-workflows-${UNIQUE_SUFFIX}" \
    --output table

# Check Service Bus queue metrics
az servicebus queue show \
    --name "event-processing-queue" \
    --namespace-name "sb-workflows-${UNIQUE_SUFFIX}" \
    --resource-group "rg-ai-workflows-${UNIQUE_SUFFIX}" \
    --query "messageCount"

# Monitor Logic App runs
az logic workflow list-runs \
    --name "la-ai-workflows-${UNIQUE_SUFFIX}" \
    --resource-group "rg-ai-workflows-${UNIQUE_SUFFIX}" \
    --top 5
```

### Common Issues

1. **AI Foundry Preview Access**: Ensure your subscription has access to Azure AI Foundry preview features
2. **Service Bus Connectivity**: Verify managed identity has proper permissions
3. **Logic App Triggers**: Check Service Bus connection configuration
4. **Resource Naming**: Ensure unique suffix prevents naming conflicts

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete \
    --name "rg-ai-workflows-${UNIQUE_SUFFIX}" \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="location=eastus" -var="unique_suffix=${UNIQUE_SUFFIX}"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name "rg-ai-workflows-${UNIQUE_SUFFIX}"
```

## Security Considerations

This IaC implements several security best practices:

- **Managed Identity**: Secure authentication between Azure services
- **Network Isolation**: AI Foundry workspace with configurable network access
- **Service Bus Security**: Built-in encryption and access controls
- **Logic Apps Security**: Managed connectors with Azure AD authentication
- **Resource Tagging**: Proper labeling for governance and cost tracking

## Customization

### Adding Custom Logic App Actions

Extend the Logic App workflow by modifying the workflow definition to include:
- Email notifications using Office 365 connector
- Teams messages using Microsoft Teams connector
- Database updates using SQL Server connector
- Custom HTTP endpoints for third-party integrations

### Scaling Considerations

- **Service Bus**: Standard tier supports up to 1,000 concurrent connections
- **Logic Apps**: Consumption plan scales automatically based on triggers
- **AI Foundry**: Scales based on model deployment and usage patterns

### Integration with Existing Systems

This solution can be integrated with:
- Microsoft Power Platform for citizen developer workflows
- Azure Monitor for centralized logging and alerting
- Azure Key Vault for secure configuration management
- Azure API Management for external API integration

## Support and Documentation

- [Azure AI Foundry Documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [Azure Logic Apps Documentation](https://learn.microsoft.com/azure/logic-apps/)
- [Azure Service Bus Documentation](https://learn.microsoft.com/azure/service-bus-messaging/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the Azure documentation links above.