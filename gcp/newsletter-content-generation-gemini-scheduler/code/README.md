# Infrastructure as Code for Newsletter Content Generation with Gemini and Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Newsletter Content Generation with Gemini and Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (create, deploy, manage)
  - Cloud Scheduler (create, manage jobs)
  - Cloud Storage (create buckets, manage objects)
  - Vertex AI (use Gemini models)
  - IAM (create service accounts, assign roles)
- For Terraform: Terraform CLI installed (version >= 1.0)
- Estimated cost: $5-15/month for moderate usage

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution, providing native integration with Google Cloud services and built-in state management.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments create newsletter-deployment \
    --location=us-central1 \
    --source-directory=. \
    --input-values="project_id=YOUR_PROJECT_ID,region=us-central1"

# Monitor deployment status
gcloud infra-manager deployments describe newsletter-deployment \
    --location=us-central1
```

### Using Terraform

Terraform provides declarative infrastructure management with state tracking and dependency resolution.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform (download providers and modules)
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure changes
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs (function URL, storage bucket, etc.)
terraform output
```

### Using Bash Scripts

Automated deployment scripts provide a guided setup process with built-in error handling and validation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script (interactive)
./scripts/deploy.sh

# Or with environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
./scripts/deploy.sh
```

## Architecture Components

This infrastructure deploys the following Google Cloud resources:

- **Cloud Storage Bucket**: Stores content templates and generated newsletters
- **Cloud Function**: Serverless function for content generation using Gemini AI
- **Cloud Scheduler Job**: Automated weekly trigger for newsletter generation
- **IAM Service Account**: Dedicated service account with minimal required permissions
- **Vertex AI Access**: Configuration for Gemini model access

## Configuration Options

### Infrastructure Manager Variables

Located in `infrastructure-manager/main.yaml`:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  function_name:
    description: "Cloud Function name"
    type: string
    default: "newsletter-generator"
  schedule:
    description: "Cron schedule for newsletter generation"
    type: string
    default: "0 9 * * 1"  # Every Monday at 9 AM
```

### Terraform Variables

Located in `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Deployment region"
  type        = string
  default     = "us-central1"
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function"
  type        = string
  default     = "512Mi"
}

variable "newsletter_topic" {
  description = "Default newsletter topic"
  type        = string
  default     = "Weekly Marketing Insights"
}
```

### Bash Script Configuration

Edit variables at the top of `scripts/deploy.sh`:

```bash
# Configuration variables
DEFAULT_REGION="us-central1"
DEFAULT_MEMORY="512MB"
DEFAULT_TIMEOUT="300s"
DEFAULT_SCHEDULE="0 9 * * 1"
```

## Testing the Deployment

After deployment, verify the system works correctly:

### 1. Test Cloud Function Directly

```bash
# Get function URL from outputs
FUNCTION_URL=$(terraform output -raw function_url)

# Test with custom topic
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{"topic":"AI in Email Marketing"}'
```

### 2. Verify Cloud Scheduler

```bash
# Manually trigger the scheduled job
gcloud scheduler jobs run newsletter-schedule \
    --location=us-central1

# Check job execution history
gcloud scheduler jobs describe newsletter-schedule \
    --location=us-central1
```

### 3. Check Generated Content

```bash
# List generated content files
gsutil ls gs://$(terraform output -raw storage_bucket_name)/generated-content/

# Download and view latest content
gsutil cp gs://$(terraform output -raw storage_bucket_name)/generated-content/*.json ./
cat *.json | jq '.'
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete newsletter-deployment \
    --location=us-central1

# Verify deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID"

# Verify destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are removed
```

## Monitoring and Observability

### Cloud Function Monitoring

```bash
# View function logs
gcloud functions logs read newsletter-generator \
    --limit=50

# Monitor function metrics
gcloud functions describe newsletter-generator \
    --format="table(status,updateTime,runtime)"
```

### Scheduler Monitoring

```bash
# Check job execution history
gcloud scheduler jobs describe newsletter-schedule \
    --location=us-central1 \
    --format="table(lastAttemptTime,state,retryConfig.maxRetryAttempts)"
```

### Cost Monitoring

```bash
# Check current billing for the project
gcloud billing accounts list
gcloud billing projects describe ${PROJECT_ID}
```

## Customization

### Modify Content Templates

Update the template structure in the Cloud Function code:

```python
# Edit terraform/function-source/main.py
template = {
    "subject_line": "Your custom subject line template",
    "intro": "Custom introduction template",
    "main_content": "Custom main content template",
    "call_to_action": "Custom CTA template",
    "tone": "professional, engaging",
    "target_audience": "your specific audience",
    "word_limit": 400  # Adjust as needed
}
```

### Adjust Scheduling

Modify the cron schedule in your chosen deployment method:

```bash
# Common schedule patterns:
# "0 9 * * 1"     # Every Monday at 9 AM
# "0 9 * * 1,3,5" # Every Monday, Wednesday, Friday at 9 AM
# "0 9 1 * *"     # First day of every month at 9 AM
# "0 9 * * *"     # Every day at 9 AM
```

### Scale Function Resources

Adjust Cloud Function resources based on usage:

```hcl
# In terraform/main.tf
resource "google_cloudfunctions2_function" "newsletter_generator" {
  build_config {
    runtime = "python312"
    available_memory = "1Gi"  # Increase for better performance
    timeout = "540s"          # Increase for complex content
  }
}
```

## Security Considerations

- **IAM Principle of Least Privilege**: Service accounts have minimal required permissions
- **Network Security**: Cloud Function uses secure HTTPS endpoints only
- **API Security**: Gemini AI access is restricted to authorized service accounts
- **Storage Security**: Cloud Storage bucket uses project-level IAM controls
- **Secret Management**: No hardcoded credentials in infrastructure code

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   ```bash
   # Check API enablement
   gcloud services list --enabled
   
   # Verify IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Function Execution Errors**:
   ```bash
   # Check function logs for detailed errors
   gcloud functions logs read newsletter-generator --limit=10
   
   # Verify Vertex AI API access
   gcloud ai models list --region=us-central1
   ```

3. **Storage Access Issues**:
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://your-bucket-name
   
   # Test bucket access
   gsutil ls gs://your-bucket-name
   ```

### Debug Mode

Enable debug logging in bash scripts:

```bash
# Run deployment with debug output
DEBUG=true ./scripts/deploy.sh
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../newsletter-content-generation-gemini-scheduler.md)
2. Review [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
3. Consult [Vertex AI Gemini documentation](https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini)
4. Reference [Cloud Scheduler documentation](https://cloud.google.com/scheduler/docs)

## Cost Optimization

- Monitor Gemini API usage through Cloud Billing
- Use Cloud Function concurrency limits to control costs
- Implement Cloud Storage lifecycle policies for old content
- Set up budget alerts for unexpected usage spikes
- Consider using smaller Gemini models for reduced costs

## Next Steps

After successful deployment, consider these enhancements:

1. **Email Integration**: Connect to Gmail API or email service providers
2. **Content Analytics**: Add BigQuery integration for content performance tracking
3. **Multi-Language Support**: Extend Gemini prompts for international content
4. **A/B Testing**: Generate multiple content variations for testing
5. **Audience Segmentation**: Integrate with customer data for personalized content