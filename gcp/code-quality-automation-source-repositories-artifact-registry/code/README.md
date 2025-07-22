# Infrastructure as Code for Code Quality Automation with Cloud Source Repositories and Artifact Registry

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Code Quality Automation with Cloud Source Repositories and Artifact Registry".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Owner or Editor permissions on the target project
- Git installed for source repository operations
- Docker installed for container image operations
- Appropriate IAM permissions for:
  - Cloud Source Repositories
  - Artifact Registry
  - Cloud Build
  - Container Analysis
  - Cloud Storage

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native Infrastructure as Code service that uses Terraform configurations with enhanced Google Cloud integration.

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create code-quality-deployment \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/code-quality-repo" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe code-quality-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a complete deployment workflow that mirrors the recipe steps with intelligent automation and error handling.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure with automated configuration
./scripts/deploy.sh

# Follow the interactive prompts to configure:
# - Project ID and region
# - Repository and registry names
# - Build trigger settings
# - Security scanning options
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `variables.yaml` file or pass variables during deployment:

```yaml
project_id:
  description: "Google Cloud Project ID"
  type: string
  required: true

region:
  description: "Google Cloud region for resources"
  type: string
  default: "us-central1"

repository_name:
  description: "Cloud Source Repository name"
  type: string
  default: "quality-demo-repo"

registry_name:
  description: "Artifact Registry repository name"
  type: string
  default: "quality-artifacts"

enable_vulnerability_scanning:
  description: "Enable container vulnerability scanning"
  type: bool
  default: true
```

### Terraform Variables

Customize deployment by modifying `terraform.tfvars` or using command-line variables:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# Repository configuration
repository_name = "quality-demo-repo"
repository_description = "Repository for code quality automation demo"

# Artifact Registry configuration
registry_name = "quality-artifacts"
registry_description = "Registry for quality-validated artifacts"
registry_format = "DOCKER"

# Build configuration
build_trigger_name = "quality-pipeline-trigger"
build_filename = "cloudbuild.yaml"

# Security settings
enable_vulnerability_scanning = true
enable_binary_authorization = true

# Monitoring settings
enable_monitoring = true
enable_alerting = true

# Tags for resource organization
labels = {
  environment = "demo"
  purpose = "code-quality"
  team = "devops"
}
```

### Bash Script Configuration

The deployment script supports environment variables for configuration:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Optional customization variables
export REPO_NAME="custom-repo-name"
export REGISTRY_NAME="custom-registry-name"
export BUILD_TRIGGER_NAME="custom-trigger-name"
export ENABLE_MONITORING="true"
export ENABLE_SECURITY_SCANNING="true"

# Run deployment with custom configuration
./scripts/deploy.sh
```

## Infrastructure Components

This Infrastructure as Code deploys the following Google Cloud resources:

### Core Services
- **Cloud Source Repositories**: Git repository with intelligent triggers
- **Artifact Registry**: Docker and Python package repositories with security scanning
- **Cloud Build**: Automated CI/CD pipeline with quality gates
- **Cloud Storage**: Build artifacts and logs storage

### Security and Monitoring
- **Container Analysis API**: Vulnerability scanning and compliance checking
- **Cloud Monitoring**: Quality metrics and performance monitoring
- **Cloud Logging**: Centralized logging for build and security events
- **IAM Roles and Policies**: Least-privilege access controls

### Build Pipeline Components
- **Build Triggers**: Automated triggers for source code changes
- **Custom Build Steps**: Multi-stage quality validation pipeline
- **Security Scanning**: Integrated vulnerability assessment
- **Artifact Management**: Automated artifact versioning and storage

## Validation and Testing

After deployment, validate the infrastructure with these commands:

### Verify Core Services

```bash
# Check Cloud Source Repository
gcloud source repos list --format="table(name,url)"

# Verify Artifact Registry
gcloud artifacts repositories list \
    --format="table(name,format,location,createTime)"

# Check Build Triggers
gcloud builds triggers list \
    --format="table(name,status,github.owner,github.name)"
```

### Test Quality Pipeline

```bash
# Clone repository and test pipeline
gcloud source repos clone ${REPO_NAME} --project=${PROJECT_ID}
cd ${REPO_NAME}

# Create test commit to trigger pipeline
echo "# Pipeline Test" > test-file.md
git add test-file.md
git commit -m "Test: Validate automated quality pipeline"
git push origin main

# Monitor build execution
gcloud builds list --ongoing --format="table(id,status,createTime)"
```

### Verify Security Scanning

```bash
# Check container vulnerability scanning
gcloud container images list-tags \
    ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REGISTRY_NAME}/quality-app \
    --format="table(digest,tags,timestamp)"

# Get vulnerability scan results
gcloud container images describe \
    ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REGISTRY_NAME}/quality-app:latest \
    --show-package-vulnerability
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete code-quality-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run automated cleanup script
./scripts/destroy.sh

# Follow prompts for:
# - Resource deletion confirmation
# - Project cleanup options
# - Storage and artifact removal
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**:
   ```bash
   # Ensure proper IAM permissions
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/owner"
   ```

2. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable sourcerepo.googleapis.com \
       artifactregistry.googleapis.com \
       cloudbuild.googleapis.com \
       containeranalysis.googleapis.com
   ```

3. **Build Failures**:
   ```bash
   # Check build logs
   BUILD_ID=$(gcloud builds list --limit=1 --format="value(id)")
   gcloud builds log ${BUILD_ID}
   ```

4. **Repository Access Issues**:
   ```bash
   # Configure git credentials
   gcloud source repos clone ${REPO_NAME} --project=${PROJECT_ID}
   cd ${REPO_NAME}
   git config credential.helper gcloud.sh
   ```

### Performance Optimization

1. **Build Performance**:
   - Use Cloud Build high-CPU machine types for faster builds
   - Implement intelligent caching for dependencies
   - Optimize Docker layer caching

2. **Cost Optimization**:
   - Use preemptible build machines when possible
   - Implement lifecycle policies for artifact retention
   - Monitor storage usage and cleanup old artifacts

3. **Security Hardening**:
   - Enable Binary Authorization for production deployments
   - Configure custom vulnerability scanning policies
   - Implement least-privilege IAM roles

## Advanced Configuration

### Custom Quality Gates

Extend the pipeline with additional quality gates by modifying the Cloud Build configuration:

```yaml
# Add custom quality steps to cloudbuild.yaml
steps:
  # Custom code complexity analysis
  - name: 'python:3.11-slim'
    entrypoint: 'bash'
    args:
    - '-c'
    - |
      pip install radon
      radon cc src/ --min B
      radon mi src/ --min B

  # Performance testing
  - name: 'python:3.11-slim'
    entrypoint: 'bash'
    args:
    - '-c'
    - |
      pip install locust
      locust --headless -u 10 -r 2 -t 30s --host http://localhost:8080
```

### Multi-Environment Support

Configure separate environments for development, staging, and production:

```bash
# Development environment
terraform workspace new development
terraform apply -var="environment=development" -var="enable_monitoring=false"

# Staging environment
terraform workspace new staging
terraform apply -var="environment=staging" -var="enable_monitoring=true"

# Production environment
terraform workspace new production
terraform apply -var="environment=production" -var="enable_monitoring=true" -var="enable_binary_authorization=true"
```

## Integration Examples

### CI/CD Integration

```bash
# GitHub Actions integration
name: Deploy to GCP
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - uses: google-github-actions/setup-gcloud@v0
    - run: |
        cd terraform/
        terraform init
        terraform apply -auto-approve
```

### Monitoring Integration

```bash
# Set up custom monitoring dashboards
gcloud monitoring dashboards create --config-from-file=monitoring-dashboard.json

# Configure alerting policies
gcloud alpha monitoring policies create --policy-from-file=alerting-policy.yaml
```

## Support and Documentation

- **Recipe Documentation**: See the main recipe file for detailed implementation guidance
- **Google Cloud Documentation**: [Cloud Source Repositories](https://cloud.google.com/source-repositories/docs), [Artifact Registry](https://cloud.google.com/artifact-registry/docs), [Cloud Build](https://cloud.google.com/build/docs)
- **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Infrastructure Manager**: [Documentation](https://cloud.google.com/infrastructure-manager/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud's official documentation.

## Security Considerations

- All resources are deployed with least-privilege IAM permissions
- Container images are automatically scanned for vulnerabilities
- Build processes run in isolated environments
- Secrets and credentials are managed through Google Secret Manager
- Network security is enforced through VPC configurations
- Audit logging is enabled for all resource access

## Cost Estimation

Estimated monthly costs for this infrastructure (varies by usage):

- Cloud Source Repositories: $1-5 (based on repository size)
- Artifact Registry: $5-20 (based on storage and bandwidth)
- Cloud Build: $10-50 (based on build frequency and duration)
- Cloud Storage: $1-10 (based on artifact storage)
- Container Analysis: $0.26 per image scan
- Monitoring and Logging: $5-15 (based on log volume)

**Total estimated monthly cost: $22-100** (excluding data transfer costs)

Use the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for accurate cost estimates based on your specific usage patterns.