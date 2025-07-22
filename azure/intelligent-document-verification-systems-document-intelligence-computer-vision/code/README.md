# Infrastructure as Code for Intelligent Document Verification Systems with Azure Document Intelligence and Azure Computer Vision

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Document Verification Systems with Azure Document Intelligence and Azure Computer Vision".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a complete document verification system consisting of:

- **Azure Document Intelligence**: Pre-trained AI models for identity document processing
- **Azure Computer Vision**: Advanced image analysis for authenticity verification
- **Azure Functions**: Serverless processing logic and business rules
- **Azure Logic Apps**: Workflow orchestration and automation
- **Azure Cosmos DB**: Audit trail and verification results storage
- **Azure Storage Account**: Document storage and processing pipeline
- **Azure API Management**: Enterprise-grade API security and monitoring

## Prerequisites

- Azure CLI installed and configured (`az --version` >= 2.50.0)
- Azure subscription with appropriate permissions for:
  - Cognitive Services (Document Intelligence, Computer Vision)
  - Function Apps and App Service Plans
  - Logic Apps
  - Cosmos DB
  - Storage Accounts
  - API Management (optional)
- For Terraform: Terraform CLI installed (`terraform --version` >= 1.0)
- For Bicep: Azure CLI with Bicep extension installed

### Required Azure Permissions

Your Azure identity needs the following RBAC roles:
- `Contributor` on the target resource group
- `Cognitive Services Contributor` for AI services
- `Storage Account Contributor` for blob storage
- `DocumentDB Account Contributor` for Cosmos DB

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Create resource group
az group create \
    --name "rg-docverify-demo" \
    --location "eastus"

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-docverify-demo" \
    --template-file main.bicep \
    --parameters @parameters.json \
    --parameters \
        location="eastus" \
        environment="demo" \
        resourcePrefix="docverify"

# Monitor deployment status
az deployment group show \
    --resource-group "rg-docverify-demo" \
    --name "main" \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Login to Azure
az login

# Review the deployment plan
terraform plan \
    -var="resource_group_name=rg-docverify-demo" \
    -var="location=eastus" \
    -var="environment=demo"

# Deploy the infrastructure
terraform apply \
    -var="resource_group_name=rg-docverify-demo" \
    -var="location=eastus" \
    -var="environment=demo"

# View deployed resources
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export AZURE_LOCATION="eastus"
export AZURE_RESOURCE_GROUP="rg-docverify-demo"
export AZURE_ENVIRONMENT="demo"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
az resource list \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --output table
```

## Configuration Options

### Bicep Parameters

Edit `bicep/parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "environment": {
      "value": "demo"
    },
    "resourcePrefix": {
      "value": "docverify"
    },
    "documentIntelligenceSku": {
      "value": "S0"
    },
    "computerVisionSku": {
      "value": "S1"
    },
    "cosmosDbThroughput": {
      "value": 400
    },
    "enableApiManagement": {
      "value": false
    }
  }
}
```

### Terraform Variables

Customize `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
resource_group_name = "rg-docverify-demo"
location           = "eastus"
environment        = "demo"
resource_prefix    = "docverify"

# AI Services Configuration
document_intelligence_sku = "S0"
computer_vision_sku       = "S1"

# Database Configuration
cosmos_db_throughput = 400

# Optional Components
enable_api_management = false
```

## Deployment Verification

After successful deployment, verify the resources:

```bash
# Check resource group contents
az resource list \
    --resource-group "rg-docverify-demo" \
    --output table

# Test Document Intelligence service
DOC_INTEL_ENDPOINT=$(az cognitiveservices account show \
    --name "docintel-demo-12345" \
    --resource-group "rg-docverify-demo" \
    --query "properties.endpoint" --output tsv)

echo "Document Intelligence endpoint: $DOC_INTEL_ENDPOINT"

# Test Computer Vision service
VISION_ENDPOINT=$(az cognitiveservices account show \
    --name "vision-demo-12345" \
    --resource-group "rg-docverify-demo" \
    --query "properties.endpoint" --output tsv)

echo "Computer Vision endpoint: $VISION_ENDPOINT"

# Test Function App
FUNCTION_URL=$(az functionapp show \
    --name "func-docverify-demo-12345" \
    --resource-group "rg-docverify-demo" \
    --query "defaultHostName" --output tsv)

echo "Function App URL: https://$FUNCTION_URL"

# Test Cosmos DB
az cosmosdb show \
    --name "cosmos-docverify-demo-12345" \
    --resource-group "rg-docverify-demo" \
    --query "provisioningState" --output tsv
```

## Testing the Document Verification System

Once deployed, test the system with a sample document:

```bash
# Get Function App details
FUNCTION_APP_NAME=$(az functionapp list \
    --resource-group "rg-docverify-demo" \
    --query "[0].name" --output tsv)

FUNCTION_KEY=$(az functionapp keys list \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "rg-docverify-demo" \
    --query "functionKeys.default" --output tsv)

FUNCTION_URL=$(az functionapp show \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "rg-docverify-demo" \
    --query "defaultHostName" --output tsv)

# Test the document verification endpoint
curl -X POST "https://$FUNCTION_URL/api/DocumentVerificationFunction" \
    -H "Content-Type: application/json" \
    -H "x-functions-key: $FUNCTION_KEY" \
    -d '{
        "document_url": "https://example.com/sample-id-document.jpg"
    }'
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name "rg-docverify-demo" \
    --yes \
    --no-wait

# Monitor deletion progress
az group show \
    --name "rg-docverify-demo" \
    --query "properties.provisioningState" \
    --output tsv 2>/dev/null || echo "Resource group deleted"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="resource_group_name=rg-docverify-demo" \
    -var="location=eastus" \
    -var="environment=demo"

# Clean up Terraform state
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Set required environment variables
export AZURE_RESOURCE_GROUP="rg-docverify-demo"

# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group show \
    --name "$AZURE_RESOURCE_GROUP" \
    --query "properties.provisioningState" \
    --output tsv 2>/dev/null || echo "Resource group deleted"
```

## Cost Estimation

Estimated monthly costs for development/testing environment:

- **Document Intelligence (S0)**: ~$15/month + $1-2 per 1,000 documents
- **Computer Vision (S1)**: ~$15/month + $1-2 per 1,000 images
- **Azure Functions (Consumption)**: ~$0-20/month depending on usage
- **Cosmos DB (400 RU/s)**: ~$24/month
- **Storage Account**: ~$1-5/month
- **Logic Apps**: ~$0-10/month depending on executions
- **API Management (Developer tier)**: ~$50/month (optional)

**Total estimated cost**: $55-130/month for development workloads

> **Note**: Costs vary significantly based on usage patterns, region, and enterprise agreements. Use the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/) for accurate estimates.

## Security Considerations

This deployment includes several security best practices:

- **Network Security**: Private endpoints for storage and database access
- **Identity and Access**: Managed identities for service-to-service authentication
- **Data Protection**: Encryption at rest and in transit for all data stores
- **API Security**: Function-level authentication and HTTPS enforcement
- **Monitoring**: Azure Monitor integration for security event tracking

### Additional Security Hardening

For production deployments, consider:

1. **Virtual Network Integration**: Deploy services in a dedicated VNet
2. **Azure Key Vault**: Store sensitive configuration in Key Vault
3. **Private Endpoints**: Use private endpoints for all PaaS services
4. **Azure Policy**: Implement governance policies for compliance
5. **Azure Sentinel**: Enable SIEM for advanced threat detection

## Customization

### Adding Custom Document Types

To support additional document types, modify the Function App code:

```python
# Add new document types to the processing logic
SUPPORTED_DOCUMENT_TYPES = [
    "prebuilt-idDocument",
    "prebuilt-businessCard",
    "prebuilt-invoice",
    "prebuilt-receipt"
]
```

### Scaling Configuration

For production workloads, adjust these parameters:

```json
{
  "cosmosDbThroughput": 4000,
  "documentIntelligenceSku": "S0",
  "computerVisionSku": "S1",
  "functionAppSku": "P1v2",
  "enableApiManagement": true
}
```

### Multi-Region Deployment

For global applications, consider deploying in multiple regions:

1. Deploy primary region with full services
2. Deploy secondary region with read replicas
3. Use Azure Front Door for global load balancing
4. Configure Cosmos DB global distribution

## Troubleshooting

### Common Issues

1. **Deployment Timeouts**: AI services can take 5-10 minutes to provision
2. **Permission Errors**: Ensure proper RBAC roles are assigned
3. **Quota Limits**: Check Azure subscription limits for cognitive services
4. **Function Deployment**: Verify storage account connectivity

### Debugging Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group "rg-docverify-demo" \
    --name "main"

# View Function App logs
az functionapp log tail \
    --name "func-docverify-demo-12345" \
    --resource-group "rg-docverify-demo"

# Check Cosmos DB connectivity
az cosmosdb sql database show \
    --account-name "cosmos-docverify-demo-12345" \
    --resource-group "rg-docverify-demo" \
    --name "DocumentVerification"
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../building-intelligent-document-verification-systems-with-azure-form-recognizer-and-azure-cognitive-services-computer-vision.md)
2. Review [Azure Documentation](https://docs.microsoft.com/azure/)
3. Consult [Azure Support](https://azure.microsoft.com/support/)
4. Check [Azure Service Health](https://status.azure.com/)

## Contributing

To improve this IaC implementation:

1. Follow Azure best practices and naming conventions
2. Test changes in a development environment
3. Update documentation for any parameter changes
4. Ensure cleanup scripts work correctly
5. Validate security configurations

## License

This infrastructure code is provided as-is under the same license as the parent recipe repository.