# Infrastructure as Code for AI-Powered App Development with Firebase Studio and Gemini

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI-Powered App Development with Firebase Studio and Gemini".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Firebase CLI installed and authenticated
- GitHub account for App Hosting repository integration
- Modern web browser for Firebase Studio access
- Appropriate GCP permissions for resource creation:
  - Firebase Admin
  - Project Editor or Owner
  - Secret Manager Admin
  - Cloud Build Editor
  - Cloud Run Admin

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/ai-app-deployment \
    --service-account PROJECT_ID@PROJECT_ID.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="main.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/ai-app-deployment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

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

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud projects describe $PROJECT_ID
gcloud firestore databases list --project=$PROJECT_ID
```

## Architecture Overview

This infrastructure creates:

- **Firebase Project**: Complete Firebase project with required APIs enabled
- **Firestore Database**: NoSQL document database in native mode
- **Firebase Authentication**: Multi-provider authentication service
- **Secret Manager**: Secure storage for Gemini API keys
- **App Hosting**: Automated deployment pipeline with GitHub integration
- **Cloud Build**: CI/CD automation for continuous deployment
- **IAM Roles**: Least-privilege service accounts and permissions

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:

```yaml
project_id: "your-project-id"
region: "us-central1"
app_name: "ai-task-manager"
enable_apis:
  - firebase.googleapis.com
  - firestore.googleapis.com
  - cloudbuild.googleapis.com
  - run.googleapis.com
  - secretmanager.googleapis.com
```

### Terraform Variables

Customize deployment in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
app_name   = "ai-task-manager"

# Firebase configuration
firestore_location_id = "us-central"
auth_providers = [
  "google.com",
  "password",
  "github.com"
]

# App Hosting configuration
github_repository = "your-username/your-repo"
build_config = {
  runtime     = "nodejs18"
  entry_point = "npm start"
}
```

### Script Variables

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export APP_NAME="ai-task-manager"
export GITHUB_REPO="your-username/your-repo"
export GEMINI_API_KEY="your-gemini-api-key"
```

## Post-Deployment Steps

After infrastructure deployment, complete these manual steps:

1. **Access Firebase Studio**:
   ```bash
   echo "🌐 Firebase Studio: https://studio.firebase.google.com"
   echo "📋 Select project: $PROJECT_ID"
   ```

2. **Configure Authentication Providers**:
   - Navigate to Firebase Console > Authentication > Sign-in method
   - Enable desired providers (Google, Email/Password, GitHub)
   - Configure OAuth settings for external providers

3. **Connect GitHub Repository**:
   - Access Firebase Console > App Hosting
   - Connect your GitHub repository
   - Configure build settings and environment variables

4. **Set up Gemini API Integration**:
   ```bash
   # Update Secret Manager with your Gemini API key
   echo "your-actual-gemini-api-key" | \
       gcloud secrets versions add gemini-api-key --data-file=-
   ```

5. **Configure Firestore Security Rules**:
   - Review and update security rules in Firebase Console
   - Test rules with Firebase Emulator Suite

## Cleanup

### Using Infrastructure Manager (GCP)

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/ai-app-deployment \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list --location=REGION
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud projects list --filter="projectId:$PROJECT_ID"

# Optionally delete the entire project
gcloud projects delete $PROJECT_ID --quiet
```

## Development Workflow

1. **Local Development**:
   - Use Firebase Emulator Suite for local testing
   - Access Firebase Studio for AI-assisted development
   - Leverage Gemini integration for code generation

2. **Version Control**:
   - Connect GitHub repository for App Hosting
   - Configure automated deployments on push
   - Use Firebase preview channels for staging

3. **Production Deployment**:
   - Deploy through App Hosting automated pipeline
   - Monitor with Firebase Performance Monitoring
   - Scale automatically with Cloud Run backend

## Monitoring and Observability

Access monitoring dashboards:

```bash
# Firebase Console
echo "📊 Firebase Console: https://console.firebase.google.com/project/$PROJECT_ID"

# Cloud Console
echo "🔍 Cloud Console: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"

# App Hosting metrics
echo "🚀 App Hosting: https://console.firebase.google.com/project/$PROJECT_ID/hosting"
```

## Cost Optimization

- **Firebase Free Tier**: Most development activities use free tier
- **Firestore**: Pay-per-operation pricing with generous free quotas
- **App Hosting**: Based on Cloud Run usage with automatic scaling
- **Cloud Build**: 120 free build minutes per day
- **Secret Manager**: Minimal cost for API key storage

Estimated monthly cost for development: $2-5 USD

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**:
   ```bash
   # Enable required APIs
   gcloud services enable firebase.googleapis.com firestore.googleapis.com
   ```

2. **Authentication Issues**:
   ```bash
   # Re-authenticate Firebase CLI
   firebase logout
   firebase login --no-localhost
   ```

3. **Project Creation Failures**:
   ```bash
   # Check project quotas and billing
   gcloud alpha billing projects describe $PROJECT_ID
   ```

4. **App Hosting Connection Issues**:
   - Verify GitHub repository access
   - Check OAuth app permissions
   - Review build configuration

### Debug Commands

```bash
# Check project status
gcloud projects describe $PROJECT_ID

# Verify enabled services
gcloud services list --enabled --project=$PROJECT_ID

# Check Firestore status
gcloud firestore databases list --project=$PROJECT_ID

# View recent operations
gcloud firestore operations list --project=$PROJECT_ID

# Check Secret Manager
gcloud secrets list --project=$PROJECT_ID
```

## Security Considerations

- **IAM**: Minimal required permissions configured
- **Firestore Rules**: User-based data access controls
- **Secret Manager**: Secure API key storage with encryption
- **App Hosting**: Automatic SSL/TLS certificates
- **Authentication**: Multi-provider security with rate limiting

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud and Firebase documentation
3. Verify CLI tool versions and authentication
4. Review Firebase Studio troubleshooting guides
5. Check GitHub repository connection and permissions

## Additional Resources

- [Firebase Studio Documentation](https://firebase.google.com/docs/studio)
- [Firebase App Hosting Guide](https://firebase.google.com/docs/app-hosting)
- [Google Cloud Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Firebase CLI Reference](https://firebase.google.com/docs/cli)
- [Gemini API Documentation](https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference)