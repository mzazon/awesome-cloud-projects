# Infrastructure as Code for Automated Video Content Generation using Veo 3 and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Video Content Generation using Veo 3 and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Vertex AI User
  - Storage Admin
  - Cloud Functions Admin
  - Cloud Scheduler Admin
  - Service Account Admin
- Access to Vertex AI Veo 3 (available in public preview)
- Basic understanding of Python and cloud functions
- Estimated cost: $15-25 for initial setup and testing (video generation costs $0.75 per second)

> **Note**: Veo 3 is available in public preview on Vertex AI and supports both 720p and 1080p video generation with synchronized audio.

## Architecture Overview

This solution deploys:

- **Cloud Storage Buckets**: Input bucket for creative briefs, output bucket for generated videos
- **Cloud Functions**: Video generation function and orchestrator function for batch processing
- **Cloud Scheduler**: Automated batch processing jobs (scheduled and on-demand)
- **Service Account**: Secure access to Vertex AI and Storage services
- **IAM Roles**: Least privilege permissions for function execution

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create video-generation-deployment \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/video-generation-repo" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe video-generation-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Set required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"
export TF_VAR_notification_email="admin@yourdomain.com"

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export NOTIFICATION_EMAIL="admin@yourdomain.com"

# Deploy infrastructure
./scripts/deploy.sh

# Follow script prompts for configuration
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `notification_email` | Email for alerts | - | Yes |
| `input_bucket_name` | Input bucket name | `${project_id}-video-briefs-${random_suffix}` | No |
| `output_bucket_name` | Output bucket name | `${project_id}-generated-videos-${random_suffix}` | No |
| `schedule_timezone` | Scheduler timezone | `America/New_York` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `notification_email` | Email for monitoring alerts | - | Yes |
| `function_memory` | Memory allocation for functions | `1024MB` | No |
| `function_timeout` | Function timeout | `540s` | No |
| `schedule_cron` | Cron schedule for automation | `0 9 * * MON,WED,FRI` | No |

## Testing Your Deployment

### 1. Verify Resource Creation

```bash
# Check Storage buckets
gsutil ls -p ${PROJECT_ID}

# Verify Cloud Functions
gcloud functions list --regions=${REGION} --gen2

# Check scheduled jobs
gcloud scheduler jobs list --location=${REGION}

# Verify service account
gcloud iam service-accounts list --filter="email:video-gen-sa*"
```

### 2. Upload Sample Creative Brief

```bash
# Create sample brief
cat > sample_brief.json << 'EOF'
{
  "id": "brief_001",
  "title": "Product Launch Video",
  "video_prompt": "A sleek modern smartphone floating in a minimalist white environment with soft lighting, slowly rotating to show all angles, with subtle particle effects and elegant typography appearing to highlight key features",
  "resolution": "1080p",
  "duration": "8s",
  "style": "modern, clean, professional",
  "target_audience": "tech enthusiasts",
  "brand_guidelines": {
    "colors": ["#1a73e8", "#ffffff", "#f8f9fa"],
    "tone": "innovative, premium"
  },
  "created_at": "2025-07-12T10:00:00Z",
  "created_by": "marketing_team"
}
EOF

# Upload to input bucket
export INPUT_BUCKET=$(terraform output -raw input_bucket_name 2>/dev/null || gsutil ls -p ${PROJECT_ID} | grep video-briefs | head -1 | sed 's|gs://||' | sed 's|/||')
gsutil cp sample_brief.json gs://${INPUT_BUCKET}/briefs/
```

### 3. Test Video Generation

```bash
# Get function URL
export GENERATION_URL=$(gcloud functions describe video-generation \
    --region=${REGION} \
    --gen2 \
    --format="value(serviceConfig.uri)")

# Test single video generation
curl -X POST "${GENERATION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
      "prompt": "A peaceful lake at sunset with mountains in the background",
      "output_bucket": "'$(terraform output -raw output_bucket_name 2>/dev/null || gsutil ls -p ${PROJECT_ID} | grep generated-videos | head -1 | sed 's|gs://||' | sed 's|/||')'",
      "resolution": "1080p"
    }'

# Monitor processing (video generation takes 3-5 minutes)
echo "Video generation initiated. Check output bucket in 5 minutes:"
echo "gsutil ls gs://$(terraform output -raw output_bucket_name 2>/dev/null || gsutil ls -p ${PROJECT_ID} | grep generated-videos | head -1 | sed 's|gs://||' | sed 's|/||')/videos/"
```

### 4. Trigger Batch Processing

```bash
# Run on-demand batch processing
gcloud scheduler jobs run on-demand-video-generation \
    --location=${REGION}

# Check processing logs
gcloud functions logs read video-orchestrator \
    --region=${REGION} \
    --gen2 \
    --limit=50
```

## Monitoring and Alerts

### View Function Logs

```bash
# Video generation function logs
gcloud functions logs read video-generation \
    --region=${REGION} \
    --gen2 \
    --limit=100

# Orchestrator function logs
gcloud functions logs read video-orchestrator \
    --region=${REGION} \
    --gen2 \
    --limit=100
```

### Check Scheduled Job Status

```bash
# View job execution history
gcloud scheduler jobs describe automated-video-generation \
    --location=${REGION}

# Check recent executions
gcloud logging read 'resource.type="gce_instance" AND logName="projects/'${PROJECT_ID}'/logs/cloudscheduler"' \
    --limit=10 \
    --format="table(timestamp,severity,textPayload)"
```

### Monitor Storage Usage

```bash
# Check bucket sizes
gsutil du -sh gs://${INPUT_BUCKET}
gsutil du -sh gs://$(terraform output -raw output_bucket_name 2>/dev/null || gsutil ls -p ${PROJECT_ID} | grep generated-videos | head -1 | sed 's|gs://||' | sed 's|/||')

# List generated videos
gsutil ls -l gs://$(terraform output -raw output_bucket_name 2>/dev/null || gsutil ls -p ${PROJECT_ID} | grep generated-videos | head -1 | sed 's|gs://||' | sed 's|/||')/videos/
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete video-generation-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Remove scheduled jobs
gcloud scheduler jobs delete automated-video-generation --location=${REGION} --quiet
gcloud scheduler jobs delete on-demand-video-generation --location=${REGION} --quiet

# Delete Cloud Functions
gcloud functions delete video-generation --region=${REGION} --gen2 --quiet
gcloud functions delete video-orchestrator --region=${REGION} --gen2 --quiet

# Remove storage buckets
gsutil -m rm -r gs://${INPUT_BUCKET}
gsutil -m rm -r gs://$(terraform output -raw output_bucket_name 2>/dev/null || gsutil ls -p ${PROJECT_ID} | grep generated-videos | head -1 | sed 's|gs://||' | sed 's|/||')

# Delete service account
gcloud iam service-accounts delete video-gen-sa-*@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Customization

### Modify Video Generation Parameters

Edit the function source code to adjust:
- Video duration (current: 8 seconds)
- Resolution options (720p/1080p)
- Aspect ratio (current: 16:9)
- Generation model parameters

### Adjust Scheduling

Modify the scheduler configuration:
- Change automation frequency in `schedule_cron` variable
- Add additional scheduled jobs for different content types
- Implement custom triggers via Pub/Sub

### Extend Creative Brief Format

Customize the brief template structure:
- Add brand-specific parameters
- Include content approval workflows
- Integrate with external content management systems

### Scale for Enterprise Use

For production environments:
- Implement VPC networking for security
- Add Cloud KMS for encryption at rest
- Configure Cloud Monitoring dashboards
- Set up Cloud Logging sinks for long-term storage
- Implement Cloud Build for CI/CD deployment

## Cost Optimization

### Monitor Usage

```bash
# Check function invocations
gcloud logging read 'resource.type="cloud_function" AND severity>=INFO' \
    --filter='timestamp>="2025-07-12T00:00:00Z"' \
    --format="table(timestamp,resource.labels.function_name,severity)"

# Storage cost analysis
gsutil du -sh gs://${INPUT_BUCKET}/**
gsutil du -sh gs://$(terraform output -raw output_bucket_name 2>/dev/null || gsutil ls -p ${PROJECT_ID} | grep generated-videos | head -1 | sed 's|gs://||' | sed 's|/||')/**
```

### Cost Reduction Tips

- Use 720p resolution for draft content before final 1080p generation
- Implement lifecycle policies on storage buckets
- Schedule batch processing during off-peak hours
- Monitor and optimize function memory allocation
- Set up budget alerts for video generation costs

## Troubleshooting

### Common Issues

1. **Veo 3 Access Denied**: Ensure Vertex AI API is enabled and service account has proper permissions
2. **Function Timeout**: Increase timeout settings for video generation function
3. **Storage Permission Errors**: Verify service account has Storage Admin role
4. **Scheduler Not Triggering**: Check time zone settings and cron expression format

### Debug Commands

```bash
# Test function connectivity
curl -X POST "${GENERATION_URL}" -H "Content-Type: application/json" -d '{"test": true}'

# Check service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.members:*video-gen-sa*"

# Verify API enablement
gcloud services list --enabled --filter="name:aiplatform.googleapis.com OR name:cloudfunctions.googleapis.com"
```

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation in the parent directory
2. Check Google Cloud documentation for specific services
3. Review function logs for detailed error messages
4. Ensure all prerequisites are met and APIs are enabled

## Additional Resources

- [Vertex AI Veo 3 Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/models/veo/3-0-generate-preview)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Cloud Storage Lifecycle Management](https://cloud.google.com/storage/docs/lifecycle)
- [Cloud Scheduler Configuration Guide](https://cloud.google.com/scheduler/docs)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)