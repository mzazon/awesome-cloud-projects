# Terraform Infrastructure for GCP Image Resizing Solution

This directory contains Terraform Infrastructure as Code (IaC) for deploying an automatic image resizing solution using Google Cloud Functions and Cloud Storage. The solution creates a serverless, event-driven pipeline that automatically generates multiple thumbnail sizes when images are uploaded to a Cloud Storage bucket.

## Architecture Overview

The infrastructure creates:
- **Two Cloud Storage buckets**: One for original images, one for resized thumbnails
- **Cloud Function (Gen 2)**: Python-based serverless function for image processing
- **Eventarc trigger**: Automatically triggers the function when images are uploaded
- **IAM permissions**: Secure access controls following the principle of least privilege
- **Function source code**: Automatically generated and deployed Python code with PIL/Pillow

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK** installed and configured
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Authenticate and set project
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** installed (version >= 1.0)
   ```bash
   # Install Terraform
   wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   sudo apt update && sudo apt install terraform
   ```

3. **Required GCP APIs** (automatically enabled by this Terraform configuration):
   - Cloud Functions API
   - Cloud Storage API
   - Eventarc API
   - Cloud Build API
   - Cloud Run API

4. **Appropriate IAM permissions** for your user account:
   - Storage Admin
   - Cloud Functions Admin
   - Service Account User
   - Project IAM Admin
   - Service Usage Admin

## Quick Start

### 1. Initialize Terraform

```bash
# Clone or navigate to the terraform directory
cd terraform/

# Initialize Terraform and download providers
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment = "dev"
function_name = "my-image-resize-function"

# Custom bucket names (optional)
bucket_names = {
  original = "my-original-images-bucket"
  resized  = "my-resized-images-bucket"
}

# Function configuration
function_config = {
  memory_mb       = 512
  timeout_seconds = 120
  max_instances   = 10
  min_instances   = 0
}

# Thumbnail sizes to generate
thumbnail_sizes = [
  { width = 150, height = 150 },
  { width = 300, height = 300 },
  { width = 600, height = 600 },
  { width = 1024, height = 1024 }
]

# Labels for resource management
labels = {
  purpose     = "image-processing"
  solution    = "serverless-resize"
  managed_by  = "terraform"
  team        = "engineering"
}
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

The deployment typically takes 3-5 minutes to complete.

### 4. Test the Solution

After deployment, test the image resizing functionality:

```bash
# Create a test image
python3 -c "
from PIL import Image
img = Image.new('RGB', (1200, 800), color='red')
img.save('test-image.jpg', 'JPEG')
print('Test image created: test-image.jpg')
"

# Upload the test image (use the bucket name from terraform output)
gsutil cp test-image.jpg gs://$(terraform output -raw original_images_bucket.name)/

# Wait for processing and check results (30 seconds)
sleep 30
gsutil ls -l gs://$(terraform output -raw resized_images_bucket.name)/

# View function logs
gcloud functions logs read $(terraform output -raw resize_function.name) \
    --gen2 --region=$(terraform output -raw region) --limit=10
```

## Configuration Options

### Storage Configuration

```hcl
# Storage class for cost optimization
storage_class = "STANDARD"  # Options: STANDARD, NEARLINE, COLDLINE, ARCHIVE

# Enable uniform bucket-level access for security
enable_uniform_bucket_level_access = true
```

### Function Configuration

```hcl
function_config = {
  memory_mb       = 512      # 128-8192 MB
  timeout_seconds = 120      # 1-540 seconds
  max_instances   = 10       # Maximum concurrent executions
  min_instances   = 0        # Minimum warm instances
  runtime         = "python311"
  entry_point     = "resize_image"
}
```

### Image Processing Configuration

```hcl
# Define thumbnail sizes
thumbnail_sizes = [
  { width = 150, height = 150 },   # Small thumbnail
  { width = 300, height = 300 },   # Medium thumbnail
  { width = 600, height = 600 },   # Large thumbnail
]

# Supported image formats
supported_image_formats = ["jpg", "jpeg", "png", "bmp", "tiff"]
```

## Outputs

After successful deployment, Terraform provides comprehensive outputs including:

- **Bucket information**: Names, URLs, and self-links for both buckets
- **Function details**: Name, URL, configuration, and service account
- **Upload instructions**: Commands for testing the solution
- **Monitoring links**: Direct links to Google Cloud Console for logs and metrics
- **Cost estimates**: Information about expected costs

View all outputs:
```bash
terraform output
```

View specific output:
```bash
terraform output original_images_bucket
terraform output resize_function
terraform output upload_instructions
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Real-time logs
gcloud functions logs tail FUNCTION_NAME --gen2 --region=REGION

# Recent logs
gcloud functions logs read FUNCTION_NAME --gen2 --region=REGION --limit=50
```

### Monitor Function Performance

```bash
# Get function details
gcloud functions describe FUNCTION_NAME --gen2 --region=REGION

# View metrics in Cloud Console
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=FUNCTION_NAME" --limit=10
```

### Common Issues and Solutions

1. **Function timeout errors**: Increase `timeout_seconds` for large images
2. **Memory errors**: Increase `memory_mb` for high-resolution images
3. **Permission errors**: Verify IAM roles are properly assigned
4. **API not enabled**: Ensure all required APIs are enabled

## Cost Optimization

The solution includes several cost optimization features:

1. **Serverless architecture**: Pay only for actual processing time
2. **Lifecycle policies**: Automatically move old images to cheaper storage classes
3. **Function limits**: Prevent runaway costs with max instances
4. **Storage classes**: Use NEARLINE/COLDLINE for archival storage

### Cost Estimates

Based on typical usage:
- **Cloud Functions**: $0.40 per million invocations (2M free monthly)
- **Storage**: $0.020 per GB/month for STANDARD class
- **Compute time**: $0.0000025 per GB-second
- **Network egress**: $0.12 per GB

## Security Features

- **Uniform bucket-level access**: Consistent security policies
- **IAM principle of least privilege**: Minimal required permissions
- **Bucket versioning**: Protection against accidental deletions
- **Service account isolation**: Dedicated service account for the function
- **Event-driven triggers**: Secure, automatic processing

## Customization and Extensions

### Adding New Thumbnail Sizes

```hcl
thumbnail_sizes = [
  { width = 50, height = 50 },     # Tiny
  { width = 150, height = 150 },   # Small
  { width = 300, height = 300 },   # Medium
  { width = 600, height = 600 },   # Large
  { width = 1200, height = 1200 }  # Extra large
]
```

### Supporting Additional Image Formats

```hcl
supported_image_formats = ["jpg", "jpeg", "png", "bmp", "tiff", "webp", "gif"]
```

### Environment-Specific Deployments

```bash
# Development environment
terraform workspace new dev
terraform apply -var="environment=dev" -var="function_config.max_instances=5"

# Production environment
terraform workspace new prod
terraform apply -var="environment=prod" -var="function_config.max_instances=100"
```

## Cleanup

To remove all created resources:

```bash
# Destroy all infrastructure
terraform destroy

# Clean up local files
rm -rf function-source/
rm -f function-source.zip test-image.jpg
```

## Advanced Configuration

### Custom Function Code

To use custom function code, modify the `local_file` resources in `main.tf` or provide your own source directory.

### Integration with CI/CD

```yaml
# Example GitHub Actions workflow
name: Deploy Image Resizing Infrastructure
on:
  push:
    branches: [main]
    paths: ['terraform/**']

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - name: Terraform Init
        run: terraform init
      - name: Terraform Plan
        run: terraform plan
      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve
```

## Support and Documentation

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Original Recipe Documentation](../image-resizing-functions-storage.md)

## Contributing

To contribute improvements to this infrastructure:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

For issues or questions, please refer to the original recipe documentation or create an issue in the project repository.