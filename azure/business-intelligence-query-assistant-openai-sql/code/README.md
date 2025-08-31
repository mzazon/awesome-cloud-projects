# Infrastructure as Code for Business Intelligence Query Assistant with Azure OpenAI and SQL Database

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Business Intelligence Query Assistant with Azure OpenAI and SQL Database".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login` completed)
- Azure subscription with Azure OpenAI Service access approved
- Appropriate permissions for resource creation (Contributor role or higher)
- Node.js 18+ for Function App development and deployment
- Azure Functions Core Tools v4 for local function development

> **Important**: Azure OpenAI Service requires special access approval. Submit a request through the Azure portal before beginning deployment.

## Resource Overview

This infrastructure creates:

- Azure OpenAI Service with GPT-4o model deployment
- Azure SQL Database with sample business data
- Azure Functions App for query processing
- Storage Account for Function App requirements
- Managed Identity for secure service-to-service authentication
- Application settings and security configurations

## Quick Start

### Using Bicep (Recommended)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy infrastructure
az deployment group create \
    --resource-group rg-bi-assistant \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters sqlAdminPassword="ComplexP@ssw0rd123!"

# Get deployment outputs
az deployment group show \
    --resource-group rg-bi-assistant \
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
terraform plan -var="location=eastus" \
    -var="sql_admin_password=ComplexP@ssw0rd123!"

# Apply infrastructure
terraform apply -var="location=eastus" \
    -var="sql_admin_password=ComplexP@ssw0rd123!" \
    -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export LOCATION="eastus"
export SQL_ADMIN_PASSWORD="ComplexP@ssw0rd123!"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment results
./scripts/deploy.sh --status
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | No |
| `resourcePrefix` | Prefix for resource names | `bi-assistant` | No |
| `sqlAdminPassword` | SQL Server admin password | None | Yes |
| `openaiSkuName` | OpenAI Service SKU | `S0` | No |
| `sqlDatabaseSku` | SQL Database SKU | `Basic` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | `eastus` | No |
| `resource_prefix` | Prefix for resource names | `bi-assistant` | No |
| `sql_admin_password` | SQL Server admin password | None | Yes |
| `openai_sku_name` | OpenAI Service SKU | `S0` | No |
| `sql_database_sku` | SQL Database SKU | `Basic` | No |

### Environment Variables (Bash Scripts)

| Variable | Description | Required |
|----------|-------------|----------|
| `LOCATION` | Azure region for deployment | Yes |
| `SQL_ADMIN_PASSWORD` | SQL Server admin password | Yes |
| `RESOURCE_PREFIX` | Prefix for resource names | No |

## Deployment Process

### 1. Infrastructure Deployment

The deployment process creates resources in this order:

1. Resource Group with appropriate tags
2. Azure OpenAI Service with cognitive services account
3. GPT-4o model deployment for natural language processing
4. Azure SQL Server with Azure AD authentication enabled
5. SQL Database with sample business schema and data
6. Storage Account for Function App requirements
7. Function App with Node.js 18 runtime
8. Application settings configuration
9. Managed Identity assignment and permissions

### 2. Function App Code Deployment

After infrastructure deployment, the Function App code must be deployed separately:

```bash
# Clone or download the function code
# Navigate to the function directory
cd ../function-code/

# Install dependencies
npm install

# Deploy to Azure using Azure Functions Core Tools
func azure functionapp publish <function-app-name>
```

### 3. Sample Data Population

The infrastructure automatically creates sample business tables:

- **Customers**: Company information with revenue data
- **Orders**: Transaction records with status tracking

## Validation & Testing

### 1. Verify Resource Deployment

```bash
# Check resource group contents
az group show --name rg-bi-assistant-<suffix>

# Verify OpenAI Service deployment
az cognitiveservices account show \
    --name openai-bi-<suffix> \
    --resource-group rg-bi-assistant-<suffix>

# Check SQL Database connectivity
az sql db show \
    --server sql-bi-server-<suffix> \
    --name BiAnalyticsDB \
    --resource-group rg-bi-assistant-<suffix>
```

### 2. Test Query Functionality

```bash
# Get Function App URL and access key
FUNCTION_URL=$(az functionapp show \
    --name func-bi-assistant-<suffix> \
    --resource-group rg-bi-assistant-<suffix> \
    --query defaultHostName --output tsv)

FUNCTION_KEY=$(az functionapp keys list \
    --name func-bi-assistant-<suffix> \
    --resource-group rg-bi-assistant-<suffix> \
    --query functionKeys.default --output tsv)

# Test natural language query
curl -X POST "https://${FUNCTION_URL}/api/QueryProcessor?code=${FUNCTION_KEY}" \
     -H "Content-Type: application/json" \
     -d '{"query": "Show me total revenue by country for all customers"}'
```

## Cleanup

### Using Bicep

```bash
# Delete resource group (removes all resources)
az group delete --name rg-bi-assistant-<suffix> --yes --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="location=eastus" \
    -var="sql_admin_password=ComplexP@ssw0rd123!" \
    -auto-approve
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm cleanup completion
./scripts/destroy.sh --verify
```

## Troubleshooting

### Common Issues

1. **Azure OpenAI Access Denied**
   - Ensure Azure OpenAI Service access is approved for your subscription
   - Submit access request through Azure portal if needed

2. **SQL Connection Issues**
   - Verify firewall rules allow Azure services
   - Check managed identity permissions
   - Confirm connection string format

3. **Function App Deployment Failures**
   - Ensure Azure Functions Core Tools v4 is installed
   - Verify Node.js 18+ is available
   - Check application settings configuration

4. **Model Deployment Errors**
   - Confirm GPT-4o model availability in selected region
   - Verify OpenAI Service quota limits
   - Check deployment capacity settings

### Debug Commands

```bash
# Check Function App logs
az functionapp log tail --name func-bi-assistant-<suffix> \
    --resource-group rg-bi-assistant-<suffix>

# Monitor OpenAI Service usage
az monitor metrics list \
    --resource openai-bi-<suffix> \
    --resource-group rg-bi-assistant-<suffix> \
    --resource-type Microsoft.CognitiveServices/accounts

# Verify SQL Database performance
az sql db show-usage \
    --server sql-bi-server-<suffix> \
    --name BiAnalyticsDB \
    --resource-group rg-bi-assistant-<suffix>
```

## Security Considerations

### Implemented Security Features

- **Managed Identity**: Eliminates credential storage in code
- **Azure AD Authentication**: Secure service-to-service communication
- **SQL Query Validation**: Prevents SQL injection attacks
- **Encrypted Communication**: HTTPS/TLS for all service communications
- **Access Keys**: Function-level authentication for API access

### Security Best Practices

1. **Password Management**: Use Azure Key Vault for production passwords
2. **Network Security**: Implement Virtual Network integration for production
3. **Monitoring**: Enable Application Insights for security monitoring
4. **Access Control**: Use Azure RBAC for granular permissions
5. **Data Protection**: Enable Advanced Threat Protection for SQL Database

## Cost Optimization

### Resource Costs (Estimated Monthly)

- Azure OpenAI Service: $10-15 (based on query volume)
- Azure SQL Database (Basic): $5
- Azure Functions (Consumption): $2-5 (based on executions)
- Storage Account: $1-2

### Cost Management Tips

1. Use consumption-based pricing for Functions
2. Monitor OpenAI API usage and set budgets
3. Consider reserved capacity for predictable workloads
4. Implement query caching to reduce API calls
5. Use Basic SQL tier for development/testing

## Customization

### Adding Business Data

Modify the SQL initialization scripts to include your business schema:

```sql
-- Add your tables in the deployment scripts
CREATE TABLE YourBusinessTable (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    -- Your columns here
);
```

### Extending Query Capabilities

Enhance the Function App code to support:

- Additional database schemas
- Custom business logic
- Advanced AI prompt engineering
- Result formatting and visualization
- Integration with Power BI or other BI tools

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation
3. Verify all prerequisites are met
4. Monitor Azure service health status
5. Review Function App logs for detailed error information

## Additional Resources

- [Azure OpenAI Service Documentation](https://learn.microsoft.com/en-us/azure/cognitive-services/openai/)
- [Azure Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [Azure SQL Database Documentation](https://learn.microsoft.com/en-us/azure/sql-database/)
- [Bicep Language Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)