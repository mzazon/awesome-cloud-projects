# Infrastructure as Code for Automated Code Refactoring with Gemini Code Assist and Source Repositories

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Code Refactoring with Gemini Code Assist and Source Repositories".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 480.0.0 or later)
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Source Repositories (roles/source.admin)
  - Cloud Build (roles/cloudbuild.builds.editor) 
  - IAM Service Accounts (roles/iam.serviceAccountAdmin)
  - Gemini Code Assist (roles/cloudaicompanion.user)
- Terraform installed (for Terraform deployment option)
- Gemini Code Assist Standard or Enterprise license

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="code-refactoring-demo"

# Deploy the infrastructure
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --source-yaml=infrastructure-manager/main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Apply the configuration
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh
```

## What Gets Deployed

This infrastructure code provisions:

1. **Google Cloud Source Repository**
   - Git repository for code storage and version control
   - Integration with Cloud Build triggers

2. **Cloud Build Trigger**
   - Automated trigger on main branch commits
   - Executes refactoring pipeline on code changes

3. **Service Account**
   - Dedicated service account for build operations
   - Configured with least privilege permissions:
     - Source Repository writer access
     - Gemini Code Assist user permissions
     - Cloud Build editor access

4. **IAM Bindings**
   - Proper role assignments for secure operations
   - Service account permissions for automation

5. **Sample Application**
   - Python application with refactoring opportunities
   - Cloud Build configuration for AI-powered analysis
   - Refactoring analysis script

## Configuration Options

### Infrastructure Manager Variables

```yaml
# Available input variables for Infrastructure Manager
project_id: "your-gcp-project-id"
region: "us-central1"
repository_name: "automated-refactoring-demo" 
service_account_prefix: "refactor-sa"
build_trigger_name: "refactor-trigger"
```

### Terraform Variables

```hcl
# terraform/variables.tf contains these customizable options:
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "repository_name" {
  description = "Name of the source repository"
  type        = string
  default     = "automated-refactoring-demo"
}

variable "enable_apis" {
  description = "Enable required APIs"
  type        = bool
  default     = true
}
```

## Outputs

After successful deployment, you'll receive:

- **Repository Clone URL**: Git URL for cloning the source repository
- **Repository Web URL**: Browser URL for repository management
- **Build Trigger ID**: Identifier for the Cloud Build trigger
- **Service Account Email**: Email of the created service account
- **Project Information**: Deployment project and region details

## Testing the Deployment

After deployment, test the automated refactoring workflow:

1. **Clone the repository**:
   ```bash
   gcloud source repos clone automated-refactoring-demo
   cd automated-refactoring-demo
   ```

2. **Add sample code** (if not already present):
   ```bash
   # The deployment includes sample Python code with refactoring opportunities
   ls -la  # Should show main.py, cloudbuild.yaml, and other files
   ```

3. **Trigger the refactoring pipeline**:
   ```bash
   # Make a small change and commit
   echo "# Updated $(date)" >> README.md
   git add README.md
   git commit -m "Test automated refactoring trigger"
   git push origin main
   ```

4. **Monitor the build**:
   ```bash
   # Watch the build execution
   gcloud builds list --limit=5
   ```

5. **Check for refactoring branches**:
   ```bash
   # Look for automatically created refactor branches
   git fetch origin
   git branch -r | grep refactor
   ```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

If needed, manually verify cleanup:

```bash
# Check for remaining resources
gcloud source repos list
gcloud builds triggers list
gcloud iam service-accounts list --filter="email~refactor"
```

## Cost Considerations

This infrastructure uses the following billable services:

- **Source Repositories**: $1/month per active repository + bandwidth
- **Cloud Build**: $0.003/build minute after free tier (120 minutes/day)
- **Gemini Code Assist**: Subscription-based pricing ($19/user/month for Standard)
- **Storage**: Minimal storage costs for repository and build artifacts

Estimated monthly cost for moderate usage: $25-50 (excluding Gemini subscription)

## Security Features

The infrastructure implements security best practices:

- **Least Privilege IAM**: Service account with minimal required permissions
- **No Hardcoded Secrets**: All authentication through IAM service accounts
- **Audit Logging**: All build activities logged in Cloud Logging
- **Source Control**: Full version control and change tracking
- **Access Controls**: Repository access managed through Google Cloud IAM

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**:
   ```bash
   # Enable required APIs
   gcloud services enable sourcerepo.googleapis.com cloudbuild.googleapis.com
   ```

2. **Permission Denied Error**:
   ```bash
   # Verify your account has necessary permissions
   gcloud auth list
   gcloud projects get-iam-policy $PROJECT_ID
   ```

3. **Build Trigger Not Firing**:
   ```bash
   # Check trigger configuration
   gcloud builds triggers list
   gcloud builds triggers describe TRIGGER_NAME
   ```

4. **Gemini Code Assist Access Issues**:
   - Verify Gemini Code Assist subscription is active
   - Check IAM permissions for cloudaicompanion.user role
   - Ensure project has API quota for AI services

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled | grep -E "(sourcerepo|cloudbuild|cloudaicompanion)"

# View recent builds
gcloud builds list --limit=10

# Check service account permissions
gcloud projects get-iam-policy $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.members:*refactor*"

# View build logs
gcloud builds log BUILD_ID
```

## Customization

### Adapting for Your Organization

1. **Repository Naming**: Update repository names to match your conventions
2. **Region Selection**: Choose regions closest to your development team
3. **Service Account Names**: Align with your naming standards
4. **Additional Languages**: Extend the analysis script for Java, Go, etc.
5. **Integration**: Connect with existing CI/CD pipelines or code review tools

### Extending the Solution

Consider these enhancements:

- **Slack/Teams Integration**: Add notifications for refactoring results
- **Multiple Repository Support**: Scale to handle multiple repositories
- **Quality Gates**: Add automated quality thresholds
- **Performance Testing**: Include performance impact analysis
- **Custom Rules**: Implement organization-specific refactoring rules

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check [Google Cloud Source Repositories documentation](https://cloud.google.com/source-repositories/docs)
3. Consult [Cloud Build documentation](https://cloud.google.com/build/docs)
4. Reference [Gemini Code Assist documentation](https://cloud.google.com/gemini/docs/codeassist)

For infrastructure-specific issues, verify:
- IAM permissions are correctly assigned
- Required APIs are enabled in your project
- Billing is enabled for your Google Cloud project
- Gemini Code Assist subscription is active and properly configured