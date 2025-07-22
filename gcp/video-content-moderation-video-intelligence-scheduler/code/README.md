# Infrastructure as Code for Video Content Moderation Workflows with Video Intelligence API and Cloud Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Video Content Moderation Workflows with Video Intelligence API and Cloud Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Video Intelligence API
  - Cloud Scheduler
  - Cloud Functions
  - Cloud Storage
  - Pub/Sub
  - IAM role management
- Python 3.9+ (for Cloud Functions)

## Cost Estimation

Expected monthly costs for moderate usage:
- Video Intelligence API: $10-30 (based on video duration analyzed)
- Cloud Functions: $5-15 (based on execution frequency)
- Cloud Storage: $1-5 (based on video storage)
- Cloud Scheduler: $0.10
- Pub/Sub: $0.40

Total estimated cost: $16-50/month

> **Note**: Costs vary significantly based on video volume, duration, and processing frequency. Review [Video Intelligence API pricing](https://cloud.google.com/video-intelligence/pricing) for detailed cost analysis.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create video-moderation-deployment \
    --location=${REGION} \
    --source=main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment status
gcloud infra-manager deployments describe video-moderation-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project settings

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud functions list --filter="name:video-moderator"
gcloud scheduler jobs list --location=${REGION}
```

## Configuration

### Infrastructure Manager Variables

Edit the input values in your deployment command:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `schedule`: Cron schedule for video processing (default: "0 */4 * * *")
- `function_timeout`: Cloud Function timeout in seconds (default: 540)
- `function_memory`: Cloud Function memory allocation (default: "1024Mi")

### Terraform Variables

Customize `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
schedule_expression    = "0 */4 * * *"  # Every 4 hours
function_timeout      = 540             # 9 minutes
function_memory       = "1024Mi"        # 1GB memory
max_function_instances = 10             # Scaling limit
```

### Bash Script Variables

Modify environment variables in the deploy script:

```bash
# Core configuration
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Processing schedule (cron format)
export SCHEDULE="0 */4 * * *"

# Function configuration
export FUNCTION_TIMEOUT="540"
export FUNCTION_MEMORY="1024Mi"
```

## Validation & Testing

### Verify Deployment

After deployment, validate the infrastructure:

```bash
# Check Cloud Storage bucket
gsutil ls gs://video-moderation-*

# Verify Cloud Function
gcloud functions list --filter="name:video-moderator"

# Check Cloud Scheduler job
gcloud scheduler jobs list --location=${REGION}

# Verify Pub/Sub topic
gcloud pubsub topics list --filter="name:video-moderation"
```

### Test Video Processing

```bash
# Upload test video to processing folder
echo "Test video content" > test-video.txt
gsutil cp test-video.txt gs://your-bucket-name/processing/test-video.mp4

# Manually trigger scheduler job
gcloud scheduler jobs run video-moderation-job-* --location=${REGION}

# Check function logs
gcloud functions logs read video-moderator-* --region=${REGION} --limit=20

# Verify video processing results
gsutil ls gs://your-bucket-name/approved/
gsutil ls gs://your-bucket-name/flagged/
```

## Monitoring & Troubleshooting

### View Logs

```bash
# Cloud Function logs
gcloud functions logs read video-moderator-* --region=${REGION}

# Cloud Scheduler logs
gcloud logging read "resource.type=cloud_scheduler_job" --limit=50

# Video Intelligence API logs
gcloud logging read "resource.type=gce_instance AND textPayload:videointelligence" --limit=20
```

### Common Issues

1. **Video Intelligence API Quota Exceeded**
   - Check API quotas in Cloud Console
   - Request quota increase if needed
   - Implement retry logic with exponential backoff

2. **Function Timeout Errors**
   - Increase function timeout (max 540 seconds)
   - Optimize video processing logic
   - Consider breaking large videos into segments

3. **Storage Permission Errors**
   - Verify service account permissions
   - Check bucket IAM policies
   - Ensure function has Storage Admin role

## Security Considerations

### IAM Best Practices

- Service accounts use least privilege principles
- Function-specific service accounts for each component
- Regular audit of IAM permissions
- No hardcoded credentials in source code

### Data Protection

- Videos are processed and moved (not copied) to minimize exposure
- Temporary processing files are automatically cleaned up
- Audit logs track all moderation decisions
- Encryption at rest and in transit enabled by default

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete video-moderation-deployment \
    --location=${REGION} \
    --delete-policy=DELETE
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud functions list --filter="name:video-moderator"
gcloud scheduler jobs list --location=${REGION}
gcloud pubsub topics list --filter="name:video-moderation"
gsutil ls gs://video-moderation-*
```

## Customization

### Extending Video Analysis

Modify the Cloud Function to include additional Video Intelligence features:

```python
# Add to features list in Cloud Function
features = [
    videointelligence.Feature.EXPLICIT_CONTENT_DETECTION,
    videointelligence.Feature.OBJECT_TRACKING,
    videointelligence.Feature.TEXT_DETECTION,
    videointelligence.Feature.SPEECH_TRANSCRIPTION
]
```

### Custom Moderation Policies

Implement custom business logic in the `analyze_explicit_content` function:

```python
def analyze_explicit_content(result):
    # Custom thresholds based on content type
    if video_category == "educational":
        confidence_threshold = 4  # Higher threshold
    else:
        confidence_threshold = 3  # Standard threshold
    
    # Implement custom scoring logic
    return moderation_decision
```

### Integration with External Systems

Add webhook notifications or API integrations:

```python
import requests

def notify_moderation_result(video_path, moderation_result):
    webhook_url = os.environ.get('WEBHOOK_URL')
    if webhook_url:
        requests.post(webhook_url, json={
            'video': video_path,
            'action': moderation_result['action'],
            'confidence': moderation_result['confidence']
        })
```

## Performance Optimization

### Scaling Configuration

- Adjust Cloud Function max instances based on video volume
- Configure Pub/Sub message retention for reliability
- Implement video preprocessing for large files
- Use regional deployment for reduced latency

### Cost Optimization

- Implement intelligent scheduling based on upload patterns
- Use batch processing for multiple videos per function invocation
- Configure lifecycle policies for processed videos
- Monitor and optimize Video Intelligence API usage

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../video-content-moderation-video-intelligence-scheduler.md)
2. Review [Google Cloud Video Intelligence documentation](https://cloud.google.com/video-intelligence/docs)
3. Consult [Cloud Functions best practices](https://cloud.google.com/functions/docs/bestpractices)
4. Reference [Cloud Scheduler configuration guide](https://cloud.google.com/scheduler/docs)

## Version History

- v1.0: Initial implementation with basic video moderation workflow
- Infrastructure Manager, Terraform, and Bash script implementations
- Support for explicit content detection and automated file organization