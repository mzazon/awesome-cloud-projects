# Infrastructure as Code for Building High-Performance AI Inference Pipelines with Cloud Bigtable and TPU

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building High-Performance AI Inference Pipelines with Cloud Bigtable and TPU".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a high-performance AI inference pipeline that includes:

- **Cloud Bigtable**: Ultra-low latency NoSQL database for feature storage
- **Vertex AI TPU v7**: Specialized AI accelerators for inference
- **Cloud Functions**: Serverless orchestration for inference pipeline
- **Memorystore Redis**: Intelligent caching layer for hot features
- **Cloud Monitoring**: Comprehensive observability and alerting
- **Cloud Storage**: Model artifact storage

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud Project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Bigtable Admin
  - Vertex AI Admin
  - Cloud Functions Admin
  - Memorystore Admin
  - Storage Admin
  - Monitoring Admin
- Python 3.9+ (for Cloud Functions deployment)
- Terraform 1.0+ (if using Terraform implementation)

### Required APIs

The following APIs must be enabled in your Google Cloud project:

- Bigtable API (`bigtable.googleapis.com`)
- Vertex AI API (`aiplatform.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Memorystore API (`redis.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)

## Cost Considerations

⚠️ **Important**: This infrastructure includes premium resources that may incur significant costs:

- **TPU v7 instances**: $2-8 per hour depending on configuration
- **Cloud Bigtable**: $0.65 per node per hour + storage costs
- **Memorystore Redis**: $0.043 per GB per hour
- **Cloud Functions**: Pay-per-invocation model
- **Cloud Storage**: Standard storage pricing

**Estimated cost during recipe execution**: $150-300 for the complete pipeline

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="ai-inference-pipeline"

# Navigate to infrastructure manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --local-source=. \
    --input-values=project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `bigtable_nodes` | Number of Bigtable nodes | `3` | No |
| `redis_memory_size` | Redis memory in GB | `5` | No |
| `tpu_type` | TPU accelerator type | `TPU_V5_LITE_POD_SLICE` | No |
| `function_memory` | Cloud Function memory | `2Gi` | No |
| `min_function_instances` | Minimum function instances | `2` | No |
| `max_function_instances` | Maximum function instances | `100` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `bigtable_cluster_nodes` | Bigtable cluster node count | `3` | No |
| `bigtable_storage_type` | Bigtable storage type | `SSD` | No |
| `redis_memory_size_gb` | Redis memory in GB | `5` | No |
| `redis_version` | Redis version | `REDIS_7_0` | No |
| `tpu_machine_type` | TPU machine type | `cloud-tpu` | No |
| `function_timeout` | Cloud Function timeout | `60s` | No |
| `enable_monitoring` | Enable monitoring resources | `true` | No |

## Deployment Steps

### 1. Pre-deployment Validation

```bash
# Verify project and authentication
gcloud auth list
gcloud config get-value project

# Check required APIs are enabled
gcloud services list --enabled --filter="name:bigtable.googleapis.com OR name:aiplatform.googleapis.com OR name:cloudfunctions.googleapis.com OR name:monitoring.googleapis.com OR name:redis.googleapis.com OR name:storage.googleapis.com"
```

### 2. Deploy Infrastructure

Choose one of the implementation methods above based on your preference and organizational standards.

### 3. Post-deployment Configuration

```bash
# Verify Bigtable instance
gcloud bigtable instances list

# Check Vertex AI endpoints
gcloud ai endpoints list --region=${REGION}

# Verify Cloud Function deployment
gcloud functions list --region=${REGION}

# Test Redis connectivity
gcloud redis instances list --region=${REGION}
```

### 4. Load Sample Data (Optional)

```bash
# Create sample feature tables
cbt createtable user_features families=embeddings,demographics,behavior
cbt createtable item_features families=content,metadata,statistics
cbt createtable contextual_features families=temporal,location,device
```

## Testing the Deployment

### 1. Function Endpoint Test

```bash
# Get function URL
FUNCTION_URL=$(gcloud functions describe inference-pipeline --region=${REGION} --format="value(serviceConfig.uri)")

# Test inference endpoint
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": "user_12345", 
        "item_id": "item_67890",
        "context": {"timestamp": "2025-07-12T10:00:00Z", "device": "mobile"}
    }'
```

### 2. Performance Validation

```bash
# Test cache performance with multiple requests
for i in {1..10}; do
    curl -X POST ${FUNCTION_URL} \
        -H "Content-Type: application/json" \
        -d '{
            "user_id": "user_test", 
            "item_id": "item_test",
            "context": {"timestamp": "2025-07-12T10:00:00Z"}
        }'
    sleep 1
done
```

### 3. Monitoring Dashboard

```bash
# View monitoring metrics
gcloud monitoring dashboards list
gcloud logging metrics list
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify resource deletion
gcloud bigtable instances list
gcloud ai endpoints list --region=${REGION}
gcloud functions list --region=${REGION}
gcloud redis instances list --region=${REGION}
gcloud storage ls
```

## Troubleshooting

### Common Issues

1. **TPU Quota Exceeded**
   ```bash
   # Check TPU quotas
   gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)"
   ```

2. **Bigtable Connection Issues**
   ```bash
   # Verify Bigtable connectivity
   cbt ls
   ```

3. **Function Deployment Failures**
   ```bash
   # Check function logs
   gcloud functions logs read inference-pipeline --region=${REGION}
   ```

4. **Redis Connection Problems**
   ```bash
   # Check Redis instance status
   gcloud redis instances describe ${REDIS_INSTANCE_ID} --region=${REGION}
   ```

### Resource Limits

- **TPU**: Limited availability in certain regions
- **Bigtable**: Minimum 3 nodes required for production
- **Redis**: Memory limits based on instance type
- **Cloud Functions**: Concurrent execution limits

## Security Considerations

### IAM and Access Control

- All resources use least privilege IAM policies
- Service accounts have minimal required permissions
- Network security follows Google Cloud best practices

### Data Protection

- Bigtable data encrypted at rest and in transit
- Redis instances use VPC native networking
- Cloud Function environment variables are encrypted

### Network Security

- Private Google Access enabled for secure communication
- Firewall rules restrict access to necessary ports only
- VPC peering configured for service communication

## Performance Optimization

### Bigtable Optimization

- SSD storage for consistent low latency
- Optimal node count for expected traffic
- Column family design for efficient reads

### Caching Strategy

- Redis LRU eviction policy for optimal memory usage
- 5-minute TTL for feature caching
- Cache warming strategies for popular features

### TPU Optimization

- Model optimization for TPU architecture
- Batch inference for improved throughput
- Auto-scaling based on traffic patterns

## Monitoring and Alerting

### Key Metrics

- Inference latency (target: <500ms)
- Cache hit ratio (target: >80%)
- Error rate (target: <1%)
- Resource utilization (target: <80%)

### Alert Policies

- High latency alerts (>500ms)
- Error rate alerts (>5%)
- Resource utilization alerts (>90%)
- Cost anomaly detection

## Customization Guide

### Scaling Configuration

```bash
# Adjust Bigtable cluster size
gcloud bigtable clusters update ${CLUSTER_ID} --num-nodes=6

# Modify Redis memory
gcloud redis instances update ${REDIS_INSTANCE_ID} --size=10

# Update function scaling
gcloud functions deploy inference-pipeline --max-instances=200
```

### Feature Engineering

1. Add new column families to Bigtable tables
2. Update inference function feature extraction logic
3. Modify model input preprocessing
4. Adjust cache key strategies

### Model Updates

1. Upload new model to Cloud Storage
2. Update Vertex AI endpoint with new model
3. Test inference with new model
4. Gradually shift traffic to new model

## Support and Resources

### Documentation

- [Cloud Bigtable Documentation](https://cloud.google.com/bigtable/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Community and Support

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - google-cloud-platform](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Google Cloud Support](https://cloud.google.com/support)

### Best Practices

- Follow [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)
- Implement [Well-Architected Framework](https://cloud.google.com/architecture/well-architected)
- Use [Cloud Security Best Practices](https://cloud.google.com/security/best-practices)

## License

This infrastructure code is provided under the same license as the parent repository.

## Contributing

For issues or improvements to this infrastructure code, please refer to the original recipe documentation or create an issue in the parent repository.