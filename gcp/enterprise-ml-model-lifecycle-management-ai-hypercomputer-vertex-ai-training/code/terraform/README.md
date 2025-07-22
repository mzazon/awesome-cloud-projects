# Terraform Infrastructure for Enterprise ML Model Lifecycle Management

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive enterprise ML model lifecycle management system on Google Cloud Platform. The infrastructure includes Cloud Workstations, AI Hypercomputer resources, Vertex AI services, and supporting components for a complete ML development and training environment.

## Architecture Overview

This Terraform configuration deploys the following components:

- **Cloud Workstations**: Secure, managed development environments for data science teams
- **AI Hypercomputer Infrastructure**: High-performance TPU and GPU resources for model training
- **Vertex AI Platform**: Comprehensive ML platform with metadata store and Tensorboard
- **Storage & Data**: Cloud Storage for artifacts, BigQuery for experiments, Artifact Registry for containers
- **Networking**: VPC with private subnets and security-focused firewall rules
- **Security**: Service accounts, IAM roles, optional Binary Authorization
- **Monitoring**: Cloud Logging, Cloud Monitoring, and budget alerts

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK** installed and configured
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Terraform** installed (version >= 1.0)
   ```bash
   terraform --version
   ```

3. **Google Cloud Project** with billing enabled
   ```bash
   gcloud config set project YOUR_PROJECT_ID
   ```

4. **Required APIs** enabled (will be enabled automatically by Terraform)
   - AI Platform API
   - Vertex AI API
   - Cloud Workstations API
   - Compute Engine API
   - Cloud Storage API
   - BigQuery API
   - Artifact Registry API

5. **IAM Permissions** - Your account needs the following roles:
   - Project Editor or Owner
   - Billing Account Administrator (if using budget alerts)
   - Security Admin (if using Binary Authorization)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/enterprise-ml-model-lifecycle-management-ai-hypercomputer-vertex-ai-training/code/terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
resource_prefix = "my-ml-env"
environment     = "dev"

# AI Hypercomputer configuration
enable_tpu_training = true
enable_gpu_training = true
tpu_accelerator_type = "v5litepod-4"
gpu_machine_type = "a3-highgpu-8g"
gpu_accelerator_count = 8

# Workstation configuration
workstation_machine_type = "n1-standard-8"
workstation_disk_size = 200

# Cost management
enable_budget_alerts = true
budget_amount = 1000
billing_account_name = "My Billing Account"

# Security features
enable_binary_authorization = false
enable_vulnerability_scanning = true

# Resource labels
labels = {
  "project"     = "enterprise-ml"
  "team"        = "data-science"
  "environment" = "development"
}
```

### 4. Plan and Apply

```bash
# Review the planned infrastructure
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Access Your Infrastructure

After deployment, use the output values to access your resources:

```bash
# Get workstation access command
terraform output -raw quick_start_commands
```

## Configuration Options

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Primary region for resources | `us-central1` | No |
| `zone` | Primary zone for zonal resources | `us-central1-a` | No |
| `resource_prefix` | Prefix for resource names | `enterprise-ml` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |

### AI Hypercomputer Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_tpu_training` | Enable TPU resources | `true` | No |
| `tpu_accelerator_type` | TPU accelerator type | `v5litepod-4` | No |
| `enable_gpu_training` | Enable GPU resources | `true` | No |
| `gpu_machine_type` | GPU machine type | `a3-highgpu-8g` | No |
| `gpu_accelerator_type` | GPU accelerator type | `nvidia-h100-80gb` | No |
| `gpu_accelerator_count` | Number of GPU accelerators | `8` | No |

### Cloud Workstations Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `workstation_machine_type` | Machine type for workstations | `n1-standard-8` | No |
| `workstation_disk_size` | Disk size in GB | `200` | No |
| `workstation_disk_type` | Disk type | `pd-ssd` | No |

### Security Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_binary_authorization` | Enable container security | `true` | No |
| `enable_vulnerability_scanning` | Enable vulnerability scanning | `true` | No |
| `workstation_service_account_roles` | IAM roles for workstations | See variables.tf | No |
| `training_service_account_roles` | IAM roles for training | See variables.tf | No |

### Cost Management

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_budget_alerts` | Enable budget monitoring | `true` | No |
| `budget_amount` | Budget amount in USD | `1000` | No |
| `budget_alert_thresholds` | Alert thresholds (%) | `[50, 75, 90, 100]` | No |

## Advanced Configuration

### Multi-Region Deployment

For high availability, enable multi-region deployment:

```hcl
enable_multi_region_deployment = true
enable_disaster_recovery = true
```

### Production Security

For production deployments, enable additional security features:

```hcl
environment = "prod"
enable_binary_authorization = true
enable_vulnerability_scanning = true
enable_private_google_access = true
```

### Custom Networking

To use existing VPC resources:

```hcl
# Create data sources for existing resources
data "google_compute_network" "existing_network" {
  name = "my-existing-network"
}

# Then reference in your configuration
```

## Outputs

The Terraform configuration provides comprehensive outputs including:

- **Access Information**: URLs and commands to access deployed resources
- **Resource Details**: Names, IDs, and configurations of all deployed resources
- **Quick Start Commands**: Copy-paste commands for immediate use
- **Infrastructure Summary**: High-level overview of deployed components
- **Security Information**: Service account details and IAM configurations

### Key Outputs

```bash
# View all outputs
terraform output

# Get specific output
terraform output workstation_access_url
terraform output ml_artifacts_bucket_name
terraform output vertex_ai_tensorboard_web_access_uris
```

## Usage Examples

### Accessing Cloud Workstations

```bash
# Start workstation tunnel
gcloud workstations start-tcp-tunnel \
  --project=YOUR_PROJECT_ID \
  --cluster=CLUSTER_NAME \
  --config=CONFIG_NAME \
  --workstation=WORKSTATION_NAME \
  --region=us-central1 \
  --local-host-port=localhost:8080 \
  --port=22
```

### Running Training Jobs

```bash
# Submit Vertex AI training job
gcloud ai custom-jobs create \
  --region=us-central1 \
  --config=training_job_config.json \
  --display-name=my-training-job
```

### Accessing Storage

```bash
# List artifacts in bucket
gsutil ls gs://YOUR_BUCKET_NAME/

# Upload training data
gsutil cp -r ./data gs://YOUR_BUCKET_NAME/datasets/
```

## Cost Optimization

### Resource Scheduling

To optimize costs, consider implementing resource scheduling:

```bash
# Stop GPU instances when not in use
gcloud compute instances stop INSTANCE_NAME --zone=us-central1-a

# Start instances when needed
gcloud compute instances start INSTANCE_NAME --zone=us-central1-a
```

### Preemptible Instances

For non-critical workloads, use preemptible instances:

```hcl
scheduling {
  preemptible = true
  on_host_maintenance = "TERMINATE"
  automatic_restart = false
}
```

### Storage Lifecycle

Configure storage lifecycle policies:

```hcl
lifecycle_rule {
  condition {
    age = 30
  }
  action {
    type = "SetStorageClass"
    storage_class = "NEARLINE"
  }
}
```

## Security Best Practices

### Service Account Security

- Use dedicated service accounts for different workloads
- Apply principle of least privilege
- Regularly rotate service account keys
- Enable audit logging for service account usage

### Network Security

- Use private subnets with no external IP addresses
- Implement VPC firewall rules with minimal required access
- Enable VPC flow logs for monitoring
- Consider VPC Service Controls for additional security

### Data Security

- Enable encryption at rest for all storage
- Use customer-managed encryption keys (CMEK) for sensitive data
- Implement data loss prevention (DLP) policies
- Regular security scanning of container images

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   gcloud services enable REQUIRED_API
   ```

2. **Insufficient Permissions**
   ```bash
   gcloud projects add-iam-policy-binding PROJECT_ID \
     --member="user:EMAIL" \
     --role="roles/REQUIRED_ROLE"
   ```

3. **Resource Quotas**
   ```bash
   gcloud compute project-info describe --project=PROJECT_ID
   ```

4. **TPU/GPU Availability**
   ```bash
   gcloud compute accelerator-types list --filter="zone:us-central1-a"
   ```

### Debug Commands

```bash
# Check resource status
terraform state list
terraform state show RESOURCE_NAME

# Validate configuration
terraform validate
terraform fmt -check

# Import existing resources
terraform import RESOURCE_TYPE.NAME RESOURCE_ID
```

## Monitoring and Alerts

### Cloud Monitoring

The infrastructure includes monitoring for:
- Resource utilization (CPU, memory, GPU)
- Training job status and performance
- Storage usage and costs
- Network traffic and security events

### Custom Metrics

Create custom metrics for ML-specific monitoring:

```bash
# Create custom metric
gcloud logging metrics create ml_training_success \
  --description="ML training job success rate" \
  --log-filter="resource.type=gce_instance AND jsonPayload.status=success"
```

### Alerting Policies

Set up alerts for critical events:

```bash
# Create alerting policy
gcloud alpha monitoring policies create \
  --policy-from-file=alerting-policy.yaml
```

## Backup and Disaster Recovery

### Data Backup

```bash
# Backup storage buckets
gsutil cp -r gs://source-bucket gs://backup-bucket

# Backup BigQuery datasets
bq mk --transfer_config \
  --project_id=PROJECT_ID \
  --data_source=cloud_storage \
  --target_dataset=backup_dataset
```

### Infrastructure Backup

```bash
# Export Terraform state
terraform show -json > terraform-state-backup.json

# Export resource configurations
gcloud config export-configs --all --path=./config-backup
```

## Updates and Maintenance

### Terraform Updates

```bash
# Update providers
terraform init -upgrade

# Plan changes
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan
```

### Security Updates

```bash
# Update container images
gcloud builds submit --tag gcr.io/PROJECT_ID/IMAGE_NAME:latest

# Update OS packages
gcloud compute instances add-metadata INSTANCE_NAME \
  --metadata-from-file startup-script=update-script.sh
```

## Cleanup

### Partial Cleanup

```bash
# Destroy specific resources
terraform destroy -target=google_compute_instance.ml_gpu_training
```

### Complete Cleanup

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

### Manual Cleanup

If Terraform destroy fails, manually delete resources:

```bash
# Delete compute instances
gcloud compute instances delete INSTANCE_NAME --zone=ZONE

# Delete storage buckets
gsutil rm -r gs://BUCKET_NAME

# Delete BigQuery datasets
bq rm -r -d PROJECT_ID:DATASET_NAME
```

## Support and Contributing

### Getting Help

1. Check the [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
2. Review [Google Cloud AI/ML documentation](https://cloud.google.com/ai-platform/docs)
3. Check the [issues section](https://github.com/your-repo/issues) for known problems

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

### Reporting Issues

When reporting issues, please include:
- Terraform version
- Provider version
- Error messages
- Resource configurations
- Steps to reproduce

## License

This Terraform configuration is provided under the [MIT License](LICENSE).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.