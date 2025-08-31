# Infrastructure as Code for RAG Knowledge Base with AI Search and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "RAG Knowledge Base with AI Search and Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- Access to Azure OpenAI Service (requires approved access request)
- For Terraform: Terraform CLI installed (>= 1.0)
- For Bicep: Bicep CLI installed (latest version)

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-rag-kb-demo \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters uniqueSuffix=$(openssl rand -hex 3)
```

### Using Terraform

```bash
cd terraform/
terraform init
terraform plan -var="location=eastus" -var="unique_suffix=$(openssl rand -hex 3)"
terraform apply
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This IaC deploys the following Azure resources:

- **Azure Blob Storage**: Document repository with hierarchical namespace
- **Azure AI Search**: Intelligent indexing and retrieval service with semantic search
- **Azure OpenAI Service**: GPT-4o deployment for natural language generation
- **Azure Functions**: Serverless API layer for RAG query processing
- **Resource Group**: Container for all related resources

## Configuration Options

### Bicep Parameters

- `location`: Azure region for resource deployment (default: eastus)
- `uniqueSuffix`: Unique identifier for resource names (required)
- `openAiModel`: OpenAI model deployment (default: gpt-4o)
- `searchSku`: AI Search service tier (default: basic)

### Terraform Variables

- `location`: Azure region for resource deployment
- `unique_suffix`: Unique identifier for resource names
- `openai_model_name`: OpenAI model deployment name
- `search_sku`: AI Search service tier
- `function_app_os_type`: Function App OS type (default: Linux)

## Post-Deployment Steps

After infrastructure deployment, complete these manual steps:

1. **Upload Sample Documents**:
   ```bash
   # Get storage account name from deployment outputs
   STORAGE_ACCOUNT="<storage-account-name>"
   
   # Create and upload sample documents
   az storage blob upload \
       --file sample-document.txt \
       --name "sample-document.txt" \
       --container-name documents \
       --account-name $STORAGE_ACCOUNT
   ```

2. **Deploy Function Code**:
   ```bash
   # Get function app name from deployment outputs
   FUNCTION_APP="<function-app-name>"
   
   # Deploy the RAG query function
   cd ../function-code/
   zip -r function-package.zip .
   az functionapp deployment source config-zip \
       --name $FUNCTION_APP \
       --resource-group $RESOURCE_GROUP \
       --src function-package.zip
   ```

3. **Verify Search Index**:
   ```bash
   # Check that the search indexer has processed documents
   az search index show \
       --service-name "<search-service-name>" \
       --name "knowledge-base-index"
   ```

## Testing the Deployment

Test your RAG knowledge base API:

```bash
# Get function URL and key from deployment outputs
FUNCTION_URL="<function-app-url>"
FUNCTION_KEY="<function-key>"

# Test the RAG API
curl -X POST "${FUNCTION_URL}/api/rag_query?code=${FUNCTION_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "query": "What are the key features of Azure Functions?"
    }'
```

## Monitoring and Observability

The deployment includes:

- **Application Insights**: Function performance monitoring
- **Search Service Metrics**: Index and query performance
- **Storage Analytics**: Document access patterns
- **OpenAI Usage Metrics**: Token consumption and costs

Access monitoring dashboards through the Azure portal.

## Security Features

- **Managed Identity**: Secure service-to-service authentication
- **Private Endpoints**: Network isolation for sensitive resources (configurable)
- **RBAC**: Role-based access control for all resources
- **Key Vault Integration**: Secure storage of API keys and secrets
- **Function-level Authentication**: API key protection for function endpoints

## Cost Optimization

- **Consumption Plan**: Pay-per-execution for Azure Functions
- **Basic Search Tier**: Cost-effective for development and small workloads
- **Blob Storage Lifecycle**: Automatic data tiering for cost savings
- **Reserved Capacity**: Consider for production OpenAI usage

Estimated monthly costs for moderate usage:
- Azure Functions: $0-50 (consumption-based)
- AI Search Basic: ~$250
- OpenAI Service: Variable based on token usage
- Blob Storage: ~$5-20

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-rag-kb-demo --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Customization

### Adding Document Types

To support additional document formats:

1. Update the search indexer skillset in your IaC
2. Add Azure AI Document Intelligence for PDF/Office documents
3. Configure custom field mappings for new content types

### Scaling for Production

For production deployments, consider:

1. **Premium Search Tier**: Higher performance and SLA
2. **Premium Functions Plan**: Dedicated compute and VNET integration
3. **Multi-region Deployment**: Global availability and disaster recovery
4. **CDN Integration**: Cached responses for common queries

### Advanced Features

Extend the solution with:

1. **Vector Search**: Add embedding generation and vector fields
2. **Conversation Memory**: Integrate Azure Cosmos DB for chat history
3. **Authentication**: Add Azure AD integration
4. **API Management**: Rate limiting and API gateway features

## Troubleshooting

### Common Issues

1. **OpenAI Access Denied**: Ensure Azure OpenAI access is approved
2. **Search Indexing Failures**: Check blob storage permissions
3. **Function Deployment Errors**: Verify Python runtime version compatibility
4. **High Latency**: Monitor OpenAI token usage and search query complexity

### Debug Commands

```bash
# Check function logs
az functionapp logs tail --name $FUNCTION_APP --resource-group $RESOURCE_GROUP

# Monitor search indexer status
az search indexer status --service-name $SEARCH_SERVICE --name blob-indexer

# Validate OpenAI deployment
az cognitiveservices account deployment show \
    --name $OPENAI_SERVICE \
    --resource-group $RESOURCE_GROUP \
    --deployment-name gpt-4o
```

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for implementation guidance
2. Review Azure service documentation for specific resource configurations
3. Consult Azure support for service-specific issues
4. Use Azure Resource Health for service status updates

## Contributing

When modifying this IaC:

1. Test changes in a development environment
2. Update parameter documentation
3. Validate security configurations
4. Update cost estimates
5. Test cleanup procedures

## Version History

- **v1.0**: Initial implementation with basic RAG functionality
- **v1.1**: Added semantic search and improved error handling
- **Latest**: Enhanced security and monitoring capabilities