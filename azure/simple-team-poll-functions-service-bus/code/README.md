# Infrastructure as Code for Simple Team Poll System with Functions and Service Bus

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Team Poll System with Functions and Service Bus".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.60 or later)
- Azure subscription with appropriate permissions for:
  - Resource Group creation/management
  - Azure Functions deployment
  - Service Bus namespace and queue management
  - Storage Account creation
- For Terraform: Terraform CLI installed (version 1.0+)
- For Bicep: Bicep CLI installed (latest version)
- Basic understanding of serverless computing and message queuing concepts

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-recipe-demo \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environmentName=demo
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
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
```

## Configuration Options

### Bicep Parameters

- `location`: Azure region for resource deployment (default: eastus)
- `environmentName`: Environment suffix for resource naming (default: demo)
- `serviceBusSku`: Service Bus pricing tier (default: Basic)
- `storageAccountType`: Storage account replication type (default: Standard_LRS)

### Terraform Variables

- `location`: Azure region for resource deployment
- `environment_name`: Environment suffix for resource naming
- `resource_group_name`: Name of the resource group to create
- `service_bus_sku`: Service Bus pricing tier
- `storage_account_tier`: Storage account performance tier

### Bash Script Environment Variables

The deployment script will prompt for or auto-generate:
- Resource group name with random suffix
- Azure region selection
- Service Bus namespace name
- Function App name
- Storage account name

## Deployed Resources

This infrastructure creates the following Azure resources:

1. **Resource Group**: Container for all related resources
2. **Service Bus Namespace**: Messaging infrastructure with basic tier
3. **Service Bus Queue**: `votes` queue for reliable message processing
4. **Storage Account**: Function App storage and vote result persistence
5. **Function App**: Serverless compute with consumption plan
6. **Application Insights**: Monitoring and logging (optional)

## Function Endpoints

After deployment, the following HTTP endpoints will be available:

- `POST /api/SubmitVote`: Submit a vote for a poll
- `GET /api/results/{pollId}`: Retrieve poll results

### Example Usage

```bash
# Submit a vote
curl -X POST "https://your-function-app.azurewebsites.net/api/SubmitVote" \
    -H "Content-Type: application/json" \
    -d '{
        "pollId": "team-lunch",
        "option": "Pizza",
        "voterId": "alice@company.com"
    }'

# Get results
curl "https://your-function-app.azurewebsites.net/api/results/team-lunch"
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Stream Function App logs
az webapp log tail \
    --name your-function-app-name \
    --resource-group your-resource-group
```

### Check Service Bus Queue Status

```bash
# Check queue message count
az servicebus queue show \
    --name votes \
    --namespace-name your-service-bus-namespace \
    --resource-group your-resource-group \
    --query "messageCount"
```

### Monitor Function Performance

Access the Function App in the Azure Portal to view:
- Execution metrics and performance
- Error rates and debugging information
- Application Insights telemetry
- Resource consumption and scaling events

## Security Considerations

### Production Hardening

For production deployments, consider these security enhancements:

1. **Authentication**: Replace anonymous access with Azure AD authentication
2. **API Management**: Use Azure API Management for rate limiting and security
3. **Network Security**: Implement private endpoints and network restrictions
4. **Key Management**: Use Azure Key Vault for connection strings and secrets
5. **CORS**: Configure appropriate CORS policies for web applications

### Example Azure AD Integration

```bash
# Enable Azure AD authentication
az functionapp auth update \
    --name your-function-app-name \
    --resource-group your-resource-group \
    --enabled true \
    --action LoginWithAzureActiveDirectory
```

## Cost Optimization

### Consumption Plan Benefits

- Pay-per-execution pricing model
- Automatic scaling based on demand
- No charges when functions are idle
- 1 million free executions per month

### Estimated Costs (per month)

- **Azure Functions**: $0-5 for light usage (consumption plan)
- **Service Bus**: $10 (basic tier with 12.5M operations)
- **Storage Account**: $1-3 (LRS, minimal data)
- **Total**: ~$11-18 for typical team polling usage

### Cost Monitoring

```bash
# View resource costs
az consumption usage list \
    --start-date 2024-01-01 \
    --end-date 2024-01-31 \
    --resource-group your-resource-group
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name your-resource-group \
    --yes \
    --no-wait
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
```

## Customization

### Adding Authentication

To add Azure AD authentication, modify the Function App configuration:

```bicep
resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  // ... existing configuration
  properties: {
    // ... existing properties
    siteConfig: {
      // ... existing siteConfig
      authSettings: {
        enabled: true
        defaultProvider: 'AzureActiveDirectory'
        clientId: 'your-app-registration-id'
        issuer: 'https://sts.windows.net/your-tenant-id/'
      }
    }
  }
}
```

### Scaling Configuration

Modify the Function App hosting plan for predictable workloads:

```bicep
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'plan-${environmentName}'
  location: location
  sku: {
    name: 'S1'  // Standard tier for reserved instances
    tier: 'Standard'
  }
}
```

### Database Integration

For enhanced poll management, integrate with Azure Cosmos DB:

```bicep
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2022-05-15' = {
  name: 'cosmos-polls-${environmentName}'
  location: location
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    databaseAccountOfferType: 'Standard'
  }
}
```

## Troubleshooting

### Common Issues

1. **Function App Deployment Fails**
   - Verify storage account connection string
   - Check Function App runtime version compatibility
   - Ensure sufficient permissions for deployment

2. **Service Bus Connection Issues**
   - Validate connection string format
   - Check Service Bus namespace status
   - Verify queue creation success

3. **Vote Processing Delays**
   - Monitor Service Bus queue depth
   - Check Function App scaling metrics
   - Review Application Insights for errors

### Debug Commands

```bash
# Check Function App status
az functionapp show \
    --name your-function-app-name \
    --resource-group your-resource-group \
    --query "state"

# List function runtime status
az functionapp function show \
    --name your-function-app-name \
    --resource-group your-resource-group \
    --function-name SubmitVote

# View Service Bus metrics
az monitor metrics list \
    --resource your-service-bus-resource-id \
    --metric "Messages" \
    --interval PT1M
```

## Extensions and Enhancements

### Real-time Updates with SignalR

Add Azure SignalR Service for real-time poll result updates:

```bicep
resource signalRService 'Microsoft.SignalRService/signalR@2022-02-01' = {
  name: 'signalr-polls-${environmentName}'
  location: location
  sku: {
    name: 'Free_F1'
    capacity: 1
  }
  properties: {
    features: [
      {
        flag: 'ServiceMode'
        value: 'Serverless'
      }
    ]
  }
}
```

### Static Web App Frontend

Deploy a complete frontend using Azure Static Web Apps:

```bicep
resource staticWebApp 'Microsoft.Web/staticSites@2022-03-01' = {
  name: 'swa-polls-${environmentName}'
  location: 'East US 2'  // Static Web Apps limited regions
  properties: {
    repositoryUrl: 'https://github.com/your-org/poll-frontend'
    branch: 'main'
    buildProperties: {
      appLocation: '/src'
      outputLocation: '/dist'
    }
  }
}
```

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../simple-team-poll-functions-service-bus.md)
- [Azure Functions documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Service Bus documentation](https://docs.microsoft.com/en-us/azure/service-bus-messaging/)
- [Azure Bicep documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Contributing

When modifying this infrastructure:

1. Test all changes in a development environment
2. Update documentation for any new parameters or resources
3. Ensure cleanup scripts handle new resources
4. Validate security configurations
5. Update cost estimates for new resources