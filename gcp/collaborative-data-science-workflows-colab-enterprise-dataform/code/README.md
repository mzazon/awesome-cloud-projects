# Infrastructure as Code for Collaborative Data Science Workflows with Colab Enterprise and Dataform

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Collaborative Data Science Workflows with Colab Enterprise and Dataform".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Project with billing enabled
- Appropriate IAM permissions for:
  - Vertex AI (Colab Enterprise)
  - BigQuery
  - Cloud Storage
  - Dataform
  - IAM administration
- Estimated cost: $50-100 for moderate data volumes

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create ds-workflow-deployment \
    --location=${REGION} \
    --source-blueprint=main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment status
gcloud infra-manager deployments describe ds-workflow-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud projects list --filter="project_id:${PROJECT_ID}"
```

## Deployment Components

This infrastructure deploys the following Google Cloud resources:

### Core Services
- **Cloud Storage bucket** with versioning enabled for data lake storage
- **BigQuery dataset** with sample tables for analytics workloads
- **Dataform repository** for version-controlled SQL transformations
- **Dataform workspace** for collaborative development

### AI/ML Platform
- **Vertex AI runtime template** for standardized Colab Enterprise environments
- **IAM roles and permissions** for secure team collaboration
- **Sample data and transformations** for demonstration purposes

### Security & Governance
- Least privilege IAM roles for service accounts
- Proper resource-level permissions for team collaboration
- Data encryption at rest and in transit
- Audit logging for compliance requirements

## Configuration Options

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PROJECT_ID` | Google Cloud Project ID | *Required* |
| `REGION` | Primary deployment region | `us-central1` |
| `BUCKET_NAME` | Cloud Storage bucket name | `ds-workflow-${random}` |
| `DATASET_NAME` | BigQuery dataset name | `analytics_${random}` |
| `REPOSITORY_NAME` | Dataform repository name | `dataform-repo-${random}` |

### Terraform Variables

```hcl
# terraform.tfvars example
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
bucket_name = "custom-bucket-name"
dataset_name = "custom_dataset"
enable_apis = true
```

### Infrastructure Manager Input Values

```yaml
# input-values.yaml example
project_id: "your-project-id"
region: "us-central1"
bucket_location: "US"
dataset_location: "us-central1"
machine_type: "n1-standard-4"
disk_size_gb: 100
```

## Validation & Testing

After deployment, verify the infrastructure:

```bash
# Verify BigQuery dataset
bq ls --project_id=${PROJECT_ID}

# Check Cloud Storage bucket
gsutil ls gs://${BUCKET_NAME}

# List Dataform repositories
gcloud dataform repositories list --region=${REGION}

# Verify API enablement
gcloud services list --enabled --filter="name:(aiplatform|bigquery|dataform|storage)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete ds-workflow-deployment \
    --location=${REGION} \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gsutil ls gs://${BUCKET_NAME} 2>/dev/null || echo "Bucket successfully deleted"
```

## Customization

### Scaling Configuration

For production workloads, consider these modifications:

```hcl
# Terraform example for production scaling
variable "machine_type" {
  description = "Machine type for Colab Enterprise"
  default     = "n1-standard-8"  # Larger instance
}

variable "disk_size_gb" {
  description = "Persistent disk size in GB"
  default     = 500  # Larger storage
}

variable "enable_gpu" {
  description = "Enable GPU acceleration"
  default     = true
}
```

### Security Hardening

```hcl
# Additional security configurations
variable "vpc_connector" {
  description = "VPC connector for private networking"
  type        = string
  default     = null
}

variable "cmek_key_name" {
  description = "Customer-managed encryption key"
  type        = string
  default     = null
}
```

### Multi-Environment Setup

```bash
# Development environment
terraform workspace new development
terraform apply -var-file="environments/dev.tfvars"

# Production environment  
terraform workspace new production
terraform apply -var-file="environments/prod.tfvars"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable bigquery.googleapis.com
   gcloud services enable dataform.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:$(gcloud config get-value account)" \
       --role="roles/owner"
   ```

3. **Resource Naming Conflicts**
   ```bash
   # Generate unique suffix
   RANDOM_SUFFIX=$(openssl rand -hex 3)
   export BUCKET_NAME="ds-workflow-${RANDOM_SUFFIX}"
   ```

4. **Colab Enterprise Unavailable**
   - Verify Vertex AI API is enabled
   - Check regional availability for Colab Enterprise
   - Ensure proper IAM permissions for notebooks

### Logging and Monitoring

```bash
# View deployment logs
gcloud logging read "resource.type=global AND protoPayload.serviceName=compute.googleapis.com" \
    --limit=50 --format="table(timestamp,protoPayload.methodName,protoPayload.status)"

# Monitor resource usage
gcloud monitoring metrics list --filter="metric.type:compute"
```

## Performance Optimization

### Cost Optimization

1. **Use preemptible instances** for development workloads
2. **Enable BigQuery slot reservations** for predictable costs
3. **Implement Cloud Storage lifecycle policies** for data archival
4. **Use sustained use discounts** for long-running workloads

### Performance Tuning

1. **Configure BigQuery partitioning** for large datasets
2. **Use Cloud Storage regional buckets** for better performance
3. **Optimize Dataform transformations** with proper clustering
4. **Select appropriate machine types** based on workload requirements

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe documentation for solution architecture details
2. **Google Cloud Documentation**: 
   - [Vertex AI Workbench](https://cloud.google.com/vertex-ai/docs/workbench)
   - [Dataform Documentation](https://cloud.google.com/dataform/docs)
   - [BigQuery Best Practices](https://cloud.google.com/bigquery/docs/best-practices)
3. **Terraform Google Provider**: [Registry Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Infrastructure Manager**: [Google Cloud Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Follow Google Cloud security best practices
3. Update documentation for any new variables or outputs
4. Validate Terraform plans before applying
5. Ensure proper resource cleanup in destroy scripts

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's requirements and policies.