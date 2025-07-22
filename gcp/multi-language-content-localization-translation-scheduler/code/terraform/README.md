# Terraform Infrastructure for Multi-Language Content Localization

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete automated content localization pipeline on Google Cloud Platform using Cloud Translation API, Cloud Scheduler, Cloud Storage, Pub/Sub, and Cloud Functions.

## Architecture Overview

The infrastructure creates an event-driven content localization pipeline that:

- **Automatically detects** uploaded content in Cloud Storage
- **Translates content** into multiple target languages using Cloud Translation API
- **Orchestrates workflows** with Cloud Scheduler for batch processing
- **Monitors pipeline health** with Cloud Monitoring and Logging
- **Scales automatically** based on content volume

## Prerequisites

- Google Cloud Platform account with billing enabled
- Terraform >= 1.6.0 installed
- gcloud CLI installed and authenticated
- Project with appropriate IAM permissions:
  - Project Editor or custom role with:
    - Cloud Translation API Admin
    - Storage Admin
    - Pub/Sub Admin
    - Cloud Functions Admin
    - Cloud Scheduler Admin
    - Monitoring Admin

## Quick Start

### 1. Initialize Terraform

```bash
# Clone or navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"
environment = "dev"

# Optional customizations
batch_schedule = "0 2 * * *"  # Daily at 2 AM UTC
function_max_instances = 10
custom_target_languages = ["es", "fr", "de", "it", "pt", "ja", "zh"]
enable_monitoring_dashboard = true
force_destroy = true  # For development environments only
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check the outputs for important information
terraform output

# Test the pipeline
echo "Hello, world!" | gsutil cp - gs://$(terraform output -raw source_bucket_name)/test.txt

# Monitor translations
gsutil ls -r gs://$(terraform output -raw translated_bucket_name)/
```

## Configuration Variables

### Required Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `project_id` | Google Cloud Project ID | string | - |
| `region` | GCP region for deployment | string | `us-central1` |

### Optional Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `environment` | Environment label (dev/staging/prod) | string | `dev` |
| `batch_schedule` | Cron schedule for batch processing | string | `0 2 * * *` |
| `function_max_instances` | Max Cloud Function instances | number | `10` |
| `custom_target_languages` | List of target language codes | list(string) | `[]` |
| `enable_monitoring_dashboard` | Enable monitoring dashboard | bool | `true` |
| `force_destroy` | Allow bucket destruction with content | bool | `false` |

See `variables.tf` for the complete list of configuration options.

## Supported File Types

The pipeline supports translation of the following file types:

- **Text files** (`.txt`)
- **Markdown files** (`.md`)
- **HTML files** (`.html`)
- **JSON files** (`.json`)
- **CSV files** (`.csv`)

## Target Languages

By default, the pipeline translates content into:
- Spanish (`es`)
- French (`fr`)
- German (`de`)
- Italian (`it`)
- Portuguese (`pt`)
- Japanese (`ja`)
- Chinese (`zh`)

You can customize target languages using the `custom_target_languages` variable.

## Usage Instructions

### Upload Content for Translation

```bash
# Upload a single file
gsutil cp document.txt gs://$(terraform output -raw source_bucket_name)/

# Upload multiple files
gsutil -m cp *.txt gs://$(terraform output -raw source_bucket_name)/content/

# Upload with folder structure
gsutil -m cp -r ./documents/ gs://$(terraform output -raw source_bucket_name)/
```

### Monitor Translation Progress

```bash
# View translated content
gsutil ls -r gs://$(terraform output -raw translated_bucket_name)/

# Download translated files
gsutil -m cp -r gs://$(terraform output -raw translated_bucket_name)/es/ ./spanish-translations/

# Check function logs
gcloud functions logs read $(terraform output -raw function_name) --region=$(terraform output -raw region)
```

### Manual Batch Processing

```bash
# Trigger batch processing manually
gcloud scheduler jobs run $(terraform output -raw batch_scheduler_job_name) --location=$(terraform output -raw region)

# Check health status
gcloud scheduler jobs run $(terraform output -raw health_monitor_job_name) --location=$(terraform output -raw region)
```

## Monitoring and Observability

### Cloud Monitoring Dashboard

If enabled, the deployment creates a Cloud Monitoring dashboard showing:

- Cloud Function execution metrics
- Pub/Sub message flow
- Translation API usage
- Storage bucket object counts
- Error rates and latency

Access the dashboard through the Google Cloud Console or use the URL from terraform outputs.

### Logging

The pipeline includes comprehensive logging:

- **Function logs**: Translation processing details
- **Audit logs**: Complete pipeline activity
- **Error logs**: Detailed error information

View logs in Cloud Logging:

```bash
# View function logs
gcloud logging read 'resource.type="cloud_function" AND resource.labels.function_name="FUNCTION_NAME"' --limit=50

# View Pub/Sub logs
gcloud logging read 'resource.type="pubsub_topic"' --limit=50
```

## Security Features

The infrastructure implements security best practices:

- **IAM**: Least privilege service accounts
- **Storage**: Uniform bucket-level access and public access prevention
- **Encryption**: Google-managed encryption keys (CMEK optional)
- **VPC**: Optional VPC connector for enhanced network security
- **Monitoring**: Comprehensive audit logging

## Cost Optimization

Built-in cost optimization features:

- **Storage lifecycle**: Automatic transition to Coldline storage
- **Function scaling**: Configurable min/max instances
- **Batch processing**: Scheduled processing during off-peak hours
- **Resource cleanup**: Automatic deletion of old objects (configurable)

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy $(terraform output -raw project_id)
   
   # Verify API enablement
   gcloud services list --enabled
   ```

2. **Function Deployment Issues**
   ```bash
   # Check function status
   gcloud functions describe $(terraform output -raw function_name) --region=$(terraform output -raw region)
   
   # View build logs
   gcloud functions logs read $(terraform output -raw function_name) --region=$(terraform output -raw region)
   ```

3. **Translation Errors**
   ```bash
   # Check Translation API quota
   gcloud monitoring metrics list --filter="metric.type:translate"
   
   # Verify function environment variables
   gcloud functions describe $(terraform output -raw function_name) --region=$(terraform output -raw region) --format="value(serviceConfig.environmentVariables)"
   ```

### Performance Tuning

Adjust these variables for better performance:

```hcl
# Increase function instances for high volume
function_max_instances = 50
function_min_instances = 2

# Optimize memory and CPU
function_memory = "1G"
function_cpu = "2"

# Adjust batch processing
batch_processing_concurrency = 10
```

## Cleanup

To remove all infrastructure:

```bash
# Destroy all resources
terraform destroy

# Verify cleanup
gcloud projects list --filter="name:translation-*"
```

**Note**: Set `force_destroy = true` in your variables to allow Terraform to delete storage buckets with content.

## Advanced Configuration

### Custom Translation Models

For enhanced accuracy, consider implementing custom translation models:

1. Prepare training data in the required format
2. Use Cloud Translation's AutoML capabilities
3. Update the function code to use custom models

### VPC Integration

For enhanced security, deploy with VPC integration:

```hcl
vpc_connector = "projects/PROJECT_ID/locations/REGION/connectors/CONNECTOR_NAME"
```

### Multi-Region Deployment

For global deployments, consider:

- Multiple regional deployments
- Cross-region bucket replication
- Global load balancing for function endpoints

## Support

For issues with this infrastructure:

1. Check the [Google Cloud Status](https://status.cloud.google.com/)
2. Review [Cloud Translation documentation](https://cloud.google.com/translate/docs)
3. Consult [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. Review function logs and monitoring dashboards

## Contributing

To contribute improvements:

1. Test changes in a development environment
2. Ensure backward compatibility
3. Update documentation
4. Follow Terraform best practices
5. Include appropriate variable validation