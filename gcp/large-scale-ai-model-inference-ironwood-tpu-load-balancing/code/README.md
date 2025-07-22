# Infrastructure as Code for Large-Scale AI Model Inference with Ironwood TPU and Cloud Load Balancing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Large-Scale AI Model Inference with Ironwood TPU and Cloud Load Balancing".

## Overview

This solution leverages Google's seventh-generation Ironwood TPU, specifically engineered for inference workloads, combined with intelligent Cloud Load Balancing to create a high-performance AI inference pipeline. The architecture distributes inference requests across multiple TPU pods while maintaining optimal resource utilization and cost efficiency through real-time monitoring and automated scaling capabilities.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts with comprehensive error handling

## Architecture Components

- **Ironwood TPU v7 Pods**: Multi-tier TPU configuration (256, 1024, 9216 chips)
- **Vertex AI Endpoints**: Managed AI model serving infrastructure
- **Cloud Load Balancing**: Intelligent traffic distribution with health checks
- **Cloud Monitoring**: Real-time performance analytics and alerting
- **Auto Scaling**: Dynamic resource adjustment based on demand
- **Redis Cache**: High-performance inference result caching

## Prerequisites

### Required Tools and Access
- Google Cloud CLI (gcloud) version 400.0.0 or later
- Google Cloud project with billing enabled
- Terraform 1.5.0+ (for Terraform deployment)
- Quota for Ironwood TPU resources in target region

### Required APIs
- Vertex AI API (`aiplatform.googleapis.com`)
- Compute Engine API (`compute.googleapis.com`)
- Kubernetes Engine API (`container.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Redis API (`redis.googleapis.com`)

### Required Permissions
- `roles/aiplatform.admin`
- `roles/compute.admin`
- `roles/container.admin`
- `roles/monitoring.admin`
- `roles/redis.admin`
- `roles/iam.serviceAccountAdmin`

### Cost Considerations
⚠️ **Warning**: This solution uses premium Ironwood TPU resources that can incur significant costs ($2,500-$15,000+ per day). Monitor usage carefully and implement proper cleanup procedures.

## Quick Start

### Prerequisites Setup

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Configure gcloud
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}

# Enable required APIs
gcloud services enable \
    aiplatform.googleapis.com \
    compute.googleapis.com \
    container.googleapis.com \
    monitoring.googleapis.com \
    logging.googleapis.com \
    redis.googleapis.com
```

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure-as-code service that provides a fully managed Terraform experience.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/ai-inference-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/tpu-inference-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars" \
    --labels="environment=production,recipe=ai-inference"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/ai-inference-deployment

# View deployment resources
gcloud infra-manager resources list \
    --deployment=projects/${PROJECT_ID}/locations/${REGION}/deployments/ai-inference-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan -var-file="terraform.tfvars"

# Apply infrastructure
terraform apply -var-file="terraform.tfvars"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# 1. Validate prerequisites
# 2. Create service accounts and IAM roles
# 3. Deploy TPU pods with different configurations
# 4. Set up Vertex AI endpoints
# 5. Configure load balancing and monitoring
# 6. Implement auto-scaling policies
# 7. Set up performance analytics

# View deployment status
./scripts/status.sh
```

## Configuration

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary deployment region | `us-central1` | Yes |
| `zone` | Primary deployment zone | `us-central1-a` | Yes |
| `model_name` | AI model identifier | `llama-70b` | Yes |
| `enable_small_tpu` | Deploy small TPU pod (256 chips) | `true` | No |
| `enable_medium_tpu` | Deploy medium TPU pod (1024 chips) | `true` | No |
| `enable_large_tpu` | Deploy large TPU pod (9216 chips) | `false` | No |
| `min_replicas` | Minimum number of replicas | `1` | No |
| `max_replicas` | Maximum number of replicas | `10` | No |
| `target_cpu_utilization` | Auto-scaling CPU threshold | `0.7` | No |

### TPU Configuration Options

#### Small TPU Pod (256 chips)
- **Use case**: Lightweight inference, testing, development
- **Memory**: 49.2 TB HBM
- **Compute**: 1.18 Million TFLOPs
- **Cost**: ~$2,500/day

#### Medium TPU Pod (1024 chips)
- **Use case**: Production workloads, standard inference
- **Memory**: 196.6 TB HBM
- **Compute**: 4.72 Million TFLOPs
- **Cost**: ~$10,000/day

#### Large TPU Pod (9216 chips)
- **Use case**: High-throughput inference, enterprise scale
- **Memory**: 1.77 PB HBM
- **Compute**: 42.5 Million TFLOPs
- **Cost**: ~$90,000/day

## Validation and Testing

### Verify TPU Deployment

```bash
# Check TPU status
gcloud compute tpus tpu-vm list --zone=${ZONE}

# Test TPU connectivity
gcloud compute tpus tpu-vm ssh ironwood-cluster-small-001 \
    --zone=${ZONE} \
    --command="python3 -c 'import tensorflow as tf; print(tf.config.list_logical_devices(\"TPU\"))'"
```

### Test Load Balancer

```bash
# Get load balancer IP
LB_IP=$(gcloud compute forwarding-rules describe ai-inference-forwarding-rule \
    --global --format="get(IPAddress)")

# Test inference endpoint
curl -X POST https://${LB_IP}/v1/predict \
    -H "Content-Type: application/json" \
    -d '{"instances": [{"text": "Hello, this is a test inference request"}]}' \
    -w "Response time: %{time_total}s\n"
```

### Monitor Performance

```bash
# View TPU utilization metrics
gcloud monitoring metrics list \
    --filter="metric.type:compute.googleapis.com/instance/cpu/utilization"

# Check auto-scaling events
gcloud logging read \
    'resource.type="gce_instance" AND jsonPayload.message:"autoscaling"' \
    --limit=10
```

## Troubleshooting

### Common Issues

#### TPU Quota Exceeded
```bash
# Check current quotas
gcloud compute project-info describe \
    --format="table(quotas.metric,quotas.limit,quotas.usage)"

# Request quota increase
echo "Visit: https://console.cloud.google.com/iam-admin/quotas"
```

#### Vertex AI Endpoint Failed
```bash
# Check endpoint status
gcloud ai endpoints list --region=${REGION}

# View endpoint logs
gcloud logging read \
    'resource.type="aiplatform.googleapis.com/Endpoint"' \
    --limit=20
```

#### Load Balancer Health Check Failures
```bash
# Check backend health
gcloud compute backend-services get-health inference-backend-medium --global

# Review health check configuration
gcloud compute health-checks describe tpu-health-check
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/ai-inference-deployment \
    --delete-policy="DELETE"

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var-file="terraform.tfvars"

# Clean up state files
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Prompt for confirmation
# 2. Delete TPU pods in proper order
# 3. Remove Vertex AI endpoints
# 4. Clean up load balancer components
# 5. Delete monitoring resources
# 6. Remove service accounts
# 7. Verify resource deletion
```

### Manual Cleanup Verification

```bash
# Verify TPU deletion
gcloud compute tpus tpu-vm list --zone=${ZONE}

# Verify Vertex AI endpoints
gcloud ai endpoints list --region=${REGION}

# Check for remaining load balancer components
gcloud compute forwarding-rules list --global
gcloud compute backend-services list --global

# Verify service account deletion
gcloud iam service-accounts list
```

## Customization

### Scaling Configuration

Modify auto-scaling behavior by adjusting these parameters:

```hcl
# In terraform/variables.tf or terraform.tfvars
target_cpu_utilization = 0.8  # Scale at 80% CPU
min_replicas = 2              # Minimum instances
max_replicas = 20             # Maximum instances
scale_down_delay = 600        # Scale down after 10 minutes
```

### Model Optimization

Configure model-specific optimizations:

```hcl
model_optimizations = {
  quantization_level = "int8"
  batch_size = 32
  sequence_length = 512
  enable_caching = true
}
```

### Multi-Region Deployment

Extend to multiple regions for global coverage:

```hcl
regions = [
  "us-central1",
  "europe-west1", 
  "asia-northeast1"
]
```

## Security Considerations

- All TPU VMs use custom service accounts with minimal required permissions
- Network access is restricted through VPC firewall rules
- Load balancer uses HTTPS with automatic SSL certificate management
- Monitoring data is encrypted at rest and in transit
- IAM roles follow principle of least privilege

## Cost Optimization

### Monitoring Costs

```bash
# Set up billing alerts
gcloud alpha billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="TPU Inference Budget" \
    --budget-amount=10000USD \
    --threshold-rule=percent:0.8,basis:CURRENT_SPEND
```

### Resource Optimization

- Use preemptible TPU instances for development/testing
- Implement intelligent auto-scaling based on inference patterns
- Enable response caching for repeated queries
- Schedule TPU resources for known usage patterns

## Support

### Documentation References

- [Google Cloud AI Hypercomputer](https://cloud.google.com/blog/products/compute/whats-new-with-ai-hypercomputer)
- [Ironwood TPU Specifications](https://cloud.google.com/resources/ironwood-tpu-interest)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud Load Balancing Guide](https://cloud.google.com/load-balancing/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud Console for resource status
3. Examine Cloud Logging for detailed error messages
4. Refer to the original recipe documentation
5. Consult Google Cloud documentation for specific services

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Ensure all resource cleanup procedures work correctly
3. Update documentation for any new features
4. Verify cost implications of changes
5. Follow Google Cloud best practices and security guidelines