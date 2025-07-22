# Infrastructure as Code for Real-Time Data Science Model Training with Vertex AI Workbench and Memorystore Redis

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Data Science Model Training with Vertex AI Workbench and Memorystore Redis".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Vertex AI Administrator
  - Redis Admin
  - Compute Admin
  - Cloud Batch Admin
  - Storage Admin
  - Monitoring Admin
- Estimated cost: $45-75 for running this recipe (depending on training duration and resource usage)

## Quick Start

### Using Infrastructure Manager (Google Cloud)

```bash
# Create a deployment
gcloud infra-manager deployments create ml-training-deployment \
    --location=us-central1 \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --gcs-source=gs://BUCKET_NAME/infrastructure-manager/main.yaml \
    --input-values=project_id=PROJECT_ID,region=us-central1
```

### Using Terraform

```bash
cd terraform/
terraform init
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys:

- **Vertex AI Workbench**: Managed Jupyter environment with GPU acceleration
- **Memorystore Redis**: High-performance in-memory caching layer
- **Cloud Batch**: Distributed training job orchestration
- **Cloud Storage**: Dataset and model artifact storage
- **Cloud Monitoring**: Performance monitoring and dashboards
- **Network Security**: VPC firewall rules and IAM permissions

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment accepts these input values:

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `redis_memory_size`: Redis instance memory in GB (default: 5)
- `workbench_machine_type`: Workbench instance machine type (default: n1-standard-4)
- `enable_gpu`: Enable GPU acceleration (default: true)

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `redis_memory_size`: Redis instance memory in GB (default: 5)
- `workbench_machine_type`: Workbench instance machine type (default: n1-standard-4)
- `workbench_gpu_type`: GPU type for acceleration (default: NVIDIA_TESLA_T4)
- `storage_bucket_name`: Cloud Storage bucket name (auto-generated if not provided)
- `environment`: Environment tag (default: training)

## Deployment Steps

### 1. Pre-deployment Setup

```bash
# Set your project ID
export PROJECT_ID="your-gcp-project-id"

# Enable required APIs
gcloud services enable aiplatform.googleapis.com \
    redis.googleapis.com \
    batch.googleapis.com \
    monitoring.googleapis.com \
    storage.googleapis.com \
    compute.googleapis.com \
    --project=${PROJECT_ID}

# Set default project
gcloud config set project ${PROJECT_ID}
```

### 2. Infrastructure Manager Deployment

```bash
# Upload configuration to Cloud Storage
gsutil cp infrastructure-manager/main.yaml gs://your-config-bucket/

# Create deployment
gcloud infra-manager deployments create ml-training-deployment \
    --location=us-central1 \
    --service-account=${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
    --gcs-source=gs://your-config-bucket/main.yaml \
    --input-values=project_id=${PROJECT_ID},region=us-central1
```

### 3. Terraform Deployment

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Plan and apply
terraform plan
terraform apply
```

### 4. Bash Script Deployment

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Post-Deployment Configuration

### 1. Access Vertex AI Workbench

```bash
# Get Workbench URL
gcloud workbench instances describe ml-workbench-SUFFIX \
    --location=us-central1-a \
    --format="value(proxyUri)"
```

### 2. Connect to Redis

```bash
# Get Redis connection details
gcloud redis instances describe ml-feature-cache-SUFFIX \
    --region=us-central1 \
    --format="table(name,host,port,state)"
```

### 3. Upload Sample Notebook

```bash
# Upload the training notebook to Cloud Storage
gsutil cp ../ml_training_notebook.ipynb gs://BUCKET_NAME/notebooks/
```

## Validation & Testing

### 1. Verify Resource Creation

```bash
# Check all resources are created
gcloud redis instances list --filter="name:ml-feature-cache*"
gcloud workbench instances list --filter="name:ml-workbench*"
gcloud storage buckets list --filter="name:ml-training-bucket*"
```

### 2. Test Redis Connectivity

```bash
# Test Redis connection from Workbench
# (Run this in the Workbench Jupyter environment)
import redis
r = redis.Redis(host='REDIS_HOST', port=6379)
print(r.ping())
```

### 3. Validate Monitoring Dashboard

```bash
# Check monitoring dashboard
gcloud monitoring dashboards list --filter="displayName:ML Training Pipeline*"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete ml-training-deployment \
    --location=us-central1 \
    --quiet
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify your service account has required IAM roles
3. **Quota Exceeded**: Check GPU and compute quotas in your region
4. **Redis Connection**: Verify firewall rules allow Redis port access

### Debug Commands

```bash
# Check resource status
gcloud redis instances describe INSTANCE_NAME --region=REGION
gcloud workbench instances describe INSTANCE_NAME --location=ZONE

# View logs
gcloud logging read "resource.type=redis_instance" --limit=10
gcloud logging read "resource.type=gce_instance" --limit=10
```

## Cost Optimization

### Resource Sizing

- **Redis Memory**: Start with 5GB, adjust based on cache requirements
- **Workbench Machine**: Use n1-standard-4 for development, scale up for production
- **GPU**: Disable GPU if not needed for training acceleration

### Cost Monitoring

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="ML Training Budget" \
    --budget-amount=100
```

## Security Considerations

### Network Security

- Redis instances are created in private networks
- Firewall rules restrict access to necessary ports only
- VPC peering ensures secure communication between services

### IAM Security

- Service accounts use principle of least privilege
- Workbench instances have minimal required permissions
- Redis instances are protected with authentication

### Data Security

- All data in transit is encrypted
- Storage buckets use encryption at rest
- Redis instances support authentication

## Performance Optimization

### Cache Configuration

- Configure Redis memory policies based on workload
- Monitor cache hit ratios through Cloud Monitoring
- Implement cache warming strategies for critical features

### Training Optimization

- Use GPU-accelerated instances for compute-intensive training
- Implement distributed training with Cloud Batch
- Monitor resource utilization and adjust instance types

## Monitoring and Alerting

### Key Metrics

- Redis memory usage and hit ratios
- Workbench CPU and GPU utilization
- Training job completion rates
- Storage costs and usage

### Alert Policies

```bash
# Create alert policy for Redis memory usage
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring-policy.yaml
```

## Extensions

### Additional Features

1. **Auto-scaling**: Implement Cloud Run functions for dynamic resource scaling
2. **Model Registry**: Integrate with Vertex AI Model Registry for version control
3. **Pipeline Automation**: Add Cloud Build triggers for CI/CD
4. **Multi-region**: Deploy across multiple regions for high availability

### Integration Options

- **BigQuery**: Connect for large-scale data analysis
- **Dataflow**: Add real-time data processing pipelines
- **Pub/Sub**: Implement event-driven training triggers
- **Cloud Functions**: Add serverless orchestration

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for architectural guidance
2. Consult Google Cloud documentation for service-specific issues
3. Review Terraform Google Cloud Provider documentation
4. Use `gcloud` CLI help commands for troubleshooting

## Additional Resources

- [Vertex AI Workbench Documentation](https://cloud.google.com/vertex-ai/docs/workbench)
- [Memorystore Redis Documentation](https://cloud.google.com/memorystore/docs/redis)
- [Cloud Batch Documentation](https://cloud.google.com/batch/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)