# Infrastructure as Code for Multi-Language Content Localization Workflows with Cloud Translation Advanced and Cloud Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Language Content Localization Workflows with Cloud Translation Advanced and Cloud Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Translation API
  - Cloud Storage
  - Cloud Functions
  - Cloud Scheduler
  - Pub/Sub
  - Cloud Build
  - IAM roles assignment
- Estimated cost: $50-100 for tutorial resources

### Required APIs

The following APIs must be enabled in your Google Cloud project:
- Cloud Translation API (`translate.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Pub/Sub API (`pubsub.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)

## Quick Start

### Environment Setup

```bash
# Set your project configuration
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Authenticate with Google Cloud
gcloud auth login
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
```

### Using Infrastructure Manager

Infrastructure Manager provides Google Cloud's native infrastructure-as-code capabilities with built-in state management and Google Cloud integration.

```bash
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/translation-workflow \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/translation-workflow" \
    --git-source-directory="/" \
    --git-source-ref="main"
```

### Using Terraform

Terraform provides cross-cloud infrastructure management with extensive provider ecosystem and state management capabilities.

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

Bash scripts provide direct CLI-based deployment with step-by-step resource creation and detailed logging.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and monitor deployment progress
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Storage Buckets**: Source and translated content storage with versioning
- **Pub/Sub Topic & Subscription**: Event-driven messaging for translation workflows
- **Cloud Function**: Serverless translation processing with multi-language support
- **Cloud Scheduler Jobs**: Automated batch processing and system monitoring
- **IAM Roles & Policies**: Least-privilege access control for all components
- **Cloud Storage Notifications**: Automatic trigger for document uploads

## Configuration Options

### Terraform Variables

Key variables you can customize in `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "target_languages" {
  description = "List of target languages for translation"
  type        = list(string)
  default     = ["es", "fr", "de", "it", "pt"]
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function"
  type        = string
  default     = "512MB"
}

variable "function_timeout" {
  description = "Timeout for Cloud Function execution"
  type        = string
  default     = "540s"
}
```

### Infrastructure Manager Configuration

Customize deployment through the `infrastructure-manager/main.yaml` configuration file:

```yaml
variables:
  project_id:
    value: "your-project-id"
  region:
    value: "us-central1"
  target_languages:
    value: ["es", "fr", "de", "it", "pt"]
```

## Validation & Testing

After deployment, verify the infrastructure:

### Test Document Upload and Translation

```bash
# Create a test document
echo "Welcome to our enterprise platform. Please complete user authentication to access advanced features." > test-document.txt

# Upload to source bucket (replace BUCKET_NAME with actual source bucket name)
gsutil cp test-document.txt gs://BUCKET_NAME/

# Wait for processing and check results
sleep 30
gsutil ls -la gs://TRANSLATED_BUCKET_NAME/
```

### Verify Cloud Function Deployment

```bash
# List deployed functions
gcloud functions list --region=${REGION}

# Check function logs
gcloud functions logs read FUNCTION_NAME --region=${REGION} --limit=10
```

### Test Scheduled Jobs

```bash
# List scheduled jobs
gcloud scheduler jobs list --location=${REGION}

# Manually trigger batch processing
gcloud scheduler jobs run batch-translation-job --location=${REGION}
```

## Monitoring and Troubleshooting

### View Cloud Function Logs

```bash
# Real-time log streaming
gcloud functions logs tail FUNCTION_NAME --region=${REGION}

# View logs with filters
gcloud logging read 'resource.type="cloud_function" AND resource.labels.function_name="FUNCTION_NAME"' --limit=20
```

### Monitor Translation Progress

```bash
# Check Pub/Sub message statistics
gcloud pubsub topics describe TOPIC_NAME

# View subscription status
gcloud pubsub subscriptions describe SUBSCRIPTION_NAME
```

### Storage Monitoring

```bash
# Monitor bucket storage usage
gsutil du -sh gs://SOURCE_BUCKET_NAME
gsutil du -sh gs://TRANSLATED_BUCKET_NAME

# List recent uploads
gsutil ls -la gs://SOURCE_BUCKET_NAME/ | tail -10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/translation-workflow
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Functions
gcloud functions delete FUNCTION_NAME --region=${REGION} --quiet

# Delete Cloud Scheduler jobs
gcloud scheduler jobs delete batch-translation-job --location=${REGION} --quiet
gcloud scheduler jobs delete translation-monitor --location=${REGION} --quiet

# Delete Pub/Sub resources
gcloud pubsub subscriptions delete SUBSCRIPTION_NAME --quiet
gcloud pubsub topics delete TOPIC_NAME --quiet

# Delete Cloud Storage buckets
gsutil -m rm -r gs://SOURCE_BUCKET_NAME
gsutil -m rm -r gs://TRANSLATED_BUCKET_NAME

# Disable APIs (optional)
gcloud services disable translate.googleapis.com
gcloud services disable cloudfunctions.googleapis.com
gcloud services disable cloudscheduler.googleapis.com
```

## Cost Management

### Estimated Costs

This infrastructure typically incurs the following costs:

- **Cloud Translation API**: $20 per million characters
- **Cloud Functions**: $0.40 per million invocations + compute time
- **Cloud Storage**: $0.02 per GB/month (Standard class)
- **Pub/Sub**: $0.60 per million messages
- **Cloud Scheduler**: Free tier (up to 3 jobs)

### Cost Optimization Tips

1. **Use Cloud Storage lifecycle policies** to automatically move old translations to cheaper storage classes
2. **Monitor Cloud Function execution time** and optimize memory allocation
3. **Implement request batching** to reduce Translation API calls
4. **Use Cloud Storage notifications** instead of polling for new files
5. **Set up budget alerts** to monitor spending

## Security Considerations

### IAM Best Practices

- Service accounts use least-privilege permissions
- Cloud Function has minimal required permissions for Translation API and Storage
- Cross-service communication uses service account authentication
- No hardcoded credentials in any configuration

### Data Protection

- All data is encrypted in transit and at rest by default
- Cloud Translation API does not store customer data
- Storage buckets use Google-managed encryption keys
- IAM policies restrict access to authorized users only

## Customization

### Adding New Target Languages

To add support for additional languages, update the `target_languages` variable in your chosen IaC tool and redeploy.

### Custom Translation Models

For enterprise deployments requiring custom translation models:

1. Create training datasets in Cloud Storage
2. Use AutoML Translation to train custom models
3. Update the Cloud Function to reference custom model IDs
4. Deploy updated infrastructure

### Integration with External Systems

The solution can be extended to integrate with:

- Content Management Systems (CMS)
- Document Management Systems
- CI/CD pipelines for documentation
- Slack/Teams for notifications
- External translation services for human review

## Support

For issues with this infrastructure code:

1. **Review the original recipe documentation** for implementation details
2. **Check Google Cloud documentation** for service-specific guidance
3. **Examine Cloud Function logs** for runtime errors
4. **Validate IAM permissions** for all service accounts
5. **Verify API quotas and limits** in the Google Cloud Console

### Common Issues

- **Function timeout errors**: Increase timeout value or optimize processing logic
- **Translation API quota exceeded**: Request quota increases or implement rate limiting
- **Storage permission errors**: Verify service account has Storage Admin role
- **Pub/Sub message delivery failures**: Check subscription configuration and dead letter queues

## Additional Resources

- [Cloud Translation API Documentation](https://cloud.google.com/translate/docs)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Cloud Storage Security Guide](https://cloud.google.com/storage/docs/security)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)