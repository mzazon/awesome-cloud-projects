# Infrastructure as Code for Secure Remote Development Environments with Cloud Workstations and Cloud Build

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Remote Development Environments with Cloud Workstations and Cloud Build".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Workstations Admin (`roles/workstations.admin`)
  - Cloud Build Editor (`roles/cloudbuild.builds.editor`)
  - Source Repository Administrator (`roles/source.admin`)
  - Artifact Registry Administrator (`roles/artifactregistry.admin`)
  - Compute Network Admin (`roles/compute.networkAdmin`)
  - Service Account Admin (`roles/iam.serviceAccountAdmin`)
- Terraform CLI installed (for Terraform deployment method)
- Estimated cost: $50-100/month for development team (varies by usage and instance types)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that provides state management and drift detection.

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/$(gcloud config get-value project)/locations/us-central1/deployments/secure-dev-environment \
    --service-account=$(gcloud config get-value account) \
    --git-source-repo="https://source.developers.google.com/p/$(gcloud config get-value project)/r/iac-config" \
    --git-source-directory="/" \
    --git-source-ref="main" \
    --input-values="project_id=$(gcloud config get-value project),region=us-central1"

# Monitor deployment status
gcloud infra-manager deployments describe projects/$(gcloud config get-value project)/locations/us-central1/deployments/secure-dev-environment
```

### Using Terraform

Terraform provides cross-cloud infrastructure as code with comprehensive Google Cloud Provider support.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=$(gcloud config get-value project)" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=$(gcloud config get-value project)" -var="region=us-central1"

# Verify deployment
terraform show
```

### Using Bash Scripts

Bash scripts provide step-by-step deployment using Google Cloud CLI commands with enhanced error handling and validation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration values
# The script will guide you through the entire deployment process
```

## Configuration

### Infrastructure Manager Variables

Edit the `infrastructure-manager/main.yaml` file to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Target deployment region (default: us-central1)
- `workstation_cluster_name`: Name for the workstation cluster
- `build_pool_name`: Name for the private Cloud Build pool
- `repository_name`: Name for the Cloud Source Repository

### Terraform Variables

Create a `terraform.tfvars` file or set variables via command line:

```hcl
project_id = "your-project-id"
region = "us-central1"
workstation_cluster_name = "secure-dev-cluster"
workstation_config_name = "secure-dev-config"
build_pool_name = "private-build-pool"
repository_name = "secure-app-repo"
machine_type = "e2-standard-4"
disk_size_gb = 100
idle_timeout = "7200s"
running_timeout = "43200s"
```

### Script Configuration

The bash scripts use environment variables for configuration. Set these before running:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export WORKSTATION_CLUSTER="secure-dev-cluster"
export WORKSTATION_CONFIG="secure-dev-config"
export BUILD_POOL="private-build-pool"
export REPO_NAME="secure-app-repo"
```

## Post-Deployment

### Access Your Development Environment

1. **Navigate to Cloud Workstations Console**:
   ```bash
   gcloud workstations list --region=$REGION
   ```

2. **Get workstation access URL**:
   ```bash
   gcloud workstations describe WORKSTATION_NAME \
       --cluster=CLUSTER_NAME \
       --config=CONFIG_NAME \
       --region=$REGION \
       --format="value(host)"
   ```

3. **Access via browser**: Use the provided HTTPS URL to access your secure development environment

### Configure Developer Access

Add developers to the appropriate IAM roles:

```bash
# Grant workstation access to developers
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:developer@yourdomain.com" \
    --role="roles/workstations.user"

# Grant source repository access
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="user:developer@yourdomain.com" \
    --role="roles/source.developer"
```

### Test the CI/CD Pipeline

1. **Clone the repository in your workstation**:
   ```bash
   git clone https://source.developers.google.com/p/PROJECT_ID/r/REPO_NAME
   ```

2. **Make a code change and push**:
   ```bash
   echo "# Updated README" >> README.md
   git add README.md
   git commit -m "Test CI/CD pipeline"
   git push origin main
   ```

3. **Monitor the build**:
   ```bash
   gcloud builds list --limit=5
   ```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/$(gcloud config get-value project)/locations/us-central1/deployments/secure-dev-environment

# Confirm deletion
gcloud infra-manager deployments list
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=$(gcloud config get-value project)" -var="region=us-central1"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# Script will remove resources in reverse order of creation
```

## Security Considerations

### Network Security

- All workstations operate within a private VPC with no external IP addresses
- Private Cloud Build pools ensure builds cannot access external networks
- VPC Service Controls can be applied for additional security perimeter

### Access Control

- IAM policies enforce least privilege access to workstations and repositories
- Service accounts have minimal required permissions
- Audit logging is enabled for all workstation and build activities

### Data Protection

- Source code never leaves Google Cloud's secure infrastructure
- Container images are stored in private Artifact Registry with vulnerability scanning
- All communications use encrypted channels (HTTPS/TLS)

## Troubleshooting

### Common Issues

1. **Workstation cluster creation fails**:
   ```bash
   # Check VPC and subnet configuration
   gcloud compute networks describe dev-vpc
   gcloud compute networks subnets describe dev-subnet --region=$REGION
   ```

2. **Build trigger not firing**:
   ```bash
   # Verify trigger configuration
   gcloud builds triggers list
   # Check repository permissions
   gcloud source repos get-iam-policy REPO_NAME
   ```

3. **Workstation access denied**:
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy $PROJECT_ID --filter="bindings.members:user:YOUR_EMAIL"
   ```

### Monitoring and Logging

- **Cloud Logging**: Monitor workstation and build activities
- **Cloud Monitoring**: Set up alerts for resource utilization
- **Audit Logs**: Review access patterns and security events

## Cost Optimization

### Workstation Cost Management

- **Idle Timeout**: Automatically stop workstations when inactive (configured to 2 hours)
- **Running Timeout**: Maximum session duration (configured to 12 hours)
- **Machine Type**: Use appropriately sized instances for your team's needs

### Build Pool Optimization

- **On-Demand Scaling**: Private build pools scale based on demand
- **Regional Deployment**: Deploy in regions closest to your team
- **Resource Monitoring**: Monitor build pool utilization and adjust size accordingly

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe in the parent directory
2. **Google Cloud Documentation**: 
   - [Cloud Workstations Documentation](https://cloud.google.com/workstations/docs)
   - [Cloud Build Documentation](https://cloud.google.com/build/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
3. **Terraform Google Provider**: [Official Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Advanced Configuration

### Custom Workstation Images

To use custom container images for workstations:

1. **Build custom image**:
   ```bash
   # Create Dockerfile with your development tools
   gcloud builds submit --tag gcr.io/$PROJECT_ID/custom-workstation:latest
   ```

2. **Update workstation configuration**:
   ```bash
   gcloud workstations configs update $WORKSTATION_CONFIG \
       --cluster=$WORKSTATION_CLUSTER \
       --region=$REGION \
       --container-image="gcr.io/$PROJECT_ID/custom-workstation:latest"
   ```

### Multi-Environment Setup

Configure separate environments (dev/staging/prod):

```bash
# Deploy with environment-specific variables
export ENVIRONMENT="staging"
terraform workspace new $ENVIRONMENT
terraform apply -var="environment=$ENVIRONMENT"
```

This infrastructure provides a secure, scalable foundation for remote development teams while maintaining enterprise-grade security and compliance capabilities.