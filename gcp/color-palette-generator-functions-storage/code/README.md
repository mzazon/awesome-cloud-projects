# Infrastructure as Code for Color Palette Generator with Cloud Functions and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Color Palette Generator with Cloud Functions and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code tool
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (Cloud Functions Developer, Cloud Functions Admin)
  - Cloud Storage (Storage Admin)
  - Cloud Build (Cloud Build Editor)
  - Artifact Registry (Artifact Registry Administrator)
- For Terraform: Terraform CLI (>= 1.0) installed
- For Infrastructure Manager: `gcloud` CLI with Infrastructure Manager API enabled

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code, providing native integration with Google Cloud services and built-in state management.

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/YOUR_PROJECT_ID/locations/us-central1/deployments/color-palette-generator \
    --service-account=YOUR_SERVICE_ACCOUNT@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --git-source-repo=https://github.com/your-repo/infrastructure \
    --git-source-directory=infrastructure-manager/ \
    --git-source-ref=main
```

### Using Terraform

Terraform provides declarative infrastructure management with excellent Google Cloud Provider support and community modules for common patterns.

```bash
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review the execution plan
terraform plan -var="project_id=YOUR_PROJECT_ID" \
               -var="region=us-central1"

# Apply the infrastructure changes
terraform apply -var="project_id=YOUR_PROJECT_ID" \
                -var="region=us-central1"

# View outputs including function URL and bucket name
terraform output
```

### Using Bash Scripts

The bash scripts provide a straightforward deployment approach following the original recipe steps with enhanced automation and error handling.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh

# Test the deployed function (optional)
./scripts/test-deployment.sh
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Storage Bucket**: Stores generated color palettes as JSON files with public read access
- **Cloud Function**: HTTP-triggered serverless function that generates color palettes using color theory algorithms
- **IAM Bindings**: Appropriate permissions for function-to-storage access
- **API Services**: Required Google Cloud APIs (Cloud Functions, Cloud Storage, Cloud Build, Artifact Registry)

## Configuration Options

### Infrastructure Manager Variables

Configure the deployment by modifying variables in `infrastructure-manager/main.yaml`:

```yaml
# Project and region settings
project_id: "your-project-id"
region: "us-central1"

# Function configuration
function_name: "generate-color-palette"
function_memory: "256MB"
function_timeout: "60s"

# Storage configuration
bucket_location: "US-CENTRAL1"
bucket_storage_class: "STANDARD"
```

### Terraform Variables

Customize the deployment by setting variables in `terraform/terraform.tfvars`:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
function_name           = "generate-color-palette"
function_memory         = 256
function_timeout        = 60
bucket_storage_class    = "STANDARD"
bucket_force_destroy    = true
enable_cors             = true

# Network configuration (optional)
vpc_connector_name = "palette-connector"  # For VPC access if needed
```

### Bash Script Environment Variables

Configure the bash deployment by setting these environment variables:

```bash
# Required
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"

# Optional customizations
export FUNCTION_NAME="generate-color-palette"
export FUNCTION_MEMORY="256MB"
export FUNCTION_TIMEOUT="60s"
export BUCKET_STORAGE_CLASS="STANDARD"
```

## Testing the Deployment

After successful deployment, test the color palette generator:

```bash
# Get the function URL (varies by deployment method)
# For Terraform:
FUNCTION_URL=$(terraform output -raw function_url)

# For bash scripts:
FUNCTION_URL=$(gcloud functions describe generate-color-palette --region=$REGION --format="value(httpsTrigger.url)")

# Test palette generation
curl -X POST $FUNCTION_URL \
     -H "Content-Type: application/json" \
     -d '{"base_color": "#3498db"}' \
     | python3 -m json.tool

# Test error handling
curl -X POST $FUNCTION_URL \
     -H "Content-Type: application/json" \
     -d '{"base_color": "invalid"}' \
     | python3 -m json.tool
```

## Monitoring and Observability

Monitor your deployed infrastructure:

```bash
# View function logs
gcloud functions logs read generate-color-palette --region=$REGION

# Monitor function metrics
gcloud monitoring metrics list --filter="resource.type=cloud_function"

# Check bucket usage
gsutil du -sh gs://YOUR_BUCKET_NAME

# View function invocation statistics
gcloud functions describe generate-color-palette --region=$REGION --format="table(status.updateTime,status.versionId)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/YOUR_PROJECT_ID/locations/us-central1/deployments/color-palette-generator
```

### Using Terraform

```bash
cd terraform/

# Destroy all created resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" \
                  -var="region=us-central1"

# Remove Terraform state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify all resources are removed
gcloud functions list --regions=$REGION
gsutil ls gs://
```

## Cost Optimization

This solution is designed for cost efficiency:

- **Cloud Functions**: Pay-per-invocation pricing with 2 million free invocations per month
- **Cloud Storage**: Standard storage with lifecycle policies for cost optimization
- **No persistent compute**: Fully serverless architecture eliminates idle costs

Estimated monthly costs for moderate usage (1000 function invocations, 1GB storage):
- Cloud Functions: ~$0.20
- Cloud Storage: ~$0.02
- **Total**: Less than $0.25/month

## Security Considerations

The infrastructure implements security best practices:

- **Least Privilege IAM**: Function service account has minimal required permissions
- **HTTPS Only**: All API endpoints use TLS encryption
- **Public Read Storage**: Bucket configured for palette sharing while maintaining write protection
- **Input Validation**: Function validates all input parameters and hex color formats
- **CORS Support**: Configured for secure web application integration

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   - Verify Cloud Build API is enabled
   - Check service account permissions
   - Ensure source code directory structure is correct

2. **Function returns 500 errors**:
   - Check function logs: `gcloud functions logs read generate-color-palette --region=$REGION`
   - Verify bucket permissions and existence
   - Validate Python dependencies in requirements.txt

3. **Storage access denied**:
   - Verify bucket IAM permissions
   - Check function service account has Storage Object Creator role
   - Ensure bucket exists and is in correct project

4. **Terraform provider issues**:
   - Update to latest Google provider version
   - Run `terraform init -upgrade`
   - Check provider authentication

### Debug Commands

```bash
# Check API enablement status
gcloud services list --enabled --filter="name:(cloudfunctions.googleapis.com OR storage.googleapis.com OR cloudbuild.googleapis.com)"

# Verify function service account
gcloud functions describe generate-color-palette --region=$REGION --format="value(serviceAccountEmail)"

# Test bucket permissions
gsutil iam get gs://YOUR_BUCKET_NAME

# Check function environment variables
gcloud functions describe generate-color-palette --region=$REGION --format="value(environmentVariables)"
```

## Customization Examples

### Adding Authentication

To add authentication to the Cloud Function:

```bash
# Deploy with authentication required
gcloud functions deploy generate-color-palette \
    --runtime python312 \
    --trigger-http \
    --no-allow-unauthenticated \
    --source ./function-source
```

### Adding VPC Connectivity

For private network access:

```hcl
# In terraform/main.tf
resource "google_vpc_access_connector" "connector" {
  name          = "palette-connector"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
}

resource "google_cloudfunctions_function" "palette_generator" {
  # ... other configuration
  vpc_connector = google_vpc_access_connector.connector.id
}
```

### Adding Caching

To add Redis caching for frequently requested palettes:

```hcl
resource "google_redis_instance" "palette_cache" {
  name           = "palette-cache"
  tier           = "BASIC"
  memory_size_gb = 1
  region         = var.region
}
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Consult Terraform Google Provider documentation
4. Review Infrastructure Manager documentation

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Validate with `terraform plan` or Infrastructure Manager preview
3. Update this README with any new configuration options
4. Ensure cleanup scripts remain functional

## License

This infrastructure code follows the same license as the parent recipe repository.