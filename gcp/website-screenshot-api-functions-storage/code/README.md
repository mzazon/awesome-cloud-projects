# Infrastructure as Code for Website Screenshot API with Cloud Functions and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Website Screenshot API with Cloud Functions and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions deployment and management
  - Cloud Storage bucket creation and management
  - Cloud Build API access
  - Service account creation and IAM policy binding
- Node.js 20 runtime environment (for local testing)

## Quick Start

### Using Infrastructure Manager

```bash
# Create deployment using Infrastructure Manager
gcloud infra-manager deployments create website-screenshot-api \
    --location=us-central1 \
    --source=infrastructure-manager/main.yaml \
    --project=${PROJECT_ID}

# Check deployment status
gcloud infra-manager deployments describe website-screenshot-api \
    --location=us-central1
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform with Google Cloud provider
terraform init

# Review planned infrastructure changes
terraform plan

# Deploy the infrastructure
terraform apply

# View deployed resources and outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete infrastructure
./scripts/deploy.sh

# The script will:
# - Create a new GCP project (optional)
# - Enable required APIs
# - Create Cloud Storage bucket with public access
# - Deploy Cloud Function with Puppeteer dependencies
# - Configure environment variables and IAM permissions
```

## Architecture Overview

The deployed infrastructure includes:

- **Cloud Functions (2nd Gen)**: Serverless function running Node.js 20 with Puppeteer for screenshot generation
- **Cloud Storage Bucket**: Object storage for generated screenshot images with public read access
- **IAM Service Account**: Managed identity for secure resource access
- **Required APIs**: Cloud Functions, Cloud Storage, Cloud Build, and Cloud Run APIs

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:
- `project_id`: Target Google Cloud project
- `region`: Deployment region (default: us-central1)
- `function_memory`: Memory allocation for Cloud Function (default: 1024MB)
- `function_timeout`: Function timeout in seconds (default: 540s)

### Terraform Variables

Configure `terraform/variables.tf` or create `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_name = "screenshot-generator"
bucket_name_suffix = "unique-suffix"
function_memory = 1024
function_timeout = 540
```

### Bash Script Environment Variables

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="screenshot-generator"
```

## Testing the Deployment

Once deployed, test the screenshot API:

```bash
# Get function URL (replace with your actual function URL)
FUNCTION_URL=$(gcloud functions describe screenshot-generator \
    --gen2 --region=us-central1 \
    --format="value(serviceConfig.uri)")

# Test screenshot generation
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{"url": "https://www.google.com"}' \
    | jq '.'

# Expected response:
# {
#   "success": true,
#   "screenshotUrl": "https://storage.googleapis.com/bucket-name/screenshot-123456789.png",
#   "filename": "screenshot-123456789.png",
#   "sourceUrl": "https://www.google.com"
# }
```

## Monitoring and Logging

View function logs and metrics:

```bash
# View function logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=screenshot-generator" \
    --limit=50 --format="table(timestamp,severity,textPayload)"

# Monitor function metrics in Cloud Console
gcloud monitoring dashboards list
```

## Security Considerations

The deployed infrastructure implements security best practices:

- **IAM Least Privilege**: Function service account has minimal required permissions
- **HTTPS Only**: All communication encrypted in transit
- **Input Validation**: URL parameter validation prevents injection attacks
- **Public Storage Access**: Screenshots are publicly readable but write-protected
- **Resource Isolation**: Function runs in isolated container environment

For production deployments, consider additional security measures:
- API authentication and rate limiting
- Private storage buckets with signed URLs
- VPC connector for network isolation
- Cloud Armor for DDoS protection

## Cost Optimization

The serverless architecture provides cost-effective scaling:

- **Pay-per-use**: Only charged for actual function invocations
- **Automatic scaling**: Scales from zero to handle traffic spikes
- **Storage costs**: Approximately $0.020/GB/month for screenshot storage
- **Function costs**: $0.0000004 per invocation plus compute time

Monitor costs using Cloud Billing:

```bash
# View current billing information
gcloud billing accounts list
gcloud billing projects describe ${PROJECT_ID}
```

## Troubleshooting

Common issues and solutions:

### Function Deployment Fails
- Verify Cloud Build API is enabled
- Check project billing is enabled
- Ensure sufficient IAM permissions
- Review function logs for detailed error messages

### Screenshot Generation Errors
- Verify target URL is accessible and valid
- Check function memory allocation (increase if needed)
- Review Puppeteer browser launch configuration
- Monitor function timeout settings

### Storage Access Issues
- Verify bucket IAM permissions
- Check public access configuration
- Ensure correct bucket naming and region

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete website-screenshot-api \
    --location=us-central1

# Verify resources are cleaned up
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
cd terraform/

# Destroy all managed infrastructure
terraform destroy

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# - Delete Cloud Function
# - Remove Cloud Storage bucket and contents  
# - Clean up IAM policies
# - Optionally delete the entire project
```

## Customization

### Adding Authentication

Modify the function code to include authentication:

```javascript
// Add to index.js before processing requests
const token = req.headers.authorization;
if (!token || !validateToken(token)) {
  return res.status(401).json({ error: 'Unauthorized' });
}
```

### Custom Screenshot Options

Extend the function to support additional parameters:

```javascript
// Add viewport customization
const width = parseInt(req.query.width) || 1200;
const height = parseInt(req.query.height) || 800;
await page.setViewport({ width, height });
```

### Batch Processing

Implement multiple URL processing:

```javascript
// Support array of URLs
const urls = Array.isArray(req.body.urls) ? req.body.urls : [req.body.url];
const results = await Promise.all(urls.map(url => generateScreenshot(url)));
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: Visit [cloud.google.com/docs](https://cloud.google.com/docs)
3. **Terraform Google Provider**: Check [registry.terraform.io/providers/hashicorp/google](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Cloud Functions Troubleshooting**: Review [cloud.google.com/functions/docs/troubleshooting](https://cloud.google.com/functions/docs/troubleshooting)

## Version Information

- **Google Cloud Functions**: 2nd Generation
- **Node.js Runtime**: 20
- **Puppeteer Version**: 24.15.0
- **Terraform Google Provider**: Latest stable version
- **Infrastructure Manager**: Current Google Cloud version

This infrastructure code is generated to match the recipe implementation and follows Google Cloud best practices for serverless screenshot generation services.