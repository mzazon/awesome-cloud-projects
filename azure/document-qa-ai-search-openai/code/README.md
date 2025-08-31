# Infrastructure as Code for Document Q&A with AI Search and OpenAI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Document Q&A with AI Search and OpenAI". This solution creates an intelligent document question-answering system using Azure AI Search for semantic vector indexing, Azure OpenAI Service for natural language understanding, and Azure Functions for serverless orchestration.

## Available Implementations

- **Bicep**: Azure's recommended infrastructure as code language
- **Terraform**: Multi-cloud infrastructure as code using Azure Provider
- **Scripts**: Bash deployment and cleanup scripts with Azure CLI

## Architecture Overview

The solution deploys:
- Azure Storage Account with blob container for document storage
- Azure OpenAI Service with text-embedding-3-large and GPT-4o model deployments
- Azure AI Search service with vector search capabilities
- Search index, skillset, data source, and indexer for document processing
- Azure Functions app with Python runtime for Q&A API
- Sample documents for testing the system

## Prerequisites

### General Requirements
- Azure CLI installed and configured (version 2.66.0 or later)
- Azure subscription with appropriate permissions:
  - Cognitive Services OpenAI Contributor
  - Storage Account Contributor
  - Search Service Contributor
  - Function App Contributor
- Basic knowledge of REST APIs and JSON document structures
- Understanding of vector embeddings and semantic search concepts

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension (automatically installed with latest Azure CLI)
- PowerShell or Bash shell

#### For Terraform
- Terraform CLI (version 1.0 or later)
- Azure Provider for Terraform

#### For Bash Scripts
- Bash shell (Linux, macOS, or Windows Subsystem for Linux)
- `openssl` command for generating random values
- `jq` command for JSON processing

### Azure OpenAI Service Availability

> **Important**: Azure OpenAI Service availability varies by region. Ensure your chosen region supports both text-embedding-3-large and GPT-4o models. Recommended regions: East US, East US 2, or West Europe.

### Cost Considerations

Estimated cost for testing resources: $20-40 (varies by usage and region)
- Azure AI Search (Basic tier): ~$250/month
- Azure OpenAI Service: Pay-per-use based on tokens
- Azure Functions: Consumption plan (pay-per-execution)
- Azure Storage: Minimal cost for document storage

## Quick Start

### Using Bicep

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-docqa-demo" \
    --template-file main.bicep \
    --parameters location="eastus" \
    --parameters projectName="docqa$(openssl rand -hex 3)"

# The deployment will output the Function App URL and keys needed for testing
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="location=eastus" -var="project_name=docqa$(openssl rand -hex 3)"

# Deploy the infrastructure
terraform apply -var="location=eastus" -var="project_name=docqa$(openssl rand -hex 3)"

# Note the outputs for testing the solution
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# The script will:
# - Create all Azure resources
# - Upload sample documents
# - Configure AI Search with vector indexing
# - Deploy the Q&A function code
# - Provide testing instructions
```

## Testing the Deployed Solution

After deployment, test the Q&A system:

### 1. Verify Search Index Population

Wait 2-3 minutes for document indexing to complete, then check:

```bash
# Get the search service name from deployment outputs
SEARCH_SERVICE="<your-search-service-name>"
SEARCH_ADMIN_KEY="<your-search-admin-key>"

# Check indexer status
curl -X GET "https://${SEARCH_SERVICE}.search.windows.net/indexers/documents-indexer/status?api-version=2024-07-01" \
     -H "api-key: ${SEARCH_ADMIN_KEY}"
```

### 2. Test the Q&A Function

```bash
# Get function URL and key from deployment outputs
FUNCTION_URL="<your-function-url>/api/qa"
FUNCTION_KEY="<your-function-key>"

# Test with a sample question
curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
     -H "Content-Type: application/json" \
     -d '{
       "question": "What capabilities does Azure AI Search provide for vector search?"
     }'
```

Expected response:
```json
{
  "answer": "Azure AI Search provides vector search capabilities that enable semantic similarity matching...",
  "sources": ["azure-ai-search-overview.txt"],
  "confidence": "high"
}
```

### 3. Upload Additional Documents

```bash
# Upload your own documents to test
STORAGE_ACCOUNT="<your-storage-account>"
STORAGE_KEY="<your-storage-key>"

az storage blob upload \
    --file "your-document.pdf" \
    --name "your-document.pdf" \
    --container-name "documents" \
    --account-name ${STORAGE_ACCOUNT} \
    --account-key ${STORAGE_KEY}

# Wait 5-10 minutes for automatic indexing
```

## Customization

### Key Configuration Options

#### Bicep Parameters
- `location`: Azure region for deployment
- `projectName`: Unique project identifier (affects all resource names)
- `openAiModelDeployments`: OpenAI model configurations
- `searchServiceSku`: AI Search service tier (Basic, Standard, etc.)

#### Terraform Variables
- `location`: Azure region for deployment
- `project_name`: Unique project identifier
- `resource_group_name`: Custom resource group name
- `storage_replication_type`: Storage account replication (LRS, ZRS, GRS)
- `function_runtime_version`: Python runtime version

#### Environment Variables (Bash Scripts)
```bash
# Set before running deploy.sh
export LOCATION="eastus"
export RESOURCE_GROUP="rg-docqa-custom"
export PROJECT_NAME="mydocqa"
```

### Advanced Customization

#### Model Configuration
To use different OpenAI models, update the deployment configurations:
- Change embedding model: Update skillset and vectorizer settings
- Modify chat model: Update function app settings and code
- Adjust model capacity: Modify SKU capacity in deployments

#### Search Configuration
- **Index Schema**: Modify field definitions for custom metadata
- **Vectorization**: Adjust embedding dimensions and algorithm parameters
- **Skillset**: Add custom skills for specialized document processing

#### Function Configuration
- **Runtime**: Change Python version or switch to other supported runtimes
- **Scaling**: Configure consumption plan limits or switch to dedicated plans
- **Authentication**: Implement custom authentication and authorization

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name "rg-docqa-demo" --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

The destroy script will:
- Remove all Azure resources
- Clean up local files
- Confirm successful deletion

## Troubleshooting

### Common Issues

#### Model Availability Errors
- **Issue**: "Model not available in region"
- **Solution**: Deploy to a region that supports both required models (eastus, eastus2, westeurope)

#### Indexing Failures
- **Issue**: Documents not appearing in search results
- **Solution**: 
  - Check indexer status using the provided curl commands
  - Verify storage account permissions
  - Ensure documents are in supported formats (PDF, DOCX, TXT)

#### Function App Errors
- **Issue**: Q&A function returns 500 errors
- **Solution**:
  - Check Function App logs in Azure Portal
  - Verify all app settings are configured correctly
  - Ensure OpenAI deployments are active

### Monitoring and Logging

Enable detailed monitoring:

```bash
# Enable Application Insights for Function App
az monitor app-insights component create \
    --app "docqa-insights" \
    --location "eastus" \
    --resource-group "rg-docqa-demo" \
    --application-type web

# Link to Function App
az functionapp config appsettings set \
    --name "func-docqa-demo" \
    --resource-group "rg-docqa-demo" \
    --settings "APPINSIGHTS_INSTRUMENTATIONKEY=$(az monitor app-insights component show --app docqa-insights --resource-group rg-docqa-demo --query instrumentationKey -o tsv)"
```

### Performance Optimization

#### Cost Optimization
- Use Azure Reserved Instances for predictable workloads
- Implement query caching for frequently asked questions
- Monitor token usage and optimize prompt engineering
- Consider scaling down non-production environments

#### Performance Tuning
- Adjust search index refresh intervals based on document update frequency
- Optimize document chunking strategies for your content type
- Fine-tune vector search parameters (efSearch, efConstruction)
- Implement response caching for common queries

## Documentation References

- [Azure AI Search Vector Search](https://learn.microsoft.com/en-us/azure/search/vector-search-overview)
- [Azure OpenAI Service](https://learn.microsoft.com/en-us/azure/ai-services/openai/)
- [Azure Functions Python Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Azure service documentation
3. Refer to the original recipe documentation
4. Check Azure service health status
5. Review deployment logs and error messages

## Version Information

- **Recipe Version**: 1.1
- **Infrastructure Code Version**: 1.0
- **Azure CLI Minimum Version**: 2.66.0
- **Terraform Minimum Version**: 1.0
- **Bicep Version**: Latest (bundled with Azure CLI)

---

> **Note**: This infrastructure code implements the complete solution described in the "Document Q&A with AI Search and OpenAI" recipe. For detailed explanation of the architecture and concepts, refer to the recipe documentation.