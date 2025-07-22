# Infrastructure as Code for Enterprise-Grade ML Model Lifecycle Management with AI Hypercomputer and Vertex AI Training

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise-Grade ML Model Lifecycle Management with AI Hypercomputer and Vertex AI Training".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Bash Scripts**: Deployment and cleanup scripts for manual provisioning

## Prerequisites

### General Requirements
- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - AI Platform Admin
  - Vertex AI Admin
  - Cloud Workstations Admin
  - Compute Admin
  - Storage Admin
  - BigQuery Admin
  - Artifact Registry Admin
  - Service Usage Admin

### Tool-Specific Prerequisites

#### Infrastructure Manager
- `gcloud` CLI version 450.0.0 or later
- Infrastructure Manager API enabled in your project

#### Terraform
- Terraform version 1.5.0 or later
- Google Cloud Provider version 5.0.0 or later

#### Bash Scripts
- `gcloud` CLI configured with appropriate permissions
- `curl` and `jq` utilities installed

## Cost Considerations

This solution provisions enterprise-grade ML infrastructure including:
- AI Hypercomputer resources (TPU v5e and A3 GPU instances)
- Cloud Workstations with high-performance configurations
- Vertex AI training jobs and endpoints
- Cloud Storage buckets with lifecycle management
- BigQuery datasets for experiment tracking

**Estimated Cost**: $200-500 for running the complete solution during testing. Monitor usage closely and clean up resources promptly to avoid unexpected charges.

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create ml-lifecycle-deployment \
    --location=${REGION} \
    --source=./main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment progress
gcloud infra-manager deployments describe ml-lifecycle-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary region for resources | `us-central1` | No |
| `zone` | Primary zone for compute resources | `us-central1-a` | No |
| `workstation_machine_type` | Machine type for Cloud Workstations | `n1-standard-8` | No |
| `training_machine_type` | Machine type for training jobs | `a3-highgpu-8g` | No |
| `enable_tpu` | Enable TPU resources | `true` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | `string` | - | Yes |
| `region` | Primary region for resources | `string` | `us-central1` | No |
| `zone` | Primary zone for compute resources | `string` | `us-central1-a` | No |
| `workstation_machine_type` | Machine type for Cloud Workstations | `string` | `n1-standard-8` | No |
| `training_machine_type` | Machine type for training jobs | `string` | `a3-highgpu-8g` | No |
| `bucket_lifecycle_age` | Age in days for bucket lifecycle | `number` | `30` | No |
| `enable_tpu` | Enable TPU resources | `bool` | `true` | No |
| `tpu_accelerator_type` | TPU accelerator type | `string` | `v5litepod-4` | No |
| `gpu_accelerator_type` | GPU accelerator type | `string` | `nvidia-h100-80gb` | No |
| `gpu_accelerator_count` | Number of GPU accelerators | `number` | `8` | No |

## Deployment Validation

After deployment, verify the infrastructure is working correctly:

### Check Core Resources

```bash
# Verify APIs are enabled
gcloud services list --enabled --filter="name:aiplatform.googleapis.com OR name:workstations.googleapis.com"

# Check Cloud Workstations
gcloud workstations clusters list --regions=${REGION}
gcloud workstations configs list --cluster=ml-workstations-cluster --region=${REGION}

# Verify AI Hypercomputer resources
gcloud compute tpus tpu-vm list --zone=${ZONE}
gcloud compute instances list --filter="zone:${ZONE} AND machineType:a3-highgpu-8g"
```

### Test Vertex AI Integration

```bash
# Check Vertex AI experiments
gcloud ai experiments list --region=${REGION}

# Verify model registry
gcloud ai models list --region=${REGION}

# Test training job submission
gcloud ai custom-jobs list --region=${REGION}
```

### Validate Storage and Data Resources

```bash
# Check Cloud Storage buckets
gsutil ls -p ${PROJECT_ID}

# Verify BigQuery datasets
bq ls --project_id=${PROJECT_ID}

# Check Artifact Registry
gcloud artifacts repositories list --location=${REGION}
```

## Monitoring and Logging

### Enable Monitoring

```bash
# View Cloud Workstations logs
gcloud workstations get-iam-policy ml-dev-workstation \
    --cluster=ml-workstations-cluster \
    --config=ml-config \
    --region=${REGION}

# Monitor training job logs
gcloud ai custom-jobs stream-logs JOB_ID --region=${REGION}

# Check TPU utilization
gcloud compute tpus tpu-vm ssh ml-tpu-training --zone=${ZONE} --command="nvidia-smi"
```

### Performance Monitoring

```bash
# Monitor GPU utilization
gcloud compute ssh ml-gpu-training --zone=${ZONE} --command="nvidia-smi"

# Check Vertex AI endpoint metrics
gcloud ai endpoints list --region=${REGION}
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Quotas**: Check compute quotas for TPU and GPU resources
3. **IAM Permissions**: Verify service accounts have necessary permissions
4. **Resource Conflicts**: Ensure resource names are unique across deployments

### Debug Commands

```bash
# Check API status
gcloud services list --enabled --filter="aiplatform"

# Verify quotas
gcloud compute project-info describe --project=${PROJECT_ID}

# Check IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Debug workstation issues
gcloud workstations describe ml-dev-workstation \
    --cluster=ml-workstations-cluster \
    --config=ml-config \
    --region=${REGION}
```

## Security Considerations

### Best Practices Implemented

- **Least Privilege IAM**: Service accounts with minimal required permissions
- **Private Endpoints**: Cloud Workstations with private endpoint access
- **Encryption**: All data encrypted at rest and in transit
- **Network Security**: Proper firewall rules and network segmentation
- **Audit Logging**: Comprehensive logging for all resource access

### Security Validation

```bash
# Check IAM policies
gcloud projects get-iam-policy ${PROJECT_ID}

# Verify encryption settings
gsutil lifecycle get gs://your-bucket-name

# Check network security
gcloud compute firewall-rules list --filter="direction:INGRESS"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete ml-lifecycle-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy -auto-approve

# Clean up state files
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
echo "Cleanup complete. Verify no resources remain in the project."
```

### Manual Cleanup Verification

```bash
# Check for remaining resources
gcloud compute instances list --filter="zone:${ZONE}"
gcloud compute tpus tpu-vm list --zone=${ZONE}
gcloud workstations clusters list --regions=${REGION}
gcloud ai models list --region=${REGION}
gsutil ls -p ${PROJECT_ID}
bq ls --project_id=${PROJECT_ID}
```

## Customization

### Scaling Configuration

To customize resource scaling:

1. **Infrastructure Manager**: Edit `main.yaml` resource specifications
2. **Terraform**: Modify variables in `terraform.tfvars`
3. **Bash Scripts**: Edit environment variables in `deploy.sh`

### Machine Type Selection

Choose appropriate machine types based on workload requirements:

- **For development**: `n1-standard-4` or `n1-standard-8`
- **For training**: `a3-highgpu-8g` or `a3-megagpu-8g`
- **For inference**: `n1-standard-2` or `n1-standard-4`

### Regional Deployment

To deploy in different regions:

1. Update region variables in your configuration
2. Ensure selected regions support required resources (TPUs, GPUs)
3. Consider data residency and compliance requirements

## Advanced Features

### Multi-Environment Support

```bash
# Deploy to development environment
terraform workspace new dev
terraform apply -var="environment=dev"

# Deploy to production environment
terraform workspace new prod
terraform apply -var="environment=prod"
```

### Automated CI/CD Integration

```bash
# Example GitHub Actions workflow
name: Deploy ML Infrastructure
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v1
      - name: Deploy
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

## Support and Documentation

### Additional Resources

- [Google Cloud AI Hypercomputer Documentation](https://cloud.google.com/ai-hypercomputer)
- [Vertex AI Training Documentation](https://cloud.google.com/vertex-ai/docs/training)
- [Cloud Workstations Documentation](https://cloud.google.com/workstations/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Review Terraform provider documentation for configuration issues

### Contributing

To contribute improvements to this infrastructure code:

1. Test changes thoroughly in a development environment
2. Update documentation for any configuration changes
3. Ensure security best practices are maintained
4. Validate all IaC implementations work correctly

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and adapt according to your organization's requirements and policies.