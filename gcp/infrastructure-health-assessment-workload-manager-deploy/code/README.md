# Infrastructure as Code for Infrastructure Health Assessment with Cloud Workload Manager and Cloud Deploy

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Health Assessment with Cloud Workload Manager and Cloud Deploy".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Workload Manager
  - Cloud Deploy
  - Cloud Monitoring
  - Cloud Functions
  - Cloud Build
  - GKE (Google Kubernetes Engine)
  - Cloud Pub/Sub
  - Cloud Storage
- Terraform v1.0+ (for Terraform implementation)
- kubectl configured for GKE cluster access

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/health-assessment \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/health-assessment
```

### Using Terraform

```bash
# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor the deployment
gcloud deploy delivery-pipelines list --region=${REGION}
gcloud container clusters list
```

## Architecture Overview

This infrastructure deployment creates:

- **Cloud Workload Manager**: Automated infrastructure health assessment
- **GKE Cluster**: Target workload for health evaluation
- **Cloud Deploy Pipeline**: Automated remediation deployment
- **Cloud Functions**: Assessment result processing
- **Cloud Pub/Sub**: Event-driven architecture for notifications
- **Cloud Storage**: Assessment report storage
- **Cloud Monitoring**: Comprehensive observability and alerting

## Configuration Options

### Infrastructure Manager Variables

The `main.yaml` file supports these input values:

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `cluster_node_count`: GKE cluster node count (default: 3)
- `assessment_schedule`: Workload Manager evaluation schedule (default: "0 */6 * * *")

### Terraform Variables

Configure these variables in `terraform.tfvars` or via command line:

```hcl
project_id           = "your-project-id"
region              = "us-central1"
zone                = "us-central1-a"
cluster_name        = "health-cluster"
deployment_pipeline = "health-pipeline"
function_name       = "health-assessor"
cluster_node_count  = 3
assessment_schedule = "0 */6 * * *"
```

### Environment Variables for Bash Scripts

Set these environment variables before running bash scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export CLUSTER_NAME="health-cluster-$(date +%s)"
export DEPLOYMENT_PIPELINE="health-pipeline-$(date +%s)"
export FUNCTION_NAME="health-assessor-$(date +%s)"
```

## Validation and Testing

After deployment, validate the infrastructure:

### Check Workload Manager

```bash
# List evaluations
gcloud workload-manager evaluations list --location=${REGION}

# Verify assessment configuration
gcloud workload-manager evaluations describe EVALUATION_ID --location=${REGION}
```

### Verify Cloud Deploy Pipeline

```bash
# List delivery pipelines
gcloud deploy delivery-pipelines list --region=${REGION}

# Check pipeline targets
gcloud deploy targets list --region=${REGION}
```

### Test GKE Cluster

```bash
# Get cluster credentials
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}

# Verify cluster status
kubectl cluster-info
kubectl get nodes
```

### Validate Cloud Function

```bash
# Check function status
gcloud functions describe ${FUNCTION_NAME} --region=${REGION}

# View function logs
gcloud functions logs read ${FUNCTION_NAME} --limit=10
```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

- **Cloud Monitoring Dashboards**: Infrastructure health metrics
- **Alert Policies**: Critical issue notifications
- **Custom Metrics**: Deployment success tracking
- **Pub/Sub Message Monitoring**: Event flow visibility

Access monitoring:

```bash
# List alert policies
gcloud alpha monitoring policies list

# View custom metrics
gcloud logging metrics list
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/health-assessment

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual verification of resource deletion
gcloud container clusters list
gcloud deploy delivery-pipelines list --region=${REGION}
gcloud functions list
```

## Troubleshooting

### Common Issues

1. **API Enablement**: Ensure all required APIs are enabled
   ```bash
   gcloud services list --enabled
   ```

2. **IAM Permissions**: Verify sufficient permissions for all services
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Resource Quotas**: Check project quotas for compute and storage
   ```bash
   gcloud compute project-info describe --project=${PROJECT_ID}
   ```

4. **Network Connectivity**: Ensure proper VPC and firewall configurations
   ```bash
   gcloud compute networks list
   gcloud compute firewall-rules list
   ```

### Debug Commands

```bash
# Check deployment logs
gcloud logging read "resource.type=cloud_function" --limit=50

# Monitor GKE cluster events
kubectl get events --sort-by=.metadata.creationTimestamp

# View Cloud Deploy rollout status
gcloud deploy rollouts list --delivery-pipeline=${DEPLOYMENT_PIPELINE} --region=${REGION}
```

## Customization

### Adding Custom Assessment Rules

Modify the Workload Manager configuration to include custom rules:

```yaml
# In Infrastructure Manager or Terraform configurations
rules:
  - ruleId: "custom-security-scan"
    description: "Organization-specific security requirements"
    enabled: true
  - ruleId: "compliance-check"
    description: "Regulatory compliance assessment"
    enabled: true
```

### Extending Remediation Templates

Add custom remediation configurations in the deployment pipeline:

```yaml
# Additional remediation templates
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-remediation
data:
  org-policy: "enabled"
  backup-strategy: "daily"
```

### Scaling Configuration

Adjust cluster and function scaling parameters:

```hcl
# Terraform variables
variable "cluster_node_count" {
  description = "Number of nodes in GKE cluster"
  type        = number
  default     = 5  # Increase for higher workloads
}

variable "function_memory" {
  description = "Cloud Function memory allocation"
  type        = string
  default     = "512MB"  # Increase for complex processing
}
```

## Security Considerations

- **Least Privilege IAM**: All service accounts use minimal required permissions
- **Network Security**: GKE cluster uses private nodes with authorized networks
- **Data Encryption**: All data encrypted at rest and in transit
- **Secret Management**: Sensitive data stored in Secret Manager
- **Audit Logging**: Comprehensive audit trail for all operations

## Cost Optimization

- **Resource Scheduling**: Assessment runs on configurable schedule to optimize costs
- **Auto-scaling**: GKE cluster auto-scales based on workload demands
- **Storage Lifecycle**: Automatic cleanup of old assessment reports
- **Function Concurrency**: Cloud Functions scaled based on actual usage

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud service documentation
3. Validate IAM permissions and API enablement
4. Check resource quotas and limits
5. Review deployment logs for error details

## Related Documentation

- [Cloud Workload Manager Documentation](https://cloud.google.com/workload-manager/docs)
- [Cloud Deploy Documentation](https://cloud.google.com/deploy/docs)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)