# Infrastructure as Code for Background Task Processing with Cloud Run Worker Pools

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Background Task Processing with Cloud Run Worker Pools".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Required APIs enabled: Cloud Run, Pub/Sub, Cloud Storage, Cloud Build
- Appropriate IAM permissions for resource creation:
  - Cloud Run Admin
  - Pub/Sub Admin
  - Storage Admin
  - Cloud Build Editor
  - Service Account Admin

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native IaC service that uses standard Terraform configuration with enhanced Google Cloud integration.

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/background-task-processing \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"
```

### Using Terraform

Terraform provides cross-platform infrastructure management with the Google Cloud provider.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# When prompted, type 'yes' to confirm deployment
```

### Using Bash Scripts

The bash scripts provide a straightforward deployment using Google Cloud CLI commands.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your deployment
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-project-id"          # Your Google Cloud Project ID
export REGION="us-central1"                  # Deployment region
export ZONE="us-central1-a"                  # Compute zone
export RANDOM_SUFFIX="abc123"                # Unique suffix for resources
```

### Terraform Variables

Key variables you can customize in `terraform/terraform.tfvars`:

```hcl
project_id     = "your-project-id"
region         = "us-central1"
zone          = "us-central1-a"
random_suffix = "abc123"

# Cloud Run Job Configuration
job_memory    = "1Gi"
job_cpu       = "1"
job_max_retries = 3

# Pub/Sub Configuration
message_retention_duration = "604800s"  # 7 days
ack_deadline_seconds      = 600

# API Service Configuration
api_memory           = "512Mi"
api_cpu             = "1"
api_min_instances   = 0
api_max_instances   = 10
```

### Infrastructure Manager Configuration

Variables are defined in `infrastructure-manager/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
```

## Architecture Overview

The deployed infrastructure includes:

1. **Cloud Run Job**: Serverless background worker for processing tasks
2. **Cloud Run API Service**: HTTP API for task submission
3. **Pub/Sub Topic and Subscription**: Message queue for task coordination
4. **Cloud Storage Bucket**: File storage for processed results
5. **Container Images**: Built and stored in Artifact Registry
6. **IAM Roles and Service Accounts**: Secure access management

## Outputs

After successful deployment, you'll receive:

- **API Service URL**: Endpoint for submitting background tasks
- **Pub/Sub Topic**: Topic name for direct message publishing
- **Storage Bucket**: Bucket name for accessing processed files
- **Cloud Run Job**: Job name for manual execution and monitoring

## Testing the Deployment

### Submit a File Processing Task

```bash
# Get the API URL from terraform outputs or deployment logs
API_URL=$(terraform output -raw api_service_url)

# Submit a file processing task
curl -X POST "${API_URL}/submit-file-task" \
    -H "Content-Type: application/json" \
    -d '{
        "filename": "test-document.pdf",
        "processing_time": 3
    }'
```

### Submit a Data Processing Task

```bash
# Submit a data transformation task
curl -X POST "${API_URL}/submit-data-task" \
    -H "Content-Type: application/json" \
    -d '{
        "dataset_size": 500,
        "transformation": "aggregation"
    }'
```

### Execute Background Job Manually

```bash
# Get job name from outputs
JOB_NAME=$(terraform output -raw job_name)

# Execute the job to process queued messages
gcloud run jobs execute ${JOB_NAME} \
    --region=${REGION} \
    --wait
```

### Verify Results

```bash
# Get bucket name from outputs
BUCKET_NAME=$(terraform output -raw bucket_name)

# List processed files
gsutil ls -r gs://${BUCKET_NAME}/

# View a processed file
gsutil cat gs://${BUCKET_NAME}/processed/test-document.pdf
```

## Monitoring and Logging

### View Job Execution Logs

```bash
# View Cloud Run Job logs
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=${JOB_NAME}" \
    --limit=50 \
    --format="table(timestamp,textPayload)"
```

### Monitor Pub/Sub Messages

```bash
# Check subscription status
gcloud pubsub subscriptions describe ${SUBSCRIPTION_NAME}

# Pull messages manually (for debugging)
gcloud pubsub subscriptions pull ${SUBSCRIPTION_NAME} \
    --auto-ack \
    --limit=5
```

### API Service Metrics

```bash
# View API service logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=task-api" \
    --limit=50
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/background-task-processing
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# When prompted, type 'yes' to confirm deletion
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud run jobs list --filter="metadata.name:background-worker"
gcloud run services list --filter="metadata.name:task-api"
gcloud pubsub topics list --filter="name:task-queue"
gsutil ls -p ${PROJECT_ID} | grep task-files
```

## Customization

### Scaling Configuration

To adjust worker scaling behavior, modify these parameters:

```hcl
# In terraform/variables.tf or Infrastructure Manager config
variable "job_parallelism" {
  description = "Number of tasks to run in parallel"
  type        = number
  default     = 1
}

variable "job_task_count" {
  description = "Number of tasks to execute per job run"
  type        = number
  default     = 1
}
```

### Security Enhancements

1. **Enable VPC Connector**: For private network access
2. **Configure IAM Conditions**: Add time and IP-based restrictions
3. **Enable Audit Logging**: Track all API and resource access
4. **Add Secret Manager**: Store sensitive configuration securely

### Performance Optimization

1. **Adjust CPU and Memory**: Optimize for your specific workload
2. **Configure Concurrency**: Set appropriate request concurrency limits
3. **Implement Caching**: Add Redis for frequently accessed data
4. **Enable CDN**: Use Cloud CDN for static content delivery

## Troubleshooting

### Common Issues

1. **Job Execution Failures**:
   ```bash
   # Check job execution history
   gcloud run jobs executions list --job=${JOB_NAME} --region=${REGION}
   ```

2. **API Service Errors**:
   ```bash
   # Check service deployment status
   gcloud run services describe task-api --region=${REGION}
   ```

3. **Pub/Sub Message Backlog**:
   ```bash
   # Monitor message backlog
   gcloud pubsub subscriptions describe ${SUBSCRIPTION_NAME}
   ```

4. **Storage Access Issues**:
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://${BUCKET_NAME}
   ```

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
export DEBUG=true
export LOG_LEVEL=DEBUG
```

## Cost Optimization

### Monitoring Costs

- Use Cloud Billing budgets and alerts
- Monitor Cloud Run CPU and memory utilization
- Optimize Pub/Sub message retention periods
- Implement Cloud Storage lifecycle policies

### Resource Optimization

- Set appropriate Cloud Run concurrency limits
- Use minimum instances = 0 for cost savings
- Configure Pub/Sub dead letter queues
- Implement intelligent retry policies

## Security Best Practices

1. **Least Privilege IAM**: Grant minimal necessary permissions
2. **Service Account Keys**: Avoid downloading service account keys
3. **VPC Security**: Use private networking where possible
4. **Audit Logging**: Enable comprehensive audit trails
5. **Secret Management**: Use Secret Manager for sensitive data

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud Run documentation
3. Consult Pub/Sub troubleshooting guides
4. Check Cloud Storage access patterns
5. Review Infrastructure Manager or Terraform provider documentation

## Additional Resources

- [Cloud Run Jobs Documentation](https://cloud.google.com/run/docs/create-jobs)
- [Pub/Sub Best Practices](https://cloud.google.com/pubsub/docs/best-practices)
- [Cloud Storage Integration Patterns](https://cloud.google.com/storage/docs/cloud-console)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)