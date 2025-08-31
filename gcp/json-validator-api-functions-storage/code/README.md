# Infrastructure as Code for JSON Validator API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "JSON Validator API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (create, deploy, manage)
  - Cloud Storage (create buckets, manage objects)
  - Cloud Build (for function deployment)
  - Service Usage (enable APIs)
  - IAM (create service accounts if needed)
- For Terraform: Terraform CLI installed (version >= 1.0)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native IaC service that manages Terraform configurations as a managed service.

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create the deployment
gcloud infra-manager deployments create json-validator-deployment \
    --location=${REGION} \
    --source-git-repo="https://github.com/your-repo/path" \
    --source-git-repo-dir="gcp/json-validator-api-functions-storage/code/infrastructure-manager" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe json-validator-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# Get the function URL from outputs
terraform output function_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the function URL and storage bucket name
```

## Configuration Options

### Infrastructure Manager Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: "us-central1")
- `function_name`: Name for the Cloud Function (default: auto-generated)
- `bucket_name`: Name for the storage bucket (default: auto-generated)
- `function_memory`: Memory allocation for the function (default: "256Mi")
- `function_timeout`: Function timeout in seconds (default: 60)

### Terraform Variables

Edit `terraform/terraform.tfvars` or provide via command line:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_name = "json-validator-custom"
bucket_name = "json-files-custom-bucket"
function_memory = "512Mi"
function_timeout = 120
```

### Bash Script Configuration

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="custom-json-validator"  # Optional
export BUCKET_NAME="custom-json-bucket"       # Optional
```

## Testing the Deployment

After successful deployment, test the JSON validator API:

```bash
# Get function URL (from terraform output or deployment logs)
FUNCTION_URL="https://your-region-your-project.cloudfunctions.net/your-function"

# Test health check
curl -X GET "${FUNCTION_URL}"

# Test JSON validation
curl -X POST "${FUNCTION_URL}" \
     -H "Content-Type: application/json" \
     -d '{"name": "test", "value": 123}'

# Test invalid JSON
curl -X POST "${FUNCTION_URL}" \
     -H "Content-Type: application/json" \
     -d '{"name": "test", "value": 123'

# Test storage file processing (upload a file first)
curl -X GET "${FUNCTION_URL}?bucket=your-bucket-name&file=test.json"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete json-validator-deployment \
    --location=${REGION} \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm when prompted to delete resources
```

## Architecture Overview

The infrastructure creates:

1. **Cloud Function**: Serverless JSON validation API
   - HTTP trigger with public access
   - Python 3.11 runtime
   - Configurable memory (256MB default) and timeout (60s default)
   - CORS enabled for web applications

2. **Cloud Storage Bucket**: 
   - Standard storage class for cost efficiency
   - Versioning enabled for data protection
   - Public read access for function integration

3. **Required APIs**: Automatically enabled
   - Cloud Functions API
   - Cloud Build API (for function deployment)
   - Cloud Storage API

4. **IAM Permissions**: Function service account with minimal required permissions

## Security Considerations

- Function is deployed with `allow-unauthenticated` for public API access
- Storage bucket has public read access - modify for production use
- Consider implementing API Gateway for production deployments
- Use Cloud Armor for DDoS protection if needed
- Enable audit logging for compliance requirements

```bash
# Example: Add authentication requirement (post-deployment)
gcloud functions remove-iam-policy-binding FUNCTION_NAME \
    --member="allUsers" \
    --role="roles/cloudfunctions.invoker" \
    --region=REGION
```

## Cost Optimization

- Function uses minimal memory allocation (256MB) for cost efficiency
- Storage bucket uses Standard class - consider Coldline for archival data
- Function has max instances limit (10) to control costs
- Consider using Cloud Scheduler for periodic cleanup of old files

## Monitoring and Logging

Access function logs and metrics:

```bash
# View function logs
gcloud functions logs read FUNCTION_NAME --region=REGION --limit=50

# View function metrics in Cloud Console
gcloud functions describe FUNCTION_NAME --region=REGION
```

Set up monitoring alerts:

```bash
# Create alert policy for function errors (example)
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring-policy.yaml
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   - Verify Cloud Build API is enabled
   - Check function code syntax in `main.py`
   - Ensure requirements.txt has correct dependencies

2. **Storage access errors**:
   - Verify bucket exists and has correct permissions
   - Check IAM roles for function service account

3. **CORS errors in web applications**:
   - Function includes CORS headers by default
   - Verify browser is not caching preflight responses

### Debug Commands

```bash
# Check function status
gcloud functions describe FUNCTION_NAME --region=REGION

# Test function locally (requires Functions Framework)
functions-framework --target=json_validator_api --debug

# Validate storage bucket access
gsutil ls -b gs://BUCKET_NAME
```

## Customization

### Extending the Function

Modify `main.py` to add features:
- JSON schema validation
- Data transformation
- Integration with other GCP services
- Custom authentication

### Infrastructure Modifications

- Add Cloud Endpoints for API management
- Integrate with Cloud Pub/Sub for async processing
- Add Cloud Monitoring alerts and dashboards
- Implement VPC connectivity for private resources

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud Functions documentation
3. Consult Google Cloud Storage documentation
4. For Terraform issues, see the Google Cloud provider documentation

## Version Compatibility

- **Google Cloud CLI**: Latest version recommended
- **Terraform**: >= 1.0 with Google Cloud provider >= 4.0
- **Python Runtime**: 3.11 (specified in function configuration)
- **Functions Framework**: 3.8.1 (specified in requirements.txt)

## License

This infrastructure code is provided as part of the cloud recipes collection. Refer to the repository license for terms of use.