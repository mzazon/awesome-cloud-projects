# Terraform Infrastructure for Batch Processing with Cloud Run Jobs and Cloud Scheduler

This Terraform configuration creates a complete serverless batch processing system on Google Cloud Platform using Cloud Run Jobs, Cloud Scheduler, and supporting services.

## Architecture Overview

The infrastructure provisions:

- **Cloud Run Jobs** for containerized batch processing workloads
- **Cloud Scheduler** for automated job execution based on cron schedules
- **Artifact Registry** for secure container image storage
- **Cloud Storage** for input/output data management
- **Cloud Build** for automated container image building
- **IAM Service Account** with appropriate permissions
- **Monitoring and Alerting** for operational visibility

## Prerequisites

1. **Google Cloud Project**: Active GCP project with billing enabled
2. **Terraform**: Version 1.0 or later installed
3. **Google Cloud CLI**: Installed and authenticated
4. **Required Permissions**: Owner or Editor role on the target project
5. **APIs**: The following APIs will be enabled automatically:
   - Cloud Build API
   - Artifact Registry API
   - Cloud Run API
   - Cloud Scheduler API
   - Cloud Storage API
   - Cloud Logging API
   - Cloud Monitoring API

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository and navigate to the terraform directory
cd gcp/batch-processing-cloud-run-jobs-scheduler/code/terraform

# Initialize Terraform
terraform init
```

### 2. Create terraform.tfvars

```hcl
# terraform.tfvars
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional: Customize resource names
resource_prefix = "batch-processing"
environment     = "dev"

# Optional: Customize batch processing configuration
scheduler_cron_schedule = "0 2 * * *"  # Daily at 2 AM
scheduler_timezone      = "America/New_York"

# Optional: Customize job resources
job_cpu    = "1"
job_memory = "2Gi"
job_task_timeout = 3600  # 1 hour

# Optional: Labels for resource management
labels = {
  environment = "dev"
  team        = "data-engineering"
  project     = "batch-processing"
}
```

### 3. Deploy Infrastructure

```bash
# Validate the configuration
terraform validate

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

```bash
# Check Cloud Run job
gcloud run jobs list --region=us-central1

# Check Cloud Scheduler job
gcloud scheduler jobs list --location=us-central1

# Check Artifact Registry
gcloud artifacts repositories list --location=us-central1

# Check Cloud Storage bucket
gsutil ls -p your-project-id
```

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | Google Cloud Project ID | `"my-project-123"` |

### Optional Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `region` | GCP region | `"us-central1"` | `"europe-west1"` |
| `zone` | GCP zone | `"us-central1-a"` | `"europe-west1-b"` |
| `resource_prefix` | Prefix for resource names | `"batch-processing"` | `"data-pipeline"` |
| `environment` | Environment name | `"dev"` | `"prod"` |
| `scheduler_cron_schedule` | Cron schedule | `"0 * * * *"` | `"0 2 * * *"` |
| `scheduler_timezone` | Timezone | `"America/New_York"` | `"UTC"` |
| `job_cpu` | CPU allocation | `"1"` | `"2"` |
| `job_memory` | Memory allocation | `"2Gi"` | `"4Gi"` |
| `job_task_timeout` | Task timeout (seconds) | `3600` | `7200` |
| `container_image` | Container image URL | `""` (auto-generated) | `"gcr.io/project/image:tag"` |
| `enable_monitoring` | Enable monitoring | `true` | `false` |

## Outputs

After deployment, Terraform provides useful outputs:

```bash
# View all outputs
terraform output

# View specific output
terraform output cloud_run_job_name
terraform output storage_bucket_name
terraform output container_image_url
```

### Key Outputs

- `cloud_run_job_name`: Name of the created Cloud Run job
- `storage_bucket_name`: Name of the Cloud Storage bucket
- `scheduler_job_name`: Name of the Cloud Scheduler job
- `artifact_registry_repository_url`: URL of the Artifact Registry repository
- `service_account_email`: Email of the service account
- `quick_start_commands`: Commands for testing and validation

## Testing the Deployment

### 1. Manual Job Execution

```bash
# Execute the batch job manually
export JOB_NAME=$(terraform output -raw cloud_run_job_name)
export REGION=$(terraform output -raw region)

gcloud run jobs execute $JOB_NAME \
    --region=$REGION \
    --wait
```

### 2. Trigger Scheduler Job

```bash
# Trigger the scheduler job manually
export SCHEDULER_JOB=$(terraform output -raw scheduler_job_name)
export REGION=$(terraform output -raw region)

gcloud scheduler jobs run $SCHEDULER_JOB \
    --location=$REGION
```

### 3. Upload Test Data

```bash
# Upload sample data to the input directory
export BUCKET_NAME=$(terraform output -raw storage_bucket_name)

echo "Sample data for processing" | gsutil cp - gs://$BUCKET_NAME/input/test.txt
```

### 4. Check Processing Results

```bash
# List processed files
gsutil ls gs://$BUCKET_NAME/output/

# View processed content
gsutil cat gs://$BUCKET_NAME/output/test.txt
```

### 5. View Logs

```bash
# View job execution logs
gcloud logging read "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"$JOB_NAME\"" \
    --limit=20 \
    --format="table(timestamp,severity,textPayload)"
```

## Container Image Management

### Option 1: Use Provided Sample Application

The Terraform configuration includes a sample batch processing application stored in the Cloud Storage bucket:

```bash
# Download sample application files
export BUCKET_NAME=$(terraform output -raw storage_bucket_name)

gsutil cp gs://$BUCKET_NAME/application/* ./

# Build and push container image
gcloud builds submit \
    --config cloudbuild.yaml \
    --substitutions _REGISTRY_NAME=$(terraform output -raw artifact_registry_repository_id)
```

### Option 2: Use Custom Container Image

```bash
# Build your custom image
docker build -t batch-processor .

# Tag for Artifact Registry
export REGISTRY_URL=$(terraform output -raw artifact_registry_repository_url)
docker tag batch-processor $REGISTRY_URL/batch-processor:latest

# Push to registry
docker push $REGISTRY_URL/batch-processor:latest
```

## Monitoring and Alerting

### View Metrics

```bash
# View Cloud Run job metrics in the console
gcloud logging read "resource.type=\"cloud_run_job\"" --limit=10
```

### Check Alert Policies

```bash
# List alert policies
gcloud alpha monitoring policies list

# View alert policy details
gcloud alpha monitoring policies describe [POLICY_ID]
```

### Custom Dashboards

Create custom dashboards in Google Cloud Console:
1. Navigate to Cloud Monitoring
2. Create dashboard
3. Add charts for:
   - Job execution count
   - Job duration
   - Success/failure rates
   - Resource utilization

## Cost Optimization

### Cost Monitoring

```bash
# Check resource usage
gcloud billing budgets list
gcloud billing budgets describe [BUDGET_ID]
```

### Optimization Recommendations

1. **Job Resources**: Adjust CPU and memory based on actual usage
2. **Storage Classes**: Use lifecycle policies for cost-effective storage
3. **Execution Frequency**: Optimize cron schedules based on business needs
4. **Monitoring**: Disable monitoring in dev environments if not needed

## Troubleshooting

### Common Issues

1. **Job Execution Failures**
   ```bash
   # Check job logs
   gcloud logging read "resource.type=\"cloud_run_job\" AND severity=\"ERROR\"" --limit=10
   ```

2. **Permission Errors**
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy PROJECT_ID
   ```

3. **Image Pull Errors**
   ```bash
   # Verify image exists
   gcloud artifacts docker images list REPOSITORY_URL
   ```

4. **Scheduler Not Triggering**
   ```bash
   # Check scheduler job status
   gcloud scheduler jobs describe JOB_NAME --location=REGION
   ```

### Debug Commands

```bash
# View all resources created by Terraform
terraform state list

# Show detailed resource information
terraform state show 'google_cloud_run_v2_job.batch_processor'

# Check resource dependencies
terraform graph | dot -Tpng > graph.png
```

## Cleanup

### Destroy Infrastructure

```bash
# Review resources to be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy

# Confirm destruction
terraform state list  # Should be empty
```

### Manual Cleanup (if needed)

```bash
# Delete remaining storage objects
gsutil -m rm -r gs://BUCKET_NAME

# Delete log exports
gcloud logging sinks delete SINK_NAME
```

## Customization Examples

### Multi-Environment Setup

```hcl
# environments/dev.tfvars
project_id = "my-project-dev"
environment = "dev"
job_cpu = "0.5"
job_memory = "1Gi"
enable_monitoring = false

# environments/prod.tfvars
project_id = "my-project-prod"
environment = "prod"
job_cpu = "2"
job_memory = "4Gi"
enable_monitoring = true
scheduler_cron_schedule = "0 1 * * *"
```

### High-Performance Configuration

```hcl
# High-performance batch processing
job_cpu = "8"
job_memory = "16Gi"
job_parallelism = 10
job_task_count = 100
build_machine_type = "E2_STANDARD_16"
```

### Multi-Region Setup

```hcl
# Multi-region deployment
regions = ["us-central1", "europe-west1", "asia-east1"]
bucket_location = "US"  # Multi-region bucket
```

## Security Best Practices

1. **Service Account**: Uses least privilege IAM roles
2. **Network Security**: Configurable VPC and subnet settings
3. **Data Encryption**: Encryption at rest and in transit by default
4. **Access Control**: Uniform bucket-level access enabled
5. **Audit Logging**: Comprehensive logging and monitoring

## Support and Documentation

- [Cloud Run Jobs Documentation](https://cloud.google.com/run/docs/create-jobs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Artifact Registry Documentation](https://cloud.google.com/artifact-registry/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This infrastructure code is provided under the Apache License 2.0. See LICENSE file for details.