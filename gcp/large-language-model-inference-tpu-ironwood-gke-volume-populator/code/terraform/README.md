# Terraform Infrastructure for TPU Ironwood LLM Inference

This Terraform configuration deploys a complete high-performance Large Language Model inference pipeline using Google Cloud's TPU Ironwood accelerators with GKE Volume Populator for optimized model data transfer.

## Architecture Overview

The infrastructure includes:

- **GKE Cluster**: Container orchestration with TPU Ironwood support
- **TPU Node Pool**: Dedicated nodes with TPU v7 accelerators
- **Parallelstore**: High-performance parallel file system for model storage
- **Cloud Storage**: Model artifact repository with versioning
- **Workload Identity**: Secure service account integration
- **Cloud Monitoring**: Performance tracking and observability

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.9.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) >= 456.0.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for cluster management

### Google Cloud Setup

1. **Create or select a Google Cloud project**:
   ```bash
   gcloud projects create your-project-id
   gcloud config set project your-project-id
   ```

2. **Enable billing for the project** (required for TPU resources)

3. **Request TPU Ironwood quota** (contact Google Cloud sales for preview access)

4. **Authenticate with Google Cloud**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

### Cost Considerations

- **TPU Ironwood**: $1,200-2,500+ per hour during active inference
- **Parallelstore**: $0.12-0.30 per GB-month depending on performance tier
- **GKE**: $0.10 per cluster per hour + compute costs
- **Cloud Storage**: $0.020 per GB-month for standard storage

## Quick Start

### 1. Configure Variables

```bash
# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration file
vim terraform.tfvars
```

**Required variables**:
```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
```

### 2. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
```

### 3. Configure kubectl

```bash
# Get cluster credentials (output from Terraform)
gcloud container clusters get-credentials <cluster-name> \
    --zone=<zone> --project=<project-id>

# Verify cluster access
kubectl get nodes
```

### 4. Upload Model Artifacts

```bash
# Upload your LLM model to Cloud Storage
gsutil -m cp -r /path/to/your/model/* \
    gs://<bucket-name>/models/llm-7b/
```

## Configuration Guide

### Environment-Specific Configurations

#### Development Environment
```hcl
environment = "development"
enable_cost_optimization = true
deletion_protection = false

# Minimal resources for testing
standard_node_count = 1
tpu_node_count = 1
parallelstore_capacity_gib = 1024
parallelstore_performance_tier = "HDD"
```

#### Production Environment
```hcl
environment = "production"
deletion_protection = true
enable_network_policy = true

# Production-scale resources
standard_node_count = 3
standard_min_nodes = 2
standard_max_nodes = 20
tpu_node_count = 2
tpu_min_nodes = 1
tpu_max_nodes = 5
parallelstore_capacity_gib = 4096
```

### TPU Configuration Options

| Accelerator Type | Count | Use Case |
|-----------------|-------|----------|
| `tpu-v7-pod-slice` | 2 | Small models, development |
| `tpu-v7-pod-slice` | 4 | Medium models, testing |
| `tpu-v7-pod-slice` | 8 | Large models, production |
| `tpu-v7-pod-slice` | 16 | Very large models |
| `tpu-v7-pod-slice` | 32 | Distributed inference |

### Regional Availability

TPU Ironwood is available in select zones:

| Region | Zones | Notes |
|--------|-------|-------|
| us-central1 | a, b, c, f | Primary TPU region |
| us-east1 | b, c, d | Secondary availability |
| europe-west1 | b, c, d | EU availability |
| asia-northeast1 | a, b, c | APAC availability |

## Deployment Patterns

### Single Model Inference
```hcl
tpu_node_count = 1
tpu_accelerator_count = 8
model_name = "llama-7b"
```

### Multi-Model Serving
```hcl
tpu_node_count = 2
tpu_accelerator_count = 16
# Deploy multiple inference services
```

### High Availability
```hcl
tpu_min_nodes = 2
tpu_max_nodes = 5
enable_monitoring = true
deletion_protection = true
```

## Post-Deployment Setup

### 1. Create Kubernetes Service Account

```bash
# Create service account with Workload Identity
kubectl create serviceaccount tpu-inference-pod --namespace=default

# Annotate for Workload Identity binding
kubectl annotate serviceaccount tpu-inference-pod \
    --namespace=default \
    iam.gke.io/gcp-service-account=<service-account-email>
```

### 2. Deploy Volume Populator Configuration

```yaml
# gcp-data-source.yaml
apiVersion: parallelstore.csi.storage.gke.io/v1
kind: GCPDataSource
metadata:
  name: llm-model-source
  namespace: default
spec:
  bucket: <bucket-name>
  path: "models/llm-7b/"
  serviceAccount: <service-account-email>
```

```bash
kubectl apply -f gcp-data-source.yaml
```

### 3. Create Storage Class

```yaml
# storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: parallelstore-csi-volume-populator
provisioner: parallelstore.csi.storage.gke.io
parameters:
  instance-name: <parallelstore-instance-name>
  location: <zone>
  capacity-gib: "1024"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

### 4. Deploy Inference Workload

```yaml
# inference-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tpu-ironwood-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tpu-ironwood-inference
  template:
    metadata:
      labels:
        app: tpu-ironwood-inference
      annotations:
        iam.gke.io/gcp-service-account: <service-account-email>
    spec:
      serviceAccountName: tpu-inference-pod
      tolerations:
      - key: google.com/tpu
        operator: Exists
        effect: NoSchedule
      nodeSelector:
        cloud.google.com/gke-accelerator: tpu-v7-pod-slice
      containers:
      - name: inference-server
        image: gcr.io/project-id/tpu-inference:latest
        resources:
          requests:
            google.com/tpu: "8"
          limits:
            google.com/tpu: "8"
        volumeMounts:
        - name: model-storage
          mountPath: /models
          readOnly: true
      volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: model-storage-pvc
```

## Monitoring and Observability

### Cloud Monitoring Dashboard

Access the pre-configured dashboard:
```bash
# Get dashboard URL from Terraform output
terraform output monitoring_dashboard_url
```

Key metrics to monitor:
- TPU utilization percentage
- Model loading time
- Inference latency (p50, p95, p99)
- Parallelstore throughput
- Memory usage patterns

### Logging Configuration

View inference logs:
```bash
# Check application logs
kubectl logs -l app=tpu-ironwood-inference --tail=100

# View Cloud Logging
gcloud logging read "resource.type=k8s_cluster" --limit=50
```

## Troubleshooting

### Common Issues

#### TPU Quota Exceeded
```
Error: TPU quota exceeded in zone us-central1-a
```
**Solution**: Request quota increase or try different zones

#### Model Loading Timeout
```
Error: Model failed to load within timeout period
```
**Solutions**:
- Increase Parallelstore performance tier
- Verify model file accessibility
- Check Volume Populator logs

#### Authentication Errors
```
Error: Permission denied accessing TPU resources
```
**Solution**: Verify Workload Identity configuration:
```bash
kubectl describe serviceaccount tpu-inference-pod
```

### Performance Optimization

#### Slow Model Loading
1. **Upgrade Parallelstore**: Switch from HDD to SSD tier
2. **Optimize Model Format**: Use optimized model formats
3. **Increase Bandwidth**: Use larger Parallelstore capacity

#### High Inference Latency
1. **Check TPU Utilization**: Ensure optimal batch sizes
2. **Monitor Memory**: Verify sufficient memory allocation
3. **Network Latency**: Check client-to-cluster network

### Validation Commands

```bash
# Check cluster status
kubectl get nodes -o wide

# Verify TPU nodes
kubectl get nodes -l cloud.google.com/gke-accelerator=tpu-v7-pod-slice

# Check Parallelstore
gcloud parallelstore instances describe <instance-name> --location=<zone>

# Verify storage bucket
gsutil ls gs://<bucket-name>/

# Test inference endpoint
curl -X POST http://<service-ip>/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Hello world", "max_tokens": 100}'
```

## Cleanup

### Destroy Infrastructure

```bash
# Remove Kubernetes resources first
kubectl delete deployment tpu-ironwood-inference
kubectl delete pvc model-storage-pvc
kubectl delete gcpdatasource llm-model-source

# Destroy Terraform resources
terraform destroy
```

### Selective Cleanup

To remove only specific resources:
```bash
# Remove TPU nodes only
terraform destroy -target=google_container_node_pool.tpu_pool

# Remove storage only
terraform destroy -target=google_storage_bucket.model_storage
```

## Security Considerations

### Best Practices Implemented

- **Workload Identity**: No service account keys in containers
- **Least Privilege IAM**: Minimal required permissions
- **Network Policies**: Pod-to-pod communication controls
- **Private Container Images**: Use private registries
- **Resource Quotas**: Prevent resource exhaustion

### Additional Security Measures

1. **Enable Binary Authorization**:
   ```bash
   gcloud container binauthz policy import policy.yaml
   ```

2. **Configure Pod Security Standards**:
   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: secure-inference
     labels:
       pod-security.kubernetes.io/enforce: restricted
   ```

3. **Use Private GKE Clusters** (for production):
   ```hcl
   private_cluster_config {
     enable_private_nodes = true
     enable_private_endpoint = false
     master_ipv4_cidr_block = "172.16.0.0/28"
   }
   ```

## Advanced Configuration

### Multi-Region Deployment

For global inference deployment:
```hcl
# Deploy in multiple regions
module "us_central" {
  source = "./modules/tpu-inference"
  region = "us-central1"
  zone   = "us-central1-a"
}

module "europe_west" {
  source = "./modules/tpu-inference"  
  region = "europe-west1"
  zone   = "europe-west1-b"
}
```

### Custom Machine Learning Workloads

For specialized inference requirements:
```hcl
# Custom TPU configuration
tpu_accelerator_type = "tpu-v7-pod-slice"
tpu_accelerator_count = 32

# High-memory nodes for large models
tpu_machine_type = "n1-highmem-16"

# Custom node pool taints
node_pool_taints = [
  {
    key    = "model-size"
    value  = "large"
    effect = "NO_SCHEDULE"
  }
]
```

## Support and Resources

### Documentation
- [TPU Ironwood Overview](https://cloud.google.com/tpu/docs/tpu-vm)
- [GKE Volume Populator](https://cloud.google.com/kubernetes-engine/docs/how-to/gcs-fuse-csi-driver)
- [Parallelstore Documentation](https://cloud.google.com/parallelstore/docs)

### Community
- [Google Cloud Community](https://cloud.google.com/community)
- [Kubernetes Community](https://kubernetes.io/community/)
- [Terraform Google Provider](https://github.com/hashicorp/terraform-provider-google)

### Professional Support
- [Google Cloud Support](https://cloud.google.com/support)
- [Professional Services](https://cloud.google.com/consulting)

## Contributing

To contribute improvements to this Terraform configuration:

1. Fork the repository
2. Create a feature branch
3. Test changes in a development environment
4. Submit a pull request with detailed descriptions

## License

This Terraform configuration is provided under the Apache 2.0 License. See LICENSE file for details.