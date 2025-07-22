# Terraform Infrastructure for Hybrid Search Document Analysis with OpenAI and PostgreSQL

This Terraform configuration deploys a complete hybrid search document analysis solution on Azure, combining Azure OpenAI Service's embedding capabilities with PostgreSQL's pgvector extension and Azure AI Search.

## Architecture Overview

The infrastructure deploys the following Azure services:

- **Azure OpenAI Service**: Provides text embedding capabilities using the text-embedding-ada-002 model
- **Azure Database for PostgreSQL Flexible Server**: Stores documents and vector embeddings with pgvector extension
- **Azure AI Search**: Handles full-text search and indexing
- **Azure Functions**: Serverless compute for document processing and hybrid search APIs
- **Azure Storage Accounts**: Document storage and function app storage
- **Azure Key Vault**: Secure storage for connection strings and API keys
- **Azure Application Insights**: Monitoring and logging (optional)
- **Azure Virtual Network**: Private networking (optional)

## Prerequisites

- Azure CLI installed and configured
- Terraform >= 1.0 installed
- Azure subscription with appropriate permissions
- Azure OpenAI Service access (may require approval)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd azure/hybrid-search-document-analysis-openai-postgresql/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Variables

Copy the example terraform.tfvars file and customize for your environment:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your desired configuration:

```hcl
# Basic Configuration
resource_group_name = "rg-my-doc-analysis"
location = "East US"
environment = "dev"
project_name = "my-doc-search"

# PostgreSQL Configuration
postgresql_admin_password = "YourSecurePassword123!"

# Optional: Enable monitoring
enable_monitoring = true

# Optional: Enable private endpoints
enable_private_endpoints = false
```

### 4. Plan the Deployment

```bash
terraform plan
```

### 5. Deploy the Infrastructure

```bash
terraform apply
```

Confirm the deployment by typing `yes` when prompted.

## Configuration Variables

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `resource_group_name` | Name of the resource group | `"rg-doc-analysis"` |
| `location` | Azure region for resources | `"East US"` |
| `postgresql_admin_password` | Admin password for PostgreSQL | `"ComplexPassword123!"` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment tag | `"demo"` |
| `project_name` | Project name for resources | `"doc-analysis"` |
| `enable_monitoring` | Enable Application Insights | `true` |
| `enable_private_endpoints` | Enable private networking | `false` |
| `openai_deployment_capacity` | OpenAI deployment capacity | `10` |
| `postgresql_sku_name` | PostgreSQL server SKU | `"GP_Standard_D2s_v3"` |
| `search_sku` | Azure AI Search SKU | `"standard"` |

For a complete list of variables, see `variables.tf`.

## Outputs

After deployment, Terraform provides important outputs including:

- API endpoints for document processing and hybrid search
- Connection strings for PostgreSQL and storage
- Resource names and configuration details
- Quick start commands for testing

View outputs:

```bash
terraform output
```

Get specific sensitive outputs:

```bash
terraform output -raw postgresql_connection_string
terraform output -raw openai_primary_key
```

## Post-Deployment Setup

### 1. Initialize PostgreSQL Database

Connect to PostgreSQL and create the required schema:

```bash
# Get connection string
POSTGRES_CONNECTION=$(terraform output -raw postgresql_connection_string)

# Connect and initialize
psql "$POSTGRES_CONNECTION" -c "
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

CREATE INDEX IF NOT EXISTS idx_documents_embedding 
ON documents USING ivfflat (embedding vector_cosine_ops) 
WITH (lists = 100);

CREATE INDEX IF NOT EXISTS idx_documents_content_fts 
ON documents USING gin(to_tsvector('english', content));
"
```

### 2. Deploy Function App Code

Deploy the Python function code to process documents and handle hybrid search:

```bash
# Get function app name
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)

# Deploy function code (you'll need to implement this)
func azure functionapp publish $FUNCTION_APP_NAME
```

### 3. Create Azure AI Search Index

Create the search index using the Azure CLI:

```bash
# Get search service details
SEARCH_SERVICE=$(terraform output -raw search_service_name)
SEARCH_KEY=$(terraform output -raw search_service_primary_key)

# Create index using REST API
curl -X PUT \
  "https://$SEARCH_SERVICE.search.windows.net/indexes/documents-index?api-version=2023-11-01" \
  -H "Content-Type: application/json" \
  -H "api-key: $SEARCH_KEY" \
  -d '{
    "name": "documents-index",
    "fields": [
      {"name": "id", "type": "Edm.String", "key": true, "searchable": false},
      {"name": "title", "type": "Edm.String", "searchable": true},
      {"name": "content", "type": "Edm.String", "searchable": true},
      {"name": "contentType", "type": "Edm.String", "filterable": true},
      {"name": "createdAt", "type": "Edm.DateTimeOffset", "filterable": true}
    ]
  }'
```

## Testing the Deployment

### Test Document Processing

```bash
# Get the process document endpoint
PROCESS_ENDPOINT=$(terraform output -raw process_document_endpoint)

# Test document processing
curl -X POST "$PROCESS_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Azure AI Overview",
    "content": "Azure AI services provide comprehensive artificial intelligence capabilities for modern applications.",
    "content_type": "text/plain"
  }'
```

### Test Hybrid Search

```bash
# Get the hybrid search endpoint
SEARCH_ENDPOINT=$(terraform output -raw hybrid_search_endpoint)

# Test hybrid search
curl -X POST "$SEARCH_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "artificial intelligence",
    "top_k": 5
  }'
```

## Security Features

This Terraform configuration includes several security best practices:

- **Managed Identity**: Function App uses system-assigned managed identity
- **Key Vault**: Sensitive information stored in Azure Key Vault
- **TLS 1.2**: Minimum TLS version enforced
- **HTTPS Only**: All storage accounts enforce HTTPS traffic
- **Network Security**: Optional private endpoints for enhanced security
- **Firewall Rules**: Configurable IP restrictions

## Monitoring and Logging

When `enable_monitoring = true`, the configuration deploys:

- **Azure Application Insights**: Application performance monitoring
- **Log Analytics Workspace**: Centralized logging
- **Function App Integration**: Automatic telemetry collection

## Cost Optimization

To minimize costs:

1. Use consumption-based pricing for Function Apps (`Y1` SKU)
2. Choose appropriate PostgreSQL SKU for your workload
3. Use Standard storage tier for non-production workloads
4. Enable monitoring only when needed
5. Use `terraform destroy` to clean up resources after testing

## Troubleshooting

### Common Issues

1. **OpenAI Service Access**: Ensure your subscription has access to Azure OpenAI
2. **PostgreSQL Connection**: Check firewall rules and connection strings
3. **Function App Deployment**: Verify runtime versions and dependencies
4. **Search Service**: Ensure search index is created properly

### Debug Commands

```bash
# Check resource group
az group show --name $(terraform output -raw resource_group_name)

# Check function app logs
az functionapp logs tail --name $(terraform output -raw function_app_name) --resource-group $(terraform output -raw resource_group_name)

# Test PostgreSQL connection
psql $(terraform output -raw postgresql_connection_string) -c "SELECT version();"
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

Confirm by typing `yes` when prompted.

## Contributing

To contribute to this Terraform configuration:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Azure documentation for the specific services
3. Consult the original recipe documentation
4. Open an issue in the repository

## License

This code is provided under the MIT License. See LICENSE file for details.