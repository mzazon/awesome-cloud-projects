# Infrastructure as Code for Dynamic Email Campaign Workflows with Gmail API and Cloud Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Dynamic Email Campaign Workflows with Gmail API and Cloud Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts for manual deployment

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active Google Cloud Project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Admin
  - Cloud Scheduler Admin
  - Storage Admin
  - BigQuery Admin
  - Service Account Admin
  - IAM Admin
- Gmail API OAuth 2.0 credentials configured
- Basic understanding of serverless architecture and email marketing

## Quick Start

### Using Infrastructure Manager (Recommended)

Infrastructure Manager is Google Cloud's native IaC solution that provides built-in state management and integrates seamlessly with Google Cloud services.

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments create email-campaign-deployment \
    --location=us-central1 \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main"

# Monitor deployment status
gcloud infra-manager deployments describe email-campaign-deployment \
    --location=us-central1
```

### Using Terraform

Terraform provides a declarative approach to infrastructure management with excellent state management and planning capabilities.

```bash
# Navigate to Terraform configuration
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id"

# Apply the configuration
terraform apply -var="project_id=your-project-id"

# Verify deployment
terraform show
```

### Using Bash Scripts

For manual deployment or CI/CD integration, use the provided bash scripts that replicate the recipe's step-by-step process.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud functions list --regions=${REGION}
gcloud scheduler jobs list --location=${REGION}
```

## Configuration

### Infrastructure Manager Variables

Edit the `infrastructure-manager/main.yaml` file to customize your deployment:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
    default: "your-project-id"
  
  region:
    description: "Google Cloud Region"
    type: string
    default: "us-central1"
  
  bucket_name:
    description: "Cloud Storage bucket name for campaign data"
    type: string
    default: "email-campaigns-bucket"
```

### Terraform Variables

Customize your deployment by editing `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
bucket_name = "email-campaigns-custom-bucket"
function_memory = 512
function_timeout = 300

# Email campaign settings
campaign_schedules = {
  daily_campaign = "0 8 * * *"
  weekly_newsletter = "0 10 * * 1"
  promotional_campaigns = "0 14 * * 3,6"
}
```

### Bash Script Variables

Set environment variables before running the deployment script:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export BUCKET_NAME="email-campaigns-$(date +%s)"
export FUNCTION_NAME="email-campaign-$(openssl rand -hex 3)"
```

## Architecture Overview

This infrastructure deploys a complete email campaign automation system with the following components:

- **Cloud Storage**: Stores email templates, campaign data, and analytics
- **Cloud Functions**: 
  - Campaign Generator: Analyzes user behavior and generates personalized campaigns
  - Email Sender: Delivers emails through Gmail API
  - Analytics: Processes campaign performance metrics
- **BigQuery**: Data warehouse for user behavior and campaign analytics
- **Cloud Scheduler**: Orchestrates campaign execution with cron jobs
- **Gmail API**: Handles email delivery and authentication
- **Cloud Monitoring**: Tracks system performance and email metrics

## Post-Deployment Configuration

After successful deployment, complete these manual configuration steps:

### 1. Gmail API OAuth Configuration

```bash
# Navigate to Google Cloud Console
# Go to APIs & Services > Credentials
# Create OAuth 2.0 Client ID for Gmail API access
# Download credentials and store in Cloud Storage

# Upload OAuth credentials to Cloud Storage
gsutil cp path/to/oauth-credentials.json gs://${BUCKET_NAME}/credentials/
```

### 2. Email Template Customization

```bash
# Download sample templates
gsutil cp gs://${BUCKET_NAME}/templates/* ./templates/

# Edit templates as needed
# Upload customized templates
gsutil cp ./templates/* gs://${BUCKET_NAME}/templates/
```

### 3. User Behavior Data Setup

```bash
# Load initial user data into BigQuery
bq load --source_format=CSV \
    ${PROJECT_ID}:email_campaigns.user_behavior \
    path/to/user_data.csv \
    user_id:STRING,email:STRING,last_activity:TIMESTAMP,purchase_history:STRING,preferences:STRING
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# View Campaign Generator logs
gcloud functions logs read ${FUNCTION_NAME}-generator \
    --region=${REGION} \
    --limit=50

# View Email Sender logs
gcloud functions logs read ${FUNCTION_NAME}-sender \
    --region=${REGION} \
    --limit=50
```

### Monitor Scheduler Jobs

```bash
# Check job status
gcloud scheduler jobs describe campaign-generator-daily \
    --location=${REGION}

# View job execution history
gcloud logging read "resource.type=cloud_scheduler_job" \
    --limit=20 \
    --format="table(timestamp, resource.labels.job_id, textPayload)"
```

### BigQuery Analytics

```bash
# Query campaign performance
bq query --use_legacy_sql=false \
    "SELECT 
        campaign_id,
        sent_count,
        opened_count,
        SAFE_DIVIDE(opened_count, sent_count) as open_rate
     FROM \`${PROJECT_ID}.email_campaigns.campaign_metrics\`
     ORDER BY timestamp DESC
     LIMIT 10"
```

## Security Considerations

### IAM Permissions

The deployment creates service accounts with minimal required permissions:

- **Cloud Functions Service Account**: Gmail API access, Storage access, BigQuery access
- **Cloud Scheduler Service Account**: Function invocation permissions
- **Analytics Service Account**: BigQuery read/write, Monitoring write

### Data Protection

- All data is encrypted at rest using Google-managed encryption keys
- OAuth credentials are stored securely in Cloud Storage with restricted access
- Email templates and user data are protected with IAM policies
- Function-to-function communication uses service account authentication

### Gmail API Security

- Uses OAuth 2.0 flow for secure Gmail API access
- Implements proper scope restrictions for email sending
- Service account keys are rotated regularly
- API quota monitoring prevents abuse

## Cost Optimization

### Estimated Monthly Costs

Based on moderate usage (1,000 emails/day):

- **Cloud Functions**: $5-10 (pay-per-invocation)
- **Cloud Storage**: $1-2 (templates and data)
- **BigQuery**: $2-5 (analytics queries)
- **Cloud Scheduler**: $0.10 (job executions)
- **Gmail API**: Free (within quotas)

**Total Estimated Cost**: $8-17/month

### Cost Optimization Tips

1. **Function Memory**: Use minimum required memory (256MB for analytics, 512MB for email processing)
2. **Storage Class**: Use Standard storage for frequently accessed data
3. **BigQuery**: Use partitioned tables for large datasets
4. **Scheduler**: Combine multiple operations in single function calls
5. **Monitoring**: Set up budget alerts for cost tracking

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete email-campaign-deployment \
    --location=us-central1 \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id"

# Clean up state files
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual cleanup verification
gcloud functions list --regions=${REGION}
gcloud scheduler jobs list --location=${REGION}
gsutil ls gs://${BUCKET_NAME} 2>/dev/null || echo "Bucket deleted successfully"
```

## Troubleshooting

### Common Issues

1. **Gmail API Quota Exceeded**
   ```bash
   # Check API quotas
   gcloud logging read "protoPayload.methodName=gmail.users.messages.send" \
       --limit=10 \
       --format="table(timestamp, protoPayload.status.code, protoPayload.status.message)"
   ```

2. **Function Deployment Failures**
   ```bash
   # Check function deployment logs
   gcloud functions logs read ${FUNCTION_NAME}-generator \
       --region=${REGION} \
       --limit=10
   ```

3. **Scheduler Job Failures**
   ```bash
   # Check scheduler job logs
   gcloud logging read "resource.type=cloud_scheduler_job AND severity>=ERROR" \
       --limit=10
   ```

4. **BigQuery Permission Issues**
   ```bash
   # Verify BigQuery permissions
   bq ls ${PROJECT_ID}:email_campaigns
   ```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Set debug environment variables
export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
export FUNCTION_DEBUG_MODE=true

# Redeploy functions with debug settings
gcloud functions deploy ${FUNCTION_NAME}-generator \
    --set-env-vars DEBUG_MODE=true,LOG_LEVEL=DEBUG
```

## Support and Documentation

### Additional Resources

- [Gmail API Documentation](https://developers.google.com/gmail/api)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

1. **Google Cloud Support**: For infrastructure and service issues
2. **Community Forums**: Stack Overflow with `google-cloud-platform` tag
3. **GitHub Issues**: For recipe-specific problems
4. **Google Cloud Documentation**: For detailed service guidance

## Contributing

To improve this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description
5. Update documentation as needed

## License

This infrastructure code is provided under the same license as the original recipe documentation.