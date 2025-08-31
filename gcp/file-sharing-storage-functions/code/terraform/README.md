# Terraform Infrastructure for GCP File Sharing Solution

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless file sharing system on Google Cloud Platform. The solution uses Cloud Storage for file storage and Cloud Functions for HTTP-triggered file upload and link generation.

## Architecture Overview

The infrastructure creates:
- **Cloud Storage Bucket**: Stores shared files with CORS configuration for web uploads
- **Cloud Functions (Gen 2)**: Two HTTP-triggered functions for file upload and link generation
- **Service Account**: Dedicated service account with least-privilege access
- **IAM Policies**: Secure access controls for Cloud Functions and public access

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK**: Install and configure `gcloud` CLI
   ```bash
   # Install gcloud CLI (if not already installed)
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Authenticate with Google Cloud
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Terraform**: Version 1.5.0 or later
   ```bash
   # Install Terraform (example for macOS using Homebrew)
   brew install terraform
   
   # Verify installation
   terraform version
   ```

3. **GCP Project**: Active project with billing enabled
   ```bash
   # Create a new project (optional)
   gcloud projects create YOUR_PROJECT_ID --name="File Sharing Project"
   
   # Set the active project
   gcloud config set project YOUR_PROJECT_ID
   
   # Enable billing (replace BILLING_ACCOUNT_ID with your billing account)
   gcloud billing projects link YOUR_PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
   ```

4. **Required Permissions**: Your user account needs the following IAM roles:
   - `roles/owner` OR the following specific roles:
     - `roles/storage.admin`
     - `roles/cloudfunctions.admin`
     - `roles/iam.serviceAccountAdmin`
     - `roles/serviceusage.serviceUsageAdmin`
     - `roles/resourcemanager.projectIamAdmin`

## Quick Start

### 1. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your project details:

```hcl
# Required
project_id = "your-gcp-project-id"

# Optional customizations
region = "us-central1"
environment = "dev"
max_file_size_mb = 10
allowed_file_extensions = ["jpg", "jpeg", "png", "pdf", "doc", "docx", "txt"]
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### 3. Test the Deployment

After deployment, test the functions using the output URLs:

```bash
# Upload a test file
curl -X POST -F "file=@test-file.txt" "$(terraform output -raw upload_function_url)"

# Generate a shareable link
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"filename":"test-file.txt"}' \
  "$(terraform output -raw link_function_url)"
```

## Configuration Reference

### Required Variables

| Variable | Description | Type |
|----------|-------------|------|
| `project_id` | GCP project ID where resources will be created | `string` |

### Optional Variables

| Variable | Description | Default | Validation |
|----------|-------------|---------|------------|
| `region` | GCP region for deployment | `us-central1` | Valid GCP region |
| `environment` | Environment name | `dev` | `dev`, `staging`, `prod` |
| `file_storage_class` | Storage class for files | `STANDARD` | `STANDARD`, `NEARLINE`, `COLDLINE`, `ARCHIVE` |
| `function_memory` | Memory allocation for functions | `256M` | `256M` to `32Gi` |
| `function_timeout` | Function timeout in seconds | `60` | `1` to `540` |
| `max_file_size_mb` | Maximum file size in MB | `10` | `1` to `5120` |
| `signed_url_expiration_hours` | Link expiration time | `1` | `1` to `168` hours |

For a complete list of variables, see `variables.tf`.

## Outputs

After successful deployment, Terraform provides these useful outputs:

- `upload_function_url`: HTTP endpoint for file uploads
- `link_function_url`: HTTP endpoint for generating shareable links
- `file_bucket_name`: Name of the Cloud Storage bucket
- `web_interface_config`: Configuration object for web integration
- `curl_upload_example`: Example curl command for uploads
- `curl_link_example`: Example curl command for link generation

View all outputs:
```bash
terraform output
```

## Usage Examples

### File Upload via HTTP

```bash
# Upload a file using curl
curl -X POST \
  -F "file=@/path/to/your/file.pdf" \
  "https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/upload-function-SUFFIX"

# Expected response
{
  "message": "File file.pdf uploaded successfully",
  "filename": "file.pdf",
  "bucket": "your-bucket-name",
  "size_bytes": 1024,
  "content_type": "application/pdf"
}
```

### Link Generation via HTTP

```bash
# Generate a shareable link using curl
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"filename":"file.pdf"}' \
  "https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/link-function-SUFFIX"

# Expected response
{
  "filename": "file.pdf",
  "download_url": "https://storage.googleapis.com/...",
  "expires_at": "2025-01-01T12:00:00Z",
  "expires_in": "1 hour(s)"
}
```

### Web Interface Integration

```javascript
// Example JavaScript integration
const config = {
  uploadUrl: "https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/upload-function-SUFFIX",
  linkUrl: "https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/link-function-SUFFIX"
};

// Upload file
async function uploadFile(file) {
  const formData = new FormData();
  formData.append('file', file);
  
  const response = await fetch(config.uploadUrl, {
    method: 'POST',
    body: formData
  });
  
  return await response.json();
}

// Generate shareable link
async function generateLink(filename) {
  const response = await fetch(config.linkUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ filename: filename })
  });
  
  return await response.json();
}
```

## Security Features

### Access Control
- **Uniform Bucket Access**: Consistent IAM-based access control
- **Service Account**: Dedicated service account with minimal required permissions
- **Public Access Prevention**: Bucket configured to prevent accidental public access

### File Security
- **File Type Validation**: Configurable allowed file extensions
- **File Size Limits**: Configurable maximum file size
- **Filename Sanitization**: Secure filename handling to prevent path traversal
- **Signed URLs**: Time-limited access with configurable expiration

### Network Security
- **CORS Configuration**: Configurable allowed origins and methods
- **HTTPS Only**: All endpoints use HTTPS encryption
- **Request Validation**: Input validation and error handling

## Cost Optimization

### Storage Lifecycle
The infrastructure includes automatic lifecycle rules:
- Files moved to NEARLINE storage after 30 days
- Files moved to COLDLINE storage after 90 days

### Function Configuration
- **Memory Optimization**: Default 256MB, adjustable based on usage
- **Timeout Settings**: Optimized timeouts to prevent unnecessary charges
- **Scaling Limits**: Configurable maximum instances to control costs

### Monitoring Costs
```bash
# Monitor storage costs
gcloud logging read "resource.type=gcs_bucket" --project=YOUR_PROJECT_ID

# Monitor function costs
gcloud logging read "resource.type=cloud_function" --project=YOUR_PROJECT_ID
```

## Monitoring and Troubleshooting

### View Function Logs
```bash
# Upload function logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=UPLOAD_FUNCTION_NAME" \
  --project=YOUR_PROJECT_ID \
  --limit=50

# Link generation function logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=LINK_FUNCTION_NAME" \
  --project=YOUR_PROJECT_ID \
  --limit=50
```

### Common Issues

1. **Permission Denied**: Ensure your account has the required IAM roles
2. **API Not Enabled**: Check that required APIs are enabled in your project
3. **Function Timeout**: Increase `function_timeout` variable if uploads fail
4. **File Too Large**: Adjust `max_file_size_mb` or client-side validation
5. **CORS Errors**: Verify `cors_origins` includes your domain

### Health Checks
```bash
# Test function endpoints
curl -I "$(terraform output -raw upload_function_url)"
curl -I "$(terraform output -raw link_function_url)"

# Check bucket status
gsutil ls -b gs://$(terraform output -raw file_bucket_name)
```

## Customization

### Adding File Type Validation
Modify the `allowed_file_extensions` variable:
```hcl
allowed_file_extensions = ["jpg", "jpeg", "png", "gif", "pdf", "doc", "docx", "txt", "zip", "mp4", "mov"]
```

### Environment-Specific Configuration
Create environment-specific `.tfvars` files:
```bash
# Development
terraform apply -var-file="dev.tfvars"

# Production
terraform apply -var-file="prod.tfvars"
```

### Custom Labels
Add custom labels for cost tracking and organization:
```hcl
labels = {
  terraform     = "true"
  application   = "file-sharing"
  team          = "engineering"
  cost-center   = "infrastructure"
  environment   = "production"
}
```

## Cleanup

To remove all created resources:

```bash
# Destroy all infrastructure
terraform destroy

# Confirm when prompted
```

**Warning**: This will permanently delete all files in the storage bucket and remove all infrastructure. Ensure you have backups of any important files.

## Advanced Configuration

### Multi-Region Deployment
For multi-region deployment, consider using Terraform workspaces:
```bash
# Create workspace for different regions
terraform workspace new us-west1
terraform workspace new europe-west1

# Deploy to specific workspace
terraform workspace select us-west1
terraform apply -var="region=us-west1"
```

### Integration with CI/CD
Example GitHub Actions workflow:
```yaml
name: Deploy File Sharing Infrastructure

on:
  push:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v1
    - name: Terraform Init
      run: terraform init
    - name: Terraform Plan
      run: terraform plan
    - name: Terraform Apply
      run: terraform apply -auto-approve
```

## Support and Contributing

### Getting Help
- Check the [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- Review [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
- See [Cloud Storage documentation](https://cloud.google.com/storage/docs)

### Best Practices
- Use version constraints in `versions.tf`
- Store Terraform state in a remote backend for team collaboration
- Use consistent naming conventions
- Apply principle of least privilege for IAM roles
- Enable audit logging for compliance requirements

---

For questions or issues with this infrastructure code, refer to the original recipe documentation or Google Cloud Platform documentation.