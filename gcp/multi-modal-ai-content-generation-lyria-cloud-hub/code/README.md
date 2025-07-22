# Infrastructure as Code for Architecting Multi-Modal AI Content Generation with Lyria and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Architecting Multi-Modal AI Content Generation with Lyria and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using official Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Appropriate permissions for resource creation:
  - Cloud Functions Admin
  - Cloud Run Admin
  - Storage Admin
  - Vertex AI User
  - Service Account Admin
  - Project IAM Admin
- Vertex AI API enabled with Lyria 2 and Veo 3 model access (preview access required)
- Estimated cost: $25-50 for initial setup and testing

> **Note**: Lyria 2 and Veo 3 are currently in preview with allowlist access. Request access through the Google Cloud console or contact your Google account representative for approval.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses standard Terraform configurations with enhanced Google Cloud integration.

```bash
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create a deployment
gcloud infra-manager deployments create lyria-content-platform \
    --location=${REGION} \
    --source=. \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe lyria-content-platform \
    --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Apply infrastructure
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete infrastructure
./scripts/deploy.sh

# The script will prompt for required configuration:
# - Project ID
# - Region
# - Service account name
```

## Configuration Parameters

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `bucket_name_suffix` | Suffix for storage bucket | random | No |
| `service_account_name` | Service account name | `content-ai-sa` | No |

### Terraform Variables

Configure variables in `terraform.tfvars` or pass via command line:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
bucket_name_suffix = "unique-suffix"
service_account_name = "content-ai-sa"
```

### Bash Script Configuration

The deploy script will prompt for configuration or can be set via environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
./scripts/deploy.sh
```

## Deployed Resources

This infrastructure creates the following Google Cloud resources:

### Core Infrastructure
- **Cloud Storage Bucket**: Content pipeline storage with versioning
- **Service Account**: IAM identity for AI content generation services
- **IAM Bindings**: Vertex AI and Storage permissions

### Serverless Functions
- **Music Generation Function**: Lyria 2 integration for text-to-music
- **Video Generation Function**: Veo 3 integration for text-to-video
- **Quality Assessment Function**: Content quality evaluation and enhancement

### Orchestration Services
- **Content Orchestrator (Cloud Run)**: Multi-modal content coordination engine
- **Synchronization Engine**: Cross-modal timing and coherence management

### Monitoring & Observability
- **Cloud Monitoring**: Custom metrics and alerting policies
- **Cloud Logging**: Structured logging for content generation workflows
- **Performance Dashboards**: Real-time platform observability

## Validation & Testing

After deployment, validate the infrastructure:

### Test Music Generation

```bash
# Get the music generation function URL
MUSIC_ENDPOINT=$(gcloud functions describe music-generation \
    --region=${REGION} --format="value(httpsTrigger.url)")

# Test music generation
curl -X POST ${MUSIC_ENDPOINT} \
    -H "Content-Type: application/json" \
    -d '{
      "prompt": "Create an uplifting soundtrack for a tech product launch",
      "style": "electronic",
      "duration": 30
    }'
```

### Test Video Generation

```bash
# Get the video generation function URL
VIDEO_ENDPOINT=$(gcloud functions describe video-generation \
    --region=${REGION} --format="value(httpsTrigger.url)")

# Test video generation
curl -X POST ${VIDEO_ENDPOINT} \
    -H "Content-Type: application/json" \
    -d '{
      "prompt": "A futuristic cityscape at sunrise",
      "duration": 5,
      "resolution": "720p"
    }'
```

### Test Content Orchestration

```bash
# Get the orchestrator service URL
ORCHESTRATOR_URL=$(gcloud run services describe content-orchestrator \
    --region=${REGION} --format="value(status.url)")

# Test multi-modal content generation
curl -X POST ${ORCHESTRATOR_URL}/generate \
    -H "Content-Type: application/json" \
    -d '{
      "prompt": "Revolutionary AI breakthrough announcement",
      "style": "professional",
      "duration": 45
    }'
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete lyria-content-platform \
    --location=${REGION} \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Troubleshooting

### Common Issues

1. **Lyria 2/Veo 3 Access Denied**
   - Ensure you have preview access to these models
   - Check your project has been allowlisted for advanced generative models
   - Verify Vertex AI API is enabled

2. **Service Account Permission Issues**
   - Verify the service account has necessary IAM roles
   - Check that APIs are enabled in your project
   - Ensure you have permission to create service accounts

3. **Function Deployment Failures**
   - Check Cloud Functions quotas in your region
   - Verify source code is valid and dependencies are available
   - Review function logs for specific error messages

4. **Storage Bucket Creation Errors**
   - Ensure bucket names are globally unique
   - Check that you have Storage Admin permissions
   - Verify the region supports your chosen storage class

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="aiplatform OR storage OR cloudfunctions"

# View function logs
gcloud functions logs read music-generation --region=${REGION}

# Check Cloud Run service status
gcloud run services list --region=${REGION}

# Verify storage bucket
gsutil ls -L gs://your-bucket-name
```

## Security Considerations

- Service accounts follow principle of least privilege
- All storage buckets use IAM-based access control
- Cloud Functions use secure environment variable injection
- Content generation requests require proper authentication
- Generated content includes proper access controls

## Cost Optimization

- Cloud Functions auto-scale to zero when not in use
- Storage lifecycle policies can be configured for older content
- Cloud Run instances scale based on demand
- Monitor usage through Cloud Monitoring dashboards
- Set up billing alerts to track generation costs

## Customization

### Adding New Content Types

To extend the platform with additional content modalities:

1. Create new Cloud Functions for content generation
2. Update the orchestration service to coordinate new types
3. Modify storage structure for new content formats
4. Update quality assessment functions for new metrics

### Performance Tuning

- Adjust Cloud Function memory and timeout settings
- Configure Cloud Run CPU and memory allocation
- Optimize storage bucket regions for your users
- Implement caching for frequently requested content

### Enterprise Integration

- Configure VPC connectivity for hybrid environments
- Implement additional authentication mechanisms
- Set up audit logging for compliance requirements
- Configure network security policies

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud Status page for service incidents
3. Consult Google Cloud documentation for specific services
4. Verify your access to preview AI models

## References

- [Original Recipe](../multi-modal-ai-content-generation-lyria-cloud-hub.md)
- [Vertex AI Generative Media Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/video/overview)
- [Google Cloud Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Cloud Run Best Practices](https://cloud.google.com/run/docs/best-practices)