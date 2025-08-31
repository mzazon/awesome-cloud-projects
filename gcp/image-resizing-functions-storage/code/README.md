# Infrastructure as Code for Automatic Image Resizing with Cloud Functions and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automatic Image Resizing with Cloud Functions and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (or Cloud Shell access)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (Cloud Functions Admin)
  - Cloud Storage (Storage Admin)
  - Eventarc (Eventarc Admin)
  - Cloud Build (Cloud Build Editor)
  - IAM (Security Admin for service account permissions)
- Python 3.11+ for local function development and testing
- Basic understanding of serverless architectures and image processing

## Architecture Overview

This infrastructure deploys:
- **Cloud Storage Buckets**: Separate buckets for original and resized images
- **Cloud Function**: Python-based image processing function with PIL/Pillow
- **Eventarc Trigger**: Automatic function execution on file uploads
- **IAM Permissions**: Service account permissions for bucket access
- **Monitoring**: Cloud Logging and monitoring integration

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager provides native Google Cloud infrastructure as code capabilities with built-in state management and Google Cloud integration.

```bash
# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/image-resize-deployment \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/image-resize-deployment
```

### Using Terraform

Terraform provides cross-platform infrastructure management with extensive provider ecosystem and state management capabilities.

```bash
# Navigate to Terraform configuration
cd terraform/

# Set required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct CLI-based deployment with step-by-step execution and immediate feedback.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployment (optional)
./scripts/test-deployment.sh
```

## Configuration Variables

### Common Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `function_name` | Cloud Function name | `resize-image-function` | No |
| `original_bucket_suffix` | Suffix for original images bucket | Random 6-char string | No |
| `resized_bucket_suffix` | Suffix for resized images bucket | Random 6-char string | No |
| `function_memory` | Memory allocation for function | `512MB` | No |
| `function_timeout` | Function timeout in seconds | `120` | No |
| `max_instances` | Maximum function instances | `10` | No |

### Infrastructure Manager Specific

```yaml
# main.yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "GCP region for deployment"
    type: string
    default: "us-central1"
```

### Terraform Specific

```hcl
# variables.tf
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for deployment"
  type        = string
  default     = "us-central1"
}
```

## Testing Your Deployment

After deployment, test the image resizing functionality:

```bash
# Create a test image
python3 -c "
from PIL import Image
img = Image.new('RGB', (1200, 800), color='red')
img.save('test-image.jpg', 'JPEG')
print('Test image created')
"

# Upload to original bucket (replace BUCKET_NAME with actual bucket name)
gsutil cp test-image.jpg gs://original-images-[SUFFIX]/

# Wait for processing (30 seconds)
sleep 30

# Verify resized images were created
gsutil ls -l gs://resized-images-[SUFFIX]/

# Expected: 3 resized versions (150x150, 300x300, 600x600)
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# View recent function executions
gcloud functions logs read resize-image-function \
    --gen2 \
    --region=us-central1 \
    --limit=50

# Follow logs in real-time
gcloud functions logs read resize-image-function \
    --gen2 \
    --region=us-central1 \
    --follow
```

### Check Function Status

```bash
# Describe function
gcloud functions describe resize-image-function \
    --gen2 \
    --region=us-central1

# List all functions
gcloud functions list --gen2
```

### Common Issues

1. **Function not triggering**: Verify Eventarc trigger is properly configured
2. **Permission errors**: Ensure service account has required Storage permissions
3. **Memory errors**: Increase function memory allocation for large images
4. **Timeout errors**: Adjust function timeout for complex processing

## Customization Options

### Modify Thumbnail Sizes

Edit the function code to change thumbnail dimensions:

```python
# In main.py
THUMBNAIL_SIZES = [
    (100, 100),   # Small thumbnail
    (250, 250),   # Medium thumbnail
    (500, 500),   # Large thumbnail
    (1000, 1000), # Extra large thumbnail
]
```

### Add Image Format Support

Extend supported formats by modifying the file extension check:

```python
# Add more formats
if not file_name.lower().endswith(('.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.gif', '.webp')):
```

### Performance Optimization

For high-volume workloads, consider:
- Increasing function memory to 1GB or 2GB
- Adjusting max instances based on expected load
- Implementing batch processing for multiple images
- Using Cloud Run for longer processing workflows

## Cost Optimization

### Free Tier Usage

- Cloud Functions: 2 million invocations/month free
- Cloud Storage: 5GB free storage
- Networking: 1GB egress free per month

### Cost Monitoring

```bash
# Enable billing export to BigQuery for detailed cost analysis
gcloud billing accounts list

# Set budget alerts
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Image Processing Budget" \
    --budget-amount=50USD
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/image-resize-deployment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run destroy script
./scripts/destroy.sh

# Verify all resources are removed
gcloud functions list --gen2
gsutil ls -p ${PROJECT_ID}
```

## Security Considerations

### Implemented Security Measures

- **Uniform Bucket-Level Access**: Consistent IAM policies across buckets
- **Least Privilege IAM**: Minimal required permissions for service accounts
- **VPC Connector**: Optional private network connectivity for functions
- **Image Format Validation**: Prevents processing of non-image files
- **Recursion Prevention**: Avoids infinite loops from processing resized images

### Additional Security Enhancements

```bash
# Enable bucket notifications audit logging
gcloud logging sinks create image-processing-audit \
    bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/audit_logs

# Add bucket lifecycle policies for automatic cleanup
gsutil lifecycle set lifecycle.json gs://original-images-[SUFFIX]
```

## Production Considerations

### Scalability

- **Auto-scaling**: Cloud Functions automatically scale from 0 to max instances
- **Concurrency**: Each function instance processes one image at a time
- **Rate Limiting**: Implement upstream rate limiting if needed

### Reliability

- **Error Handling**: Function includes comprehensive error handling
- **Retry Logic**: Cloud Functions automatically retry failed executions
- **Dead Letter Queues**: Configure for failed processing scenarios

### Monitoring

```bash
# Create custom metrics
gcloud logging metrics create image_processing_errors \
    --description="Count of image processing errors" \
    --log-filter='resource.type="cloud_function" AND severity="ERROR"'

# Set up alerting
gcloud alpha monitoring policies create --policy-from-file=alert-policy.yaml
```

## Integration Examples

### With Cloud CDN

```bash
# Create Cloud CDN distribution for resized images
gcloud compute backend-buckets create resized-images-backend \
    --gcs-bucket-name=resized-images-[SUFFIX]

gcloud compute url-maps create image-cdn-map \
    --default-backend-bucket=resized-images-backend
```

### With Firebase/Web Applications

```javascript
// JavaScript example for web integration
async function uploadAndGetThumbnails(file) {
    // Upload original image
    const uploadUrl = await getSignedUploadUrl();
    await fetch(uploadUrl, { method: 'PUT', body: file });
    
    // Wait for processing
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    // Fetch thumbnail URLs
    const thumbnails = await fetchThumbnailUrls(file.name);
    return thumbnails;
}
```

## Support and Documentation

- **Google Cloud Functions Documentation**: https://cloud.google.com/functions/docs
- **Google Cloud Storage Documentation**: https://cloud.google.com/storage/docs
- **Eventarc Documentation**: https://cloud.google.com/eventarc/docs
- **Infrastructure Manager Documentation**: https://cloud.google.com/infrastructure-manager/docs
- **Terraform Google Provider**: https://registry.terraform.io/providers/hashicorp/google/latest/docs

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud's support resources.

---

**Generated by**: Recipe Infrastructure Code Generator v1.3  
**Last Updated**: 2025-07-12  
**Compatible With**: Google Cloud CLI v400+, Terraform v1.5+, Infrastructure Manager v1.0+