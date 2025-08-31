# Social Media Video Creation with Veo 3 and Vertex AI - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless video generation pipeline using Google Cloud Platform services, including Veo 3 for video generation, Gemini for quality validation, and Cloud Functions for orchestration.

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage**: Bucket for storing generated videos, metadata, and function source code
- **Cloud Functions (3)**: 
  - Video Generator: Uses Veo 3 to create videos from text prompts
  - Quality Validator: Uses Gemini to analyze video quality and appropriateness
  - Operation Monitor: Tracks video generation status and completion
- **Service Account**: With appropriate IAM permissions for all services
- **API Enablement**: Automatically enables required Google Cloud APIs

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (gcloud)
- Access to Google Cloud Project with appropriate permissions

### Required Permissions

Your Google Cloud account needs the following IAM roles:
- `Project Editor` or equivalent custom role with:
  - `cloudfunctions.admin`
  - `storage.admin` 
  - `iam.serviceAccountAdmin`
  - `serviceusage.serviceUsageAdmin`
  - `resourcemanager.projectIamAdmin`

### Google Cloud Setup

1. **Authenticate with Google Cloud:**
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Set your project:**
   ```bash
   gcloud config set project YOUR_PROJECT_ID
   ```

3. **Enable required APIs (optional - Terraform will do this):**
   ```bash
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable storage.googleapis.com
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

4. **Request Veo 3 Access:**
   - Veo 3 is currently in preview and requires waitlist approval
   - Request access through the [official Google Cloud waitlist form](https://docs.google.com/forms/d/e/1FAIpQLSciY6O_qGg2J0A8VUcK4egJ3_Tysh-wGTl-l218XtC0e7lM_w/viewform)

## Quick Start

### 1. Initialize Terraform

```bash
cd ./gcp/social-media-video-creation-veo-vertex-ai/code/terraform/
terraform init
```

### 2. Create terraform.tfvars

Create a `terraform.tfvars` file with your project configuration:

```hcl
# Required Variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional Customizations
bucket_prefix   = "my-social-videos"
function_prefix = "my-video-gen"

# Security Settings
allow_unauthenticated_invocation = false  # Set to true for public access
force_destroy_bucket            = false  # Set to true for easy cleanup during testing

# Video Configuration
default_video_duration = 8
default_aspect_ratio   = "9:16"
video_resolution      = "720p"

# Resource Limits
max_instances = 5

# Labels for Organization
labels = {
  environment = "production"
  project     = "social-media-videos"
  team        = "ai-team"
  managed-by  = "terraform"
}
```

### 3. Plan and Apply

```bash
# Review the planned infrastructure changes
terraform plan

# Apply the infrastructure (will prompt for confirmation)
terraform apply

# Or apply without prompts
terraform apply -auto-approve
```

### 4. Get Deployment Information

```bash
# View all outputs
terraform output

# Get specific function URLs
terraform output video_generator_function_url
terraform output quality_validator_function_url
terraform output operation_monitor_function_url
```

## Configuration Variables

### Required Variables

| Variable | Description | Type | Example |
|----------|-------------|------|---------|
| `project_id` | Google Cloud project ID | string | `"my-project-123"` |

### Optional Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `region` | GCP region for deployment | string | `"us-central1"` |
| `bucket_prefix` | Prefix for storage bucket name | string | `"social-videos"` |
| `function_prefix` | Prefix for function names | string | `"video-gen"` |
| `max_instances` | Max instances per function | number | `10` |
| `allow_unauthenticated_invocation` | Enable public access | bool | `false` |
| `default_video_duration` | Default video length (seconds) | number | `8` |
| `default_aspect_ratio` | Default video aspect ratio | string | `"9:16"` |
| `video_resolution` | Video resolution | string | `"720p"` |
| `labels` | Resource labels | map(string) | See variables.tf |

For a complete list of variables, see [`variables.tf`](./variables.tf).

## Usage Examples

### 1. Generate a Video

```bash
# Get the video generator function URL
GENERATOR_URL=$(terraform output -raw video_generator_function_url)

# Generate a video
curl -X POST $GENERATOR_URL \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "A serene mountain landscape at sunset with gentle clouds",
    "duration": 8,
    "aspect_ratio": "9:16"
  }'
```

### 2. Monitor Operation Status

```bash
# Get the monitor function URL
MONITOR_URL=$(terraform output -raw operation_monitor_function_url)

# Check operation status (replace OPERATION_NAME with actual value from step 1)
curl -X POST $MONITOR_URL \
  -H "Content-Type: application/json" \
  -d '{"operation_name": "projects/PROJECT/locations/us-central1/operations/OPERATION_ID"}'
```

### 3. Validate Video Quality

```bash
# Get the validator function URL
VALIDATOR_URL=$(terraform output -raw quality_validator_function_url)

# Validate video (replace VIDEO_URI with actual generated video)
curl -X POST $VALIDATOR_URL \
  -H "Content-Type: application/json" \
  -d '{"video_uri": "gs://BUCKET_NAME/raw-videos/video_file.mp4"}'
```

### 4. Access Generated Videos

```bash
# Get the bucket name
BUCKET_NAME=$(terraform output -raw storage_bucket_name)

# List generated videos
gsutil ls gs://$BUCKET_NAME/raw-videos/

# Download a video
gsutil cp gs://$BUCKET_NAME/raw-videos/video_file.mp4 ./
```

## Monitoring and Logging

### View Function Logs

```bash
# Get function names
VIDEO_GEN_FUNCTION=$(terraform output -raw video_generator_function_name)
VALIDATOR_FUNCTION=$(terraform output -raw quality_validator_function_name)
MONITOR_FUNCTION=$(terraform output -raw operation_monitor_function_name)

# View logs
gcloud functions logs read $VIDEO_GEN_FUNCTION --region=us-central1
gcloud functions logs read $VALIDATOR_FUNCTION --region=us-central1
gcloud functions logs read $MONITOR_FUNCTION --region=us-central1
```

### Google Cloud Console Links

After deployment, access management consoles:

```bash
# Get console URLs
terraform output management_urls
```

## Security Considerations

### Authentication

- **Default**: Functions require authentication (recommended for production)
- **Public Access**: Set `allow_unauthenticated_invocation = true` for testing only
- **Service Account**: Uses least-privilege permissions

### Data Protection

- **Encryption**: Uses Google-managed encryption by default
- **Access Control**: Uniform bucket-level access enabled
- **Audit Logging**: Enabled by default for all operations

### Network Security

- **VPC**: Functions use default network (customizable via variables)
- **HTTPS**: All function endpoints use HTTPS only
- **CORS**: Configured for web browser access

## Cost Management

### Estimated Costs

The infrastructure includes several cost optimization features:

- **Pay-per-use**: Functions scale to zero when not in use
- **Lifecycle Management**: Automatic storage class transitions
- **Resource Limits**: Configurable instance limits

### Cost Breakdown (Estimated Monthly)

| Service | Usage | Estimated Cost |
|---------|-------|---------------|
| Cloud Functions | 1K invocations/month | ~$0.40 |
| Cloud Storage | 10GB | ~$0.20 |
| Vertex AI (Veo 3) | 100 videos | Variable |
| Vertex AI (Gemini) | 1K analyses | ~$2.00 |

**Note**: Costs vary significantly based on usage patterns and video generation frequency.

## Troubleshooting

### Common Issues

1. **Veo 3 Access Denied**
   ```
   Error: Failed to start video generation: Permission denied
   ```
   - **Solution**: Ensure you have Veo 3 preview access approved

2. **Function Deployment Timeout**
   ```
   Error: Operation timed out
   ```
   - **Solution**: Increase timeout in versions.tf or retry deployment

3. **Storage Permissions Error**
   ```
   Error: Failed to access video file
   ```
   - **Solution**: Check service account permissions and bucket access

4. **API Not Enabled**
   ```
   Error: API not enabled
   ```
   - **Solution**: Terraform should auto-enable APIs. Manual enable if needed:
   ```bash
   gcloud services enable aiplatform.googleapis.com
   ```

### Debug Mode

Enable debug logging:

```hcl
# In terraform.tfvars
enable_debug_logging = true
```

### Validation

Test deployment:

```bash
# Check if functions are healthy
curl -X GET $(terraform output -raw video_generator_function_url)/health
curl -X GET $(terraform output -raw quality_validator_function_url)/health
curl -X GET $(terraform output -raw operation_monitor_function_url)/health
```

## Customization

### Adding Custom Function Code

1. Modify function source code in `./functions/` directories
2. Update requirements.txt if adding dependencies
3. Re-apply Terraform:
   ```bash
   terraform apply
   ```

### Custom AI Models

To use different AI models, update variables:

```hcl
veo_model_version    = "veo-3.0-generate-preview"
gemini_model_version = "gemini-2.0-flash-exp"
```

### Network Configuration

For custom VPC deployment:

```hcl
vpc_network   = "projects/PROJECT/global/networks/my-vpc"
vpc_subnet    = "projects/PROJECT/regions/REGION/subnetworks/my-subnet"
vpc_connector = "my-vpc-connector"
```

## Cleanup

### Destroy Infrastructure

```bash
# Remove all resources (will prompt for confirmation)
terraform destroy

# Or destroy without prompts
terraform destroy -auto-approve
```

### Selective Cleanup

Remove only specific resources:

```bash
# Remove functions but keep storage
terraform destroy -target=google_cloudfunctions2_function.video_generator
terraform destroy -target=google_cloudfunctions2_function.quality_validator
terraform destroy -target=google_cloudfunctions2_function.operation_monitor
```

**Warning**: If `force_destroy_bucket = false`, you must manually empty the storage bucket before destruction.

## Support and Documentation

### Additional Resources

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Veo 3 Model Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/models/veo/3-0-generate-preview)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help

1. Check function logs for detailed error messages
2. Review Google Cloud Console for resource status
3. Validate API quotas and limits in Google Cloud Console
4. Ensure proper IAM permissions are configured

## Version Information

- **Terraform Version**: >= 1.0
- **Google Provider**: ~> 6.0
- **Cloud Functions Runtime**: Python 3.11
- **Infrastructure Version**: 1.0

For the complete infrastructure configuration, see the source files in this directory.