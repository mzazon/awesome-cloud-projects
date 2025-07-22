# Infrastructure as Code for Large-Scale ML Training Pipelines with TPU v6e and Dataproc Serverless

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete machine learning training pipeline using Google Cloud's TPU v6e (Trillium) processors and Dataproc Serverless.

## Architecture Overview

The infrastructure deploys:

- **Cloud TPU v6e**: Latest generation TPU with 4.7x performance improvement for transformer training
- **Dataproc Serverless**: Managed Apache Spark for scalable data preprocessing
- **Cloud Storage**: High-performance object storage for training data and models
- **Vertex AI**: Managed ML training orchestration
- **Cloud Monitoring**: Comprehensive observability and alerting
- **Cloud Functions**: Pipeline orchestration and automation
- **IAM**: Secure service accounts with least-privilege access

## Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) >= 2.0
- [Google Cloud Project](https://console.cloud.google.com/) with billing enabled

### Required Permissions
Your account needs the following IAM roles:
- `Project Editor` or equivalent custom role with:
  - `compute.admin`
  - `tpu.admin`
  - `dataproc.admin`
  - `storage.admin`
  - `aiplatform.admin`
  - `monitoring.admin`
  - `cloudfunctions.admin`
  - `iam.serviceAccountAdmin`

### API Prerequisites
The following APIs will be automatically enabled by Terraform:
- Compute Engine API
- Cloud TPU API
- Dataproc API
- Cloud Storage API
- Vertex AI API
- Cloud Monitoring API
- Cloud Logging API
- Cloud Functions API
- IAM API

## Quick Start

### 1. Initialize Terraform

```bash
# Clone the repository and navigate to the terraform directory
cd gcp/large-scale-ml-training-pipelines-tpu-v6e-dataproc-serverless/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central2"  # TPU v6e availability
zone       = "us-central2-b"

# Optional customizations
bucket_name_prefix           = "my-ml-pipeline"
tpu_accelerator_type        = "v6e-8"      # or v6e-16, v6e-32, etc.
enable_monitoring           = true
enable_preemptible_tpu      = false        # Set to true for cost savings
dataproc_max_executors      = 20

# Resource labels
resource_labels = {
  environment = "production"
  team        = "ml-engineering"
  project     = "transformer-training"
  cost-center = "research"
}
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check TPU status
gcloud compute tpus describe $(terraform output -raw tpu_name) \
    --zone=$(terraform output -raw zone)

# Check storage bucket
gsutil ls -la gs://$(terraform output -raw storage_bucket_name)/

# View monitoring dashboard
echo "Dashboard URL: $(terraform output -raw monitoring_dashboard_url)"
```

## Configuration Options

### TPU Configuration

```hcl
# TPU accelerator types (choose based on workload)
tpu_accelerator_type = "v6e-8"    # 8 cores, 32GB HBM
tpu_accelerator_type = "v6e-16"   # 16 cores, 64GB HBM
tpu_accelerator_type = "v6e-32"   # 32 cores, 128GB HBM
tpu_accelerator_type = "v6e-64"   # 64 cores, 256GB HBM

# Cost optimization
enable_preemptible_tpu = true     # Up to 70% cost savings
```

### Dataproc Configuration

```hcl
# Executor configuration
dataproc_executor_memory = "8g"   # Memory per executor
dataproc_driver_memory   = "4g"   # Driver memory
dataproc_max_executors   = 50     # Auto-scaling limit
```

### Storage Configuration

```hcl
# Storage options
storage_class               = "STANDARD"  # or NEARLINE, COLDLINE
bucket_versioning_enabled   = true        # Data protection
bucket_uniform_access       = true        # Enhanced security
```

### Monitoring Configuration

```hcl
# Monitoring and alerting
enable_monitoring = true
alert_notification_channels = [
  "projects/PROJECT_ID/notificationChannels/CHANNEL_ID"
]
```

## Cost Management

### Estimated Costs (US Central regions)

| Resource | Hourly Cost (Approx.) | Notes |
|----------|----------------------|-------|
| TPU v6e-8 | $2.40-$3.20 | Varies by region, preemptible saves ~70% |
| Dataproc Serverless | Pay-per-use | ~$0.05-0.15 per vCPU-hour |
| Cloud Storage | Minimal | $0.02/GB/month + operations |
| Vertex AI Training | Included | When using TPU resources |
| Monitoring/Logging | Free tier | First 50GB logs/month free |

### Cost Optimization Tips

1. **Use Preemptible TPUs**: Set `enable_preemptible_tpu = true` for development
2. **Auto-scaling**: Dataproc Serverless automatically scales down when idle
3. **Storage Lifecycle**: Automatic transitions to cheaper storage classes
4. **Monitoring**: Track usage with built-in cost monitoring dashboard

## Security Features

### Service Account Security
- Dedicated service account with minimal required permissions
- No overprivileged default compute service account usage
- Separate service accounts for different components

### Network Security
- Firewall rules restrict TPU access to specified source ranges
- VPC network isolation for TPU and Dataproc resources
- Private Google Access for secure Cloud Storage access

### Data Security
- Cloud Storage uniform bucket-level access
- Object versioning for data protection
- Encryption at rest and in transit by default

## Monitoring and Observability

### Built-in Dashboards
- TPU utilization and performance metrics
- Dataproc batch job status and resource usage
- Training progress and model metrics
- Cost tracking and resource utilization

### Alerting Policies
- High TPU error rates
- Dataproc job failures
- Resource quota approaching limits
- Unexpected cost increases

### Logging
- Centralized logging for all components
- Training progress logs
- Performance debugging information
- Audit logs for security compliance

## Troubleshooting

### Common Issues

1. **TPU v6e Availability**
   ```bash
   # Check TPU availability
   gcloud compute tpus locations describe us-central2 \
       --format="value(availableAcceleratorTypes)"
   ```

2. **Quota Limits**
   ```bash
   # Check TPU quotas
   gcloud compute project-info describe \
       --format="table(quotas.metric,quotas.usage,quotas.limit)"
   ```

3. **Service Account Permissions**
   ```bash
   # Verify service account roles
   gcloud projects get-iam-policy PROJECT_ID \
       --flatten="bindings[].members" \
       --filter="bindings.members:SERVICE_ACCOUNT_EMAIL"
   ```

### Debug Commands

```bash
# TPU status
terraform output useful_commands

# View logs
gcloud logging read 'resource.type="tpu_worker"' --limit=50

# Check Dataproc batch
gcloud dataproc batches describe BATCH_ID --region=REGION

# Monitor training progress
gcloud compute tpus tpu-vm ssh TPU_NAME --zone=ZONE \
    --command="tail -f /tmp/training.log"
```

## Advanced Configuration

### Custom Training Scripts

Replace the default training scripts by modifying the template files:
- `scripts/preprocessing_job.py.tpl`: Dataproc preprocessing logic
- `scripts/tpu_training_script.py.tpl`: TPU training implementation

### Multi-Region Deployment

For multi-region training:

```hcl
# Deploy in multiple regions
module "us_central" {
  source = "./modules/ml-pipeline"
  region = "us-central2"
  # ... other variables
}

module "europe_west" {
  source = "./modules/ml-pipeline"
  region = "europe-west4"
  # ... other variables
}
```

### Custom Networks

For custom VPC networks:

```hcl
# Use custom VPC
tpu_network    = "projects/PROJECT_ID/global/networks/my-vpc"
tpu_subnetwork = "projects/PROJECT_ID/regions/REGION/subnetworks/my-subnet"
```

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy

# Confirm deletion
# Type 'yes' when prompted
```

### Manual Cleanup

Some resources may require manual cleanup:

```bash
# Delete any remaining TPU instances
gcloud compute tpus list --filter="name:training-tpu-*"
gcloud compute tpus delete TPU_NAME --zone=ZONE

# Clean up storage buckets (if force_destroy = false)
gsutil rm -r gs://BUCKET_NAME
```

## Support and Documentation

### Google Cloud Documentation
- [Cloud TPU v6e Documentation](https://cloud.google.com/tpu/docs/v6e)
- [Dataproc Serverless Guide](https://cloud.google.com/dataproc-serverless/docs)
- [Vertex AI Training](https://cloud.google.com/vertex-ai/docs/training)

### Terraform Resources
- [Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

### Best Practices
- [ML on Google Cloud Best Practices](https://cloud.google.com/architecture/ml-on-gcp-best-practices)
- [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)

## Contributing

For improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate with `terraform plan`
3. Follow Google Cloud and Terraform best practices
4. Update documentation for any new variables or outputs

## License

This infrastructure code is provided as-is for educational and reference purposes. Please review and adapt security configurations for production use.