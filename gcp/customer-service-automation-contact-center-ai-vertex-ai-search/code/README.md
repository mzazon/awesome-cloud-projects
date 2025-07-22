# Infrastructure as Code for Customer Service Automation with Contact Center AI and Vertex AI Search

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Customer Service Automation with Contact Center AI and Vertex AI Search".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Contact Center AI Platform
  - Vertex AI Discovery Engine
  - Cloud Run
  - Cloud Storage
  - Service Account management
- Contact Center AI Platform API enabled (may require special setup)
- Estimated cost: $50-100 for resources created during deployment

> **Note**: Contact Center AI requires special setup and may have additional licensing requirements. Ensure you have the necessary permissions and have enabled the Contact Center AI API in your project.

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create customer-service-automation \
    --location=${REGION} \
    --source=main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment status
gcloud infra-manager deployments describe customer-service-automation \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud run services list --region=${REGION}
gcloud storage ls gs://customer-service-kb-*
```

## Architecture Overview

The infrastructure creates:

- **Cloud Storage Bucket**: Knowledge base document storage with versioning and lifecycle policies
- **Vertex AI Search Engine**: Enterprise search with natural language processing capabilities
- **Cloud Run Service**: Serverless API for search and conversation analysis
- **IAM Roles and Permissions**: Secure service-to-service communication
- **Sample Knowledge Base**: Pre-populated FAQ, troubleshooting, and policy documents
- **Agent Dashboard**: Web interface for customer service representatives

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `bucket_name_suffix` | Suffix for storage bucket name | Random | No |
| `enable_versioning` | Enable bucket versioning | `true` | No |
| `cloud_run_memory` | Cloud Run memory allocation | `1Gi` | No |
| `cloud_run_cpu` | Cloud Run CPU allocation | `1` | No |
| `max_instances` | Maximum Cloud Run instances | `10` | No |

### Terraform Variables

All variables are defined in `variables.tf` with descriptions and validation rules:

```bash
# Example with custom values
terraform apply \
    -var="project_id=my-project" \
    -var="region=us-west1" \
    -var="bucket_name_suffix=prod" \
    -var="cloud_run_memory=2Gi"
```

### Bash Script Environment Variables

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export BUCKET_NAME_SUFFIX="dev"  # Optional
export CLOUD_RUN_MEMORY="1Gi"   # Optional
export CLOUD_RUN_CPU="1"        # Optional
export MAX_INSTANCES="10"       # Optional
```

## Deployment Verification

After deployment, verify the infrastructure:

```bash
# Check Cloud Run service status
gcloud run services describe customer-service-api-* --region=${REGION}

# Verify storage bucket creation
gcloud storage ls gs://customer-service-kb-*

# Test the API endpoint
SERVICE_URL=$(gcloud run services describe customer-service-api-* \
    --region=${REGION} --format="value(status.url)")

curl -X POST "${SERVICE_URL}/search" \
    -H "Content-Type: application/json" \
    -d '{"query": "How do I reset my password?"}'

# Check Vertex AI Search engine status
gcloud discoveryengine data-stores list --location=global
```

## Usage Examples

### Knowledge Base Search

```bash
# Search for password reset information
curl -X POST "${SERVICE_URL}/search" \
    -H "Content-Type: application/json" \
    -d '{"query": "password reset login issues"}'

# Search for billing inquiries
curl -X POST "${SERVICE_URL}/search" \
    -H "Content-Type: application/json" \
    -d '{"query": "billing payment subscription charges"}'
```

### Conversation Analysis

```bash
# Analyze customer conversation
curl -X POST "${SERVICE_URL}/analyze-conversation" \
    -H "Content-Type: application/json" \
    -d '{"conversation": "Customer is frustrated because they cannot access their account and have tried multiple times to reset their password"}'
```

### Agent Dashboard Access

The agent dashboard is automatically deployed and accessible via:
```
https://storage.googleapis.com/${BUCKET_NAME}/dashboard/index.html
```

Update the dashboard's API_BASE_URL with your Cloud Run service URL for full functionality.

## Customization

### Adding Custom Knowledge Base Documents

```bash
# Upload additional documents to the knowledge base
gsutil cp your-documents/* gs://${BUCKET_NAME}/knowledge-base/

# Trigger re-indexing (may require additional API calls)
# See Vertex AI Search documentation for re-indexing procedures
```

### Modifying Search Configuration

Edit the search engine configuration in your chosen IaC tool to adjust:
- Search result count
- Snippet length
- Summary generation settings
- Content filtering rules

### Scaling Configuration

Adjust Cloud Run settings for different workloads:

```bash
# For high-traffic environments
terraform apply -var="max_instances=50" -var="cloud_run_memory=2Gi"

# For development environments
terraform apply -var="max_instances=3" -var="cloud_run_memory=512Mi"
```

## Monitoring and Observability

### Built-in Monitoring

The deployment includes:
- Cloud Run automatic metrics and logging
- Storage bucket access logging
- Vertex AI Search query analytics

### Custom Monitoring Setup

```bash
# Enable additional monitoring
gcloud logging sinks create customer-service-logs \
    bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/customer_service_logs \
    --log-filter='resource.type="cloud_run_revision"'

# Create alerting policies
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring-policy.yaml
```

## Security Considerations

### IAM and Access Control

The infrastructure implements least-privilege access:
- Service accounts with minimal required permissions
- No public access to storage buckets (except dashboard)
- Authenticated API endpoints where appropriate

### Data Protection

- Storage bucket versioning enabled
- Lifecycle policies for cost optimization
- No sensitive data in environment variables
- Encrypted data at rest and in transit

### Network Security

- Cloud Run deployed with appropriate ingress settings
- VPC integration available for private deployments
- HTTPS enforcement for all external endpoints

## Troubleshooting

### Common Issues

1. **Contact Center AI API not enabled**:
   ```bash
   gcloud services enable contactcenteraiplatform.googleapis.com
   ```

2. **Insufficient permissions**:
   ```bash
   # Add required roles to your user account
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/discoveryengine.admin"
   ```

3. **Cloud Run deployment failures**:
   ```bash
   # Check Cloud Run logs
   gcloud logs read "resource.type=cloud_run_revision" --limit=50
   ```

4. **Vertex AI Search indexing issues**:
   ```bash
   # Check data store status
   gcloud discoveryengine data-stores describe ${SEARCH_ENGINE_ID} \
       --location=global
   ```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# For Terraform
export TF_LOG=DEBUG
terraform apply

# For gcloud commands
gcloud config set core/verbosity debug
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete customer-service-automation \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id"

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual verification
gcloud run services list --region=${REGION}
gcloud storage ls gs://customer-service-kb-* || echo "Buckets cleaned up"
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
gcloud run services delete customer-service-api-* --region=${REGION} --quiet
gcloud storage rm -r gs://customer-service-kb-* || true
gcloud discoveryengine data-stores delete ${SEARCH_ENGINE_ID} --location=global --quiet
```

## Cost Optimization

### Resource Optimization

- Use Cloud Run's pay-per-request model for cost efficiency
- Implement storage lifecycle policies for long-term cost reduction
- Monitor Vertex AI Search query volumes and optimize usage patterns

### Cost Monitoring

```bash
# Set up budget alerts
gcloud beta billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Customer Service AI Budget" \
    --budget-amount=100USD

# Monitor current costs
gcloud beta billing projects describe ${PROJECT_ID}
```

## Performance Tuning

### Cloud Run Optimization

- Adjust memory and CPU based on actual usage patterns
- Configure concurrency settings for optimal performance
- Use Cloud Run's traffic allocation for blue-green deployments

### Search Performance

- Optimize knowledge base document structure
- Use Vertex AI Search's analytics to improve query performance
- Implement caching strategies for frequently accessed information

## Integration Examples

### With Contact Center AI

```python
# Example Python integration
from google.cloud import contactcenterinsights_v1

client = contactcenterinsights_v1.ContactCenterInsightsClient()
# Integration code for conversation analysis
```

### With Other Google Cloud Services

```bash
# Integration with Pub/Sub for real-time processing
gcloud pubsub topics create customer-service-events
gcloud pubsub subscriptions create process-conversations \
    --topic=customer-service-events
```

## Support and Documentation

- [Google Cloud Contact Center AI Documentation](https://cloud.google.com/solutions/contact-center-ai-platform)
- [Vertex AI Search Documentation](https://cloud.google.com/generative-ai-app-builder/docs/enterprise-search-introduction)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud documentation for specific services.

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate with `terraform plan` or `gcloud infra-manager preview`
3. Update documentation for any new variables or outputs
4. Follow Google Cloud best practices for security and performance

## License

This infrastructure code is provided as part of the cloud recipes collection. Use in accordance with your organization's policies and Google Cloud terms of service.