# Infrastructure as Code for Newsletter Content Generation with Gemini and Scheduler

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless newsletter content generation system on Google Cloud Platform using Gemini AI, Cloud Functions, Cloud Scheduler, and Cloud Storage.

## Overview

This Terraform configuration deploys:

- **Cloud Storage Bucket**: For storing content templates and generated newsletters
- **Cloud Functions**: Serverless function for newsletter content generation using Gemini AI
- **Cloud Scheduler**: Automated job scheduling for regular newsletter generation
- **Vertex AI**: Integration with Gemini AI models for intelligent content creation
- **IAM Resources**: Service accounts and permissions for secure access
- **Monitoring**: Optional alerting and monitoring configuration

## Prerequisites

- Google Cloud Project with billing enabled
- Terraform >= 1.5 installed
- Google Cloud CLI installed and authenticated
- Appropriate IAM permissions:
  - Project Editor or custom role with:
    - Cloud Functions Admin
    - Cloud Scheduler Admin
    - Storage Admin
    - Vertex AI User
    - Service Account Admin
    - Project IAM Admin

## Required APIs

The following Google Cloud APIs will be automatically enabled:

- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Vertex AI API (`aiplatform.googleapis.com`)
- Cloud Run API (`run.googleapis.com`)
- Eventarc API (`eventarc.googleapis.com`)
- Pub/Sub API (`pubsub.googleapis.com`)

## Quick Start

1. **Initialize Terraform**:
   ```bash
   cd terraform/
   terraform init
   ```

2. **Configure Variables**:
   Create a `terraform.tfvars` file:
   ```hcl
   project_id = "your-gcp-project-id"
   region     = "us-central1"
   
   # Optional customizations
   resource_prefix             = "newsletter-gen"
   environment                = "dev"
   function_memory            = 512
   schedule_cron              = "0 9 * * 1"  # Monday at 9 AM
   default_newsletter_topic   = "Weekly Marketing Insights"
   enable_public_access       = false
   enable_monitoring          = true
   alert_email               = "admin@example.com"
   ```

3. **Plan Deployment**:
   ```bash
   terraform plan
   ```

4. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

## Configuration Variables

### Required Variables

| Variable | Description | Type |
|----------|-------------|------|
| `project_id` | Google Cloud project ID | string |

### Optional Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `region` | Google Cloud region | "us-central1" | string |
| `resource_prefix` | Prefix for resource names | "newsletter-gen" | string |
| `environment` | Environment (dev/staging/prod) | "dev" | string |
| `function_name` | Cloud Function name | "newsletter-generator" | string |
| `function_memory` | Function memory in MB | 512 | number |
| `function_timeout` | Function timeout in seconds | 300 | number |
| `python_runtime` | Python runtime version | "python312" | string |
| `schedule_cron` | Cron schedule expression | "0 9 * * 1" | string |
| `schedule_timezone` | Timezone for schedule | "America/New_York" | string |
| `default_newsletter_topic` | Default newsletter topic | "Weekly Marketing Insights" | string |
| `enable_public_access` | Allow public function access | false | bool |
| `enable_monitoring` | Enable monitoring and alerts | true | bool |
| `alert_email` | Email for alerts | "" | string |

## Outputs

After successful deployment, Terraform provides these outputs:

- `function_url`: HTTP trigger URL for the Cloud Function
- `storage_bucket_name`: Name of the Cloud Storage bucket
- `scheduler_job_name`: Name of the Cloud Scheduler job
- `function_console_url`: Direct link to function in Cloud Console
- `test_curl_command`: Example command to test the function

## Testing the Deployment

1. **Manual Function Test**:
   ```bash
   # Get the function URL from outputs
   FUNCTION_URL=$(terraform output -raw function_url)
   
   # Test with custom topic (if public access enabled)
   curl -X POST "$FUNCTION_URL" \
     -H "Content-Type: application/json" \
     -d '{"topic":"AI in Email Marketing"}'
   
   # Or use gcloud (authenticated)
   gcloud functions call $(terraform output -raw function_name) \
     --region=$(terraform output -raw region) \
     --data='{"topic":"AI in Email Marketing"}'
   ```

2. **Check Generated Content**:
   ```bash
   # List generated content
   gsutil ls gs://$(terraform output -raw storage_bucket_name)/generated-content/
   
   # Download latest content
   gsutil cp gs://$(terraform output -raw storage_bucket_name)/generated-content/* ./
   ```

3. **Test Scheduler**:
   ```bash
   # Manually trigger the scheduler job
   gcloud scheduler jobs run $(terraform output -raw scheduler_job_name) \
     --location=$(terraform output -raw region)
   ```

## Customization

### Content Template

Modify the content template by updating the Cloud Storage object:

```bash
# Download current template
gsutil cp gs://$(terraform output -raw storage_bucket_name)/templates/content-template.json ./

# Edit the template file
# Upload modified template
gsutil cp content-template.json gs://$(terraform output -raw storage_bucket_name)/templates/
```

### Function Code

To modify the function code:

1. Edit the template file: `templates/main.py.tpl`
2. Run `terraform apply` to redeploy with changes

### Schedule Modification

Update the `schedule_cron` variable and run `terraform apply`:

```bash
terraform apply -var="schedule_cron=0 6 * * 1,3,5"  # Mon, Wed, Fri at 6 AM
```

## Security Considerations

- **Function Access**: By default, public access is disabled. Use `allowed_members` to grant specific access.
- **Service Accounts**: Minimal permissions are granted using principle of least privilege.
- **Storage**: Bucket uses uniform bucket-level access for consistent security.
- **Monitoring**: Enable monitoring to track function performance and failures.

## Cost Optimization

- **Function Memory**: Adjust `function_memory` based on actual usage patterns
- **Storage Class**: Use `bucket_storage_class` for cost-appropriate storage
- **Lifecycle**: Automatic cleanup of old content versions after 30 days
- **Monitoring**: Track costs in Cloud Billing console

## Monitoring and Logging

When `enable_monitoring` is true and `alert_email` is provided:

- Email notifications for function failures
- Cloud Monitoring dashboards available in Cloud Console
- Function logs available in Cloud Logging

Access monitoring:
```bash
# View function logs
gcloud logs read "resource.type=cloud_function AND resource.labels.function_name=$(terraform output -raw function_name)" --limit=50

# Open monitoring dashboard
echo "$(terraform output -raw function_console_url)"
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure your account has the required IAM roles
2. **API Not Enabled**: Check that all required APIs are enabled in your project
3. **Function Timeout**: Increase `function_timeout` if content generation takes longer
4. **Storage Access**: Verify service account has storage permissions

### Debug Commands

```bash
# Check function status
gcloud functions describe $(terraform output -raw function_name) --region=$(terraform output -raw region)

# View recent logs
gcloud logs read "resource.type=cloud_function" --limit=10 --format="table(timestamp,severity,textPayload)"

# Test storage access
gsutil ls gs://$(terraform output -raw storage_bucket_name)
```

## Cleanup

To remove all deployed resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources including stored content. Consider backing up important data before destruction.

## Support

- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

When modifying this Terraform code:

1. Follow Google Cloud best practices
2. Update variable descriptions and validation rules
3. Add appropriate outputs for new resources
4. Test changes in a development environment
5. Update this README with new features or configuration options