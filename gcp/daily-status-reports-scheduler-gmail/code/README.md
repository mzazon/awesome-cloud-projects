# Infrastructure as Code for Daily System Status Reports with Cloud Scheduler and Gmail

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Daily System Status Reports with Cloud Scheduler and Gmail".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active GCP project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (cloudfunctions.editor)
  - Cloud Scheduler (cloudscheduler.admin)
  - Service Account Admin (iam.serviceAccountAdmin)
  - Project IAM Admin (resourcemanager.projectIamAdmin)
- Gmail account configured for application access (App Password)
- For Terraform: Terraform >= 1.0 installed

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's managed Terraform service that provides state management and deployment orchestration.

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com --project=${PROJECT_ID}

# Create deployment
gcloud infra-manager deployments create daily-status-reports \
    --location=${REGION} \
    --git-source-repo="https://github.com/your-repo/path-to-config" \
    --git-source-directory="infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe daily-status-reports \
    --location=${REGION}
```

### Using Terraform

Terraform provides declarative infrastructure management with state tracking and dependency resolution.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform (downloads providers and modules)
terraform init

# Review planned changes
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="sender_email=your-email@gmail.com" \
    -var="sender_password=your-app-password" \
    -var="recipient_email=admin@example.com"

# Apply infrastructure changes
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="sender_email=your-email@gmail.com" \
    -var="sender_password=your-app-password" \
    -var="recipient_email=admin@example.com"
```

### Using Bash Scripts

Bash scripts provide step-by-step deployment using gcloud CLI commands, following the original recipe implementation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export SENDER_EMAIL="your-email@gmail.com"
export SENDER_PASSWORD="your-app-password"
export RECIPIENT_EMAIL="admin@example.com"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud functions list --filter="name:daily-status-report"
gcloud scheduler jobs list --location=${REGION}
```

## Configuration Options

### Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `PROJECT_ID` | Yes | GCP Project ID | `my-monitoring-project` |
| `REGION` | Yes | GCP Region for resources | `us-central1` |
| `SENDER_EMAIL` | Yes | Gmail account for sending reports | `monitoring@company.com` |
| `SENDER_PASSWORD` | Yes | Gmail App Password | `abcd efgh ijkl mnop` |
| `RECIPIENT_EMAIL` | Yes | Email address to receive reports | `devops-team@company.com` |

### Gmail Configuration

1. **Enable 2-Factor Authentication** on your Gmail account
2. **Generate App Password**:
   - Go to Google Account settings
   - Security → 2-Step Verification → App passwords
   - Generate password for "Mail" application
   - Use this 16-character password as `SENDER_PASSWORD`

### Schedule Customization

The default schedule runs daily at 9 AM UTC (`0 9 * * *`). To modify:

**Infrastructure Manager/Terraform:**
```hcl
variable "schedule" {
  description = "Cron schedule for daily reports"
  type        = string
  default     = "0 9 * * *"  # 9 AM UTC daily
}
```

**Bash Scripts:**
```bash
# Edit the schedule in deploy.sh
--schedule="0 6 * * *"  # 6 AM UTC daily
```

## Validation & Testing

### Test Function Deployment

```bash
# Test function manually
gcloud functions call daily-status-report-${RANDOM_SUFFIX}

# Check function logs
gcloud functions logs read daily-status-report-${RANDOM_SUFFIX} --limit=10
```

### Test Scheduler Job

```bash
# List scheduler jobs
gcloud scheduler jobs list --location=${REGION}

# Manually trigger job
gcloud scheduler jobs run daily-report-trigger-${RANDOM_SUFFIX} \
    --location=${REGION}

# Check job execution history
gcloud logging read 'resource.type="cloud_scheduler_job"' \
    --limit=10 --format="table(timestamp,severity,textPayload)"
```

### Verify Email Delivery

```bash
# Check function execution logs for email sending
gcloud logging read 'resource.type="cloud_function"' \
    --filter='textPayload:"Status report sent"' \
    --limit=5 --format="table(timestamp,textPayload)"
```

## Troubleshooting

### Common Issues

1. **Gmail Authentication Failures**
   ```bash
   # Verify app password is correctly set
   echo $SENDER_PASSWORD
   
   # Check function environment variables
   gcloud functions describe daily-status-report-${RANDOM_SUFFIX} \
       --format="value(environmentVariables)"
   ```

2. **Function Timeout Issues**
   ```bash
   # Increase function timeout (max 540s for HTTP functions)
   gcloud functions deploy daily-status-report-${RANDOM_SUFFIX} \
       --timeout=120s --update-env-vars="existing_vars"
   ```

3. **Permission Errors**
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:serviceAccount:status-reporter@${PROJECT_ID}.iam.gserviceaccount.com"
   ```

4. **Scheduler Job Failures**
   ```bash
   # Check scheduler job logs
   gcloud logging read 'resource.type="cloud_scheduler_job"' \
       --filter='severity>=ERROR' --limit=10
   ```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment (this removes all resources)
gcloud infra-manager deployments delete daily-status-reports \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="sender_email=your-email@gmail.com" \
    -var="sender_password=your-app-password" \
    -var="recipient_email=admin@example.com"

# Clean up Terraform state (optional)
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list --filter="name:daily-status-report"
gcloud scheduler jobs list --location=${REGION}
gcloud iam service-accounts list --filter="email:status-reporter@"
```

## Cost Optimization

### Resource Costs (Estimated Monthly)

- **Cloud Functions**: $0.40-1.60 (based on 1 execution/day at 256MB memory)
- **Cloud Scheduler**: $0.10 (1 job with daily execution)
- **Cloud Monitoring API**: Free tier (first 150 requests/minute)
- **Total Estimated**: $0.50-2.00/month

### Cost Reduction Tips

1. **Optimize Function Memory**: Use minimum required memory (128MB-256MB)
2. **Reduce Execution Time**: Optimize code for faster execution
3. **Use Free Tier**: Stay within Cloud Monitoring free tier limits
4. **Regional Deployment**: Use cheapest region for your use case

## Security Considerations

### Best Practices Implemented

- ✅ Service Account with least privilege access
- ✅ No hardcoded credentials in code
- ✅ Environment variables for sensitive data
- ✅ Authenticated function invocation only
- ✅ IAM-based access control

### Additional Security Recommendations

1. **Secret Manager**: Store email passwords in Secret Manager instead of environment variables
2. **VPC Connector**: Deploy function in VPC for network isolation
3. **Audit Logging**: Enable Cloud Audit Logs for compliance
4. **Regular Rotation**: Rotate Gmail app passwords regularly

## Monitoring & Alerting

### Built-in Monitoring

The solution includes basic monitoring through:
- Cloud Functions execution logs
- Cloud Scheduler job execution history
- Email delivery confirmation logs

### Enhanced Monitoring Setup

```bash
# Create alert policy for function failures
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring-policy.yaml

# Set up log-based metrics
gcloud logging metrics create function_errors \
    --description="Cloud Function execution errors" \
    --log-filter='resource.type="cloud_function" severity>=ERROR'
```

## Customization

### Adding Custom Metrics

Extend the function code to collect additional metrics:

```python
# Add to collect_system_metrics() function
storage_request = monitoring_v3.ListTimeSeriesRequest({
    "name": project_name,
    "filter": 'metric.type="storage.googleapis.com/api/request_count"',
    "interval": interval
})
```

### Multiple Project Monitoring

Modify the function to monitor multiple projects:

```python
# Set multiple project IDs in environment variables
MONITORED_PROJECTS = os.environ.get('MONITORED_PROJECTS', '').split(',')

for project_id in MONITORED_PROJECTS:
    project_metrics = collect_project_metrics(project_id)
    # Add to report
```

### Custom Email Templates

Replace the `format_report_body()` function with HTML templates for richer reporting:

```python
from email.mime.text import MimeText
from email.mime.multipart import MimeMultipart

# Create HTML email with charts and styling
html_body = create_html_report(report_data)
msg.attach(MimeText(html_body, 'html'))
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: 
   - [Cloud Functions](https://cloud.google.com/functions/docs)
   - [Cloud Scheduler](https://cloud.google.com/scheduler/docs)
   - [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
3. **Terraform Google Provider**: [Registry Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: Google Cloud Community forums and Stack Overflow

## Contributing

To improve this infrastructure code:

1. Test changes in a development project
2. Follow Google Cloud best practices
3. Update documentation for any new variables or resources
4. Ensure all deployment methods remain compatible

---

**Last Updated**: 2025-01-12  
**Recipe Version**: 1.1  
**Infrastructure Code Version**: 1.0