# Infrastructure as Code for Automated Code Review Pipelines with Firebase Studio and Cloud Build

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Code Review Pipelines with Firebase Studio and Cloud Build".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Build API
  - Cloud Tasks API
  - Cloud Functions API
  - Cloud Source Repositories API
  - Firebase API
  - AI Platform API
  - Cloud Storage (for metrics and artifacts)
- Git configured for repository operations
- Node.js 18+ (for sample application)
- Basic understanding of CI/CD concepts

## Quick Start

### Using Infrastructure Manager (GCP Native)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/code-review-deployment \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --git-source-repo=https://source.developers.google.com/p/PROJECT_ID/r/REPO_NAME \
    --git-source-directory=infrastructure-manager \
    --git-source-ref=main \
    --input-values="project_id=PROJECT_ID,region=REGION"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
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

## Architecture Overview

This IaC deploys the following components:

- **Cloud Source Repository**: Private Git repository with CI/CD integration
- **Cloud Build Triggers**: Automated pipeline execution for main and feature branches
- **Cloud Functions**: 
  - AI-powered code review processor using Gemini API
  - Metrics collection and analysis system
- **Cloud Tasks Queue**: Asynchronous processing for intensive code analysis
- **Cloud Storage Buckets**: Artifact storage and metrics data warehouse
- **IAM Roles & Permissions**: Least-privilege security configuration
- **Firebase Studio Integration**: AI-powered development environment setup

## Configuration Variables

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

- `project_id`: Your Google Cloud Project ID
- `region`: Deployment region (default: us-central1)
- `queue_max_concurrent_dispatches`: Cloud Tasks concurrency (default: 10)
- `function_memory`: Cloud Function memory allocation (default: 1GB)
- `function_timeout`: Cloud Function timeout (default: 540s)

### Terraform Variables

Available in `terraform/variables.tf`:

- `project_id`: Google Cloud Project ID (required)
- `region`: Deployment region (default: "us-central1")
- `zone`: Deployment zone (default: "us-central1-a")
- `repo_name_suffix`: Repository name suffix for uniqueness
- `enable_apis`: List of APIs to enable (default: all required APIs)
- `function_memory`: Memory allocation for Cloud Functions (default: 1024)
- `queue_max_dispatches`: Maximum concurrent task dispatches (default: 10)

### Bash Script Variables

Set these environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export GEMINI_API_KEY="your-gemini-api-key"  # Required for AI functionality
```

## Post-Deployment Setup

After deploying the infrastructure:

1. **Configure Firebase Studio Workspace**:
   ```bash
   # Get repository URL
   gcloud source repos describe code-review-repo-SUFFIX --format="value(url)"
   
   # Visit Firebase Studio and import the repository
   echo "Import at: https://studio.firebase.google.com"
   ```

2. **Set up Gemini API Key**:
   ```bash
   # Store API key securely (replace with your actual key)
   gcloud functions deploy FUNCTION_NAME \
       --update-env-vars GEMINI_API_KEY=your-actual-api-key
   ```

3. **Test the Pipeline**:
   ```bash
   # Clone the created repository
   gcloud source repos clone code-review-repo-SUFFIX
   cd code-review-repo-SUFFIX
   
   # Make a test change and push
   echo "// Test change" >> index.js
   git add . && git commit -m "Test automated review pipeline"
   git push origin main
   ```

## Monitoring and Observability

The deployed infrastructure includes comprehensive monitoring:

- **Cloud Build Logs**: Pipeline execution details
- **Cloud Function Logs**: AI review processing logs
- **Cloud Tasks Monitoring**: Queue processing metrics
- **Cloud Storage**: Metrics data and build artifacts
- **Cloud Logging**: Centralized log aggregation

Access monitoring dashboards:
```bash
# View recent builds
gcloud builds list --limit=10

# Check function logs
gcloud functions logs read FUNCTION_NAME --region=REGION

# Monitor task queue
gcloud tasks queues describe QUEUE_NAME --location=REGION
```

## Security Considerations

The IaC implements security best practices:

- **IAM Least Privilege**: Minimal required permissions for each component
- **API Security**: Cloud Functions with proper authentication
- **Code Security**: Automated security scanning in CI/CD pipeline
- **Data Encryption**: Encryption at rest and in transit for all data
- **Network Security**: Private service connectivity where applicable

## Cost Optimization

Estimated monthly costs (development usage):
- Cloud Build: $5-10 (based on build minutes)
- Cloud Functions: $2-5 (based on invocations)
- Cloud Tasks: $1-3 (based on task volume)
- Cloud Storage: $1-2 (for artifacts and metrics)
- **Total: ~$10-20/month for typical development teams**

Cost optimization features:
- Automatic scaling to zero for unused resources
- Efficient resource allocation based on workload
- Configurable retention policies for artifacts and logs

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/code-review-deployment
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify cleanup completion
echo "Cleanup completed. Verify no remaining resources in console."
```

## Customization

### Adding New Code Analysis Rules

Modify the Cloud Function code to include custom analysis rules:

1. Edit the Gemini prompt in the function source
2. Add organization-specific coding standards
3. Integrate with additional security scanning tools
4. Configure custom quality gates

### Extending Firebase Studio Integration

Enhance the development experience:

1. Configure additional AI assistance features
2. Set up custom workspace templates
3. Integrate with external code review tools
4. Add team-specific development workflows

### Multi-Language Support

Extend the pipeline for different programming languages:

1. Add language-specific build steps
2. Configure appropriate testing frameworks
3. Implement language-specific quality rules
4. Set up specialized AI analysis prompts

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **IAM Permissions**: Verify service accounts have necessary permissions
3. **Gemini API Key**: Confirm API key is correctly configured and valid
4. **Resource Quotas**: Check project quotas for Cloud Functions and Cloud Build

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# Verify IAM bindings
gcloud projects get-iam-policy PROJECT_ID

# Test function connectivity
curl -X POST FUNCTION_URL -H "Content-Type: application/json" -d '{}'

# Monitor build execution
gcloud builds list --ongoing
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: [Cloud Build](https://cloud.google.com/build/docs), [Cloud Tasks](https://cloud.google.com/tasks/docs), [Cloud Functions](https://cloud.google.com/functions/docs)
3. **Firebase Studio**: [Firebase Studio Documentation](https://firebase.google.com/docs/studio)
4. **Community Support**: [Google Cloud Community](https://cloud.google.com/community)

## Advanced Features

### Multi-Environment Deployment

Configure separate environments:

```bash
# Development environment
terraform workspace new dev
terraform apply -var="project_id=dev-project" -var="environment=dev"

# Production environment
terraform workspace new prod
terraform apply -var="project_id=prod-project" -var="environment=prod"
```

### Integration with External Tools

- **Slack Notifications**: Add webhook integration for build notifications
- **JIRA Integration**: Automatically create tickets for critical issues
- **GitHub/GitLab**: Configure external repository integration
- **Monitoring Tools**: Export metrics to external monitoring platforms

This IaC provides a complete foundation for implementing automated code review pipelines with AI-powered analysis and comprehensive CI/CD integration using Google Cloud services.