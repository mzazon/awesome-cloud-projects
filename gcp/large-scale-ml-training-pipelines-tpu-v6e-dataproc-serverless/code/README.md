# Infrastructure as Code for Large-Scale ML Training Pipelines with Cloud TPU v6e and Dataproc Serverless

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Large-Scale Machine Learning Training Pipelines with Cloud TPU v6e and Dataproc Serverless".

## Solution Overview

This solution combines Google's latest Cloud TPU v6e (Trillium) processors with Dataproc Serverless to create automated, cost-effective machine learning training pipelines. The infrastructure enables organizations to train large language models and complex neural networks with 4.7x performance improvement over previous TPU generations while eliminating infrastructure management overhead.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for manual provisioning

## Architecture Components

The infrastructure provisions the following Google Cloud resources:

- **Cloud Storage**: High-performance data lake for training datasets and model artifacts
- **Cloud TPU v6e**: Latest Trillium processors optimized for transformer model training
- **Dataproc Serverless**: Auto-scaling Apache Spark for data preprocessing
- **Vertex AI**: Managed ML training pipeline orchestration
- **Cloud Monitoring**: Comprehensive observability and alerting
- **IAM**: Least-privilege service accounts and security policies

## Prerequisites

### Required Tools
- Google Cloud CLI (`gcloud`) version 2.0+ with beta components enabled
- Terraform 1.6+ (for Terraform implementation)
- Infrastructure Manager enabled in your project (for Infrastructure Manager implementation)
- bash shell (for script-based deployment)

### Required Permissions
Your account must have the following IAM roles:
- Project Editor or Owner
- Cloud TPU Admin
- Dataproc Admin
- Storage Admin
- Vertex AI Admin
- Monitoring Admin

### Required APIs
The following Google Cloud APIs must be enabled:
```bash
gcloud services enable compute.googleapis.com
gcloud services enable tpu.googleapis.com
gcloud services enable dataproc.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable aiplatform.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable config.googleapis.com  # For Infrastructure Manager
```

### Cost Considerations
- **Estimated cost**: $800-2000 per complete pipeline execution
- **TPU v6e**: Primary cost component (~$50-100/hour for v6e-8 slice)
- **Dataproc Serverless**: Variable based on data volume (~$0.10-1.00/GB processed)
- **Cloud Storage**: Minimal for most workloads (~$0.02/GB/month)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native infrastructure as code solution that uses Terraform configurations with Google Cloud integration.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central2"
export DEPLOYMENT_NAME="ml-training-pipeline-$(date +%s)"

# Create deployment
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --source-local-source=./ \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=us-central2"

# Apply infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=us-central2"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central2"

# Deploy infrastructure
./deploy.sh

# View deployment status
gcloud compute tpus tpu-vm list --zone=${REGION}-b
gcloud dataproc batches list --region=${REGION}
```

## Configuration Variables

### Infrastructure Manager / Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Google Cloud region for resources | `us-central2` | No |
| `zone` | Compute zone for TPU resources | `us-central2-b` | No |
| `tpu_accelerator_type` | TPU accelerator type | `v6e-8` | No |
| `bucket_name` | Cloud Storage bucket name | `ml-training-pipeline-${random}` | No |
| `tpu_name` | Cloud TPU instance name | `training-tpu-${random}` | No |
| `enable_monitoring` | Enable Cloud Monitoring dashboard | `true` | No |
| `enable_vertex_ai` | Enable Vertex AI training integration | `true` | No |
| `network_name` | VPC network name | `default` | No |
| `subnet_name` | VPC subnet name | `default` | No |

### Bash Script Environment Variables

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central2"

# Optional variables with defaults
export ZONE="${REGION}-b"
export TPU_ACCELERATOR_TYPE="v6e-8"
export BUCKET_NAME="ml-training-pipeline-$(date +%s)"
export TPU_NAME="training-tpu-$(openssl rand -hex 3)"
export ENABLE_MONITORING="true"
```

## Post-Deployment Steps

After successful infrastructure deployment:

1. **Upload Training Data**:
   ```bash
   # Upload your training datasets
   gsutil -m cp -r /path/to/training/data/ gs://${BUCKET_NAME}/raw-data/
   ```

2. **Configure Training Scripts**:
   ```bash
   # Upload your TPU-optimized training code
   gcloud compute tpus tpu-vm scp training_script.py ${TPU_NAME}:/tmp/ --zone=${ZONE}
   ```

3. **Submit Preprocessing Job**:
   ```bash
   # Submit Dataproc Serverless preprocessing
   gcloud dataproc batches submit pyspark \
       gs://${BUCKET_NAME}/scripts/preprocessing_job.py \
       --batch=preprocessing-$(date +%s) \
       --region=${REGION}
   ```

4. **Start Training**:
   ```bash
   # Initiate TPU training
   gcloud compute tpus tpu-vm ssh ${TPU_NAME} \
       --zone=${ZONE} \
       --command="cd /tmp && python training_script.py"
   ```

## Monitoring and Observability

The infrastructure includes comprehensive monitoring:

- **TPU Metrics**: Utilization, memory usage, and training progress
- **Dataproc Metrics**: Job execution status and resource consumption
- **Storage Metrics**: Data transfer rates and storage utilization
- **Custom Dashboards**: Pre-configured training pipeline dashboard
- **Alerting**: Automated alerts for training failures and resource issues

Access the monitoring dashboard:
```bash
# Get dashboard URL
gcloud monitoring dashboards list --filter="displayName:TPU Training Dashboard"
```

## Troubleshooting

### Common Issues

1. **TPU Creation Fails**:
   ```bash
   # Check TPU quota and availability
   gcloud compute tpus locations describe ${REGION}
   gcloud compute project-info describe --format="value(quotas[].limit)"
   ```

2. **Dataproc Job Fails**:
   ```bash
   # Check job logs
   gcloud dataproc batches describe ${BATCH_ID} --region=${REGION}
   gcloud logging read "resource.type=dataproc_batch"
   ```

3. **Storage Access Issues**:
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://${BUCKET_NAME}
   ```

### Performance Optimization

1. **TPU Utilization**: Monitor TPU metrics to ensure >80% utilization
2. **Data Pipeline**: Use Parquet format and optimal partitioning for Spark jobs
3. **Network**: Ensure TPU and storage are in the same region for optimal performance
4. **Batch Sizes**: Tune batch sizes for optimal TPU memory utilization

## Security Considerations

The infrastructure implements security best practices:

- **IAM**: Least-privilege service accounts for all components
- **Network**: Resources deployed in private subnets where possible
- **Encryption**: Data encrypted at rest and in transit
- **Audit Logging**: Comprehensive audit trails for all operations
- **Access Control**: Fine-grained access controls for storage and compute resources

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --delete-policy=DELETE
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=us-central2"
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Verify cleanup
gcloud compute tpus tpu-vm list --zone=${REGION}-b
gsutil ls -b gs://${BUCKET_NAME} 2>/dev/null || echo "Bucket deleted"
```

### Manual Cleanup Verification

```bash
# Check for remaining resources
gcloud compute tpus tpu-vm list --format="table(name,zone,state)"
gcloud dataproc batches list --region=${REGION} --format="table(name,state)"
gcloud storage buckets list --filter="name:ml-training-pipeline"
```

## Performance Benchmarks

Expected performance characteristics:

- **Data Preprocessing**: 100GB dataset processed in ~10-15 minutes
- **TPU Training**: 1B parameter model training at ~15-20 TFlops/s
- **Storage Throughput**: 10-50 GB/s sustained read performance
- **End-to-End Pipeline**: Complete cycle in 2-4 hours for typical workloads

## Cost Optimization

Strategies to optimize costs:

1. **Use Preemptible TPUs**: Up to 70% cost savings for development workloads
2. **Optimize Data Format**: Use Parquet with Snappy compression
3. **Monitor Resource Usage**: Set up billing alerts and cost monitoring
4. **Schedule Training**: Use off-peak hours when possible
5. **Automatic Cleanup**: Implement automated resource cleanup policies

## Extending the Solution

Common extensions and integrations:

1. **Multi-Region Training**: Deploy across multiple regions for fault tolerance
2. **Hybrid Cloud**: Integrate with on-premises data sources
3. **AutoML Integration**: Combine with Vertex AI AutoML for automated hyperparameter tuning
4. **MLOps Pipeline**: Integrate with CI/CD pipelines for automated model deployment
5. **Real-time Serving**: Add Cloud Run deployment for trained model serving

## Support and Resources

- **Original Recipe**: Refer to the complete recipe documentation for detailed implementation guidance
- **Google Cloud Documentation**: [Cloud TPU documentation](https://cloud.google.com/tpu/docs)
- **Terraform Google Provider**: [Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Infrastructure Manager**: [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
- **Community Support**: Stack Overflow with tags `google-cloud-tpu` and `google-cloud-dataproc`

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **Terraform Google Provider**: ~> 5.0
- **Infrastructure Manager**: Latest stable version
- **gcloud CLI**: 2.0+

For questions or issues specific to this infrastructure code, please refer to the original recipe documentation or consult the Google Cloud documentation for the respective services.