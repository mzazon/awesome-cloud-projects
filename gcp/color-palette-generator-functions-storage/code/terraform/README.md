# Terraform Infrastructure for Color Palette Generator

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless color palette generator using Google Cloud Platform services.

## Architecture Overview

The infrastructure deploys:
- **Cloud Function**: HTTP-triggered serverless function for color palette generation
- **Cloud Storage**: Bucket for storing generated color palettes as JSON files
- **Service Account**: Dedicated service account with least privilege permissions
- **IAM Bindings**: Public access configuration for function and storage bucket

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK**: Installed and configured with appropriate permissions
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform**: Version 1.0 or higher installed
   ```bash
   terraform --version
   ```

3. **Required Permissions**: Your Google Cloud account must have the following roles:
   - Cloud Functions Admin
   - Storage Admin
   - Service Account Admin
   - Project IAM Admin
   - Service Usage Admin

4. **APIs Enabled**: The Terraform configuration will automatically enable required APIs, or you can enable them manually:
   ```bash
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable storage.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   gcloud services enable artifactregistry.googleapis.com
   ```

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file or set variables via command line:

```hcl
# terraform.tfvars
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
function_name       = "generate-color-palette"
bucket_name_prefix  = "color-palettes"
function_memory     = 256
function_timeout    = 60
storage_class       = "STANDARD"
enable_public_access = true

labels = {
  environment = "production"
  application = "color-palette-generator"
  team        = "design-tools"
}
```

### 3. Plan and Apply

```bash
# Review the execution plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Get Outputs

```bash
# Display important output values
terraform output

# Get the function URL for testing
terraform output function_url
```

## Testing the Deployment

### Test Color Palette Generation

```bash
# Get the function URL
FUNCTION_URL=$(terraform output -raw function_url)

# Test with a blue base color
curl -X POST "$FUNCTION_URL" \
     -H "Content-Type: application/json" \
     -d '{"base_color": "#3498db"}' | jq

# Test with different colors
curl -X POST "$FUNCTION_URL" \
     -H "Content-Type: application/json" \
     -d '{"base_color": "#e74c3c"}' | jq
```

### Verify Storage

```bash
# Get bucket name and list stored palettes
BUCKET_NAME=$(terraform output -raw bucket_name)
gsutil ls gs://$BUCKET_NAME/palettes/

# View a specific palette
gsutil cat gs://$BUCKET_NAME/palettes/*.json
```

### Test Error Handling

```bash
# Test invalid color format
curl -X POST "$FUNCTION_URL" \
     -H "Content-Type: application/json" \
     -d '{"base_color": "invalid"}' | jq

# Test missing parameter
curl -X POST "$FUNCTION_URL" \
     -H "Content-Type: application/json" \
     -d '{}' | jq
```

## Configuration Options

### Input Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | string | - | Yes |
| `region` | Deployment region | string | `us-central1` | No |
| `function_name` | Cloud Function name | string | `generate-color-palette` | No |
| `bucket_name_prefix` | Storage bucket prefix | string | `color-palettes` | No |
| `function_memory` | Function memory (MB) | number | `256` | No |
| `function_timeout` | Function timeout (seconds) | number | `60` | No |
| `storage_class` | Storage class | string | `STANDARD` | No |
| `enable_public_access` | Enable public bucket access | bool | `true` | No |
| `enable_cors` | Enable CORS headers | bool | `true` | No |
| `labels` | Resource labels | map(string) | See variables.tf | No |
| `enable_api_services` | Auto-enable APIs | bool | `true` | No |

### Output Values

The configuration provides comprehensive outputs including:
- Function URL and configuration details
- Storage bucket information
- Service account details
- Testing commands and URLs
- Resource identifiers for monitoring

## Security Considerations

### Service Account Permissions

The Cloud Function uses a dedicated service account with minimal required permissions:
- `roles/storage.objectAdmin` on the palette storage bucket only
- No additional project-level permissions

### Public Access

Public access is configured for:
- **Cloud Function**: Allows unauthenticated HTTP requests (required for API functionality)
- **Storage Bucket**: Allows public read access to generated palette files (configurable via `enable_public_access`)

### Network Security

- Cloud Function uses HTTPS-only endpoints
- CORS headers are configurable for web application integration
- No VPC or firewall configuration required (serverless)

## Cost Optimization

### Function Configuration

- Memory allocation: 256MB (adjustable based on usage patterns)
- Timeout: 60 seconds (sufficient for color calculations)
- Runtime: Python 3.12 (latest supported version)

### Storage Configuration

- Storage class: STANDARD (for immediate access)
- Lifecycle rule: Automatically moves files to NEARLINE after 90 days
- Versioning enabled for palette history (can be disabled to reduce costs)

### Monitoring Costs

Use these commands to monitor usage and costs:

```bash
# Check function invocations
gcloud functions logs read $FUNCTION_NAME --limit 10

# Monitor storage usage
gsutil du -sh gs://$BUCKET_NAME

# View Cloud Monitoring metrics
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=$FUNCTION_NAME" --limit 10
```

## Customization Examples

### High-Performance Configuration

```hcl
function_memory  = 512
function_timeout = 30
storage_class   = "STANDARD"
```

### Cost-Optimized Configuration

```hcl
function_memory     = 128
storage_class      = "COLDLINE"
enable_public_access = false
```

### Development Environment

```hcl
labels = {
  environment = "development"
  purpose     = "testing"
}
enable_api_services = false  # If APIs already enabled
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   # Verify project permissions
   gcloud projects get-iam-policy $PROJECT_ID
   
   # Check service account permissions
   gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:serviceAccount:*"
   ```

2. **Function Deployment Failed**
   ```bash
   # Check build logs
   gcloud functions logs read $FUNCTION_NAME --limit 50
   
   # Verify source code archive
   ls -la function-source.zip
   ```

3. **Storage Access Issues**
   ```bash
   # Test bucket permissions
   gsutil ls gs://$BUCKET_NAME
   
   # Check IAM bindings
   gsutil iam get gs://$BUCKET_NAME
   ```

### Debug Mode

Enable detailed logging by setting environment variables:

```bash
export TF_LOG=DEBUG
terraform apply
```

## Cleanup

To remove all created resources:

```bash
# Destroy infrastructure
terraform destroy

# Clean up local files
rm -f function-source.zip
rm -rf function-source/
```

**Warning**: This will permanently delete all generated color palettes and cannot be undone.

## Support and Documentation

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Google Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Original Recipe Documentation](../README.md)

## Version History

- **v1.0**: Initial Terraform implementation
- **v1.1**: Added comprehensive outputs and validation
- **v1.2**: Enhanced security and cost optimization features