# Infrastructure as Code for Building Cloud-Native Development Environments with Firebase Studio and Gemini Code Assist

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Cloud-Native Development Environments with Firebase Studio and Gemini Code Assist".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Terraform installed (version 1.5 or later)
- Firebase CLI installed (`npm install -g firebase-tools`)
- Docker installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Firebase project management
  - Cloud Source Repositories
  - Artifact Registry
  - Cloud Build
  - Cloud Run
  - IAM service account management
  - AI Platform services

## Quick Start

### Using Infrastructure Manager (Google Cloud)

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Create a deployment using Infrastructure Manager
gcloud infra-manager deployments create firebase-studio-dev \
    --location=us-central1 \
    --service-account=$(gcloud config get-value account) \
    --git-source-repo=https://github.com/your-org/your-repo.git \
    --git-source-directory=infrastructure-manager/ \
    --git-source-ref=main \
    --input-values=project_id=$(gcloud config get-value project)

# Monitor deployment progress
gcloud infra-manager deployments describe firebase-studio-dev \
    --location=us-central1
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud projects list --filter="name:firebase-studio-dev-*"
```

## Architecture Overview

This IaC deployment creates:

- **Firebase Project**: Central project for Firebase Studio integration
- **Cloud Source Repositories**: Git repositories for version control
- **Artifact Registry**: Container image storage with security scanning
- **Cloud Build**: Automated CI/CD pipelines
- **Cloud Run**: Serverless application hosting
- **IAM Resources**: Service accounts and permissions for AI services
- **AI Platform APIs**: Gemini Code Assist and related services

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Google Cloud region"
    type: string
    default: "us-central1"
  firebase_project_name:
    description: "Firebase project display name"
    type: string
    default: "AI Development Environment"
```

### Terraform Variables

Edit `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
# terraform.tfvars
project_id = "your-project-id"
region = "us-central1"
firebase_project_name = "AI Development Environment"
repository_name = "ai-app-repo"
registry_name = "ai-app-registry"
```

### Script Variables

Edit environment variables in `scripts/deploy.sh`:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FIREBASE_PROJECT_NAME="AI Development Environment"
```

## Post-Deployment Steps

After successful deployment, complete these manual steps:

1. **Access Firebase Studio**:
   ```bash
   echo "Navigate to: https://studio.firebase.google.com"
   echo "Select project: $(gcloud config get-value project)"
   ```

2. **Create Firebase Studio Workspace**:
   - Sign in to Firebase Studio
   - Create new workspace
   - Choose "Full-stack AI app" template
   - Connect to your Cloud Source Repository

3. **Configure Gemini Code Assist**:
   - Enable AI assistance in Firebase Studio
   - Configure project-specific AI settings
   - Test code completion and suggestions

4. **Verify Cloud Build Integration**:
   ```bash
   # Check build triggers
   gcloud builds triggers list
   
   # Test a manual build
   gcloud builds submit --config=cloudbuild.yaml
   ```

## Validation

### Verify Firebase Project
```bash
# List Firebase projects
firebase projects:list

# Check project configuration
gcloud config get-value project
```

### Verify Source Repositories
```bash
# List repositories
gcloud source repos list

# Test repository access
gcloud source repos clone [REPO_NAME] --project=[PROJECT_ID]
```

### Verify Artifact Registry
```bash
# List repositories
gcloud artifacts repositories list

# Test Docker authentication
gcloud auth configure-docker us-central1-docker.pkg.dev
```

### Verify AI Services
```bash
# Check enabled APIs
gcloud services list --enabled --filter="name:aiplatform.googleapis.com"

# Test service account permissions
gcloud iam service-accounts list --filter="email:*gemini-code-assist*"
```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete the deployment
gcloud infra-manager deployments delete firebase-studio-dev \
    --location=us-central1 \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Manual cleanup for Firebase Studio
echo "Manual cleanup required:"
echo "1. Visit https://studio.firebase.google.com"
echo "2. Delete associated workspaces"
echo "3. Visit https://console.firebase.google.com"
echo "4. Delete Firebase project if desired"
```

## Security Considerations

This deployment implements security best practices:

- **IAM Least Privilege**: Service accounts have minimal required permissions
- **Artifact Registry**: Container image vulnerability scanning enabled
- **Cloud Build**: Secure build environments with controlled access
- **API Security**: AI services configured with appropriate access controls
- **Network Security**: Default VPC security rules applied

## Cost Estimation

Estimated monthly costs (varies by usage):

- **Firebase Studio**: Free during preview period
- **Cloud Source Repositories**: Free for small repositories
- **Artifact Registry**: $0.10 per GB stored
- **Cloud Build**: $0.003 per build minute
- **Cloud Run**: Pay-per-use pricing
- **AI Platform**: Variable based on API usage

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services list --enabled
   ```

2. **Permission Denied**: Verify IAM permissions
   ```bash
   gcloud projects get-iam-policy $(gcloud config get-value project)
   ```

3. **Firebase Studio Access**: Ensure project is correctly configured
   ```bash
   firebase projects:list
   firebase use --add
   ```

4. **Build Failures**: Check Cloud Build logs
   ```bash
   gcloud builds log [BUILD_ID]
   ```

### Support Resources

- [Firebase Studio Documentation](https://firebase.google.com/docs/studio)
- [Gemini Code Assist Documentation](https://developers.google.com/gemini-code-assist/docs)
- [Google Cloud Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
- [Cloud Source Repositories](https://cloud.google.com/source-repositories/docs)
- [Artifact Registry](https://cloud.google.com/artifact-registry/docs)

## Customization

### Adding Custom Build Steps

Edit `cloudbuild.yaml` to add custom build steps:

```yaml
steps:
  # Add custom step
  - name: 'gcr.io/cloud-builders/npm'
    args: ['run', 'custom-script']
```

### Modifying AI Service Configuration

Update IAM permissions in the Terraform configuration:

```hcl
resource "google_project_iam_member" "ai_permissions" {
  project = var.project_id
  role    = "roles/aiplatform.admin"
  member  = "serviceAccount:${google_service_account.gemini_assist.email}"
}
```

### Environment-Specific Configurations

Create multiple terraform workspaces for different environments:

```bash
# Create development workspace
terraform workspace new development

# Create production workspace
terraform workspace new production

# Switch between workspaces
terraform workspace select development
```

## Integration with Firebase Studio

This infrastructure provides the foundation for Firebase Studio integration:

1. **Automated Repository Setup**: Source repositories are automatically configured
2. **Container Registry**: Artifact Registry provides secure image storage
3. **CI/CD Pipeline**: Cloud Build enables automated deployments
4. **AI Services**: Gemini Code Assist APIs are enabled and configured
5. **Project Integration**: Firebase project is ready for Studio workspace creation

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for context
2. Review Google Cloud documentation for specific services
3. Verify all prerequisites are met
4. Check IAM permissions and API enablement
5. Review deployment logs for specific error messages

## Version History

- **v1.0**: Initial infrastructure code generation
- Compatible with recipe version 1.0
- Supports Infrastructure Manager, Terraform, and Bash deployments