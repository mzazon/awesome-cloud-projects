# Infrastructure as Code for AI Training Optimization with Dynamic Workload Scheduler and Batch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Training Optimization with Dynamic Workload Scheduler and Batch".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Required Tools
- Google Cloud CLI installed and configured (gcloud version 380.0.0 or later)
- Terraform installed (version 1.0+ for Terraform implementation)
- `jq` command-line JSON processor
- OpenSSL for generating random identifiers

### Required Permissions
- Compute Engine API enabled
- Cloud Batch API enabled  
- Cloud Monitoring API enabled
- Cloud Storage API enabled
- IAM permissions:
  - Batch Job Editor
  - Compute Instance Admin
  - Service Account User
  - Storage Admin
  - Monitoring Editor

### Estimated Costs
- GPU resources: $15-25 for 45-minute training session
- Storage: $0.02-0.05 per GB for training data
- Monitoring: Minimal cost for metrics and logs

## Quick Start

### Using Infrastructure Manager

1. Set up your Google Cloud project:
   ```bash
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   gcloud config set project ${PROJECT_ID}
   ```

2. Deploy the infrastructure:
   ```bash
   gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/ai-training-deployment \
       --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
       --local-source="infrastructure-manager/" \
       --inputs-file="infrastructure-manager/inputs.yaml"
   ```

3. Monitor deployment status:
   ```bash
   gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/ai-training-deployment
   ```

### Using Terraform

1. Initialize Terraform:
   ```bash
   cd terraform/
   terraform init
   ```

2. Review and customize variables:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your project settings
   ```

3. Plan and apply the infrastructure:
   ```bash
   terraform plan
   terraform apply
   ```

4. View outputs:
   ```bash
   terraform output
   ```

### Using Bash Scripts

1. Set up environment variables:
   ```bash
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   export ZONE="us-central1-a"
   ```

2. Make scripts executable and deploy:
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

3. Monitor the deployment:
   ```bash
   # The script will provide monitoring commands and job status
   ```

## Architecture Overview

The deployed infrastructure includes:

- **Dynamic Workload Scheduler**: Optimizes GPU resource allocation with up to 53% cost savings
- **Cloud Batch**: Manages training job execution and scaling
- **Cloud Storage**: Stores training datasets, scripts, and model outputs
- **Compute Engine**: GPU-enabled instances (G2 with NVIDIA L4 GPUs)
- **Cloud Monitoring**: Dashboards and alerts for performance tracking
- **IAM Service Accounts**: Secure access to resources

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/inputs.yaml`:

```yaml
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"
machine_type: "g2-standard-4"
gpu_type: "nvidia-l4"
gpu_count: 1
boot_disk_size: 50
training_duration_minutes: 15
```

### Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Instance configuration
machine_type    = "g2-standard-4"
gpu_type        = "nvidia-l4"
gpu_count       = 1
boot_disk_size  = 50

# Training configuration
training_duration_minutes = 15
max_training_time_seconds  = 3600

# Resource naming
random_suffix = "abc123"  # Or leave empty for auto-generation

# Labels for cost tracking
labels = {
  workload-type = "ai-training"
  cost-center   = "ml-research"
  environment   = "development"
}
```

### Bash Script Configuration

Modify environment variables in `scripts/deploy.sh`:

```bash
# Deployment configuration
export MACHINE_TYPE="g2-standard-4"
export GPU_TYPE="nvidia-l4"
export GPU_COUNT="1"
export BOOT_DISK_SIZE="50"
export TRAINING_DURATION="15"  # minutes
```

## Post-Deployment Steps

### 1. Upload Training Data

```bash
# Copy your training datasets to the created bucket
gsutil cp -r /path/to/your/training/data gs://ai-training-data-*/datasets/

# Upload custom training scripts
gsutil cp your_training_script.py gs://ai-training-data-*/scripts/
```

### 2. Submit Training Jobs

```bash
# Get the job template from outputs
export JOB_CONFIG=$(terraform output -raw batch_job_config_file)  # For Terraform
# Or use the generated job configuration from scripts deployment

# Submit a training job
gcloud batch jobs submit my-training-job-$(date +%s) \
    --location=${REGION} \
    --config=${JOB_CONFIG}
```

### 3. Monitor Training Progress

```bash
# View monitoring dashboard URL
echo "Monitoring Dashboard: $(terraform output -raw monitoring_dashboard_url)"

# Check job status
gcloud batch jobs list --location=${REGION}

# View training logs
gcloud logging read "resource.type=\"batch_job\"" --limit=20
```

## Monitoring and Optimization

### Key Metrics to Monitor

1. **GPU Utilization**: Target >70% for cost efficiency
2. **Job Queue Time**: Monitor Dynamic Workload Scheduler performance
3. **Training Progress**: Accuracy, loss, and convergence metrics
4. **Cost per Training Run**: Track spending patterns

### Alert Policies

The infrastructure automatically creates alerts for:
- GPU utilization below 70%
- Job failures or timeouts
- Unexpected cost spikes

### Cost Optimization

```bash
# View current resource costs
gcloud billing budgets list

# Monitor GPU usage patterns
gcloud monitoring metrics list --filter="metric.type:compute.googleapis.com/instance/accelerator"

# Analyze job efficiency
gcloud batch jobs describe JOB_NAME --location=${REGION} --format="yaml(statusEvents)"
```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/ai-training-deployment
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **GPU Quota Exceeded**
   ```bash
   # Check current quotas
   gcloud compute project-info describe --format="yaml(quotas)"
   
   # Request quota increase
   gcloud alpha compute quotas list --filter="metric:nvidia_l4_gpus"
   ```

2. **Job Stuck in Queue**
   ```bash
   # Check Dynamic Workload Scheduler status
   gcloud batch jobs describe JOB_NAME --location=${REGION} --format="yaml(statusEvents)"
   
   # View queue position and resource availability
   gcloud compute accelerator-types list --zones=${ZONE}
   ```

3. **High Costs**
   ```bash
   # Enable cost monitoring
   gcloud billing budgets create --billing-account=BILLING_ACCOUNT_ID \
       --display-name="AI Training Budget" \
       --budget-amount=100USD
   
   # Use Flex Start mode for additional savings
   # (configured automatically in the infrastructure)
   ```

4. **Training Script Failures**
   ```bash
   # Check container logs
   gcloud logging read "resource.type=\"batch_job\" AND resource.labels.job_id=\"JOB_NAME\""
   
   # Verify training script accessibility
   gsutil ls gs://ai-training-data-*/scripts/
   ```

### Performance Optimization

1. **Optimize Data Loading**:
   - Use Cloud Storage FUSE for faster data access
   - Implement parallel data loading in training scripts
   - Use Cloud Storage Transfer Service for large datasets

2. **GPU Efficiency**:
   - Monitor GPU memory utilization
   - Optimize batch sizes for your specific models
   - Use mixed precision training when supported

3. **Cost Management**:
   - Leverage Dynamic Workload Scheduler Flex Start mode
   - Use preemptible instances for development workloads
   - Implement automatic job termination for runaway processes

## Advanced Configuration

### Custom Training Images

```bash
# Build custom container image
docker build -t gcr.io/${PROJECT_ID}/custom-training:latest .
docker push gcr.io/${PROJECT_ID}/custom-training:latest

# Update job configuration to use custom image
# Edit the batch job JSON configuration
```

### Multi-Region Deployment

```bash
# Deploy to multiple regions for disaster recovery
export BACKUP_REGION="us-west1"

# Run deployment scripts with different region settings
REGION=${BACKUP_REGION} ./scripts/deploy.sh
```

### Integration with Vertex AI

```bash
# Use Vertex AI for hyperparameter tuning
gcloud ai hp-tuning-jobs create \
    --display-name="hyperparameter-tuning-job" \
    --config=vertex-ai-config.yaml
```

## Security Considerations

### IAM Best Practices
- Service accounts use least privilege access
- Workload Identity enabled for secure access
- Regular audit of IAM permissions

### Data Security
- Encryption at rest enabled for Cloud Storage
- VPC Service Controls for additional network security
- Secure transmission of training data

### Compliance
- Cloud Security Command Center integration
- Audit logging enabled for all resources
- Regular security scanning of container images

## Support and Resources

### Documentation Links
- [Dynamic Workload Scheduler Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/dws)
- [Cloud Batch Documentation](https://cloud.google.com/batch/docs)
- [GPU Optimization Guide](https://cloud.google.com/compute/docs/gpus)

### Community Resources
- [Google Cloud AI/ML Community](https://cloud.google.com/community)
- [Cloud Batch GitHub Examples](https://github.com/GoogleCloudPlatform/batch-samples)

### Getting Help
- For infrastructure issues: Check Google Cloud Console and logs
- For training optimization: Review monitoring dashboards
- For cost concerns: Use Cloud Billing reports and budgets

## Version History

- **v1.1**: Added Dynamic Workload Scheduler integration
- **v1.0**: Initial implementation with Cloud Batch and basic monitoring

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud's official documentation.