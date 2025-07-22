# Infrastructure as Code for Edge-to-Cloud MLOps Pipelines with Distributed Cloud Edge and Vertex AI Pipelines

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Edge-to-Cloud MLOps Pipelines with Distributed Cloud Edge and Vertex AI Pipelines".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts for step-by-step deployment

## Prerequisites

- Google Cloud account with appropriate permissions for Vertex AI, Distributed Cloud Edge, Cloud Storage, Cloud Monitoring, GKE, and Cloud Functions
- gcloud CLI installed and configured (version 400.0.0 or later)
- Terraform CLI installed (version 1.0+ for Terraform implementation)
- Advanced knowledge of machine learning workflows and containerization
- Understanding of edge computing concepts and hybrid cloud architectures
- Estimated cost: $200-500 for resources created during this deployment

> **Note**: This advanced recipe requires careful resource management to avoid significant costs. Distributed Cloud Edge involves substantial infrastructure components.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code at scale.

```bash
# Set up environment variables
export PROJECT_ID="mlops-edge-$(date +%s)"
export REGION="us-central1"

# Create new project and set billing (optional)
gcloud projects create ${PROJECT_ID}
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable config.googleapis.com

# Deploy infrastructure using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/edge-mlops-pipeline \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-config-bucket/infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/edge-mlops-pipeline
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive ecosystem support for complex MLOps infrastructure.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify deployment
terraform output edge_inference_endpoint
terraform output vertex_ai_region
terraform output mlops_bucket_name
```

### Using Bash Scripts

Bash scripts provide step-by-step deployment following the original recipe instructions with additional automation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="mlops-edge-$(date +%s)"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
./scripts/monitor.sh

# Test the deployed infrastructure
./scripts/validate.sh
```

## Deployment Details

### Infrastructure Manager Configuration

The Infrastructure Manager implementation includes:

- **Service Accounts**: MLOps pipeline service account with appropriate IAM roles
- **Storage**: Cloud Storage buckets for MLOps artifacts and edge models with versioning enabled
- **Compute**: GKE cluster for edge simulation with autoscaling configuration
- **AI/ML**: Vertex AI Model Registry and experiment tracking setup
- **Monitoring**: Cloud Monitoring dashboards and alerting policies
- **Serverless**: Cloud Functions for automated model updates
- **Networking**: VPC and firewall rules for secure communication

Key configuration files:
- `infrastructure-manager/main.yaml`: Primary infrastructure definition
- `infrastructure-manager/variables.yaml`: Configurable parameters
- `infrastructure-manager/outputs.yaml`: Deployment outputs

### Terraform Configuration

The Terraform implementation provides:

- **Modular Structure**: Organized into logical modules for different components
- **Variable Management**: Comprehensive variable definitions with validation
- **State Management**: Remote state storage in Cloud Storage
- **Provider Versioning**: Pinned provider versions for reproducible deployments
- **Resource Dependencies**: Proper dependency management between resources

Key files:
- `terraform/main.tf`: Primary resource definitions
- `terraform/variables.tf`: Input variables with descriptions and validation
- `terraform/outputs.tf`: Output values for integration and verification
- `terraform/versions.tf`: Provider version constraints
- `terraform/terraform.tfvars.example`: Example variable values

### Bash Scripts Implementation

The bash scripts provide:

- **Step-by-Step Deployment**: Following the original recipe methodology
- **Error Handling**: Comprehensive error checking and rollback capabilities
- **Progress Tracking**: Clear progress indicators and logging
- **Validation**: Built-in testing and verification steps
- **Cleanup**: Complete resource cleanup with confirmation prompts

Available scripts:
- `scripts/deploy.sh`: Complete infrastructure deployment
- `scripts/destroy.sh`: Clean resource removal
- `scripts/validate.sh`: Post-deployment validation and testing
- `scripts/monitor.sh`: Real-time deployment monitoring

## Customization

### Environment Variables

All implementations support customization through environment variables:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"              # GCP region for resources
export ZONE="us-central1-a"              # GCP zone for compute resources

# Optional customization variables
export CLUSTER_NAME="edge-simulation-cluster"  # GKE cluster name
export MODEL_NAME="edge-inference-model"       # Vertex AI model name
export RANDOM_SUFFIX="$(openssl rand -hex 3)"  # Unique resource suffix
```

### Infrastructure Manager Variables

Edit `infrastructure-manager/variables.yaml`:

```yaml
project_id:
  description: "Google Cloud Project ID"
  type: string
  required: true

region:
  description: "GCP region for resource deployment"
  type: string
  default: "us-central1"

cluster_machine_type:
  description: "Machine type for GKE cluster nodes"
  type: string
  default: "e2-standard-4"

cluster_node_count:
  description: "Initial number of nodes in GKE cluster"
  type: integer
  default: 3
```

### Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# GKE cluster configuration
cluster_name         = "edge-simulation-cluster"
cluster_machine_type = "e2-standard-4"
cluster_node_count   = 3

# MLOps configuration
model_name = "edge-inference-model"
enable_gpu = false

# Storage configuration
storage_class = "STANDARD"
enable_versioning = true

# Monitoring configuration
enable_monitoring = true
alert_email = "your-email@example.com"
```

### Script Configuration

Edit variables at the top of `scripts/deploy.sh`:

```bash
# Deployment configuration
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DEFAULT_MACHINE_TYPE="e2-standard-4"
DEFAULT_NODE_COUNT=3

# Enable/disable components
ENABLE_MONITORING=true
ENABLE_EDGE_SIMULATION=true
ENABLE_TELEMETRY_COLLECTION=true
```

## Validation & Testing

### Infrastructure Manager Validation

```bash
# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/edge-mlops-pipeline

# List deployed resources
gcloud infra-manager deployments list --location=${REGION}

# Validate Vertex AI setup
gcloud ai models list --region=${REGION}
```

### Terraform Validation

```bash
# Validate Terraform configuration
terraform validate

# Check infrastructure state
terraform show

# Test outputs
terraform output -json | jq .
```

### Bash Script Validation

```bash
# Run validation script
./scripts/validate.sh

# Check individual components
kubectl get pods -n edge-inference
gcloud ai experiments list --region=${REGION}
gsutil ls -p ${PROJECT_ID}
```

### End-to-End Testing

```bash
# Test edge inference service
INFERENCE_ENDPOINT=$(kubectl get service edge-inference-service -n edge-inference -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -X POST http://${INFERENCE_ENDPOINT}/predict \
    -H "Content-Type: application/json" \
    -d '{"feature1": 42, "feature2": 84}'

# Test telemetry collection
TELEMETRY_ENDPOINT=$(kubectl get service telemetry-collector -n edge-inference -o jsonpath='{.spec.clusterIP}')

kubectl run curl-test --rm -i --tty --image=curlimages/curl -- \
    curl -X POST http://${TELEMETRY_ENDPOINT}/telemetry \
    -H "Content-Type: application/json" \
    -d '{"edge_location": "test", "model_version": "v1", "prediction": 1}'
```

## Monitoring & Observability

### Cloud Monitoring Dashboard

Access the MLOps monitoring dashboard:

```bash
# List monitoring dashboards
gcloud monitoring dashboards list --filter="displayName:Edge MLOps"

# Get dashboard URL
echo "https://console.cloud.google.com/monitoring/dashboards"
```

### Key Metrics to Monitor

- **Edge Inference Request Rate**: Monitor API request volume to edge services
- **Model Prediction Latency**: Track inference response times across edge locations
- **Model Accuracy Metrics**: Monitor prediction confidence and feedback scores
- **Resource Utilization**: Track CPU, memory, and storage usage across GKE cluster
- **Pipeline Execution Status**: Monitor Vertex AI Pipeline runs and success rates

### Alerting

Configure alerts for critical metrics:

```bash
# List configured alert policies
gcloud alpha monitoring policies list --filter="displayName:Edge"

# Create custom alerts
gcloud alpha monitoring policies create --policy-from-file=custom-alert-policy.yaml
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/edge-mlops-pipeline

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Clean up Terraform state
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script with confirmation
./scripts/destroy.sh

# Force cleanup without prompts (use with caution)
./scripts/destroy.sh --force
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud compute instances list --project=${PROJECT_ID}
gcloud container clusters list --project=${PROJECT_ID}
gcloud ai models list --region=${REGION} --project=${PROJECT_ID}
gsutil ls -p ${PROJECT_ID}

# Delete project entirely (optional)
gcloud projects delete ${PROJECT_ID}
```

## Troubleshooting

### Common Issues

1. **API Enablement**: Ensure all required APIs are enabled before deployment
   ```bash
   gcloud services enable compute.googleapis.com aiplatform.googleapis.com storage.googleapis.com
   ```

2. **IAM Permissions**: Verify service account has necessary permissions
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Resource Quotas**: Check regional quotas for compute and AI services
   ```bash
   gcloud compute project-info describe --project=${PROJECT_ID}
   ```

4. **GKE Cluster Issues**: Verify cluster status and node availability
   ```bash
   kubectl get nodes
   kubectl describe nodes
   ```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# Terraform debug mode
export TF_LOG=DEBUG
terraform apply

# gcloud debug mode
gcloud --verbosity=debug services enable compute.googleapis.com

# Script debug mode
bash -x scripts/deploy.sh
```

### Support Resources

- [Vertex AI MLOps Documentation](https://cloud.google.com/vertex-ai/docs/start/introduction-mlops)
- [Google Distributed Cloud Edge Documentation](https://cloud.google.com/distributed-cloud/edge/latest/docs)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Security Considerations

### IAM and Authentication

- Service accounts follow principle of least privilege
- Workload Identity enabled for secure GKE pod authentication
- API keys and secrets managed through Secret Manager
- Network policies implemented for pod-to-pod communication

### Network Security

- Private GKE cluster with authorized networks
- VPC firewall rules limiting access to necessary ports
- Load balancer with SSL termination
- Private connectivity to Google Cloud services

### Data Protection

- Encryption at rest for Cloud Storage buckets
- Encryption in transit for all API communications
- Model artifacts signed and verified during deployment
- Audit logging enabled for all resource access

## Performance Optimization

### Resource Sizing

- GKE cluster configured with appropriate machine types for ML workloads
- Autoscaling enabled for dynamic resource allocation
- Resource requests and limits set for all containers
- Storage classes optimized for performance and cost

### Monitoring and Scaling

- Horizontal Pod Autoscaler configured for inference workloads
- Cluster autoscaling enabled for node management
- Custom metrics for ML-specific scaling decisions
- Performance profiling enabled for optimization insights

## Cost Management

### Resource Optimization

- Use of preemptible instances where appropriate
- Storage lifecycle policies for automated archival
- Regional persistent disks for cost-effective storage
- Scheduled scaling for non-production environments

### Cost Monitoring

```bash
# Enable cost monitoring
gcloud billing budgets create --billing-account=${BILLING_ACCOUNT} \
    --display-name="MLOps Pipeline Budget" \
    --budget-amount=500USD

# Monitor spending
gcloud billing budgets list --billing-account=${BILLING_ACCOUNT}
```

## Support

For issues with this infrastructure code:

1. Review the troubleshooting section above
2. Check the original recipe documentation for context
3. Consult Google Cloud documentation for specific services
4. Use `gcloud feedback` to report infrastructure issues
5. Review Terraform provider documentation for Terraform-specific issues

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a separate project/environment
2. Validate all deployment methods work correctly
3. Update documentation to reflect any changes
4. Follow Google Cloud security and best practices guidelines