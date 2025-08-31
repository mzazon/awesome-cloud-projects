# Infrastructure as Code for Lorem Ipsum Generator Cloud Functions API

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Lorem Ipsum Generator Cloud Functions API".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Required API permissions:
  - Cloud Functions API
  - Cloud Storage API
  - Cloud Build API
  - Infrastructure Manager API (for Infrastructure Manager deployment)
- Terraform installed (version >= 1.0) for Terraform implementation
- Estimated cost: $0.01-0.50 USD for function invocations and storage (within free tier limits)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's managed Terraform service that provides native IaC capabilities with state management and drift detection.

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments create lorem-ipsum-deployment \
    --location=us-central1 \
    --source-type=source_repo \
    --source-repo=./main.yaml \
    --input-values project_id=${PROJECT_ID},region=us-central1

# Check deployment status
gcloud infra-manager deployments describe lorem-ipsum-deployment \
    --location=us-central1
```

### Using Terraform

Terraform provides cross-cloud infrastructure management with explicit state control and extensive provider ecosystem.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=us-central1"

# View outputs including function URL
terraform output function_url
```

### Using Bash Scripts

Bash scripts provide direct Google Cloud CLI commands for straightforward deployment and cleanup operations.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required environment variables:
# - PROJECT_ID: Your Google Cloud project ID
# - REGION: Deployment region (default: us-central1)
```

## Architecture Overview

The infrastructure deploys:

- **Cloud Functions (2nd gen)**: HTTP-triggered serverless function for lorem ipsum generation
- **Cloud Storage Bucket**: Caching layer for frequently requested text patterns
- **IAM Bindings**: Proper permissions for function-to-storage access
- **Required APIs**: Automatic enablement of necessary Google Cloud services

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `lorem-generator` | No |
| `bucket_name` | Storage bucket name | `lorem-cache-${random_suffix}` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Compute zone | `us-central1-a` | No |
| `function_memory` | Function memory allocation | `256` | No |
| `function_timeout` | Function timeout in seconds | `60` | No |

### Bash Script Environment Variables

The deployment script accepts these environment variables:

```bash
export PROJECT_ID="your-project-id"          # Required
export REGION="us-central1"                  # Optional, defaults to us-central1
export ZONE="us-central1-a"                  # Optional, defaults to us-central1-a
```

## Testing the Deployment

After successful deployment, test the lorem ipsum API:

```bash
# Get function URL (varies by deployment method)
# For Terraform:
FUNCTION_URL=$(terraform output -raw function_url)

# For Infrastructure Manager:
FUNCTION_URL=$(gcloud infra-manager deployments describe lorem-ipsum-deployment \
    --location=us-central1 --format="value(outputs.function_url)")

# Test basic functionality
curl "${FUNCTION_URL}?paragraphs=2&words=30" | python3 -m json.tool

# Test parameter validation
curl "${FUNCTION_URL}?paragraphs=5&words=100" | python3 -m json.tool

# Test caching (repeat same request)
curl "${FUNCTION_URL}?paragraphs=3&words=50" | python3 -m json.tool
```

Expected API response format:
```json
{
  "text": "Lorem ipsum dolor sit amet...",
  "paragraphs": 2,
  "words_per_paragraph": 30,
  "cached": false
}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete lorem-ipsum-deployment \
    --location=us-central1 \
    --delete-policy=DELETE
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Security Considerations

- **Public Function Access**: The Cloud Function is deployed with `--allow-unauthenticated` for public API access
- **CORS Configuration**: Function includes CORS headers for web browser integration
- **Parameter Validation**: Input validation prevents abuse with reasonable limits (1-10 paragraphs, 10-200 words)
- **IAM Permissions**: Function service account has minimal required permissions for Cloud Storage access

For production deployments requiring authentication:

```bash
# Deploy with authentication required
gcloud functions deploy lorem-generator \
    --gen2 \
    --runtime python312 \
    --trigger-http \
    --source ./function-source \
    --entry-point lorem_generator \
    --region us-central1
    # Remove --allow-unauthenticated flag
```

## Monitoring and Observability

View function metrics and logs:

```bash
# View function logs
gcloud functions logs read lorem-generator --gen2 --region=us-central1

# View function metrics in Cloud Console
gcloud console functions

# Monitor storage bucket usage
gsutil du -s gs://your-bucket-name
```

## Customization

### Extending the Lorem Ipsum Function

1. **Add text generation styles**: Modify the `LOREM_WORDS` array in the function source
2. **Implement rate limiting**: Add Cloud Firestore integration for usage tracking
3. **Add formatting options**: Extend the function to support HTML, Markdown, or other output formats
4. **Custom caching strategies**: Modify the caching logic for different performance characteristics

### Infrastructure Modifications

1. **Enable function authentication**: Remove `--allow-unauthenticated` flag
2. **Add custom domains**: Configure Cloud Load Balancing for custom domain mapping
3. **Implement monitoring**: Add Cloud Monitoring alerts for function errors or high latency
4. **Scale storage**: Configure different storage classes or retention policies

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check enabled APIs
   gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com"
   
   # Verify IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Storage bucket access denied**:
   ```bash
   # Check bucket permissions
   gsutil iam get gs://your-bucket-name
   
   # Verify function service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:*compute@developer.gserviceaccount.com"
   ```

3. **Function returns 500 errors**:
   ```bash
   # View detailed function logs
   gcloud functions logs read lorem-generator --gen2 --region=us-central1 --limit=50
   ```

### Performance Optimization

- **Cold starts**: Consider using minimum instances for frequently accessed functions
- **Memory allocation**: Adjust function memory based on usage patterns
- **Caching strategy**: Monitor cache hit rates and adjust caching logic accordingly

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for implementation details
2. Consult [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
3. Check [Google Cloud Storage documentation](https://cloud.google.com/storage/docs)
4. Visit [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Cost Optimization

- **Cloud Functions**: Use 2nd generation for better cold start performance and cost efficiency
- **Storage**: Implement lifecycle policies for cached content if long-term storage grows
- **Monitoring**: Set up billing alerts to track usage and costs
- **Resource cleanup**: Regularly clean old cached content to minimize storage costs

This implementation provides a production-ready lorem ipsum generation API with proper caching, security, and observability features while maintaining cost efficiency through serverless architecture.