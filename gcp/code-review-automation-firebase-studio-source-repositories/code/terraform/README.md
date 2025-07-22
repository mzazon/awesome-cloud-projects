# Infrastructure as Code for Code Review Automation with Firebase Studio and Cloud Source Repositories

This directory contains Terraform Infrastructure as Code (IaC) for deploying an AI-powered code review automation system using Firebase Studio, Cloud Source Repositories, Vertex AI, and Cloud Functions.

## Architecture Overview

The infrastructure deploys:

- **Cloud Source Repository**: Git repository with automated triggers
- **Cloud Functions Gen2**: Serverless code analysis orchestration
- **Vertex AI Gemini**: AI-powered code analysis and review generation
- **Firebase Studio**: Agentic development environment (preview feature)
- **Cloud Storage**: Function source code and analysis results storage
- **Secret Manager**: Secure configuration management
- **Eventarc**: Event-driven triggers for repository changes
- **Cloud Monitoring**: Performance monitoring and alerting
- **Cloud Logging**: Structured logging and analysis

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (gcloud)
- [Git](https://git-scm.com/downloads)

### Google Cloud Setup

1. **Create or select a Google Cloud project**:
   ```bash
   gcloud projects create your-project-id
   gcloud config set project your-project-id
   ```

2. **Enable billing for the project**:
   ```bash
   gcloud billing accounts list
   gcloud billing projects link your-project-id \
     --billing-account=YOUR-BILLING-ACCOUNT-ID
   ```

3. **Authenticate with Google Cloud**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

4. **Set up Terraform service account** (recommended for production):
   ```bash
   gcloud iam service-accounts create terraform-deploy \
     --display-name="Terraform Deployment Service Account"
   
   gcloud projects add-iam-policy-binding your-project-id \
     --member="serviceAccount:terraform-deploy@your-project-id.iam.gserviceaccount.com" \
     --role="roles/editor"
   
   gcloud iam service-accounts keys create terraform-key.json \
     --iam-account=terraform-deploy@your-project-id.iam.gserviceaccount.com
   
   export GOOGLE_APPLICATION_CREDENTIALS=terraform-key.json
   ```

### Required Permissions

The deployment account needs these IAM roles:
- `roles/resourcemanager.projectIamAdmin`
- `roles/serviceusage.serviceUsageAdmin`
- `roles/source.admin`
- `roles/cloudfunctions.admin`
- `roles/aiplatform.admin`
- `roles/storage.admin`
- `roles/secretmanager.admin`
- `roles/eventarc.admin`
- `roles/firebase.admin`
- `roles/monitoring.admin`
- `roles/logging.admin`

## Quick Start

### 1. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your specific values
nano terraform.tfvars
```

Required variables to customize:
- `project_id`: Your Google Cloud project ID
- `region`: Preferred Google Cloud region
- `notification_channels`: Email addresses for alerts

### 2. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 3. Verify Deployment

```bash
# Check function deployment
gcloud functions describe $(terraform output -raw function_name) \
  --region=$(terraform output -raw deployment_region)

# Test the webhook endpoint
curl -X POST "$(terraform output -raw function_url)" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "push",
    "changedFiles": [{
      "path": "test.js",
      "content": "function test() { eval(userInput); }"
    }]
  }'
```

## Configuration Options

### AI Model Configuration

Choose from available Vertex AI models:
- `gemini-2.0-flash-thinking` (recommended, latest reasoning model)
- `gemini-1.5-pro` (high capability, slower)
- `gemini-1.5-flash` (fast, good for most use cases)
- `gemini-1.0-pro` (legacy, stable)

### Analysis Configuration

Customize code analysis behavior:
```hcl
code_analysis_config = {
  temperature           = 0.3    # Lower for more focused analysis
  max_tokens           = 4096   # Analysis detail level
  analysis_depth       = "comprehensive"  # basic|detailed|comprehensive
  include_suggestions  = true   # Include improvement suggestions
  check_security       = true   # Security vulnerability scanning
  check_performance    = true   # Performance optimization checks
  check_best_practices = true   # Coding standards verification
}
```

### Supported Languages

Enable analysis for specific programming languages:
```hcl
supported_languages = [
  "javascript",
  "typescript", 
  "python",
  "java",
  "go",
  "rust",
  "cpp",
  "csharp",
  "php",
  "ruby"
]
```

## Usage

### Repository Setup

1. **Clone the created repository**:
   ```bash
   gcloud source repos clone $(terraform output -raw repository_name)
   cd $(terraform output -raw repository_name)
   ```

2. **Add sample code for testing**:
   ```bash
   # Create a sample file with code quality issues
   cat > src/example.js << 'EOF'
   function processUser(userInput) {
     // Security issue: eval usage
     return eval(userInput);
   }
   EOF
   
   git add .
   git commit -m "Add sample code for AI review testing"
   git push origin main
   ```

3. **Monitor analysis results**:
   ```bash
   # Check function logs
   gcloud functions logs read $(terraform output -raw function_name) \
     --region=$(terraform output -raw deployment_region)
   
   # View analysis results in storage
   gsutil ls gs://$(terraform output -raw analysis_results_bucket)/
   ```

### Firebase Studio Integration

If Firebase Studio is enabled:

1. **Access Firebase Studio**:
   ```bash
   echo "Firebase Studio URL: $(terraform output -raw firebase_studio_url)"
   ```

2. **Configure code review agents** in the Studio workspace
3. **Customize analysis prompts** and review templates
4. **Train agents** on your specific coding standards

### Webhook Configuration

Set up repository webhooks for automated triggers:

1. Go to Cloud Console > Source Repositories
2. Select your repository: `$(terraform output -raw repository_name)`
3. Navigate to Settings > Triggers
4. Add Cloud Build trigger pointing to: `$(terraform output -raw function_url)`
5. Configure for push and pull request events

## Monitoring and Troubleshooting

### View Analysis Results

```bash
# List recent analysis results
gsutil ls -l gs://$(terraform output -raw analysis_results_bucket)/ | head -10

# Download and view specific analysis
gsutil cp gs://$(terraform output -raw analysis_results_bucket)/analysis-*.json .
cat analysis-*.json | jq .
```

### Monitor Function Performance

```bash
# View function metrics
gcloud functions describe $(terraform output -raw function_name) \
  --region=$(terraform output -raw deployment_region) \
  --format="table(serviceConfig.uri,serviceConfig.availableMemory,serviceConfig.timeoutSeconds)"

# Check function logs for errors
gcloud functions logs read $(terraform output -raw function_name) \
  --region=$(terraform output -raw deployment_region) \
  --severity=ERROR
```

### Debug Common Issues

1. **Function timeout errors**: Increase `function_timeout` variable
2. **Memory limit exceeded**: Increase `function_memory` variable  
3. **API quota exceeded**: Check Vertex AI quotas in Cloud Console
4. **Permission errors**: Verify service account IAM roles

## Cost Optimization

### Estimated Costs

- **Cloud Functions**: ~$0.40 per million invocations
- **Vertex AI**: ~$0.25 per 1K input characters
- **Cloud Storage**: ~$0.02 per GB/month
- **Other services**: Minimal usage-based costs

### Optimization Tips

1. **Adjust function memory** based on actual usage
2. **Set lifecycle policies** on storage buckets
3. **Monitor Vertex AI usage** and optimize prompts
4. **Use Cloud Monitoring** to identify bottlenecks

## Security Considerations

### Data Privacy

- Analysis results are stored in your Google Cloud project
- No code is sent to external services
- Secret Manager protects sensitive configuration

### Access Control

- Function uses dedicated service account with minimal permissions
- Repository access controlled through Cloud IAM
- Monitoring data isolated to your project

### Compliance

- All data remains within your specified Google Cloud region
- Audit logs available through Cloud Logging
- Compliance with Google Cloud security standards

## Customization

### Adding New Languages

1. Update `supported_languages` variable
2. Modify analysis prompts in function code
3. Test with sample files in new languages

### Custom Analysis Rules

1. Edit the Vertex AI configuration in Secret Manager
2. Update function code analysis prompts
3. Deploy function updates

### Integration with External Tools

Extend the function to integrate with:
- GitHub/GitLab webhooks
- Slack notifications
- Jira ticket creation
- Custom dashboards

## Cleanup

### Remove All Resources

```bash
# Destroy all infrastructure
terraform destroy -auto-approve

# Clean up local files
rm -f terraform-key.json
rm -f terraform.tfstate*
rm -f .terraform.lock.hcl
rm -rf .terraform/
```

### Selective Cleanup

```bash
# Remove specific resources
terraform destroy -target=google_cloudfunctions2_function.code_review_trigger
terraform destroy -target=google_storage_bucket.analysis_results
```

## Troubleshooting

### Common Issues

1. **"Firebase Studio not available"**
   - Set `enable_firebase_studio = false` if not in preview program
   - Check Firebase Studio availability in your region

2. **"Insufficient permissions"**
   - Verify all required IAM roles are assigned
   - Check organization policies for resource restrictions

3. **"Function deployment failed"**
   - Check Cloud Build logs in Cloud Console
   - Verify function source code syntax

4. **"Vertex AI quota exceeded"**
   - Request quota increase in Cloud Console
   - Reduce analysis frequency or batch size

### Getting Help

- **Google Cloud Documentation**: https://cloud.google.com/docs
- **Terraform Google Provider**: https://registry.terraform.io/providers/hashicorp/google
- **Firebase Studio**: https://firebase.google.com/docs/studio
- **Vertex AI**: https://cloud.google.com/vertex-ai/docs

### Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Terraform and Google Cloud documentation
3. Consult the original recipe documentation
4. Submit issues to your organization's DevOps team

## Advanced Configuration

### Multi-Environment Deployment

```bash
# Development environment
terraform workspace new dev
terraform apply -var="environment=dev"

# Production environment  
terraform workspace new prod
terraform apply -var="environment=prod" -var="enable_monitoring=true"
```

### Custom Secret Management

```bash
# Add custom secrets for external integrations
gcloud secrets create github-webhook-secret --data-file=webhook-secret.txt
gcloud secrets create slack-bot-token --data-file=slack-token.txt
```

### Performance Tuning

```bash
# Monitor function performance
gcloud monitoring metrics list --filter="metric.type:cloudfunctions"

# Adjust based on metrics
terraform apply -var="function_memory=1Gi" -var="max_concurrent_reviews=10"
```

---

**Note**: This infrastructure deploys preview features (Firebase Studio) that may have usage limitations. Review Google Cloud documentation for current feature availability and pricing.