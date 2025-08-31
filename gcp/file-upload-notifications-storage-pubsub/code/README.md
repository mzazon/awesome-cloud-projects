# Infrastructure as Code for File Upload Notifications with Cloud Storage and Pub/Sub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "File Upload Notifications with Cloud Storage and Pub/Sub".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using official Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Project with billing enabled and appropriate permissions:
  - Storage Admin (`roles/storage.admin`) on the bucket
  - Pub/Sub Admin (`roles/pubsub.admin`) on the project
  - Project Editor or Owner role for resource creation
- For Terraform: Terraform >= 1.0 installed
- For Infrastructure Manager: Access to Google Cloud Infrastructure Manager API

## Architecture Overview

This infrastructure implements an event-driven file processing system that automatically publishes notifications to Pub/Sub when files are uploaded to Cloud Storage. The system consists of:

- **Cloud Storage Bucket**: Stores uploaded files and generates object change events
- **Pub/Sub Topic**: Receives storage event notifications with detailed object metadata
- **Pub/Sub Subscription**: Enables applications to consume file upload notifications
- **IAM Service Account**: Manages permissions between Cloud Storage and Pub/Sub

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses configuration files to manage Google Cloud resources.

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/file-notifications \
    --service-account="PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/file-notifications
```

### Using Terraform

Terraform provides a declarative way to manage infrastructure across multiple cloud providers.

```bash
# Set your project ID and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a simple way to deploy the infrastructure using gcloud CLI commands.

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
gcloud pubsub topics list --filter="name:file-upload-notifications"
gcloud storage buckets list --filter="name:${PROJECT_ID}-uploads"
```

## Configuration

### Infrastructure Manager Variables

Modify the `main.yaml` file to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: `us-central1`)
- `topic_name`: Name for the Pub/Sub topic
- `subscription_name`: Name for the Pub/Sub subscription
- `bucket_name`: Name for the Cloud Storage bucket

### Terraform Variables

Create a `terraform.tfvars` file or set variables via command line:

```hcl
project_id = "your-project-id"
region     = "us-central1"
topic_name = "file-upload-notifications"
subscription_name = "file-processor"
bucket_name = "your-project-uploads"
```

### Script Variables

Edit the script files or set environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export TOPIC_NAME="file-upload-notifications"
export SUBSCRIPTION_NAME="file-processor"
export BUCKET_NAME="${PROJECT_ID}-uploads"
```

## Testing the Infrastructure

After deployment, test the file upload notification system:

```bash
# Create a test file
echo "Test file content $(date)" > test-upload.txt

# Upload to trigger notification (replace bucket name)
gcloud storage cp test-upload.txt gs://your-bucket-name/

# Check for messages in the subscription
gcloud pubsub subscriptions pull your-subscription-name \
    --limit=1 \
    --format="value(message.data)" | base64 -d

# Clean up test file
rm test-upload.txt
```

## Monitoring and Observability

Monitor your notification system using:

```bash
# Check bucket notification configuration
gcloud storage buckets notifications list gs://your-bucket-name/

# Monitor subscription metrics
gcloud pubsub subscriptions describe your-subscription-name

# View topic metrics
gcloud pubsub topics describe your-topic-name

# Check Cloud Storage metrics in Cloud Monitoring
gcloud logging read "resource.type=gcs_bucket" --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/file-notifications

# Confirm deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are removed
gcloud pubsub topics list --filter="name:file-upload-notifications"
gcloud storage buckets list --filter="name:${PROJECT_ID}-uploads"
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your service account has the required IAM roles
2. **Bucket Already Exists**: Bucket names must be globally unique
3. **API Not Enabled**: Enable required APIs (Storage, Pub/Sub)
4. **Notification Configuration**: Verify Cloud Storage service account has Pub/Sub Publisher role

### Useful Commands

```bash
# Check enabled APIs
gcloud services list --enabled

# Enable required APIs
gcloud services enable storage.googleapis.com pubsub.googleapis.com

# Check IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Debug notification issues
gcloud storage buckets notifications list gs://your-bucket-name/
```

## Customization

### Adding Additional Event Types

Modify the notification configuration to include more event types:

```yaml
# In Infrastructure Manager main.yaml
eventTypes:
  - OBJECT_FINALIZE
  - OBJECT_DELETE
  - OBJECT_METADATA_UPDATE
```

### Content-Based Routing

Add custom attributes to route different file types:

```yaml
# Example custom attributes
customAttributes:
  source: "file-uploads"
  environment: "production"
```

### Security Enhancements

- Implement VPC Service Controls for additional security
- Use Customer-Managed Encryption Keys (CMEK) for data encryption
- Configure Pub/Sub message retention and dead letter queues

## Performance Optimization

- Configure Pub/Sub subscription with appropriate acknowledgment deadline
- Use message filtering to reduce processing overhead
- Implement exponential backoff for failed message processing
- Monitor subscription lag and adjust processing capacity

## Cost Optimization

- Configure appropriate Cloud Storage lifecycle policies
- Set Pub/Sub message retention periods based on requirements
- Use regional buckets for reduced storage costs when appropriate
- Monitor and alert on unexpected usage patterns

## Support

For issues with this infrastructure code:

1. Check the [Cloud Storage Pub/Sub notifications documentation](https://cloud.google.com/storage/docs/pubsub-notifications)
2. Review [Pub/Sub best practices](https://cloud.google.com/pubsub/docs/best-practices)
3. Consult the [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)
4. Refer to the original recipe documentation for implementation details

## Additional Resources

- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Storage Event-driven Architecture](https://cloud.google.com/architecture/event-driven-cloud-storage)
- [Pub/Sub Message Flow Control](https://cloud.google.com/pubsub/docs/flow-control)