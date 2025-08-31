# Terraform Infrastructure for Automated Code Documentation with Gemini AI

This directory contains Terraform Infrastructure as Code (IaC) for deploying an automated code documentation system using Google Cloud services and Vertex AI Gemini models.

## Overview

This infrastructure deploys a complete CI/CD documentation automation solution that:

- 📚 Automatically generates API documentation from code
- 📝 Creates comprehensive README files
- 💬 Enhances code with AI-generated comments
- 🔄 Triggers on code changes via Cloud Build
- 📧 Sends notifications when documentation is updated
- 🌐 Hosts a documentation website on Cloud Storage

## Architecture Components

- **Vertex AI Gemini**: AI model for code analysis and documentation generation
- **Cloud Functions**: Serverless processing for documentation generation and notifications
- **Cloud Storage**: Centralized documentation storage with versioning
- **Cloud Build**: CI/CD pipeline for automated documentation triggers
- **Eventarc**: Event-driven notifications for documentation updates
- **IAM**: Least-privilege service accounts for secure resource access

## Prerequisites

1. **Google Cloud Project** with billing enabled
2. **Terraform** >= 1.0 installed
3. **gcloud CLI** installed and authenticated
4. **Required APIs** will be enabled automatically by Terraform
5. **Permissions**: Project Editor or equivalent custom role with:
   - Service Account Admin
   - Cloud Functions Admin
   - Storage Admin
   - Cloud Build Editor
   - Vertex AI User

## Quick Start

### 1. Clone and Navigate

```bash
cd gcp/automated-code-documentation-gemini-build/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file:

```hcl
project_id  = "your-project-id"
region      = "us-central1"
environment = "dev"
name_prefix = "my-docs"

# Optional customizations
gemini_model         = "gemini-1.5-flash"
function_memory      = 512
enable_notifications = true
enable_website       = true
enable_public_access = false  # Set to true for testing only
```

### 4. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Verify Deployment

```bash
# Check outputs
terraform output

# Test the documentation function
terraform output test_curl_command
```

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | ✅ |
| `region` | Deployment region | `us-central1` | ❌ |
| `environment` | Environment name | `dev` | ❌ |
| `name_prefix` | Resource name prefix | `doc-automation` | ❌ |

### AI Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `gemini_model` | Vertex AI model | `gemini-1.5-flash` | `gemini-1.5-flash`, `gemini-1.5-pro`, `gemini-1.0-pro` |

### Function Configuration

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `function_memory` | Memory for doc function (MB) | `512` | `128-8192` |
| `function_timeout` | Timeout for doc function (s) | `300` | `60-540` |
| `notification_function_memory` | Memory for notification function (MB) | `256` | `128-8192` |

### Storage Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `bucket_location` | Storage bucket location | `US` | `US`, `EU`, `ASIA`, specific regions |
| `storage_class` | Storage class | `STANDARD` | `STANDARD`, `NEARLINE`, `COLDLINE`, `ARCHIVE` |
| `enable_versioning` | Enable bucket versioning | `true` | `true`, `false` |

### Feature Toggles

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_notifications` | Enable notification system | `true` |
| `enable_website` | Enable documentation website | `true` |
| `enable_public_access` | Enable public function access | `false` |
| `create_build_trigger` | Create manual build trigger | `true` |

## Usage Examples

### Basic Deployment

```hcl
# terraform.tfvars
project_id = "my-project-123"
region     = "us-central1"
```

### Production Configuration

```hcl
# terraform.tfvars
project_id               = "production-docs-456"
region                   = "us-central1"
environment              = "prod"
name_prefix              = "prod-docs"
gemini_model            = "gemini-1.5-pro"
function_memory         = 1024
storage_class           = "STANDARD"
enable_public_access    = false
enable_notifications    = true
enable_website          = true

labels = {
  environment = "production"
  team        = "platform"
  cost-center = "engineering"
}
```

### Development Configuration

```hcl
# terraform.tfvars
project_id               = "dev-docs-789"
region                   = "us-central1"
environment              = "dev"
gemini_model            = "gemini-1.5-flash"
function_memory         = 256
storage_class           = "STANDARD"
enable_public_access    = true  # For testing
enable_notifications    = false
enable_website          = true
```

## Testing the Deployment

### 1. Test Documentation Function

```bash
# Get the test command from Terraform output
FUNCTION_URL=$(terraform output -raw doc_processor_function_uri)

# Test with sample code
curl -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -d '{
    "repo_path": "test.py",
    "file_content": "def hello_world():\n    \"\"\"Print hello world\"\"\"\n    print(\"Hello, World!\")",
    "doc_type": "api"
  }'
```

### 2. Verify Storage

```bash
# List generated documentation
BUCKET_NAME=$(terraform output -raw documentation_bucket_name)
gsutil ls -r gs://$BUCKET_NAME/
```

### 3. Test Build Trigger

```bash
# Manually trigger documentation build
TRIGGER_NAME=$(terraform output -raw build_trigger_name)
gcloud builds triggers run $TRIGGER_NAME --region=$(terraform output -raw region)
```

### 4. Access Documentation Website

```bash
# Get website URL
terraform output documentation_website_url
```

## Outputs Reference

### Key Outputs

- `documentation_bucket_name`: Storage bucket for documentation
- `doc_processor_function_uri`: Documentation function endpoint
- `documentation_website_url`: Website URL (if enabled)
- `service_account_email`: Service account for integration
- `build_trigger_name`: Build trigger name (if created)

### Console URLs

- `storage_console_url`: Google Cloud Console for storage
- `functions_console_url`: Google Cloud Console for functions
- `build_console_url`: Google Cloud Console for Cloud Build

## Customization

### Adding Custom Notification Integrations

Edit `notification-source/main.py` to add:

```python
# Example: Slack integration
def send_slack_notification(message):
    # Implement Slack webhook integration
    pass

# Example: Email integration
def send_email_notification(message):
    # Implement email notification
    pass
```

### Custom Documentation Prompts

Edit `function-source/main.py` to customize AI prompts:

```python
def generate_custom_prompt(doc_type, file_content):
    # Add your custom prompt logic
    pass
```

### Additional Storage Lifecycle Rules

```hcl
lifecycle_rules = [
  {
    action = {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition = {
      age = 30
    }
  },
  {
    action = {
      type = "Delete"
    }
    condition = {
      age = 365
    }
  }
]
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Documentation function logs
gcloud functions logs read $(terraform output -raw doc_processor_function_name) \
  --region=$(terraform output -raw region) \
  --limit=50

# Notification function logs (if enabled)
gcloud functions logs read $(terraform output -raw notification_function_name) \
  --region=$(terraform output -raw region) \
  --limit=50
```

### Monitor Cloud Build

```bash
# List recent builds
gcloud builds list --limit=10

# View specific build
gcloud builds describe BUILD_ID
```

### Check Storage Usage

```bash
# Storage usage summary
gsutil du -sh gs://$(terraform output -raw documentation_bucket_name)

# Detailed file listing
gsutil ls -lh gs://$(terraform output -raw documentation_bucket_name)/**
```

## Cost Optimization

### Estimated Monthly Costs

- **Cloud Functions**: $0.40 per 1M invocations + $0.0000025/GB-second
- **Cloud Storage**: $0.020/GB/month (Standard), $0.010/GB/month (Nearline)
- **Vertex AI**: $0.000125 per 1K input tokens, $0.000375 per 1K output tokens
- **Cloud Build**: $0.003/build-minute

### Cost Reduction Tips

1. **Use Nearline/Coldline storage** for archival documentation
2. **Reduce function memory** if not needed
3. **Enable lifecycle rules** to automatically transition old files
4. **Use gemini-1.5-flash** instead of pro model for cost savings
5. **Disable notifications** in development environments

## Security Considerations

### Network Security

- Functions use **ALLOW_INTERNAL_ONLY** ingress by default
- Public access disabled unless explicitly enabled
- IAM-based authentication for all function calls

### Data Security

- **Uniform bucket-level access** enabled
- **Least privilege** service account permissions
- **Encryption at rest** using Google-managed keys
- **Audit logging** via Cloud Audit Logs

### Access Control

- Service account with minimal required permissions
- IAM conditions for granular access control
- Website access limited to specific paths (if public)

## Cleanup

### Destroy Infrastructure

```bash
# Remove all resources
terraform destroy

# Verify cleanup
gcloud projects list --filter="projectId:$(terraform output -raw project_id)"
```

### Manual Cleanup (if needed)

```bash
# Delete storage bucket manually
gsutil -m rm -r gs://$(terraform output -raw documentation_bucket_name)

# Delete service account manually
gcloud iam service-accounts delete $(terraform output -raw service_account_email)
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure required APIs are enabled
2. **Permission Denied**: Check service account permissions
3. **Function Timeout**: Increase timeout or reduce input size
4. **Storage Access**: Verify bucket permissions and IAM roles

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# Verify service account
gcloud iam service-accounts describe $(terraform output -raw service_account_email)

# Test function locally (requires Cloud Functions Framework)
cd function-source/
functions-framework --target=generate_docs --port=8080
```

## Support

For issues with this infrastructure:

1. Check the [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
2. Review [Google Cloud Documentation](https://cloud.google.com/docs)
3. Check the original recipe documentation
4. Use `terraform plan` to debug configuration issues

## Contributing

To contribute improvements:

1. Test changes in a development environment
2. Update variable descriptions and validation rules
3. Add appropriate outputs for new resources
4. Update this README with new features
5. Follow Terraform best practices and style guidelines