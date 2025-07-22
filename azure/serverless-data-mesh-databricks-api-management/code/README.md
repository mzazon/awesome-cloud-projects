# Infrastructure as Code for Serverless Data Mesh with Databricks and API Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless Data Mesh with Databricks and API Management".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.40 or later installed and configured
- Azure subscription with Owner or Contributor access
- Appropriate permissions for creating:
  - Azure Databricks workspaces
  - Azure API Management instances
  - Azure Key Vault
  - Azure Event Grid topics
  - Azure AD service principals
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed

## Architecture Overview

This solution deploys a decentralized data mesh architecture including:

- **Azure Databricks Workspace** with Unity Catalog for distributed data processing
- **Azure API Management** (Consumption tier) for serverless API governance
- **Azure Key Vault** for secure credential management
- **Azure Event Grid** for real-time data product events
- **Service Principal** for secure authentication
- **Sample data product APIs** with governance policies

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-data-mesh-demo \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters publisherName="DataMeshTeam" \
    --parameters publisherEmail="datamesh@example.com"

# Get deployment outputs
az deployment group show \
    --resource-group rg-data-mesh-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review deployment plan
terraform plan \
    -var="location=eastus" \
    -var="publisher_name=DataMeshTeam" \
    -var="publisher_email=datamesh@example.com"

# Apply configuration
terraform apply \
    -var="location=eastus" \
    -var="publisher_name=DataMeshTeam" \
    -var="publisher_email=datamesh@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-data-mesh-demo"
export LOCATION="eastus"
export PUBLISHER_NAME="DataMeshTeam"
export PUBLISHER_EMAIL="datamesh@example.com"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment summary
./scripts/deploy.sh --status
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | Yes |
| `resourceGroupName` | Name of the resource group | `rg-data-mesh-demo` | Yes |
| `publisherName` | API Management publisher name | `DataMeshTeam` | Yes |
| `publisherEmail` | API Management publisher email | N/A | Yes |
| `databricksWorkspaceName` | Name for Databricks workspace | Auto-generated | No |
| `apimServiceName` | Name for API Management service | Auto-generated | No |
| `keyVaultName` | Name for Key Vault | Auto-generated | No |
| `eventGridTopicName` | Name for Event Grid topic | Auto-generated | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `location` | Azure region | `string` | `eastus` | Yes |
| `resource_group_name` | Resource group name | `string` | `rg-data-mesh-demo` | Yes |
| `publisher_name` | API Management publisher | `string` | N/A | Yes |
| `publisher_email` | Publisher email address | `string` | N/A | Yes |
| `databricks_sku` | Databricks workspace SKU | `string` | `premium` | No |
| `apim_sku` | API Management SKU | `string` | `Consumption` | No |
| `enable_rbac` | Enable RBAC for Key Vault | `bool` | `true` | No |
| `tags` | Resource tags | `map(string)` | `{}` | No |

### Environment Variables (Bash Scripts)

| Variable | Description | Required |
|----------|-------------|----------|
| `RESOURCE_GROUP` | Resource group name | Yes |
| `LOCATION` | Azure region | Yes |
| `PUBLISHER_NAME` | API Management publisher name | Yes |
| `PUBLISHER_EMAIL` | Publisher email address | Yes |
| `SUBSCRIPTION_ID` | Azure subscription ID | Auto-detected |

## Deployment Outputs

After successful deployment, you'll receive:

- **Databricks Workspace URL**: Access URL for the Databricks workspace
- **API Management Gateway URL**: Base URL for accessing data product APIs
- **Key Vault Name**: Name of the created Key Vault for secret management
- **Event Grid Topic Endpoint**: Endpoint for publishing data product events
- **Service Principal Details**: Application ID for authentication
- **Sample API Subscription Key**: Key for testing data product APIs

## Post-Deployment Configuration

### 1. Configure Unity Catalog

```bash
# Access your Databricks workspace
DATABRICKS_URL=$(az databricks workspace show \
    --name ${DATABRICKS_WORKSPACE_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query workspaceUrl --output tsv)

echo "Access Databricks at: https://${DATABRICKS_URL}"

# Upload and run the sample notebook provided in the recipe
```

### 2. Test API Management

```bash
# Get API Management details
APIM_URL=$(az apim show \
    --name ${APIM_SERVICE_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query gatewayUrl --output tsv)

# Test the sample API endpoint
curl -X GET "${APIM_URL}/customer-analytics/metrics?dateFrom=2024-01-01" \
    -H "Ocp-Apim-Subscription-Key: ${SUBSCRIPTION_KEY}"
```

### 3. Verify Event Grid

```bash
# List Event Grid subscriptions
az eventgrid event-subscription list \
    --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
    --output table
```

## Customization

### Adding New Data Products

1. **Create new API definitions**: Add OpenAPI specifications for your domain-specific data products
2. **Import APIs**: Use Azure CLI or Terraform to import APIs into API Management
3. **Configure policies**: Apply governance policies for authentication, rate limiting, and caching
4. **Set up monitoring**: Configure Azure Monitor for API usage tracking

### Scaling for Production

1. **Upgrade API Management**: Change from Consumption to Standard/Premium tier for production workloads
2. **Multi-region deployment**: Deploy across multiple Azure regions for high availability
3. **Network isolation**: Configure VNet integration for secure network access
4. **Advanced security**: Implement OAuth 2.0, client certificates, and IP filtering

### Cost Optimization

1. **Serverless compute**: Leverage Databricks serverless SQL warehouses and compute
2. **API Management tiers**: Use Consumption tier for variable workloads
3. **Event Grid pricing**: Optimize for event volume and delivery requirements
4. **Storage optimization**: Implement Delta Lake optimization techniques

## Monitoring and Observability

### Azure Monitor Integration

```bash
# Enable diagnostics for API Management
az monitor diagnostic-settings create \
    --name apim-diagnostics \
    --resource ${APIM_RESOURCE_ID} \
    --workspace ${LOG_ANALYTICS_WORKSPACE_ID} \
    --logs '[{"category":"GatewayLogs","enabled":true}]'

# Enable diagnostics for Databricks
az monitor diagnostic-settings create \
    --name databricks-diagnostics \
    --resource ${DATABRICKS_RESOURCE_ID} \
    --workspace ${LOG_ANALYTICS_WORKSPACE_ID} \
    --logs '[{"category":"clusters","enabled":true}]'
```

### Key Metrics to Monitor

- API Gateway response times and error rates
- Databricks cluster utilization and job performance
- Event Grid delivery success rates
- Key Vault access patterns and security events

## Security Considerations

### Authentication and Authorization

- **Azure AD Integration**: APIs are secured with Azure AD JWT validation
- **RBAC**: Key Vault uses Role-Based Access Control
- **Service Principal**: Secure authentication for Databricks operations
- **API Subscriptions**: Subscription keys for API access control

### Data Protection

- **Encryption**: All data is encrypted at rest and in transit
- **Network Security**: Private endpoints available for production deployments
- **Secrets Management**: Sensitive credentials stored in Key Vault
- **Access Policies**: Least privilege access patterns implemented

## Troubleshooting

### Common Issues

1. **API Management provisioning timeout**
   - Solution: API Management deployment can take 30-45 minutes
   - Check deployment status with `az deployment group show`

2. **Databricks workspace access issues**
   - Solution: Verify service principal permissions
   - Check Azure AD role assignments

3. **Event Grid delivery failures**
   - Solution: Validate webhook endpoints
   - Check Event Grid topic access keys

4. **Key Vault access denied**
   - Solution: Verify RBAC permissions
   - Check service principal role assignments

### Debugging Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main \
    --query properties.provisioningState

# View API Management logs
az monitor activity-log list \
    --resource-group ${RESOURCE_GROUP} \
    --resource-type Microsoft.ApiManagement/service

# Test connectivity
az network test-connectivity \
    --source-resource ${SOURCE_RESOURCE_ID} \
    --dest-resource ${DEST_RESOURCE_ID}
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-data-mesh-demo \
    --yes \
    --no-wait

# Or delete specific deployment
az deployment group delete \
    --resource-group rg-data-mesh-demo \
    --name main
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="location=eastus" \
    -var="publisher_name=DataMeshTeam" \
    -var="publisher_email=datamesh@example.com"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
./scripts/destroy.sh --verify
```

## Cost Estimation

### Monthly Cost Breakdown (USD)

| Service | Configuration | Estimated Cost |
|---------|---------------|----------------|
| Azure Databricks | Premium SKU, minimal usage | $40-60 |
| API Management | Consumption tier | $3-5 per million calls |
| Key Vault | Standard tier | $3-5 |
| Event Grid | Standard tier | $0.60 per million events |
| **Total** | **Minimal usage** | **$50-75** |

> **Note**: Costs vary based on usage patterns, region, and specific configurations. Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for accurate estimates.

## Additional Resources

- [Azure Databricks Documentation](https://docs.microsoft.com/azure/databricks/)
- [Azure API Management Documentation](https://docs.microsoft.com/azure/api-management/)
- [Data Mesh Architecture Guide](https://docs.microsoft.com/azure/architecture/reference-architectures/data/data-mesh)
- [Unity Catalog Documentation](https://docs.microsoft.com/azure/databricks/data-governance/unity-catalog/)
- [Azure Event Grid Documentation](https://docs.microsoft.com/azure/event-grid/)

## Support

For issues with this infrastructure code:

1. Check the [troubleshooting section](#troubleshooting) above
2. Refer to the original recipe documentation
3. Consult Azure service documentation
4. Review Azure service health and status pages

## Contributing

When modifying this infrastructure code:

1. Follow Azure naming conventions
2. Update parameter descriptions
3. Add appropriate resource tags
4. Test deployments in development environment
5. Update this README with changes