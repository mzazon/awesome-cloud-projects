# Infrastructure as Code for Large Language Model Inference with TPU Ironwood and GKE Volume Populator

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Large Language Model Inference with TPU Ironwood and GKE Volume Populator".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) version 456.0.0 or later installed and configured
- `kubectl` installed and configured
- Google Cloud project with billing enabled and TPU quota allocation
- Advanced knowledge of Kubernetes, TPU architecture, and machine learning inference pipelines
- Existing LLM model artifacts (weights, tokenizer) stored in Cloud Storage
- Appropriate permissions for resource creation:
  - `roles/container.admin` - For GKE cluster management
  - `roles/tpu.admin` - For TPU resource management
  - `roles/storage.admin` - For Cloud Storage and Parallelstore management
  - `roles/iam.serviceAccountAdmin` - For service account management
  - `roles/compute.admin` - For compute resource management
  - `roles/monitoring.admin` - For observability configuration

## Cost Considerations

**Important**: This infrastructure uses premium Google Cloud resources:
- TPU Ironwood pods: $1,200-2,500 per hour during active inference
- Parallelstore instances: $0.15-0.30 per GB/month
- GKE cluster: $0.10 per cluster per hour + compute costs
- Cloud Storage: Standard rates apply

**Warning**: TPU Ironwood resources are currently in limited preview and require explicit quota approval. Contact Google Cloud sales for access to these next-generation accelerators.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native Infrastructure as Code tool that provides declarative resource management with built-in drift detection and state management.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="tpu-inference-deployment"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infrastructure-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
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

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

The bash scripts provide a streamlined deployment experience with built-in validation and error handling.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export CLUSTER_NAME="tpu-ironwood-cluster"

# Deploy the infrastructure
./scripts/deploy.sh

# The script will:
# 1. Validate prerequisites
# 2. Enable required APIs
# 3. Create Cloud Storage bucket
# 4. Deploy GKE cluster with TPU support
# 5. Configure service accounts and permissions
# 6. Create Parallelstore instance
# 7. Deploy Volume Populator configuration
# 8. Deploy TPU inference workload
# 9. Configure monitoring and observability

# Verify deployment
kubectl get pods -l app=tpu-ironwood-inference
kubectl get service tpu-inference-service
```

## Configuration Options

### Terraform Variables

Key variables that can be customized in `terraform.tfvars`:

```hcl
# Project and location settings
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# TPU and model configuration
tpu_type           = "v7-8"
model_bucket_name  = "your-model-bucket"
model_path         = "models/llm-7b/"

# Cluster configuration
cluster_name       = "tpu-ironwood-cluster"
node_count         = 2
machine_type       = "e2-standard-4"

# Storage configuration
parallelstore_capacity_gb = 1024
parallelstore_tier       = "SSD"

# Monitoring configuration
enable_monitoring = true
```

### Infrastructure Manager Parameters

Parameters can be set when creating the deployment:

```bash
--input-values="project_id=your-project,region=us-central1,tpu_type=v7-8,model_bucket=your-bucket"
```

## Validation and Testing

After deployment, validate the infrastructure:

### Check TPU Resources

```bash
# Verify TPU pod allocation
kubectl get pods -l app=tpu-ironwood-inference -o wide

# Check TPU resource requests
kubectl describe pod -l app=tpu-ironwood-inference | grep -A 5 "Requests:"
```

### Test Model Loading

```bash
# Check Volume Populator transfer status
kubectl describe pvc model-storage-pvc

# Verify model files are accessible
kubectl exec -it deployment/tpu-ironwood-inference -- ls -la /models/
```

### Performance Testing

```bash
# Get service endpoint
EXTERNAL_IP=$(kubectl get service tpu-inference-service --output jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test inference endpoint
curl -X POST http://${EXTERNAL_IP}/generate \
    -H "Content-Type: application/json" \
    -d '{
      "prompt": "The future of artificial intelligence is",
      "max_tokens": 100,
      "temperature": 0.7
    }'

# Performance benchmark
time curl -X POST http://${EXTERNAL_IP}/generate \
    -H "Content-Type: application/json" \
    -d '{"prompt": "Test prompt", "max_tokens": 50}'
```

### Monitoring and Observability

```bash
# Check Cloud Monitoring metrics
gcloud logging read "resource.type=gke_container AND labels.app=tpu-ironwood-inference" --limit=10

# View TPU utilization
gcloud monitoring metrics list --filter="metric.type:tpu"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Kubernetes resources
# 2. Remove GKE cluster
# 3. Delete Parallelstore instance
# 4. Remove Cloud Storage bucket
# 5. Clean up service accounts
# 6. Verify resource deletion
```

### Manual Cleanup Verification

After running cleanup, verify all resources are removed:

```bash
# Check for remaining GKE clusters
gcloud container clusters list

# Verify Parallelstore instances are deleted
gcloud parallelstore instances list --location=${REGION}

# Check Cloud Storage buckets
gsutil ls

# Verify service accounts are removed
gcloud iam service-accounts list --filter="displayName:TPU Inference"
```

## Troubleshooting

### Common Issues

1. **TPU Quota Exceeded**
   ```bash
   # Check TPU quotas
   gcloud compute project-info describe --flatten="quotas[]" | grep -i tpu
   
   # Request quota increase
   # Visit: https://console.cloud.google.com/iam-admin/quotas
   ```

2. **Volume Populator Transfer Failed**
   ```bash
   # Check transfer logs
   kubectl logs -l app=volume-populator
   
   # Verify source bucket access
   gsutil ls gs://your-bucket-name/models/
   ```

3. **TPU Pod Scheduling Issues**
   ```bash
   # Check node resources
   kubectl describe nodes
   
   # Verify TPU node pool
   gcloud container node-pools describe default-pool --cluster=${CLUSTER_NAME} --zone=${ZONE}
   ```

4. **Service Account Permissions**
   ```bash
   # Verify IAM bindings
   gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.members:serviceAccount"
   ```

### Performance Optimization

1. **Model Loading Optimization**
   - Use Parallelstore SSD tier for faster I/O
   - Optimize model sharding across TPU cores
   - Implement model caching strategies

2. **TPU Utilization Monitoring**
   ```bash
   # Monitor TPU metrics
   gcloud alpha monitoring dashboards create --config-from-file=monitoring-dashboard.yaml
   ```

3. **Cost Optimization**
   - Use preemptible TPU instances for development
   - Implement auto-scaling based on demand
   - Set up budget alerts for cost control

## Architecture Notes

This infrastructure implements several key architectural patterns:

- **TPU Ironwood Integration**: Leverages Google's latest 7th-generation TPU architecture for optimal LLM inference performance
- **Volume Populator Pattern**: Automates model data transfer from Cloud Storage to high-performance Parallelstore
- **Workload Identity**: Provides secure, keyless authentication between Kubernetes and Google Cloud services
- **Observability**: Comprehensive monitoring and logging for production inference workloads

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file for detailed implementation guidance
2. **Google Cloud Documentation**: 
   - [TPU Documentation](https://cloud.google.com/tpu/docs)
   - [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
3. **Terraform Google Provider**: [Official Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Security Considerations

- All service accounts follow the principle of least privilege
- Workload Identity eliminates the need for service account keys
- Network policies restrict inter-pod communication
- TPU resources are isolated within the cluster
- Model data is encrypted at rest and in transit

## Version Information

- **Terraform Google Provider**: ~> 6.0
- **Kubernetes Provider**: ~> 2.33
- **Infrastructure Manager**: Latest stable version
- **Required APIs**: Container, AI Platform, Compute, Storage, Parallelstore, Monitoring, Logging