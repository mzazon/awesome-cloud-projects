# Terraform Infrastructure for Automated Regulatory Compliance System

This Terraform configuration deploys a complete automated regulatory compliance reporting system on Google Cloud Platform using Document AI, Cloud Functions, Cloud Scheduler, and Cloud Storage.

## Architecture Overview

The infrastructure creates:
- **Document AI Processor**: Extracts structured data from compliance documents
- **Cloud Storage Buckets**: Secure storage for input documents, processed results, and reports
- **Cloud Functions**: Serverless processing and report generation
- **Cloud Scheduler**: Automated periodic report generation
- **Monitoring & Alerting**: Comprehensive observability with automated notifications
- **IAM & Security**: Least-privilege access controls and audit trails

## Prerequisites

### Required Tools
- [Terraform](https://terraform.io/downloads) >= 1.0
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (gcloud CLI)
- Active Google Cloud Project with billing enabled

### Required Permissions
Your account needs the following IAM roles:
- `roles/editor` or `roles/owner` on the target project
- `roles/serviceusage.serviceUsageAdmin` for API management
- `roles/iam.serviceAccountAdmin` for service account creation

### Enable APIs
The configuration automatically enables required APIs, but you can manually enable them:
```bash
gcloud services enable documentai.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudscheduler.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable monitoring.googleapis.com
```

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd gcp/automated-regulatory-compliance-document-ai-scheduler/code/terraform/
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Configure Variables
Create a `terraform.tfvars` file:
```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"
environment = "dev"
resource_prefix = "compliance"
notification_email = "your-email@example.com"

# Optional customizations
function_memory = 1024
function_timeout = 540
report_function_memory = 512
bucket_lifecycle_age = 365
```

### 4. Review and Deploy
```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Verify Deployment
```bash
# Check the deployment outputs
terraform output

# View created resources
gcloud functions list --regions=us-central1
gcloud storage ls
gcloud scheduler jobs list --location=us-central1
```

## Configuration Variables

### Required Variables
| Variable | Description | Type | Example |
|----------|-------------|------|---------|
| `project_id` | GCP project ID | string | `"my-compliance-project"` |

### Optional Variables
| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `region` | GCP region for resources | `"us-central1"` | string |
| `zone` | GCP zone for zonal resources | `"us-central1-a"` | string |
| `environment` | Environment name | `"dev"` | string |
| `resource_prefix` | Prefix for resource names | `"compliance"` | string |
| `document_ai_location` | Document AI processor location | `"us"` | string |
| `function_memory` | Cloud Function memory (MB) | `1024` | number |
| `function_timeout` | Cloud Function timeout (seconds) | `540` | number |
| `notification_email` | Email for alerts | `"compliance@example.com"` | string |
| `daily_report_schedule` | Cron schedule for daily reports | `"0 8 * * *"` | string |
| `weekly_report_schedule` | Cron schedule for weekly reports | `"0 9 * * 1"` | string |
| `monthly_report_schedule` | Cron schedule for monthly reports | `"0 10 1 * *"` | string |

### Environment-Specific Configurations

#### Development Environment
```hcl
environment = "dev"
function_memory = 512
bucket_lifecycle_age = 90
force_destroy_buckets = true
```

#### Production Environment
```hcl
environment = "prod"
function_memory = 1024
bucket_lifecycle_age = 2555  # 7 years for compliance
force_destroy_buckets = false
enable_uniform_bucket_level_access = true
```

## Usage Instructions

### Document Upload and Processing

1. **Upload documents** to the input bucket (triggers automatic processing):
   ```bash
   # Using gcloud CLI
   gsutil cp document.pdf gs://$(terraform output -raw input_bucket_name)/
   
   # View processing results
   gsutil ls gs://$(terraform output -raw processed_bucket_name)/processed/
   ```

2. **Monitor processing** via Cloud Logging:
   ```bash
   gcloud logging read 'resource.type="cloud_function"' --limit=10
   ```

### Manual Report Generation

Trigger reports manually using the Cloud Function URL:
```bash
# Get function URL
REPORT_URL=$(terraform output -raw report_generator_function_url)

# Generate daily report
curl -X POST -H "Content-Type: application/json" \
     -d '{"report_type": "daily"}' \
     "$REPORT_URL"

# Generate weekly report
curl -X POST -H "Content-Type: application/json" \
     -d '{"report_type": "weekly"}' \
     "$REPORT_URL"
```

### Accessing Reports

```bash
# List generated reports
gsutil ls gs://$(terraform output -raw reports_bucket_name)/reports/

# Download specific report
gsutil cp gs://$(terraform output -raw reports_bucket_name)/reports/daily_compliance_report_20241201_120000.json ./
```

## Monitoring and Alerting

### Key Metrics
- **Compliance Violations**: Tracks documents with compliance issues
- **Processing Errors**: Monitors function execution failures
- **Successful Processing**: Counts successfully processed documents

### Alert Policies
- **High Compliance Violations**: Triggers when >5 violations occur in 5 minutes
- **High Processing Error Rate**: Triggers when >10 errors occur in 10 minutes

### Accessing Monitoring

```bash
# View metrics in console
open "$(terraform output -raw monitoring_dashboard_link)"

# View function logs
open "$(terraform output -raw logs_explorer_link)"

# Check scheduler jobs
open "$(terraform output -raw scheduler_console_link)"
```

## Security Considerations

### Data Protection
- All buckets have uniform bucket-level access enabled
- Public access prevention is enforced
- Object versioning enabled for audit trails
- Lifecycle policies prevent indefinite storage costs

### Access Control
- Dedicated service account with least-privilege permissions
- IAM roles strictly limited to required operations
- Cloud Functions use service account authentication

### Compliance Features
- Complete audit trails via Cloud Audit Logs
- Document versioning for regulatory requirements
- Encrypted storage (Google-managed keys)
- Monitoring and alerting for compliance violations

## Customization

### Adding Custom Compliance Rules

Modify the `document_processor.py` function to add custom validation logic:

```python
def validate_compliance_data(data, document_name):
    # Add your custom compliance rules here
    if 'sox' in document_name.lower():
        # SOX-specific validation
        pass
    elif 'gdpr' in document_name.lower():
        # GDPR-specific validation
        pass
    # ... existing validation logic
```

### Custom Scheduling

Modify scheduler variables for different reporting frequencies:
```hcl
daily_report_schedule = "0 6 * * *"    # 6 AM daily
weekly_report_schedule = "0 8 * * 0"   # 8 AM Sundays
monthly_report_schedule = "0 9 1 * *"  # 9 AM 1st of month
```

### Multi-Environment Deployment

Use Terraform workspaces for multiple environments:
```bash
# Create and switch to production workspace
terraform workspace new prod
terraform workspace select prod

# Deploy with production variables
terraform apply -var-file="prod.tfvars"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**
   ```bash
   # Manually enable required APIs
   gcloud services enable documentai.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   ```

3. **Function Deployment Failures**
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   ```

4. **Document Processing Errors**
   ```bash
   # View function logs
   gcloud functions logs read document-processor --limit=50
   ```

### Log Analysis

```bash
# Check for compliance violations
gcloud logging read 'resource.type="cloud_function" AND textPayload:"NON_COMPLIANT"'

# Monitor processing success
gcloud logging read 'resource.type="cloud_function" AND textPayload:"Document processed successfully"'

# Review error logs
gcloud logging read 'resource.type="cloud_function" AND severity="ERROR"'
```

## Cleanup

### Remove All Resources
```bash
# Destroy all infrastructure
terraform destroy

# Verify resource removal
gcloud functions list
gcloud storage ls
gcloud scheduler jobs list --location=us-central1
```

### Selective Cleanup
```bash
# Remove only specific resources
terraform destroy -target=google_cloud_scheduler_job.daily_compliance_report
```

## Cost Optimization

### Estimated Costs (Monthly)
- **Document AI**: ~$1.50 per 1,000 pages processed
- **Cloud Functions**: ~$0.40 per million invocations + compute time
- **Cloud Storage**: ~$0.02 per GB stored
- **Cloud Scheduler**: ~$0.10 per job per month
- **Monitoring**: Included in free tier for basic usage

### Cost Reduction Tips
1. Adjust `bucket_lifecycle_age` to automatically delete old documents
2. Use `NEARLINE` or `COLDLINE` storage classes for archival data
3. Optimize function memory allocation based on actual usage
4. Monitor and adjust scheduler frequency based on requirements

## Support and Documentation

### Related Resources
- [Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help
- Review Terraform logs: `terraform apply -debug`
- Check Google Cloud Console for resource status
- Use `gcloud` CLI for debugging cloud resources
- Monitor Cloud Logging for application-level issues

---

For additional customization or enterprise features, consider extending this implementation with:
- Custom Document AI processors for specific document types
- Integration with BigQuery for advanced analytics
- Multi-region deployment for high availability
- Custom notification channels (Slack, PagerDuty, etc.)