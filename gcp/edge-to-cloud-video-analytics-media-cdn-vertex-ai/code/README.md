# Infrastructure as Code for Edge-to-Cloud Video Analytics with Media CDN and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Edge-to-Cloud Video Analytics with Media CDN and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Storage Admin
  - Cloud Functions Admin
  - Vertex AI User
  - Media CDN Admin
  - Service Account Admin
  - Eventarc Admin
- Estimated cost: $50-200 for testing (varies by video processing volume and CDN usage)

> **Note**: Media CDN requires approval from Google Cloud sales. Contact your account team to request access before deployment.

## Architecture Overview

This solution implements an intelligent video analytics pipeline that combines:

- **Cloud Storage**: Video content repository and analytics results storage
- **Media CDN**: Global edge distribution for optimized video delivery
- **Cloud Functions**: Event-driven processing triggers for automated workflows
- **Vertex AI**: Advanced video analytics including object detection and content classification
- **Video Intelligence API**: Comprehensive video analysis capabilities

## Quick Start

### Using Infrastructure Manager

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to infrastructure manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/video-analytics-deployment \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"
```

### Using Terraform

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Deploy the infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `video_bucket_name` | Name for video content bucket | `video-content-${random}` | No |
| `results_bucket_name` | Name for analytics results bucket | `analytics-results-${random}` | No |
| `enable_cdn` | Enable Media CDN configuration | `true` | No |
| `video_processing_memory` | Memory allocation for processing functions | `1024MB` | No |

### Terraform Variables

All variables can be customized in `terraform/variables.tf`:

```hcl
# Example terraform.tfvars
project_id = "your-project-id"
region = "us-central1"
video_bucket_name = "my-video-content"
results_bucket_name = "my-analytics-results"
enable_cdn = true
video_processing_memory = 1024
```

### Script Configuration

Environment variables for bash scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export VIDEO_BUCKET_NAME="video-content-$(date +%s)"
export RESULTS_BUCKET_NAME="analytics-results-$(date +%s)"
export ENABLE_CDN="true"
```

## Deployment Process

### Infrastructure Manager Deployment

1. **Prepare Configuration**:
   ```bash
   # Create deployment configuration
   gcloud infra-manager deployments create video-analytics-deployment \
       --location=${REGION} \
       --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com
   ```

2. **Deploy Resources**:
   ```bash
   # Apply the infrastructure
   gcloud infra-manager deployments apply video-analytics-deployment \
       --location=${REGION}
   ```

3. **Monitor Deployment**:
   ```bash
   # Check deployment status
   gcloud infra-manager deployments describe video-analytics-deployment \
       --location=${REGION}
   ```

### Terraform Deployment

1. **Initialize and Plan**:
   ```bash
   cd terraform/
   terraform init
   terraform plan -out=tfplan
   ```

2. **Apply Configuration**:
   ```bash
   terraform apply tfplan
   ```

3. **Verify Outputs**:
   ```bash
   terraform output
   ```

### Script-based Deployment

1. **Environment Setup**:
   ```bash
   # The deploy script will automatically:
   # - Enable required APIs
   # - Create storage buckets
   # - Deploy Cloud Functions
   # - Configure Vertex AI
   # - Set up Media CDN (requires manual completion)
   ```

2. **Execute Deployment**:
   ```bash
   ./scripts/deploy.sh
   ```

## Post-Deployment Configuration

### Media CDN Setup

Due to Media CDN's advanced configuration requirements, complete the setup in Google Cloud Console:

1. Navigate to **Network Services > Media CDN**
2. Create **EdgeCacheService** with your storage bucket as origin
3. Configure custom domain and SSL certificates
4. Set up cache policies for optimal video delivery

### Testing the Pipeline

1. **Upload Test Video**:
   ```bash
   # Upload a video file to trigger the analytics pipeline
   gsutil cp sample-video.mp4 gs://${VIDEO_BUCKET_NAME}/test-videos/
   ```

2. **Monitor Processing**:
   ```bash
   # Check Cloud Function logs
   gcloud functions logs read video-processor --limit 50
   
   # Check analytics results
   gsutil ls gs://${RESULTS_BUCKET_NAME}/analysis/
   ```

3. **View Results**:
   ```bash
   # View generated insights
   gsutil cat gs://${RESULTS_BUCKET_NAME}/insights/*_insights.json
   ```

## Validation & Testing

### Verify Infrastructure

```bash
# Check deployed resources
gcloud storage buckets list --filter="name:video-content OR name:analytics-results"
gcloud functions list --filter="name:video-processor OR name:advanced-video-analytics"
gcloud ai datasets list --region=${REGION}

# Test video upload and processing
gsutil cp test-video.mp4 gs://${VIDEO_BUCKET_NAME}/test/
gcloud functions logs read video-processor --limit 10
```

### Performance Testing

```bash
# Monitor CDN performance
gcloud compute network-edge-security-services list

# Check analytics processing speed
gsutil ls -l gs://${RESULTS_BUCKET_NAME}/analysis/ | head -5
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable storage.googleapis.com cloudfunctions.googleapis.com aiplatform.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Media CDN Access**:
   - Contact Google Cloud sales for Media CDN approval
   - Alternative: Use Cloud CDN for basic caching needs

4. **Function Deployment Failures**:
   ```bash
   # Check function deployment status
   gcloud functions describe video-processor --region=${REGION}
   ```

### Debugging

```bash
# Enable detailed logging
export TF_LOG=DEBUG  # For Terraform
gcloud config set core/verbosity debug  # For gcloud commands

# Check service status
gcloud services list --enabled
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete video-analytics-deployment \
    --location=${REGION} \
    --delete-policy=DELETE
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Execute cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud storage buckets list --filter="name:video-content OR name:analytics-results"
gcloud functions list --filter="name:video-processor"
```

### Manual Cleanup Verification

```bash
# Verify all resources are removed
gcloud storage buckets list | grep -E "(video-content|analytics-results)"
gcloud functions list | grep -E "(video-processor|advanced-video-analytics)"
gcloud ai datasets list --region=${REGION}
```

## Customization

### Extending Video Analytics

1. **Custom ML Models**:
   ```bash
   # Add custom Vertex AI model endpoints
   # Modify terraform/vertex_ai.tf to include custom models
   ```

2. **Additional Processing Functions**:
   ```bash
   # Add new Cloud Functions for specialized processing
   # Update terraform/cloud_functions.tf
   ```

3. **Enhanced CDN Configuration**:
   ```bash
   # Modify cache policies in terraform/media_cdn.tf
   # Add custom edge security services
   ```

### Advanced Configurations

- **Multi-region Deployment**: Modify region variables in terraform/variables.tf
- **Custom Storage Classes**: Update bucket configurations for different storage needs
- **Enhanced Security**: Add VPC Service Controls and private endpoints
- **Monitoring Integration**: Add Cloud Monitoring dashboards and alerting

## Cost Optimization

### Resource Optimization

1. **Storage Classes**:
   - Use Coldline/Archive storage for processed videos
   - Implement lifecycle policies for automatic tier transition

2. **Function Optimization**:
   - Adjust memory allocation based on video sizes
   - Implement concurrent processing limits

3. **CDN Optimization**:
   - Configure appropriate cache TTL values
   - Use compression for smaller video files

### Monitoring Costs

```bash
# Enable billing export
gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT_ID}

# Monitor resource usage
gcloud monitoring dashboards list
```

## Security Considerations

### Best Practices Implemented

- **IAM Least Privilege**: Functions use minimal required permissions
- **Storage Security**: Buckets configured with appropriate access controls
- **Network Security**: Functions deployed with VPC connector support
- **Data Encryption**: All data encrypted at rest and in transit

### Additional Security Enhancements

```bash
# Enable VPC Service Controls
gcloud access-context-manager perimeters create video-analytics-perimeter

# Configure private Google Access
gcloud compute networks subnets update default --enable-private-ip-google-access
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: Check [Cloud Documentation](https://cloud.google.com/docs)
3. **Terraform Google Provider**: See [Terraform Google Provider Docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Infrastructure Manager**: Reference [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Version Information

- **Recipe Version**: 1.0
- **Terraform Google Provider**: ~> 5.0
- **Infrastructure Manager**: Latest stable
- **Generated**: 2025-07-12

---

> **Note**: This infrastructure code follows Google Cloud's Well-Architected Framework principles. For production deployments, consider implementing additional monitoring, alerting, and security controls based on your organization's requirements.