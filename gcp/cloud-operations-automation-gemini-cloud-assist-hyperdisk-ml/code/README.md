# Infrastructure as Code for Cloud Operations Automation with Gemini Cloud Assist and Hyperdisk ML

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cloud Operations Automation with Gemini Cloud Assist and Hyperdisk ML".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for creating:
  - Compute Engine instances and disks
  - Google Kubernetes Engine clusters
  - Vertex AI resources
  - Cloud Functions
  - Cloud Monitoring resources
  - Cloud Storage buckets
  - Cloud Scheduler jobs
- Access to Gemini Cloud Assist (private preview access required)
- Estimated cost: $50-100 for resources created during deployment

## Quick Start

### Using Infrastructure Manager

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="ml-ops-automation"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/inputs.yaml"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project details

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud compute instances list
gcloud container clusters list
```

## Architecture Overview

This infrastructure deploys:

- **Hyperdisk ML Volume**: Ultra-high throughput storage (up to 1,200,000 MiB/s) optimized for ML workloads
- **GKE Cluster**: Kubernetes cluster with ML-optimized configuration including GPU node pools
- **Vertex AI Agent**: AI-powered operations automation for intelligent infrastructure management
- **Cloud Monitoring**: Custom metrics and alerting for ML workload performance
- **Cloud Functions**: Automation functions integrated with Gemini Cloud Assist
- **Cloud Storage**: Dataset storage with intelligent lifecycle management
- **Cloud Scheduler**: Automated scaling and optimization routines

## Configuration

### Infrastructure Manager Variables

Edit `infrastructure-manager/inputs.yaml`:

```yaml
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"
cluster_name: "ml-ops-cluster"
hyperdisk_size_gb: 10240
node_count: 2
max_node_count: 10
```

### Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
cluster_name = "ml-ops-cluster"
hyperdisk_size_gb = 10240
node_count = 2
max_node_count = 10
gpu_node_count = 0
max_gpu_nodes = 5
```

### Bash Script Environment Variables

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export CLUSTER_NAME="ml-ops-cluster"
export HYPERDISK_SIZE="10TB"
export NODE_COUNT="2"
export MAX_NODES="10"
```

## Deployment Details

### Hyperdisk ML Configuration

- **Storage Type**: Hyperdisk ML for ultra-high throughput
- **Capacity**: 10TB (configurable)
- **Throughput**: 100,000 MiB/s provisioned
- **Attachment**: Supports up to 2,500 concurrent instances
- **Use Case**: Optimized for distributed ML training and inference

### GKE Cluster Features

- **Node Pools**: CPU nodes (c3-standard-4) and GPU nodes (g2-standard-4 with NVIDIA L4)
- **Autoscaling**: Enabled with configurable min/max nodes
- **Network Policy**: Enabled for enhanced security
- **CSI Driver**: GCE Persistent Disk CSI driver for storage integration
- **Addons**: Monitoring and logging enabled

### Vertex AI Integration

- **Service Account**: Dedicated service account with AI Platform permissions
- **Agent Configuration**: Operations optimizer with workload analysis capabilities
- **Permissions**: Monitoring metric writer and AI Platform user roles
- **Integration**: Connected to Gemini Cloud Assist for intelligent automation

### Monitoring and Automation

- **Custom Metrics**: ML training duration and storage throughput tracking
- **Alerting**: Performance-based alerts for ML workload anomalies
- **Automation Functions**: HTTP-triggered functions for scaling and optimization
- **Scheduling**: Automated optimization routines every 15 minutes

## Validation and Testing

### Verify Hyperdisk ML Deployment

```bash
# Check Hyperdisk ML status
gcloud compute disks describe ${HYPERDISK_NAME} \
    --zone=${ZONE} \
    --format="table(name,type,status,sizeGb,provisionedIops)"

# Verify throughput configuration
gcloud compute disks describe ${HYPERDISK_NAME} \
    --zone=${ZONE} \
    --format="value(provisionedThroughput)"
```

### Test GKE Cluster

```bash
# Get cluster credentials
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}

# Check cluster status
kubectl cluster-info

# Verify node pools
kubectl get nodes --show-labels
```

### Validate ML Workload Integration

```bash
# Deploy sample ML workload
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ml-test-job
spec:
  template:
    spec:
      containers:
      - name: ml-test
        image: gcr.io/google-samples/hello-app:1.0
        command: ["/bin/sh", "-c"]
        args: ["echo 'ML workload test completed'; sleep 60"]
      restartPolicy: Never
EOF

# Check job status
kubectl get jobs
kubectl logs job/ml-test-job
```

### Test Automation Functions

```bash
# Get function URL
FUNCTION_URL=$(gcloud functions describe ${FUNCTION_NAME} \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Test function endpoint
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"recommendation":{"type":"scale_cluster","action":"test"}}'
```

## Security Considerations

### IAM and Permissions

- Service accounts follow least privilege principle
- Workload Identity enabled for secure pod-to-service authentication
- Network policies configured for cluster security
- Storage access controlled through IAM bindings

### Network Security

- Private GKE cluster option available (uncomment in configuration)
- Network policies enabled for pod-to-pod communication control
- Firewall rules configured for necessary service communication

### Data Protection

- Encryption at rest enabled for all storage resources
- Encryption in transit for all service communications
- Secret management through Google Secret Manager (when configured)

## Monitoring and Observability

### Cloud Monitoring Integration

```bash
# View custom metrics
gcloud logging metrics list --filter="name:ml_training_duration OR name:storage_throughput"

# Check alerting policies
gcloud alpha monitoring policies list --format="table(displayName,enabled)"
```

### Performance Monitoring

```bash
# Monitor Hyperdisk ML performance
gcloud compute operations list --filter="operationType:compute.disks.createSnapshot"

# View GKE cluster metrics
kubectl top nodes
kubectl top pods --all-namespaces
```

## Troubleshooting

### Common Issues

1. **Hyperdisk ML Provisioning Errors**:
   - Verify zone supports Hyperdisk ML
   - Check quotas for high-performance storage
   - Ensure proper IAM permissions

2. **GKE Cluster Creation Failures**:
   - Verify Compute Engine API is enabled
   - Check regional quotas for instances
   - Ensure subnet has adequate IP address space

3. **Vertex AI Permission Issues**:
   - Verify AI Platform API is enabled
   - Check service account permissions
   - Ensure Workload Identity is properly configured

4. **Function Deployment Failures**:
   - Check Cloud Functions API is enabled
   - Verify source code syntax and dependencies
   - Ensure proper IAM roles for deployment

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:compute.googleapis.com OR name:aiplatform.googleapis.com"

# Verify quotas
gcloud compute project-info describe --format="table(quotas.metric,quotas.usage,quotas.limit)"

# Check deployment logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=${FUNCTION_NAME}" --limit=50
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud compute instances list
gcloud container clusters list
gcloud functions list
```

### Manual Cleanup Verification

```bash
# Check for remaining resources
gcloud compute disks list --filter="type:hyperdisk-ml"
gcloud container clusters list
gcloud functions list --regions=${REGION}
gcloud scheduler jobs list --location=${REGION}
gcloud storage buckets list --filter="name:ml-datasets"
```

## Cost Optimization

### Resource Sizing Recommendations

- **Hyperdisk ML**: Start with 1TB for testing, scale based on dataset size
- **GKE Nodes**: Use preemptible instances for non-critical workloads
- **GPU Nodes**: Set minimum to 0 to avoid idle costs
- **Storage**: Implement lifecycle policies for dataset archival

### Cost Monitoring

```bash
# Enable billing export for cost analysis
gcloud billing accounts list
gcloud logging sinks create ml-ops-billing-sink \
    bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/billing_export
```

## Support and Documentation

- **Recipe Documentation**: Refer to the original recipe markdown for detailed explanations
- **Google Cloud Documentation**: [Cloud Operations Documentation](https://cloud.google.com/products/operations)
- **Hyperdisk ML Guide**: [Hyperdisk Performance Documentation](https://cloud.google.com/compute/docs/disks/hyperdisk-performance)
- **Vertex AI Documentation**: [Vertex AI Overview](https://cloud.google.com/vertex-ai/docs)
- **Gemini Cloud Assist**: Contact Google Cloud support for private preview access

## Extensions and Enhancements

Consider implementing these advanced features:

1. **Multi-Region Deployment**: Extend to multiple regions for global ML workload distribution
2. **Advanced Cost Analytics**: Integrate with BigQuery for detailed cost analysis and optimization
3. **Security Scanning**: Add Container Analysis API for vulnerability scanning
4. **Compliance Monitoring**: Implement Policy Controller for governance and compliance
5. **Disaster Recovery**: Add cross-region backup and recovery capabilities

For issues with this infrastructure code, refer to the original recipe documentation or open an issue with the appropriate provider's support channels.