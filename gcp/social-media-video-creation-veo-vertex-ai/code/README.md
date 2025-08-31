# Infrastructure as Code for Social Media Video Creation with Veo 3 and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Social Media Video Creation with Veo 3 and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Required APIs enabled:
  - Cloud Functions API
  - Cloud Storage API
  - Vertex AI API
  - Cloud Build API
  - Cloud Logging API
  - Cloud Monitoring API
- Appropriate IAM permissions for:
  - Cloud Functions deployment
  - Cloud Storage bucket creation
  - Vertex AI model access
  - Service account management
- **Important**: Veo 3 access requires waitlist approval. Request access through the [official Google Cloud waitlist form](https://docs.google.com/forms/d/e/1FAIpQLSciY6O_qGg2J0A8VUcK4egJ3_Tysh-wGTl-l218XtC0e7lM_w/viewform) before deployment.

## Architecture Overview

This solution deploys:
- 3 Cloud Functions (video generator, quality validator, status monitor)
- Cloud Storage bucket with organized folder structure
- IAM service accounts and roles for secure access
- Cloud Logging and Monitoring configurations

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create social-video-pipeline \
    --location=${REGION} \
    --service-account=$(gcloud config get-value account) \
    --git-source-repo="https://github.com/your-repo/path" \
    --git-source-directory="infrastructure-manager" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe social-video-pipeline \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Set required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud functions list --filter="name:video-*"
gsutil ls -L gs://social-videos-*
```

## Testing the Deployment

After successful deployment, test the video generation pipeline:

```bash
# Get the video generator function URL
FUNCTION_URL=$(gcloud functions describe video-generator-* \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Test video generation
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "prompt": "A colorful sunset over a mountain landscape with gentle clouds moving across the sky",
        "duration": 8,
        "aspect_ratio": "9:16"
    }'

# Monitor operation status
MONITOR_URL=$(gcloud functions describe monitor-* \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Check operation status (replace OPERATION_NAME with actual value from previous response)
curl -X POST ${MONITOR_URL} \
    -H "Content-Type: application/json" \
    -d '{"operation_name": "OPERATION_NAME"}'
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `BUCKET_NAME` | Storage bucket name | Auto-generated | No |
| `RANDOM_SUFFIX` | Resource naming suffix | Auto-generated | No |

### Infrastructure Manager Variables

```yaml
# infrastructure-manager/main.yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  enable_monitoring:
    description: "Enable Cloud Monitoring integration"
    type: bool
    default: true
```

### Terraform Variables

```hcl
# terraform/variables.tf
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Deployment region"
  type        = string
  default     = "us-central1"
}

variable "bucket_location" {
  description = "Storage bucket location"
  type        = string
  default     = "US"
}
```

## Outputs

After deployment, the following outputs are available:

- **Video Generator URL**: HTTP endpoint for video generation requests
- **Quality Validator URL**: HTTP endpoint for content validation
- **Status Monitor URL**: HTTP endpoint for operation monitoring
- **Storage Bucket Name**: Name of the created Cloud Storage bucket
- **Service Account Email**: Email of the created service account

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete social-video-pipeline \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
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

## Cost Considerations

Estimated costs for testing and development:

- **Cloud Functions**: $0.40 per million invocations + $0.0000025 per GB-second
- **Cloud Storage**: $0.02 per GB per month (Standard class)
- **Veo 3 API**: $0.30 per generated video (8-second duration)
- **Gemini 2.5 Flash**: $0.075 per 1K input tokens
- **Cloud Logging**: $0.50 per GB ingested
- **Cloud Monitoring**: $0.258 per million data points

> **Cost Optimization Tip**: Enable Cloud Storage lifecycle policies to automatically archive or delete old videos to reduce storage costs.

## Security Features

The deployment includes several security best practices:

- **Least Privilege IAM**: Service accounts with minimal required permissions
- **Private Storage**: Cloud Storage bucket not publicly accessible
- **Function Authentication**: Optional IAM-based authentication for Cloud Functions
- **Encryption**: Data encrypted at rest and in transit by default
- **Audit Logging**: Cloud Audit Logs enabled for compliance tracking

## Troubleshooting

### Common Issues

1. **Veo 3 Access Denied**
   ```bash
   # Verify Veo 3 access approval
   gcloud ai models list --region=us-central1 --filter="name:veo"
   ```

2. **Function Deployment Failures**
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # View function logs
   gcloud functions logs read video-generator-* --limit=50
   ```

3. **Storage Permission Issues**
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:serviceAccount"
   ```

4. **API Quota Exceeded**
   ```bash
   # Check quota usage
   gcloud compute project-info describe \
       --format="table(quotas.metric,quotas.usage,quotas.limit)"
   ```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Enable Cloud Functions debug logging
gcloud functions deploy video-generator-* \
    --set-env-vars="DEBUG=true" \
    --update-env-vars

# View detailed logs
gcloud logging read "resource.type=cloud_function" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"
```

## Monitoring and Alerting

### Cloud Monitoring Dashboards

The deployment creates monitoring dashboards for:
- Function invocation rates and latency
- Video generation success/failure rates
- Storage bucket usage
- API quota consumption

### Alerting Policies

Recommended alerts to set up:
- Function error rate > 5%
- Video generation time > 3 minutes
- Storage bucket usage > 80% of quota
- Veo 3 API errors

```bash
# Create sample alert policy
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/alert-policy.yaml
```

## Performance Optimization

### Function Configuration

- **Memory Allocation**: Adjust based on video complexity
  - Generator: 512MB (default) to 2GB for complex prompts
  - Validator: 1GB (default) to 4GB for high-resolution analysis
  - Monitor: 256MB (sufficient for status checks)

- **Timeout Settings**: 
  - Generator: 540s (maximum for HTTP functions)
  - Validator: 300s
  - Monitor: 60s

### Scaling Considerations

- **Concurrent Executions**: Default limit is 1000 per function
- **Regional Deployment**: Deploy in multiple regions for global users
- **Batch Processing**: Group multiple requests for cost efficiency

## Integration Examples

### API Gateway Integration

```yaml
# api-gateway.yaml
swagger: '2.0'
info:
  title: Video Generation API
  version: '1.0'
paths:
  /generate:
    post:
      operationId: generateVideo
      x-google-backend:
        address: ${VIDEO_GENERATOR_URL}
```

### Workflow Orchestration

```python
# workflows/video-pipeline.py
from google.cloud import workflows_v1

# Define workflow steps
workflow_definition = {
    "generateVideo": {
        "call": "http.post",
        "args": {
            "url": "${VIDEO_GENERATOR_URL}",
            "body": "${request}"
        }
    },
    "monitorProgress": {
        "call": "sys.sleep",
        "args": {
            "seconds": 30
        },
        "next": "checkStatus"
    }
}
```

## Support and Documentation

- **Recipe Documentation**: Refer to the original recipe for detailed implementation guidance
- **Google Cloud Documentation**: [Cloud Functions](https://cloud.google.com/functions/docs), [Vertex AI](https://cloud.google.com/vertex-ai/docs)
- **Veo 3 Documentation**: [Video Generation API](https://cloud.google.com/vertex-ai/generative-ai/docs/video/generate-videos-from-text)
- **Community Support**: [Google Cloud Community](https://cloud.google.com/community)

## Contributing

To improve this infrastructure code:

1. Test changes in a development project
2. Validate against Google Cloud best practices
3. Update documentation accordingly
4. Submit changes following the project's contribution guidelines

---

> **Note**: This infrastructure code is generated from the recipe "Social Media Video Creation with Veo 3 and Vertex AI". For the latest updates and detailed implementation guidance, refer to the original recipe documentation.