# Infrastructure as Code for Hybrid Search Document Analysis with OpenAI and PostgreSQL

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hybrid Search Document Analysis with OpenAI and PostgreSQL".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2 installed and configured (or Azure Cloud Shell)
- Azure account with appropriate permissions to create:
  - Azure OpenAI Service resources
  - Azure Database for PostgreSQL Flexible Server
  - Azure AI Search services
  - Azure Functions and App Service Plans
  - Azure Storage accounts
  - Resource groups
- Azure OpenAI Service access (requires approval if not already granted)
- Basic understanding of document processing, vector embeddings, and search concepts
- Python 3.8+ for local development and testing

## Quick Start

### Using Bicep (Azure Native)

```bash
# Navigate to the bicep directory
cd bicep/

# Create a resource group
az group create --name rg-doc-analysis --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-doc-analysis \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters openAIAccountName=openai-doc-$(openssl rand -hex 3) \
    --parameters postgresServerName=postgres-doc-$(openssl rand -hex 3) \
    --parameters searchServiceName=search-doc-$(openssl rand -hex 3) \
    --parameters functionAppName=func-doc-$(openssl rand -hex 3) \
    --parameters storageAccountName=storage$(openssl rand -hex 3)
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This solution deploys a comprehensive hybrid search system that combines:

- **Azure OpenAI Service**: Generates semantic embeddings for document content
- **PostgreSQL with pgvector**: Stores documents and enables vector similarity search
- **Azure AI Search**: Provides full-text search capabilities with advanced ranking
- **Azure Functions**: Orchestrates document processing and search operations
- **Azure Storage**: Supports function app deployment and document storage

## Configuration Options

### Bicep Parameters

Edit the `main.bicep` file or create a parameters file to customize:

- `location`: Azure region for resource deployment
- `openAIAccountName`: Name for the Azure OpenAI service
- `postgresServerName`: Name for the PostgreSQL server
- `searchServiceName`: Name for the Azure AI Search service
- `functionAppName`: Name for the Azure Functions app
- `storageAccountName`: Name for the storage account
- `postgresAdminPassword`: Password for PostgreSQL admin user

### Terraform Variables

Edit `terraform.tfvars` or use command line variables:

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << 'EOF'
resource_group_name = "rg-doc-analysis"
location = "eastus"
openai_account_name = "openai-doc-unique"
postgres_server_name = "postgres-doc-unique"
search_service_name = "search-doc-unique"
function_app_name = "func-doc-unique"
storage_account_name = "storageunique"
postgres_admin_password = "ComplexPassword123!"
EOF
```

## Post-Deployment Setup

After deploying the infrastructure, complete these steps:

1. **Deploy the embedding model**:
   ```bash
   az cognitiveservices account deployment create \
       --name YOUR_OPENAI_ACCOUNT_NAME \
       --resource-group YOUR_RESOURCE_GROUP \
       --deployment-name text-embedding-ada-002 \
       --model-name text-embedding-ada-002 \
       --model-version "2" \
       --model-format OpenAI \
       --sku-capacity 10 \
       --sku-name Standard
   ```

2. **Initialize the database schema**:
   ```bash
   # Connect to PostgreSQL and create the schema
   psql "host=YOUR_POSTGRES_SERVER.postgres.database.azure.com port=5432 dbname=postgres user=adminuser password=YOUR_PASSWORD sslmode=require" -c "
   CREATE EXTENSION IF NOT EXISTS vector;
   CREATE TABLE IF NOT EXISTS documents (
       id SERIAL PRIMARY KEY,
       title VARCHAR(500) NOT NULL,
       content TEXT NOT NULL,
       file_path VARCHAR(1000),
       content_type VARCHAR(100),
       embedding vector(1536),
       created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
       updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
   );
   CREATE INDEX IF NOT EXISTS idx_documents_embedding ON documents USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
   CREATE INDEX IF NOT EXISTS idx_documents_content_fts ON documents USING gin(to_tsvector('english', content));
   "
   ```

3. **Create the Azure AI Search index**:
   ```bash
   # Create search index (replace with your service name and key)
   curl -X PUT \
       "https://YOUR_SEARCH_SERVICE.search.windows.net/indexes/documents-index?api-version=2023-11-01" \
       -H "Content-Type: application/json" \
       -H "api-key: YOUR_SEARCH_KEY" \
       -d '{
           "name": "documents-index",
           "fields": [
               {"name": "id", "type": "Edm.String", "key": true, "searchable": false, "filterable": true, "sortable": true},
               {"name": "title", "type": "Edm.String", "searchable": true, "filterable": true, "sortable": true, "analyzer": "standard.lucene"},
               {"name": "content", "type": "Edm.String", "searchable": true, "filterable": false, "sortable": false, "analyzer": "standard.lucene"},
               {"name": "contentType", "type": "Edm.String", "searchable": false, "filterable": true, "sortable": true},
               {"name": "createdAt", "type": "Edm.DateTimeOffset", "searchable": false, "filterable": true, "sortable": true}
           ]
       }'
   ```

## Testing the Deployment

1. **Test document processing**:
   ```bash
   # Test the document processing function
   curl -X POST \
       "https://YOUR_FUNCTION_APP.azurewebsites.net/api/process_document" \
       -H "Content-Type: application/json" \
       -d '{
           "title": "Test Document",
           "content": "This is a test document for the hybrid search system.",
           "content_type": "text/plain"
       }'
   ```

2. **Test hybrid search**:
   ```bash
   # Test the hybrid search function
   curl -X POST \
       "https://YOUR_FUNCTION_APP.azurewebsites.net/api/hybrid_search" \
       -H "Content-Type: application/json" \
       -d '{
           "query": "test document search",
           "top_k": 5
       }'
   ```

## Monitoring and Troubleshooting

- **Monitor function execution**: Use Azure Monitor to track function performance and errors
- **Check PostgreSQL logs**: Monitor database performance and query execution
- **Review search analytics**: Use Azure AI Search analytics to optimize search performance
- **OpenAI usage tracking**: Monitor token usage and costs through Azure OpenAI metrics

## Security Considerations

The deployed infrastructure includes:

- **Network security**: Firewall rules and private endpoints where applicable
- **Identity and access management**: Managed identities for secure service-to-service communication
- **Data encryption**: Encryption at rest and in transit for all data stores
- **Key management**: Secure storage of API keys and connection strings

## Cost Optimization

- **Azure OpenAI**: Costs based on token usage for embeddings
- **PostgreSQL**: Consider scaling down during off-peak hours
- **Azure AI Search**: Monitor search unit usage and adjust as needed
- **Azure Functions**: Consumption plan scales automatically with usage

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name rg-doc-analysis --yes --no-wait
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

### Adding New Document Types

To support additional document types, modify the Azure Functions code to include:

1. **Document parsers**: Add support for PDF, Word, and other formats
2. **Content extractors**: Integrate with Azure Form Recognizer for complex documents
3. **Preprocessing pipelines**: Add text cleaning and normalization steps

### Scaling Considerations

For production deployments, consider:

1. **PostgreSQL scaling**: Use higher-tier instances for better performance
2. **Search service scaling**: Increase search units for higher query volumes
3. **Function app scaling**: Configure appropriate scaling rules for processing load
4. **Embedding model scaling**: Increase deployment capacity for higher throughput

### Advanced Features

Extend the solution with:

1. **Multi-language support**: Add language detection and language-specific processing
2. **Document versioning**: Track document changes and maintain version history
3. **Access controls**: Implement user-based access controls for documents
4. **Analytics dashboard**: Add reporting and analytics for search patterns

## Support

For issues with this infrastructure code:

1. **Azure-specific issues**: Refer to [Azure documentation](https://docs.microsoft.com/azure/)
2. **OpenAI integration**: Check [Azure OpenAI Service documentation](https://learn.microsoft.com/azure/ai-services/openai/)
3. **PostgreSQL issues**: Review [Azure Database for PostgreSQL documentation](https://learn.microsoft.com/azure/postgresql/)
4. **Search service issues**: Consult [Azure AI Search documentation](https://learn.microsoft.com/azure/search/)

## Additional Resources

- [Azure OpenAI Service pricing](https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/)
- [PostgreSQL pgvector extension](https://github.com/pgvector/pgvector)
- [Azure AI Search vector search](https://learn.microsoft.com/azure/search/vector-search-overview)
- [Azure Functions best practices](https://learn.microsoft.com/azure/azure-functions/functions-best-practices)