# Infrastructure as Code for Automated Accessibility Compliance with Document AI and Build

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Accessibility Compliance with Document AI and Build".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Project with billing enabled and Owner role permissions
- Basic understanding of CI/CD pipelines and accessibility concepts
- Existing source code repository (GitHub, GitLab, or Cloud Source Repositories)
- Python 3.9+ for accessibility analysis scripts
- Estimated cost: $15-25 for Document AI processing, Cloud Build minutes, and Security Command Center standard tier

## Architecture Overview

This solution implements automated WCAG 2.1 accessibility compliance testing by:

- **Document AI** for intelligent content analysis and structure extraction
- **Cloud Build** for CI/CD pipeline integration and automated testing
- **Security Command Center** for centralized compliance monitoring and alerting
- **Cloud Functions** for automated notification processing
- **Cloud Storage** for compliance report storage and artifact management
- **Pub/Sub** for event-driven compliance notifications

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create accessibility-compliance \
    --location=us-central1 \
    --config=main.yaml \
    --input-values=project_id=$(gcloud config get-value project),region=us-central1

# Monitor deployment status
gcloud infra-manager deployments describe accessibility-compliance \
    --location=us-central1

# Get deployment outputs
gcloud infra-manager deployments describe accessibility-compliance \
    --location=us-central1 \
    --format="value(outputs)"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned infrastructure changes
terraform plan -var="project_id=$(gcloud config get-value project)" \
               -var="region=us-central1"

# Deploy infrastructure
terraform apply -var="project_id=$(gcloud config get-value project)" \
                -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set execute permissions
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy complete infrastructure
./scripts/deploy.sh

# Follow the interactive prompts to configure:
# - Project ID and region
# - Repository information for build triggers
# - Notification preferences
```

## Configuration Options

### Infrastructure Manager Variables

Customize the deployment by modifying values in `infrastructure-manager/main.yaml`:

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `repository_name`: Source repository name for build triggers
- `repository_owner`: Repository owner/organization
- `enable_notifications`: Enable compliance notification system

### Terraform Variables

Configure deployment using `terraform/variables.tf` or command-line variables:

```bash
# Example with custom configuration
terraform apply \
    -var="project_id=my-project-id" \
    -var="region=us-east1" \
    -var="repository_name=my-web-app" \
    -var="repository_owner=my-github-org" \
    -var="enable_manual_triggers=true"
```

### Script Configuration

The bash scripts support environment variable configuration:

```bash
# Set custom configuration before deployment
export PROJECT_ID="my-accessibility-project"
export REGION="us-east1"
export REPOSITORY_NAME="my-app-repository"
export REPOSITORY_OWNER="my-github-username"

# Run deployment with custom settings
./scripts/deploy.sh
```

## Post-Deployment Setup

### 1. Configure Repository Integration

After deployment, connect your source repository to the build triggers:

```bash
# For GitHub repositories
gcloud builds triggers create github \
    --repo-name="your-repository-name" \
    --repo-owner="your-github-username" \
    --branch-pattern="^main$" \
    --build-config="cloudbuild.yaml"

# For Cloud Source Repositories
gcloud builds triggers create cloud-source-repositories \
    --repo="your-repo-name" \
    --branch-pattern="^main$" \
    --build-config="cloudbuild.yaml"
```

### 2. Upload Accessibility Analysis Scripts

The deployment creates the infrastructure, but you'll need to upload the analysis scripts:

```bash
# Upload accessibility analyzer to your repository
# (This script is generated during the manual recipe process)
cp accessibility_analyzer.py your-repository/
cp cloudbuild.yaml your-repository/

# Commit and push to trigger initial build
git add . && git commit -m "Add accessibility compliance testing"
git push origin main
```

### 3. Configure Notification Endpoints

Update the Cloud Function to integrate with your preferred notification system:

```bash
# Get the function name from outputs
FUNCTION_NAME=$(terraform output -raw compliance_function_name)

# Update function with your notification preferences
gcloud functions deploy $FUNCTION_NAME \
    --update-env-vars SLACK_WEBHOOK_URL=your-slack-webhook,EMAIL_RECIPIENTS=team@company.com
```

## Validation & Testing

### 1. Verify Infrastructure Deployment

```bash
# Check deployed resources
gcloud services list --enabled --filter="name:documentai OR name:cloudbuild OR name:securitycenter"

# Verify Document AI processor
gcloud documentai processors list --location=us-central1

# Check Cloud Storage bucket
gsutil ls -p $(gcloud config get-value project) | grep accessibility-compliance

# Verify Security Command Center source
gcloud scc sources list --organization=$(gcloud organizations list --format="value(name)" | head -1)
```

### 2. Test Accessibility Analysis

```bash
# Create sample HTML file with accessibility violations
cat > test-violations.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Test Page</title></head>
<body>
    <h1>Test Page</h1>
    <img src="test.png">
    <h4>Skipped Heading Level</h4>
    <input type="text" placeholder="Unlabeled input">
</body>
</html>
EOF

# Trigger manual build for testing
gcloud builds submit --config=cloudbuild.yaml .

# Check compliance reports
gsutil ls gs://accessibility-compliance-*/reports/
```

### 3. Validate Security Command Center Integration

```bash
# List accessibility compliance findings
ORG_ID=$(gcloud organizations list --format="value(name)" | head -1 | cut -d'/' -f2)
gcloud scc findings list \
    --organization=$ORG_ID \
    --filter="category=\"ACCESSIBILITY_COMPLIANCE\"" \
    --format="table(name,category,state,sourceProperties.violations_count)"
```

## Monitoring and Maintenance

### Compliance Dashboard

Access your compliance dashboard through:

1. **Security Command Center**: Monitor findings and compliance posture
2. **Cloud Build History**: Track build execution and compliance testing
3. **Cloud Storage Reports**: Review detailed compliance analysis results
4. **Cloud Monitoring**: Set up custom metrics for compliance tracking

### Regular Maintenance Tasks

```bash
# Update Document AI processor (if needed)
gcloud documentai processors list --location=us-central1

# Clean up old compliance reports (optional)
gsutil -m rm gs://accessibility-compliance-*/reports/old-reports/**

# Review and update accessibility rules in analyzer script
# Monitor for new WCAG guidelines and update analysis logic
```

## Troubleshooting

### Common Issues

1. **Document AI API Not Enabled**
   ```bash
   gcloud services enable documentai.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Ensure your account has required roles
   gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
       --member="user:your-email@company.com" \
       --role="roles/owner"
   ```

3. **Build Trigger Failures**
   ```bash
   # Check build logs
   gcloud builds log $(gcloud builds list --limit=1 --format="value(id)")
   
   # Verify cloudbuild.yaml syntax
   gcloud builds submit --config=cloudbuild.yaml --dry-run .
   ```

4. **Missing Organization Access**
   ```bash
   # Verify organization access for Security Command Center
   gcloud organizations list
   gcloud projects get-ancestors $(gcloud config get-value project)
   ```

### Support Resources

- [Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Cloud Build Configuration Reference](https://cloud.google.com/build/docs/configuring-builds)
- [Security Command Center API](https://cloud.google.com/security-command-center/docs)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete accessibility-compliance \
    --location=us-central1 \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all infrastructure
terraform destroy -var="project_id=$(gcloud config get-value project)" \
                  -var="region=us-central1"

# Clean up Terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow interactive prompts to confirm resource deletion
# Script will remove resources in proper dependency order
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
gcloud documentai processors delete PROCESSOR_ID --location=us-central1 --quiet
gsutil -m rm -r gs://accessibility-compliance-*
gcloud pubsub topics delete accessibility-compliance-alerts --quiet
gcloud functions delete compliance-notifier --region=us-central1 --quiet

# Clean up local files
rm -f test-violations.html *.accessibility.json
```

## Security Considerations

This infrastructure implements security best practices including:

- **Least Privilege IAM**: Service accounts with minimal required permissions
- **Encryption**: Data encrypted at rest and in transit
- **Network Security**: Private service connections where applicable
- **Audit Logging**: Comprehensive logging for compliance and security monitoring
- **Resource Isolation**: Proper resource tagging and organization

## Cost Optimization

Monitor and optimize costs through:

- **Resource Tagging**: All resources tagged for cost allocation
- **Lifecycle Policies**: Automatic cleanup of old compliance reports
- **Efficient Processing**: Document AI batch processing for cost efficiency
- **Resource Monitoring**: CloudWatch alerts for unexpected cost increases

## Customization

Extend this solution by:

1. **Adding Custom Rules**: Modify `accessibility_analyzer.py` for organization-specific requirements
2. **Integration**: Connect with existing notification systems (Slack, Microsoft Teams, JIRA)
3. **Reporting**: Create custom dashboards using Looker Studio
4. **Multi-language Support**: Add translation API integration for international content
5. **Visual Testing**: Integrate Cloud Vision API for color contrast analysis

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for implementation details
2. Check Google Cloud documentation for service-specific troubleshooting
3. Verify permissions and API enablement
4. Review build logs and error messages for specific failure points

For accessibility compliance questions:
- Consult WCAG 2.1 documentation
- Consider manual testing by accessibility experts
- Engage with disability advocacy groups for comprehensive validation