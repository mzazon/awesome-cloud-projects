# Terraform Infrastructure for Automated Video Generation with Veo 3

This Terraform configuration deploys a complete automated video generation system using Google Cloud's Vertex AI Veo 3 model, Cloud Storage, Cloud Functions, and Cloud Scheduler.

## Architecture Overview

The infrastructure creates:
- **Cloud Storage Buckets**: Input bucket for creative briefs, output bucket for generated videos
- **Service Account**: Dedicated service account with minimal required permissions
- **Cloud Functions**: Video generation function and orchestrator function for batch processing
- **Cloud Scheduler**: Automated and on-demand job scheduling
- **Monitoring**: Optional alert policies for production monitoring

## Prerequisites

1. **Google Cloud SDK**: Install and authenticate the gcloud CLI
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Authenticate and set default project
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform**: Install Terraform 1.5 or later
   ```bash
   # Install via package manager (example for macOS)
   brew install terraform
   
   # Or download from https://terraform.io/downloads
   ```

3. **Google Cloud Project**: Project with billing enabled and appropriate permissions
   - Owner or Editor role recommended for initial deployment
   - Minimum required: Project Editor, Security Admin, Service Account Admin

4. **Vertex AI Access**: Ensure Veo 3 is available in your project
   - Veo 3 is in public preview and available to all users as of 2025
   - Must be deployed in a supported region (us-central1 recommended)

## Quick Start

### 1. Initialize Terraform

```bash
# Clone or navigate to the terraform directory
cd /path/to/terraform

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customization
environment = "prod"
resource_prefix = "video-gen"
enable_monitoring = true
alert_notification_email = "admin@yourdomain.com"

# Storage configuration
storage_class = "STANDARD"
enable_versioning = true
lifecycle_delete_age_days = 90

# Function configuration
video_generation_memory = 1024
video_generation_timeout = 540
orchestrator_memory = 512
orchestrator_timeout = 900

# Scheduling configuration
automated_schedule = "0 9 * * MON,WED,FRI"
schedule_timezone = "America/New_York"
automated_batch_size = 10

# Video generation defaults
default_video_resolution = "1080p"
default_video_duration = 8
```

### 3. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

```bash
# Check outputs
terraform output

# Test the video generation function
curl -X POST "$(terraform output -raw video_generation_function_url)" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "A peaceful lake at sunset with mountains in the background",
    "output_bucket": "'$(terraform output -raw output_bucket_name)'",
    "resolution": "1080p"
  }'
```

## Configuration Variables

### Required Variables

| Variable | Description | Type | Example |
|----------|-------------|------|---------|
| `project_id` | Google Cloud project ID | string | `"my-video-project"` |

### Core Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `region` | GCP region for deployment | `"us-central1"` | Any Vertex AI supported region |
| `zone` | GCP zone for zonal resources | `"us-central1-a"` | Any zone in the region |
| `environment` | Environment name | `"dev"` | `dev`, `staging`, `prod`, `test` |
| `resource_prefix` | Prefix for resource names | `"video-gen"` | Any valid identifier |

### Storage Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `storage_class` | Storage class for buckets | `"STANDARD"` | `STANDARD`, `NEARLINE`, `COLDLINE`, `ARCHIVE` |
| `enable_versioning` | Enable bucket versioning | `true` | `true`, `false` |
| `lifecycle_delete_age_days` | Days before auto-deletion | `90` | 30-365 |

### Function Configuration

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `video_generation_memory` | Memory for video function (MB) | `1024` | 128-8192 |
| `video_generation_timeout` | Timeout for video function (s) | `540` | 60-3600 |
| `orchestrator_memory` | Memory for orchestrator (MB) | `512` | 128-8192 |
| `orchestrator_timeout` | Timeout for orchestrator (s) | `900` | 60-3600 |

### Scheduling Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `automated_schedule` | Cron expression for automation | `"0 9 * * MON,WED,FRI"` |
| `schedule_timezone` | Timezone for schedules | `"America/New_York"` |
| `automated_batch_size` | Briefs per automated batch | `10` |
| `manual_batch_size` | Briefs per manual batch | `5` |

### Video Generation Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `default_video_resolution` | Default video resolution | `"1080p"` | `720p`, `1080p` |
| `default_video_duration` | Default video duration (s) | `8` | 4-8 |
| `veo_model_name` | Veo model identifier | `"veo-3.0-generate-preview"` | Model name |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_monitoring` | Enable monitoring/alerts | `true` |
| `alert_notification_email` | Email for alerts | `""` |
| `function_error_threshold` | Errors before alert | `5` |

## Usage Examples

### Upload Creative Brief

```bash
# Create a creative brief JSON file
cat > my_brief.json << EOF
{
  "id": "brief_003",
  "title": "My Custom Video",
  "video_prompt": "A futuristic city skyline at night with neon lights and flying cars",
  "resolution": "1080p",
  "duration": "8s",
  "style": "cyberpunk, futuristic",
  "target_audience": "sci-fi enthusiasts",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "created_by": "content_creator"
}
EOF

# Upload to input bucket
gsutil cp my_brief.json gs://$(terraform output -raw input_bucket_name)/briefs/
```

### Trigger Manual Processing

```bash
# Trigger orchestrator function manually
curl -X POST "$(terraform output -raw orchestrator_function_url)" \
  -H "Content-Type: application/json" \
  -d '{"trigger": "manual", "batch_size": 5}'
```

### Check Generated Content

```bash
# List generated videos
gsutil ls gs://$(terraform output -raw output_bucket_name)/videos/

# List video metadata
gsutil ls gs://$(terraform output -raw output_bucket_name)/metadata/

# List batch processing reports
gsutil ls gs://$(terraform output -raw output_bucket_name)/reports/

# Download a specific video
gsutil cp gs://$(terraform output -raw output_bucket_name)/videos/generated_video_*.mp4 ./
```

### Manage Scheduled Jobs

```bash
# List scheduled jobs
gcloud scheduler jobs list --location=$(terraform output -raw region)

# Run on-demand job manually
gcloud scheduler jobs run $(terraform output -raw on_demand_scheduler_job_name) \
  --location=$(terraform output -raw region)

# Pause automated scheduling
gcloud scheduler jobs pause $(terraform output -raw automated_scheduler_job_name) \
  --location=$(terraform output -raw region)

# Resume automated scheduling
gcloud scheduler jobs resume $(terraform output -raw automated_scheduler_job_name) \
  --location=$(terraform output -raw region)
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Video generation function logs
gcloud functions logs read video-generation \
  --region=$(terraform output -raw region) \
  --gen2 \
  --limit=50

# Orchestrator function logs
gcloud functions logs read video-orchestrator \
  --region=$(terraform output -raw region) \
  --gen2 \
  --limit=50
```

### Monitor Costs

```bash
# View Vertex AI usage
gcloud ai operations list --region=$(terraform output -raw region)

# Check storage usage
gsutil du -sh gs://$(terraform output -raw input_bucket_name)
gsutil du -sh gs://$(terraform output -raw output_bucket_name)
```

### Debug Generation Issues

1. **Check Vertex AI Quotas**: Ensure sufficient quota for Veo 3 operations
2. **Verify IAM Permissions**: Service account must have `aiplatform.user` role
3. **Review Function Logs**: Check for timeout or memory issues
4. **Validate Creative Briefs**: Ensure JSON format is correct
5. **Monitor Storage Access**: Verify bucket permissions and CORS settings

## Security Considerations

### Implemented Security Features

- **Least Privilege IAM**: Service account has minimal required permissions
- **Bucket Versioning**: Protects against accidental content deletion
- **Uniform Bucket Access**: Simplifies permission management
- **Function Timeout Limits**: Prevents runaway processes
- **CORS Configuration**: Secure cross-origin access for web applications

### Additional Security Recommendations

1. **VPC Service Controls**: Consider implementing VPC-SC for data boundary protection
2. **Private Google Access**: Deploy functions in VPC with private Google access
3. **Audit Logging**: Enable Cloud Audit Logs for security monitoring
4. **Secret Manager**: Store sensitive configuration in Secret Manager
5. **Binary Authorization**: Implement for container image verification

## Cost Optimization

### Included Cost Controls

- **Lifecycle Policies**: Automatic transition to cheaper storage classes
- **Function Limits**: Memory and timeout limits prevent cost overruns
- **Batch Processing**: Efficient resource utilization through batching
- **Regional Deployment**: Single-region deployment reduces data transfer costs

### Additional Optimization Tips

1. **Use 720p for Drafts**: Generate draft videos at lower resolution first
2. **Batch Scheduling**: Schedule generation during off-peak hours
3. **Storage Classes**: Use NEARLINE/COLDLINE for archived content
4. **Function Tuning**: Optimize memory allocation based on usage patterns
5. **Monitoring Alerts**: Set up billing alerts for cost control

## Cleanup

### Destroy All Resources

```bash
# Remove all Terraform-managed resources
terraform destroy

# Confirm when prompted
```

### Manual Cleanup (if needed)

```bash
# Delete any remaining objects in buckets
gsutil -m rm -r gs://$(terraform output -raw input_bucket_name)/* || true
gsutil -m rm -r gs://$(terraform output -raw output_bucket_name)/* || true

# Delete buckets
gsutil rb gs://$(terraform output -raw input_bucket_name) || true
gsutil rb gs://$(terraform output -raw output_bucket_name) || true
```

## Support and Documentation

### Google Cloud Documentation

- [Vertex AI Veo 3 Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/models/veo/3-0-generate-preview)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)

### Terraform Documentation

- [Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify your account has necessary IAM roles
3. **Region Availability**: Confirm Vertex AI Veo 3 is available in your region
4. **Quota Limits**: Check and request quota increases if needed
5. **Billing Account**: Ensure project has an active billing account

For additional support, refer to the original recipe documentation or Google Cloud support channels.