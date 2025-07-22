# Infrastructure as Code for Blockchain Supply Chain Transparency with Confidential Ledger and Cosmos DB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Blockchain Supply Chain Transparency with Confidential Ledger and Cosmos DB".

## Available Implementations

- **Bicep**: Azure's native infrastructure as code language (recommended)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with Owner or Contributor access
- Azure AD permissions to create service principals and manage access
- Appropriate permissions for creating:
  - Azure Confidential Ledger
  - Azure Cosmos DB
  - Azure Logic Apps
  - Azure Event Grid
  - Azure API Management
  - Azure Key Vault
  - Azure Storage Account
  - Azure Monitor and Application Insights
- For Terraform: Terraform v1.0+ installed
- For Bicep: Bicep CLI (comes with Azure CLI v2.20.0+)
- OpenSSL (for generating random values)
- Estimated cost: $200-300/month for development environment

> **Note**: Azure Confidential Ledger requires specific regions for deployment. Verify [regional availability](https://docs.microsoft.com/en-us/azure/confidential-ledger/overview#region-availability) before starting.

## Quick Start

### Using Bicep (Recommended)

```bash
cd bicep/

# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Create deployment
az deployment sub create \
    --location eastus \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment progress
az deployment sub show \
    --name main \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var-file="terraform.tfvars"

# Apply infrastructure
terraform apply -var-file="terraform.tfvars"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment status
# Follow the script output for deployment progress
```

## Architecture Overview

This solution implements a blockchain-powered supply chain transparency system using:

- **Azure Confidential Ledger**: Tamper-proof blockchain for immutable transaction records with cryptographic verification
- **Azure Cosmos DB**: Globally distributed database for high-performance queries with multi-region support
- **Azure Logic Apps**: Workflow orchestration for blockchain recording and event processing
- **Azure Event Grid**: Event-driven architecture for real-time notifications across supply chain participants
- **Azure API Management**: Secure gateway for partner integration with rate limiting and authentication
- **Azure Key Vault**: Secure credential and certificate management with managed identity integration
- **Azure Blob Storage**: Document and certificate storage with lifecycle management
- **Azure Monitor & Application Insights**: Comprehensive monitoring, logging, and analytics for compliance

## Configuration

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroupName": {
      "value": "rg-supply-chain-ledger"
    },
    "location": {
      "value": "eastus"
    },
    "environment": {
      "value": "dev"
    },
    "ledgerType": {
      "value": "Public"
    },
    "cosmosDbConsistencyLevel": {
      "value": "Session"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
resource_group_name = "rg-supply-chain-ledger"
location           = "East US"
environment        = "dev"
ledger_type        = "Public"
cosmos_consistency = "Session"

# Optional: Override default naming
ledger_name_override    = ""
cosmos_account_override = ""
storage_account_override = ""
```

### Script Configuration

Environment variables can be set before running deployment scripts:

```bash
export RESOURCE_GROUP="rg-supply-chain-ledger"
export LOCATION="eastus"
export ENVIRONMENT="dev"

# Run deployment
./scripts/deploy.sh
```

## Validation

After deployment, validate the infrastructure:

### Check Core Services

```bash
# Verify Confidential Ledger
az confidentialledger show \
    --name your-ledger-name \
    --resource-group your-resource-group \
    --query "{Name:name, State:properties.provisioningState}" \
    --output table

# Verify Cosmos DB
az cosmosdb show \
    --name your-cosmos-account \
    --resource-group your-resource-group \
    --query "{Name:name, State:properties.provisioningState}" \
    --output table

# Test Logic App trigger
az logic workflow show \
    --name your-logic-app \
    --resource-group your-resource-group \
    --query "{Name:name, State:properties.state}" \
    --output table
```

### End-to-End Testing

```bash
# Get Logic App trigger URL
LOGIC_APP_URL=$(az logic workflow show \
    --name your-logic-app-name \
    --resource-group your-resource-group \
    --query "accessEndpoint" \
    --output tsv)

# Submit test transaction
curl -X POST ${LOGIC_APP_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "transactionId": "TXN-'$(date +%s)'",
      "productId": "PROD-001",
      "action": "ProductCreated",
      "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "location": "Factory-A",
      "participant": "Manufacturer-001",
      "metadata": {
        "batchNumber": "BATCH-2024-001",
        "quantity": 1000,
        "qualityCertificate": "CERT-001"
      }
    }'

# Test Event Grid publishing
EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
    --name your-event-grid-topic \
    --resource-group your-resource-group \
    --query endpoint \
    --output tsv)

EVENT_GRID_KEY=$(az eventgrid topic key list \
    --name your-event-grid-topic \
    --resource-group your-resource-group \
    --query key1 \
    --output tsv)

curl -X POST ${EVENT_GRID_ENDPOINT} \
    -H "aeg-sas-key: ${EVENT_GRID_KEY}" \
    -H "Content-Type: application/json" \
    -d '[{
      "id": "test-001",
      "eventType": "ProductCreated",
      "subject": "test/validation",
      "eventTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "data": {
        "productId": "TEST-001",
        "message": "Validation successful"
      }
    }]'
```

## Monitoring

### View Deployment Logs

```bash
# Monitor resource group deployments
az deployment group list \
    --resource-group your-resource-group \
    --query "[].{Name:name, State:properties.provisioningState, Timestamp:properties.timestamp}" \
    --output table

# View Application Insights metrics
az monitor app-insights component show \
    --app supply-chain-insights \
    --resource-group your-resource-group \
    --query "instrumentationKey" \
    --output tsv
```

### Custom Metrics and Alerts

The infrastructure includes pre-configured monitoring for:

- Transaction volume alerts
- Ledger performance metrics
- Cosmos DB request units and latency
- Logic App execution failures
- Event Grid delivery status

## Security Considerations

### Default Security Features

- **Managed Identity**: All services use managed identities for authentication
- **Key Vault Integration**: Secrets and connection strings stored securely
- **Network Security**: Private endpoints where applicable
- **RBAC**: Role-based access control configured
- **Encryption**: Data encrypted at rest and in transit

### Security Customization

```bash
# Enable additional security features
az keyvault update \
    --name your-keyvault-name \
    --resource-group your-resource-group \
    --enable-purge-protection true \
    --enable-soft-delete true

# Configure private endpoints (requires VNET)
az network private-endpoint create \
    --name cosmos-private-endpoint \
    --resource-group your-resource-group \
    --vnet-name your-vnet \
    --subnet your-subnet \
    --private-connection-resource-id "/subscriptions/.../cosmosdb-account" \
    --connection-name cosmos-connection
```

## Cleanup

### Using Bicep

```bash
# Delete the deployment
az deployment sub delete --name main

# Verify resource group deletion
az group show --name your-resource-group --query "properties.provisioningState"
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var-file="terraform.tfvars"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
# The script will handle dependencies and cleanup order
```

### Manual Cleanup (if needed)

```bash
# Delete resource group and all resources
az group delete \
    --name your-resource-group \
    --yes \
    --no-wait

# Purge soft-deleted Key Vault (if purge protection is disabled)
az keyvault purge \
    --name your-keyvault-name \
    --location eastus
```

## Troubleshooting

### Common Issues

1. **Confidential Ledger Region Availability**
   ```bash
   # Check available regions
   az provider show \
       --namespace Microsoft.ConfidentialLedger \
       --query "resourceTypes[?resourceType=='ledgers'].locations" \
       --output table
   ```

2. **API Management Long Deployment Time**
   - API Management can take 20-45 minutes to deploy
   - Use `--no-wait` flag for non-blocking deployment
   - Monitor progress: `az deployment group show --name main --resource-group your-rg`

3. **Cosmos DB Throughput Limits**
   ```bash
   # Check current throughput
   az cosmosdb sql database throughput show \
       --account-name your-cosmos-account \
       --resource-group your-resource-group \
       --name SupplyChainDB
   ```

4. **Logic App Permissions**
   ```bash
   # Verify managed identity assignment
   az logic workflow show \
       --name your-logic-app \
       --resource-group your-resource-group \
       --query "identity"
   ```

### Debug Mode

Enable verbose logging for deployments:

```bash
# Bicep with debug
az deployment sub create \
    --location eastus \
    --template-file main.bicep \
    --parameters @parameters.json \
    --debug

# Terraform with debug
export TF_LOG=DEBUG
terraform apply -var-file="terraform.tfvars"
```

## Cost Optimization

### Development Environment

- Use Cosmos DB serverless mode for low-volume testing
- Select API Management Consumption tier
- Configure Storage account lifecycle policies
- Use Azure Monitor free tier limits

### Production Environment

- Enable Cosmos DB autoscale
- Use API Management Standard/Premium for SLA requirements
- Configure geo-replication based on business needs
- Implement proper resource tagging for cost allocation

### Cost Monitoring

```bash
# View current month costs
az consumption usage list \
    --billing-period-name 202401 \
    --query "[?contains(instanceName, 'your-resource-prefix')]" \
    --output table

# Set up budget alerts
az consumption budget create \
    --account-id "/subscriptions/your-subscription-id" \
    --budget-name supply-chain-budget \
    --amount 500 \
    --category Cost \
    --time-grain Monthly \
    --start-date 2024-01-01 \
    --end-date 2024-12-31
```

## Advanced Configuration

### Multi-Region Deployment

For production deployments across multiple regions:

```bash
# Deploy to additional regions
az deployment sub create \
    --location westus2 \
    --template-file main.bicep \
    --parameters @parameters-westus2.json

# Configure Cosmos DB multi-region writes
az cosmosdb update \
    --name your-cosmos-account \
    --resource-group your-resource-group \
    --locations regionName=eastus failoverPriority=0 \
                regionName=westus2 failoverPriority=1 \
    --enable-multiple-write-locations true
```

### Custom Domain Configuration

```bash
# Configure custom domain for API Management
az apim update \
    --service-name your-apim-name \
    --resource-group your-resource-group \
    --set hostnameConfigurations[0].hostName=api.yourdomain.com \
         hostnameConfigurations[0].certificateSource=Custom
```

## Support

For issues with this infrastructure code:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review the original recipe documentation
3. Consult Azure service documentation:
   - [Azure Confidential Ledger](https://docs.microsoft.com/en-us/azure/confidential-ledger/)
   - [Azure Cosmos DB](https://docs.microsoft.com/en-us/azure/cosmos-db/)
   - [Azure Logic Apps](https://docs.microsoft.com/en-us/azure/logic-apps/)
   - [Azure Event Grid](https://docs.microsoft.com/en-us/azure/event-grid/)
   - [Azure API Management](https://docs.microsoft.com/en-us/azure/api-management/)
4. Check Azure service health and known issues
5. Contact Azure support for service-specific issues

## Additional Resources

- [Azure Confidential Computing](https://docs.microsoft.com/en-us/azure/confidential-computing/)
- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Supply Chain Security Best Practices](https://docs.microsoft.com/en-us/azure/security/fundamentals/supply-chain)
- [Blockchain Development on Azure](https://docs.microsoft.com/en-us/azure/blockchain/)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update parameter files and documentation
3. Validate all deployment options (Bicep, Terraform, Scripts)
4. Update cost estimates if resource configuration changes
5. Test cleanup procedures after modifications