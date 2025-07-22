# Infrastructure as Code for Enterprise Knowledge Discovery with Google Agentspace and Vertex AI Search

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Knowledge Discovery with Google Agentspace and Vertex AI Search".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Discovery Engine (Vertex AI Search)
  - Cloud Storage
  - BigQuery
  - AI Platform (Vertex AI)
  - Agentspace (Preview access required)
  - IAM role management
  - Cloud Monitoring
- Terraform installed (version >= 1.0) for Terraform deployment
- Bash shell environment for script execution

> **Note**: Google Agentspace is currently in preview and may require allowlisting. Some features may have limited availability.

## Quick Start

### Using Infrastructure Manager

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/enterprise-knowledge-discovery \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="infrastructure-manager/"

# Monitor deployment status
gcloud infra-manager deployments describe \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/enterprise-knowledge-discovery
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration
```

## Configuration

### Infrastructure Manager Configuration

The Infrastructure Manager deployment uses the following key parameters:

- `project_id`: Google Cloud project ID
- `region`: Primary deployment region (default: us-central1)
- `random_suffix`: Unique suffix for resource naming
- `enable_agentspace`: Enable Agentspace features (default: true)

### Terraform Variables

Key variables in `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Primary region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Primary zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "bucket_name_prefix" {
  description = "Prefix for storage bucket names"
  type        = string
  default     = "enterprise-docs"
}

variable "dataset_name_prefix" {
  description = "Prefix for BigQuery dataset names"
  type        = string
  default     = "knowledge_analytics"
}

variable "search_app_prefix" {
  description = "Prefix for Vertex AI Search application"
  type        = string
  default     = "enterprise-search"
}
```

Customize by creating a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
```

### Bash Script Configuration

The deployment script will prompt for:

- Google Cloud project ID
- Preferred region and zone
- Whether to enable Agentspace features
- Sample document upload preferences

## Architecture Components

This infrastructure deploys:

### Storage Layer
- **Cloud Storage Bucket**: Document repository with lifecycle policies
- **BigQuery Dataset**: Analytics and search metrics storage
- **Sample Documents**: HR policies, API documentation, financial reports

### Search and AI Layer
- **Vertex AI Search Data Store**: Document indexing and search capabilities
- **Vertex AI Search Engine**: Semantic search with LLM enhancement
- **Document Import Pipeline**: Automated content ingestion

### Agent Layer (Preview)
- **Google Agentspace Agent**: Knowledge discovery orchestration
- **Agent Workflows**: Natural language query processing
- **Search Integration**: Vertex AI Search connectivity

### Security and Monitoring
- **Custom IAM Roles**: Granular access control for knowledge discovery
- **Service Accounts**: Secure application authentication
- **Cloud Monitoring Dashboard**: Performance and usage analytics
- **Audit Logging**: Search query and access tracking

## Validation

After deployment, verify the infrastructure:

### Test Search Functionality

```bash
# Test Vertex AI Search
curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d '{"query": "remote work policy", "pageSize": 5}' \
  "https://discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/engines/${SEARCH_APP_ID}-engine:search"
```

### Verify Data Analytics

```bash
# Query search analytics
bq query --use_legacy_sql=false \
  "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.search_queries\` LIMIT 10"
```

### Check Agentspace Integration

```bash
# Test agent query (if Agentspace is enabled)
gcloud alpha agentspace agents query \
  --agent-id="enterprise-knowledge-agent" \
  --location=global \
  --query="What is our remote work policy?"
```

## Monitoring and Analytics

The deployed infrastructure includes:

### Cloud Monitoring Dashboard
- Search query volume metrics
- Document access patterns
- System performance indicators
- User engagement analytics

### BigQuery Analytics Tables
- `search_queries`: Query logs and click-through rates
- `document_analytics`: Document usage and relevance scores

### Cost Monitoring
- Storage usage tracking
- Search API consumption
- Compute resource utilization

## Security Features

### Access Control
- **Knowledge Discovery Reader**: Search and read permissions
- **Knowledge Discovery Administrator**: Full management access
- **Service Account**: Application-level authentication

### Data Protection
- Storage bucket versioning enabled
- IAM-based document access control
- Audit logging for compliance
- Encryption at rest and in transit

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/enterprise-knowledge-discovery \
    --quiet
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup Verification

Verify all resources are removed:

```bash
# Check remaining resources
gcloud alpha discovery-engine engines list --location=global
gcloud alpha discovery-engine data-stores list --location=global
gsutil ls -p ${PROJECT_ID}
bq ls --project_id=${PROJECT_ID}
```

## Troubleshooting

### Common Issues

1. **Agentspace API Access**: Ensure your project has preview access to Google Agentspace
2. **Document Import Delays**: Document indexing can take 10-15 minutes; check operation status
3. **IAM Permissions**: Verify service account has necessary permissions for all services
4. **API Quotas**: Check project quotas for Discovery Engine and Vertex AI services

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:discoveryengine.googleapis.com"
gcloud services list --enabled --filter="name:agentspace.googleapis.com"

# Monitor operations
gcloud alpha discovery-engine operations list --location=global

# Check IAM policies
gcloud projects get-iam-policy ${PROJECT_ID}
```

## Cost Optimization

### Storage Optimization
- Lifecycle policies automatically move older documents to cheaper storage tiers
- Document versioning helps manage storage growth
- Regular cleanup of unused analytics data

### Search Optimization
- Configure appropriate search result limits
- Use semantic search features efficiently
- Monitor and optimize query patterns

### Compute Optimization
- Serverless architecture scales automatically
- Pay-per-use pricing model
- Resource scheduling for non-critical workloads

## Customization

### Adding Custom Document Types

1. Modify the document upload section in deployment scripts
2. Update search configuration for specific content types
3. Adjust analytics queries for new document categories

### Integrating with Enterprise Systems

1. Configure additional data sources in Cloud Storage
2. Set up automated content ingestion pipelines
3. Integrate with existing identity providers for SSO

### Extending Analytics

1. Add custom BigQuery tables for specialized metrics
2. Create additional Cloud Monitoring dashboards
3. Implement automated reporting workflows

## Support

### Documentation References
- [Google Cloud Discovery Engine Documentation](https://cloud.google.com/generative-ai-app-builder/docs)
- [Vertex AI Search Best Practices](https://cloud.google.com/generative-ai-app-builder/docs/best-practices)
- [Google Agentspace Documentation](https://cloud.google.com/agentspace/docs)
- [BigQuery Analytics Guide](https://cloud.google.com/bigquery/docs/best-practices-performance-overview)

### Getting Help
- For infrastructure issues: Review logs in Cloud Logging
- For search problems: Check Discovery Engine operation status
- For access issues: Verify IAM role assignments
- For cost concerns: Use Cloud Billing reports and recommendations

### Contributing
To improve this infrastructure code:
1. Test changes in a development environment
2. Update relevant documentation
3. Ensure compatibility with all deployment methods
4. Validate security and cost implications