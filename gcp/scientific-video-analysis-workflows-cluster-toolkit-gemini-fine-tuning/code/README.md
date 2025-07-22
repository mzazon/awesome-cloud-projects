# Infrastructure as Code for Scientific Video Analysis Workflows with Cluster Toolkit and Gemini Fine-tuning

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scientific Video Analysis Workflows with Cluster Toolkit and Gemini Fine-tuning".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate quotas for compute resources:
  - Compute Engine instances (minimum 32 vCPUs)
  - GPU resources (T4 or V100 GPUs)
  - Cloud Storage (minimum 1TB)
- Required permissions:
  - Compute Engine Admin
  - Storage Admin
  - Vertex AI Administrator
  - BigQuery Admin
  - Cloud Dataflow Admin
  - Service Account Admin
- Terraform (>= 1.5) installed (for Terraform deployment)
- Scientific video dataset for analysis (minimum 100GB recommended)
- Estimated cost: $200-500 depending on cluster size and processing duration

> **Warning**: This infrastructure creates significant compute resources that can incur substantial costs. Monitor usage carefully and clean up resources when not needed.

## Quick Start

### Using Infrastructure Manager

```bash
# Create deployment configuration
gcloud infra-manager deployments create video-analysis-deployment \
    --location=us-central1 \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --git-source-repo=https://github.com/your-repo/infrastructure \
    --git-source-directory=infrastructure-manager/ \
    --git-source-ref=main \
    --input-values=project_id=PROJECT_ID,region=us-central1

# Apply the deployment
gcloud infra-manager deployments apply video-analysis-deployment \
    --location=us-central1
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Note the important outputs
terraform output cluster_login_command
terraform output storage_bucket_name
terraform output vertex_ai_endpoint
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete infrastructure
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create Cloud Storage buckets
# 3. Deploy HPC cluster using Cluster Toolkit
# 4. Configure Vertex AI endpoints
# 5. Set up BigQuery datasets
# 6. Deploy monitoring and automation scripts
```

## Architecture Components

The infrastructure deploys:

- **HPC Cluster**: Slurm-based cluster with CPU and GPU partitions
- **Cluster Toolkit**: Infrastructure provisioning and management
- **Vertex AI**: Model endpoints for Gemini fine-tuning
- **Cloud Storage**: Data lake for videos and results
- **Cloud Dataflow**: Pipeline orchestration
- **BigQuery**: Results storage and analytics
- **Monitoring**: Job scheduling and performance tracking

## Configuration Options

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export CLUSTER_NAME="video-analysis-cluster"
export BUCKET_NAME="scientific-video-data-${RANDOM_SUFFIX}"
```

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `project_id`: Your GCP project ID
- `region`: Deployment region (default: us-central1)
- `cluster_name`: Name for the HPC cluster
- `max_compute_nodes`: Maximum nodes in compute partition (default: 10)
- `max_gpu_nodes`: Maximum nodes in GPU partition (default: 4)
- `storage_bucket_name`: Cloud Storage bucket name
- `enable_auto_scaling`: Enable cluster auto-scaling (default: true)

### Infrastructure Manager Variables

Key inputs for Infrastructure Manager deployment:

- `project_id`: Your GCP project ID
- `region`: Deployment region
- `cluster_configuration`: HPC cluster settings
- `ai_model_settings`: Vertex AI model configuration

## Post-Deployment Setup

### 1. Access the HPC Cluster

```bash
# Get cluster login command from Terraform output
CLUSTER_LOGIN=$(terraform output -raw cluster_login_command)
$CLUSTER_LOGIN

# Or connect directly
gcloud compute ssh video-analysis-cluster-login-0 \
    --zone=us-central1-a
```

### 2. Upload Scientific Videos

```bash
# Upload your video dataset
gsutil -m cp -r /path/to/your/videos/ \
    gs://$(terraform output -raw storage_bucket_name)/raw-videos/

# Set up metadata
gsutil cp video-metadata.json \
    gs://$(terraform output -raw storage_bucket_name)/raw-videos/metadata/
```

### 3. Submit Video Analysis Jobs

```bash
# On the cluster login node
/shared/scripts/submit-video-analysis.sh \
    gs://bucket-name/raw-videos/your-video.mp4 \
    bucket-name \
    projects/PROJECT_ID/locations/REGION/endpoints/scientific-video-gemini
```

### 4. Monitor Processing

```bash
# Check job status
squeue

# View processing logs
tail -f /shared/logs/video-analysis-*.out

# Monitor via Cloud Console
gcloud logging read "resource.type=gce_instance AND logName=projects/PROJECT_ID/logs/video-analysis"
```

## Usage Examples

### Processing Multiple Videos

```bash
# Batch process all videos in a directory
for video in gs://bucket-name/raw-videos/*.mp4; do
    /shared/scripts/submit-video-analysis.sh \
        $video \
        bucket-name \
        projects/PROJECT_ID/locations/REGION/endpoints/scientific-video-gemini
done
```

### Querying Results

```bash
# Query processed results in BigQuery
bq query --use_legacy_sql=false \
    "SELECT video_file, analysis_results, timestamp 
     FROM \`PROJECT_ID.video_analysis_results.video_analysis_results\` 
     WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
     ORDER BY timestamp DESC"
```

### Monitoring Cluster Performance

```bash
# View cluster utilization
sinfo -N -l

# Check node status
scontrol show nodes

# View completed jobs
sacct -S today
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete video-analysis-deployment \
    --location=us-central1 \
    --delete-policy=DELETE
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Drain and delete the HPC cluster
# 2. Remove Vertex AI endpoints and models
# 3. Delete Cloud Storage buckets
# 4. Remove BigQuery datasets
# 5. Clean up IAM roles and service accounts
```

### Manual Cleanup Verification

```bash
# Verify HPC cluster removal
gcloud compute instances list --filter="name:video-analysis-cluster"

# Check storage bucket deletion
gsutil ls gs://scientific-video-data-*

# Verify Vertex AI cleanup
gcloud ai endpoints list --region=us-central1

# Check BigQuery datasets
bq ls --project_id=PROJECT_ID
```

## Troubleshooting

### Common Issues

**Cluster deployment fails**:
- Verify compute quotas are sufficient
- Check IAM permissions for Cluster Toolkit
- Ensure required APIs are enabled

**Video processing jobs fail**:
- Check GPU availability with `sinfo -p gpu`
- Verify model endpoint is accessible
- Review job logs in `/shared/logs/`

**Storage access errors**:
- Verify service account permissions
- Check bucket accessibility with `gsutil ls`
- Ensure proper authentication setup

**High costs**:
- Monitor cluster auto-scaling behavior
- Check for idle GPU nodes
- Review storage lifecycle policies

### Performance Optimization

**Cluster scaling**:
```bash
# Adjust cluster size
scontrol update NodeName=compute-[1-20] State=RESUME

# Enable preemptible instances for cost savings
scontrol update NodeName=compute-[1-10] Features=preemptible
```

**Storage optimization**:
```bash
# Set lifecycle policies
gsutil lifecycle set lifecycle.json gs://bucket-name
```

**Model optimization**:
- Use batch prediction for multiple videos
- Cache model responses for similar content
- Fine-tune model with domain-specific data

## Security Considerations

- All storage buckets use encryption at rest
- Cluster communication uses private IPs
- Service accounts follow least privilege principle
- Network access is restricted to necessary ports
- Audit logging is enabled for all resources

## Customization

### Adding Custom Analysis Scripts

```bash
# Deploy custom analysis code to cluster
gcloud compute scp custom-analysis.py \
    video-analysis-cluster-login-0:/shared/scripts/ \
    --zone=us-central1-a
```

### Integrating Additional AI Models

```bash
# Deploy additional Vertex AI models
gcloud ai models upload \
    --region=us-central1 \
    --display-name=custom-video-model \
    --container-image-uri=gcr.io/PROJECT_ID/custom-model
```

### Scaling Configuration

Modify cluster size by updating:
- Terraform: `max_compute_nodes` and `max_gpu_nodes` variables
- Infrastructure Manager: cluster configuration inputs
- Scripts: edit cluster configuration files

## Monitoring and Logging

### Cloud Monitoring Dashboards

The infrastructure includes custom dashboards for:
- Cluster utilization metrics
- Video processing throughput
- Storage usage and costs
- AI model performance

### Alerting

Configure alerts for:
- High cluster utilization
- Failed video processing jobs
- Storage quota approaching limits
- Unusual cost increases

## Support and Documentation

- [Google Cloud Cluster Toolkit Documentation](https://cloud.google.com/cluster-toolkit/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud Dataflow Documentation](https://cloud.google.com/dataflow/docs)
- [HPC on Google Cloud Best Practices](https://cloud.google.com/architecture/best-practices-for-using-mpi-on-compute-engine)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support channels.

## Cost Management

### Monitoring Costs

```bash
# Set up billing alerts
gcloud alpha billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Video Analysis Budget" \
    --budget-amount=500 \
    --threshold-rule=percent=80

# Monitor current spend
gcloud billing accounts get-iam-policy BILLING_ACCOUNT_ID
```

### Cost Optimization Tips

- Use preemptible instances for non-critical workloads
- Enable cluster auto-scaling to reduce idle resources
- Set up storage lifecycle policies for automatic data archival
- Monitor and optimize model inference costs
- Use committed use discounts for predictable workloads

## License

This infrastructure code is provided under the same license as the original recipe documentation.