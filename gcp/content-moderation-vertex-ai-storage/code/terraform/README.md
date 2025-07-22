# Content Moderation with Vertex AI and Cloud Storage - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive content moderation system using Google Cloud Platform services. The infrastructure implements automated content analysis using Vertex AI's Gemini models for both image and text moderation.

## Architecture Overview

The solution deploys:

- **Cloud Storage Buckets**: Incoming, quarantine, and approved content storage
- **Cloud Functions**: Serverless content analysis and notification handlers
- **Pub/Sub**: Event-driven messaging for reliable processing
- **Vertex AI**: Gemini model integration for multimodal content analysis
- **Monitoring**: Cloud Monitoring alerts and logging for operational visibility
- **Security**: IAM roles, service accounts, and security policies

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK** installed and configured
2. **Terraform** v1.0+ installed
3. **Google Cloud Project** with billing enabled
4. **Required permissions** in your GCP project:
   - Project Owner or Editor role
   - Or the following specific roles:
     - Storage Admin
     - Cloud Functions Admin
     - Pub/Sub Admin
     - Vertex AI Admin
     - Service Account Admin
     - Project IAM Admin

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Configure Variables

Copy the example variables file and customize for your environment:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set required values:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"
```

### 3. Plan the Deployment

Review the infrastructure that will be created:

```bash
terraform plan
```

### 4. Deploy the Infrastructure

Apply the Terraform configuration:

```bash
terraform apply
```

When prompted, type `yes` to confirm the deployment.

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | GCP project ID | `"my-content-mod-project"` |
| `region` | GCP region for resources | `"us-central1"` |
| `zone` | GCP zone for zonal resources | `"us-central1-a"` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name | `"dev"` |
| `resource_prefix` | Prefix for resource names | `"content-mod"` |
| `storage_class` | Storage class for buckets | `"STANDARD"` |
| `function_memory_mb` | Memory for functions | `1024` |
| `function_timeout` | Function timeout in seconds | `540` |
| `vertex_ai_location` | Vertex AI region | `"us-central1"` |

See `variables.tf` for all available configuration options.

## Deployment Outputs

After successful deployment, Terraform provides important outputs:

### Bucket Information
- `incoming_bucket_name`: Upload content here for processing
- `quarantine_bucket_name`: Flagged content location
- `approved_bucket_name`: Approved content location

### Function Information
- `content_moderation_function_name`: Main processing function
- `notification_function_name`: Quarantine notification function

### Usage Commands
- `upload_command`: Command to upload test content
- `function_logs_command`: Command to view function logs

## Testing the System

### 1. Upload Test Content

Use the output command to upload content:

```bash
# Upload an image
gsutil cp test-image.jpg gs://[incoming-bucket-name]/

# Upload text content
echo "This is test content" | gsutil cp - gs://[incoming-bucket-name]/test.txt
```

### 2. Monitor Processing

View function logs to monitor processing:

```bash
gcloud functions logs read [function-name] --region=[region]
```

### 3. Check Results

List processed content:

```bash
# Check approved content
gsutil ls gs://[approved-bucket-name]/

# Check quarantined content
gsutil ls gs://[quarantine-bucket-name]/
```

## Security Considerations

The infrastructure implements several security best practices:

- **IAM Roles**: Least privilege service account permissions
- **Bucket Security**: Uniform bucket-level access and public access prevention
- **Network Security**: Private Google Access for enhanced security
- **Monitoring**: Comprehensive logging and alerting

## Cost Optimization

The configuration includes several cost optimization features:

- **Lifecycle Policies**: Automatic transition to cheaper storage classes
- **Scaling**: Auto-scaling functions based on demand
- **Resource Cleanup**: Configurable force-destroy for testing environments

## Customization

### Custom Service Account

To use an existing service account:

```hcl
custom_service_account_email = "existing-sa@your-project.iam.gserviceaccount.com"
```

### Notification Integration

The notification function can be extended to integrate with:
- Email notifications
- Slack webhooks
- PagerDuty alerts
- Custom notification systems

### Advanced Configuration

For production deployments, consider:

```hcl
deletion_protection                    = true
enable_bucket_public_access_prevention = true
enable_uniform_bucket_level_access     = true
bucket_lifecycle_age_days             = 90
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Permissions**: Verify your account has necessary IAM permissions
3. **Quotas**: Check project quotas for Cloud Functions and Vertex AI
4. **Regions**: Ensure Vertex AI is available in your chosen region

### Logs and Monitoring

View detailed logs:

```bash
# Function logs
gcloud functions logs read [function-name] --region=[region]

# Storage logs
gcloud logging read "resource.type=gcs_bucket"

# Vertex AI logs
gcloud logging read "resource.type=aiplatform.googleapis.com"
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources and data. Use with caution, especially in production environments.

## Advanced Features

### Scaling Configuration

Adjust function scaling based on your needs:

```hcl
function_max_instances = 100  # Handle high traffic
function_min_instances = 2    # Reduce cold starts
```

### Multi-Region Deployment

Deploy across multiple regions for high availability:

```hcl
region = "us-central1"
vertex_ai_location = "us-central1"
bucket_location = "US"  # Multi-region bucket
```

### Custom Moderation Rules

Modify the function code to implement custom moderation policies:

1. Edit `function_code/main.py`
2. Adjust confidence thresholds
3. Add custom content categories
4. Implement business-specific rules

## Support and Documentation

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Modify as needed for your specific requirements.