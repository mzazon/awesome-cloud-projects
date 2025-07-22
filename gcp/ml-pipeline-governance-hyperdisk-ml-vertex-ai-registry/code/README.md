# Infrastructure as Code for ML Pipeline Governance with Hyperdisk ML and Vertex AI Model Registry

This directory contains Infrastructure as Code (IaC) implementations for the recipe "ML Pipeline Governance with Hyperdisk ML and Vertex AI Model Registry".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for the following services:
  - Compute Engine
  - Vertex AI
  - Cloud Workflows
  - Cloud Monitoring
  - Cloud Logging
  - Cloud Storage
- Terraform (version >= 1.0) for Terraform deployment
- Python 3.7+ for governance policy scripts

## Architecture Overview

This solution implements a comprehensive ML governance system that combines:

- **Hyperdisk ML**: High-performance storage optimized for ML workloads (up to 1,200,000 MiB/s throughput)
- **Vertex AI Model Registry**: Centralized model lifecycle management with versioning and metadata tracking
- **Cloud Workflows**: Automated governance orchestration and compliance enforcement
- **Cloud Monitoring**: Real-time performance tracking and governance metrics
- **Policy Engine**: Automated compliance validation and audit trail generation

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/ml-governance-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars" \
    --labels="environment=production,recipe=ml-governance"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/ml-governance-deployment
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

# Apply configuration
terraform apply -var-file="terraform.tfvars"

# Verify resources
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

# Verify deployment
gcloud compute disks list --filter="name~hyperdisk-ml"
gcloud ai models list --region=${REGION}
gcloud workflows list --location=${REGION}
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Primary deployment region | `us-central1` | No |
| `zone` | Compute zone for instances | `us-central1-a` | No |
| `hyperdisk_size_gb` | Hyperdisk ML volume size | `1000` | No |
| `hyperdisk_throughput` | Provisioned throughput (MiB/s) | `10000` | No |
| `machine_type` | ML training instance type | `n1-standard-8` | No |
| `enable_monitoring` | Create monitoring dashboard | `true` | No |
| `enable_governance_workflow` | Deploy governance automation | `true` | No |

### Customization Examples

#### High-Performance Configuration
```hcl
# terraform.tfvars
hyperdisk_size_gb = 2000
hyperdisk_throughput = 50000
machine_type = "n1-standard-16"
```

#### Development Environment
```hcl
# terraform.tfvars
hyperdisk_size_gb = 500
hyperdisk_throughput = 5000
machine_type = "n1-standard-4"
enable_monitoring = false
```

#### Production Environment
```hcl
# terraform.tfvars
hyperdisk_size_gb = 5000
hyperdisk_throughput = 100000
machine_type = "n1-highmem-8"
enable_governance_workflow = true
enable_monitoring = true
```

## Deployment Validation

### Verify Hyperdisk ML Performance

```bash
# Check Hyperdisk ML volume
gcloud compute disks describe ml-training-hyperdisk-${RANDOM_SUFFIX} \
    --region=${REGION} \
    --format="table(name,status,type,provisionedThroughput)"

# Expected: Status=READY, Type=hyperdisk-ml, ProvisionedThroughput=10000
```

### Verify Vertex AI Model Registry

```bash
# List registered models
gcloud ai models list --region=${REGION}

# Check model with governance labels
gcloud ai models list \
    --region=${REGION} \
    --filter="labels.governance=enabled" \
    --format="table(displayName,labels,createTime)"
```

### Test Governance Workflow

```bash
# Execute governance workflow
WORKFLOW_NAME=$(gcloud workflows list --location=${REGION} --format="value(name)" --filter="name~governance")

gcloud workflows run ${WORKFLOW_NAME} \
    --location=${REGION} \
    --data='{"model_id":"your-model-id","region":"'${REGION}'"}'

# Check execution results
gcloud workflows executions list \
    --workflow=${WORKFLOW_NAME} \
    --location=${REGION} \
    --limit=1
```

### Validate Monitoring Setup

```bash
# List monitoring dashboards
gcloud monitoring dashboards list \
    --filter="displayName~'ML Governance'"

# Check custom metrics
gcloud logging read "resource.type=gce_instance" \
    --limit=10 \
    --format="table(timestamp,resource.labels.instance_id,textPayload)"
```

## Cost Optimization

### Resource Costs (Estimated Monthly)

| Resource | Configuration | Estimated Cost (USD) |
|----------|---------------|---------------------|
| Hyperdisk ML (1TB) | 10,000 MiB/s throughput | $400-600 |
| Compute Instance | n1-standard-8 (part-time) | $150-300 |
| Vertex AI Model Registry | Model storage and ops | $50-100 |
| Cloud Workflows | Execution-based pricing | $10-50 |
| Cloud Monitoring | Custom metrics and dashboards | $20-40 |

### Cost Reduction Strategies

1. **Right-size Hyperdisk ML**: Start with lower throughput (5,000 MiB/s) and scale as needed
2. **Use Preemptible Instances**: For development and testing environments
3. **Implement Auto-shutdown**: Stop training instances when not in use
4. **Optimize Storage**: Use lifecycle policies for training data in Cloud Storage

```bash
# Example: Reduce throughput for development
gcloud compute disks update ml-training-hyperdisk-${RANDOM_SUFFIX} \
    --provisioned-throughput=5000 \
    --region=${REGION}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/ml-governance-deployment

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Plan destruction (review what will be deleted)
terraform plan -destroy -var-file="terraform.tfvars"

# Destroy infrastructure
terraform destroy -var-file="terraform.tfvars"

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud compute disks list --filter="name~ml-training"
gcloud ai models list --region=${REGION}
gcloud workflows list --location=${REGION}
```

### Manual Cleanup (if needed)

```bash
# Force delete remaining resources
gcloud compute instances delete ml-training-instance-* --zone=${ZONE} --quiet
gcloud compute disks delete ml-training-hyperdisk-* --region=${REGION} --quiet
gcloud ai models delete [MODEL_ID] --region=${REGION} --quiet
gcloud workflows delete ml-governance-workflow-* --location=${REGION} --quiet

# Remove storage bucket
gsutil -m rm -r gs://ml-training-data-*

# Delete service accounts
gcloud iam service-accounts delete ml-governance-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Troubleshooting

### Common Issues

#### Hyperdisk ML Creation Fails
```bash
# Check quotas
gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)"

# Verify region support
gcloud compute disk-types list --filter="name=hyperdisk-ml" --format="table(name,zone)"
```

#### Vertex AI Permissions Error
```bash
# Check IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members~'ml-governance-sa'"

# Add missing permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:ml-governance-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/aiplatform.admin"
```

#### Workflow Execution Fails
```bash
# Check workflow logs
gcloud logging read "resource.type=cloud_workflow" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"

# Validate workflow syntax
gcloud workflows deploy ml-governance-workflow \
    --source=governance-workflow.yaml \
    --location=${REGION} \
    --dry-run
```

### Performance Optimization

#### Hyperdisk ML Tuning
```bash
# Monitor disk performance
gcloud monitoring metrics list --filter="metric.type~disk"

# Adjust throughput based on usage
gcloud compute disks update ml-training-hyperdisk-${RANDOM_SUFFIX} \
    --provisioned-throughput=20000 \
    --region=${REGION}
```

#### Training Instance Optimization
```bash
# Use high-memory instances for large models
gcloud compute instances set-machine-type ml-training-instance-${RANDOM_SUFFIX} \
    --machine-type=n1-highmem-16 \
    --zone=${ZONE}

# Enable GPU acceleration (if needed)
gcloud compute instances stop ml-training-instance-${RANDOM_SUFFIX} --zone=${ZONE}
gcloud compute instances set-machine-type ml-training-instance-${RANDOM_SUFFIX} \
    --machine-type=n1-standard-8 \
    --zone=${ZONE}
gcloud compute instances start ml-training-instance-${RANDOM_SUFFIX} --zone=${ZONE}
```

## Security Considerations

### IAM Best Practices

1. **Principle of Least Privilege**: Grant only necessary permissions
2. **Service Account Security**: Use dedicated service accounts for each component
3. **Network Security**: Implement VPC firewall rules for training instances
4. **Data Encryption**: Enable encryption at rest and in transit

### Security Validation

```bash
# Check service account permissions
gcloud iam service-accounts get-iam-policy ml-governance-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Verify encryption settings
gcloud compute disks describe ml-training-hyperdisk-${RANDOM_SUFFIX} \
    --region=${REGION} \
    --format="value(diskEncryptionKey.kmsKeyName)"

# Review network security
gcloud compute firewall-rules list --format="table(name,direction,allowed)"
```

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# .github/workflows/ml-governance.yml
name: ML Governance Pipeline
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: google-github-actions/setup-gcloud@v1
    - name: Deploy ML Governance
      run: |
        cd terraform/
        terraform init
        terraform apply -auto-approve
```

### Custom Policy Integration

```python
# custom-policies.py
from governance_policies import MLGovernancePolicies

class CustomMLPolicies(MLGovernancePolicies):
    def __init__(self):
        super().__init__()
        self.policies.update({
            'data_retention_days': 90,
            'model_approval_required': True,
            'security_scan_threshold': 'HIGH'
        })
    
    def validate_data_retention(self, model_metadata):
        # Custom validation logic
        pass
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for conceptual guidance
2. **Google Cloud Documentation**: 
   - [Hyperdisk ML Documentation](https://cloud.google.com/compute/docs/disks/hyperdisks)
   - [Vertex AI Model Registry](https://cloud.google.com/vertex-ai/docs/model-registry)
   - [Cloud Workflows](https://cloud.google.com/workflows/docs)
3. **Terraform Provider**: [Google Cloud Terraform Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: Stack Overflow with tags `google-cloud-platform`, `vertex-ai`, `terraform`

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud security best practices
3. Update documentation for any configuration changes
4. Validate all resource configurations before submitting changes

---

**Note**: This infrastructure creates billable Google Cloud resources. Monitor your usage and costs, and clean up resources when no longer needed.