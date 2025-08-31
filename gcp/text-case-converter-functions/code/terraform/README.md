# Terraform Infrastructure for Text Case Converter API

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless text case conversion API on Google Cloud Platform using Cloud Functions.

## Architecture Overview

The infrastructure deploys:
- **Cloud Function (Gen 2)**: HTTP-triggered serverless function for text processing
- **Cloud Storage Bucket**: Stores function source code
- **IAM Policies**: Configures public access (optional)
- **Required APIs**: Enables necessary GCP services

## Features

- ✅ **Serverless Architecture**: Pay-per-use with automatic scaling
- ✅ **CORS Support**: Cross-origin requests enabled for web applications
- ✅ **Multiple Case Types**: Supports uppercase, lowercase, camelCase, snake_case, kebab-case, PascalCase, and more
- ✅ **Error Handling**: Comprehensive validation and error responses
- ✅ **Security**: Configurable authentication and HTTPS by default
- ✅ **Monitoring**: Integrated with Cloud Logging and Monitoring

## Prerequisites

1. **Google Cloud Account**: With billing enabled
2. **Terraform**: Version >= 1.0 installed
3. **gcloud CLI**: Authenticated and configured
4. **Project Permissions**: 
   - Cloud Functions Admin
   - Storage Admin
   - Service Account Admin
   - Project IAM Admin

## Quick Start

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
function_name = "text-case-converter"
```

### 3. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Test the Function

Use the output command to test:

```bash
# Get the test command from Terraform output
terraform output curl_test_command

# Example test
curl -X POST https://us-central1-your-project.cloudfunctions.net/text-case-converter \
  -H "Content-Type: application/json" \
  -d '{"text": "hello world", "case_type": "camel"}'
```

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP Project ID | - | ✅ |
| `region` | Deployment region | `us-central1` | ❌ |
| `function_name` | Function name | `text-case-converter` | ❌ |

### Performance Variables

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `memory_mb` | Memory allocation | `128` | 128-8192 MB |
| `timeout_seconds` | Execution timeout | `60` | 1-540 seconds |
| `max_instances` | Maximum instances | `10` | 1-1000 |
| `min_instances` | Minimum instances | `0` | 0-max_instances |

### Security Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `allow_unauthenticated` | Public access | `true` |
| `runtime` | Python version | `python311` |

## Supported Case Types

The API supports these text transformations:

- **upper/uppercase**: `HELLO WORLD`
- **lower/lowercase**: `hello world`
- **title/titlecase**: `Hello World`
- **capitalize**: `Hello world`
- **camel/camelcase**: `helloWorld`
- **pascal/pascalcase**: `HelloWorld`
- **snake/snakecase**: `hello_world`
- **kebab/kebabcase**: `hello-world`

## API Usage

### Request Format

```json
{
  "text": "Your text here",
  "case_type": "camel"
}
```

### Response Format

```json
{
  "original": "Your text here",
  "case_type": "camel",
  "converted": "yourTextHere"
}
```

### Error Response

```json
{
  "error": "Error description"
}
```

## Cost Optimization

- **Free Tier**: 2M invocations/month included
- **Scale to Zero**: No charges when not in use
- **Right-sizing**: Adjust memory allocation based on usage
- **Source Cleanup**: Automatic deletion of old source objects

## Monitoring

### View Function Logs

```bash
# Using gcloud CLI
gcloud functions logs read text-case-converter --region=us-central1 --limit=50

# Using Terraform output
terraform output function_logs_command
```

### Monitor Performance

```bash
# Get function details
gcloud functions describe text-case-converter --region=us-central1
```

## Advanced Configuration

### Custom Environment Variables

```hcl
environment_variables = {
  LOG_LEVEL = "INFO"
  MAX_TEXT_LENGTH = "10000"
}
```

### Custom Labels

```hcl
labels = {
  environment = "production"
  team        = "api-team"
  cost-center = "engineering"
}
```

### Private Function (Authentication Required)

```hcl
allow_unauthenticated = false
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   gcloud auth application-default login
   ```

2. **API Not Enabled**
   ```bash
   gcloud services enable cloudfunctions.googleapis.com
   ```

3. **Function Build Fails**
   - Check Python syntax in templates/main.py
   - Verify requirements.txt format

### Debug Commands

```bash
# Check function status
terraform show google_cloudfunctions2_function.text_case_converter

# View function configuration
gcloud functions describe text-case-converter --region=us-central1

# Test function locally (if using Functions Framework)
functions-framework --target=text_case_converter --source=templates/main.py
```

## Cleanup

Remove all deployed resources:

```bash
terraform destroy
```

**⚠️ Warning**: This will permanently delete all resources including the function and storage bucket.

## Security Considerations

- **HTTPS Only**: All traffic is encrypted in transit
- **CORS Configured**: Restricts cross-origin access patterns
- **Input Validation**: Prevents malicious input processing
- **Error Handling**: Avoids exposing internal details
- **IAM Integration**: Supports Google Cloud IAM for authentication

## Development Workflow

1. **Local Testing**: Use Functions Framework for local development
2. **Staging**: Deploy to staging environment first
3. **Production**: Use separate Terraform workspaces or projects
4. **CI/CD**: Integrate with Cloud Build or GitHub Actions

## Support

For issues with this infrastructure:
- Review Terraform logs: `terraform plan -detailed-exitcode`
- Check GCP Console: Cloud Functions section
- View function logs: Use monitoring commands above
- Consult [GCP Documentation](https://cloud.google.com/functions/docs)

## License

This infrastructure code is provided as-is for educational and production use.