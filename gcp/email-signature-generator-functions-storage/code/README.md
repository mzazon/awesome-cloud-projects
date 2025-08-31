# Infrastructure as Code for Email Signature Generator with Cloud Functions and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Email Signature Generator with Cloud Functions and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (Developer role)
  - Cloud Storage (Admin role)
  - Cloud Build (Editor role)
  - Service Account (Admin role)
- For Terraform: Terraform CLI installed (version >= 1.0)

## Quick Start

### Using Infrastructure Manager

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy infrastructure
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/email-signature-generator \
    --service-account SERVICE_ACCOUNT_EMAIL \
    --local-source infrastructure-manager/ \
    --input-values project_id=PROJECT_ID,region=us-central1
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Deploy infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Function (Gen 2)**: HTTP-triggered serverless function for signature generation
- **Cloud Storage Bucket**: Public bucket for storing generated HTML signatures
- **IAM Service Account**: Service account with minimal required permissions
- **IAM Bindings**: Appropriate permissions for Cloud Function to access Storage

## Configuration Options

### Infrastructure Manager Variables

Edit the `infrastructure-manager/main.yaml` file or provide input values:

- `project_id`: Your Google Cloud Project ID
- `region`: Deployment region (default: us-central1)
- `bucket_name`: Storage bucket name (auto-generated if not provided)
- `function_name`: Cloud Function name (default: generate-signature)

### Terraform Variables

Available variables in `terraform/variables.tf`:

```hcl
# Required
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

# Optional with defaults
variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "bucket_name" {
  description = "Name for the Cloud Storage bucket"
  type        = string
  default     = ""  # Auto-generated if empty
}

variable "function_name" {
  description = "Name for the Cloud Function"
  type        = string
  default     = "generate-signature"
}
```

### Script Environment Variables

Required environment variables for bash scripts:

```bash
export PROJECT_ID="your-project-id"           # Required
export REGION="us-central1"                   # Optional, defaults to us-central1
export BUCKET_NAME="custom-bucket-name"       # Optional, auto-generated if not set
export FUNCTION_NAME="generate-signature"     # Optional, defaults to generate-signature
```

## Testing the Deployment

After successful deployment, test the email signature generator:

```bash
# Get the function URL (from Terraform output or gcloud)
FUNCTION_URL=$(gcloud functions describe generate-signature \
    --gen2 \
    --region=us-central1 \
    --format="value(serviceConfig.uri)")

# Test with sample data
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Jane Smith",
        "title": "Senior Developer", 
        "company": "Tech Solutions Inc",
        "email": "jane.smith@techsolutions.com",
        "phone": "+1 (555) 987-6543",
        "website": "https://techsolutions.com"
    }'
```

Expected response includes:
- `success: true`
- `signature_html`: Generated HTML signature
- `storage_url`: Public URL to stored signature
- `generated_at`: Timestamp

## Cost Estimation

Estimated monthly costs (assuming typical usage):

- **Cloud Functions**: $0.00 - $0.40 (2M free invocations/month)
- **Cloud Storage**: $0.00 - $0.10 (5GB free storage)
- **Cloud Build**: $0.00 - $0.05 (120 minutes free build time)

**Total**: $0.00 - $0.50/month (most usage falls within free tier)

## Security Considerations

This deployment implements several security best practices:

- **Least Privilege IAM**: Service account has minimal required permissions
- **Public Storage Access**: Only generated signatures are publicly readable
- **CORS Configuration**: Function includes proper CORS headers
- **Input Validation**: Function validates and sanitizes input parameters

For production environments, consider:
- Implementing authentication/authorization
- Adding rate limiting
- Using private storage with signed URLs
- Implementing input validation and sanitization

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/email-signature-generator
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure your account has required IAM roles
2. **API Not Enabled**: Run `gcloud services enable cloudfunctions.googleapis.com storage.googleapis.com cloudbuild.googleapis.com`
3. **Billing Not Enabled**: Enable billing on your Google Cloud Project
4. **Function Not Responding**: Check function logs with `gcloud functions logs read generate-signature --gen2`

### Validation Commands

```bash
# Check function status
gcloud functions describe generate-signature --gen2 --region=us-central1

# List storage bucket contents
gsutil ls gs://YOUR_BUCKET_NAME/

# View function logs
gcloud functions logs read generate-signature --gen2 --limit=50
```

## Customization

### Adding Custom Templates

To add signature templates:

1. Modify the Cloud Function source code in `main.py`
2. Add template selection logic
3. Store templates in Cloud Storage
4. Update function to reference stored templates

### Implementing Authentication

To add authentication:

1. Enable Firebase Authentication or Google Identity
2. Modify function to validate tokens
3. Update IAM bindings for authenticated access
4. Remove `--allow-unauthenticated` from function deployment

### Adding Web Interface

To create a web frontend:

1. Deploy static website to Cloud Storage or Cloud Run
2. Create HTML form for signature parameters
3. Use JavaScript to call the Cloud Function API
4. Display generated signatures with preview

## Monitoring and Observability

### Cloud Monitoring

The deployment automatically enables basic monitoring. View metrics in the Google Cloud Console:

- Function invocations and duration
- Error rates and success rates
- Storage bucket usage
- Build pipeline status

### Logging

Access logs through:

```bash
# Function logs
gcloud functions logs read generate-signature --gen2

# Cloud Build logs
gcloud builds list --limit=10
```

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud documentation:
   - [Cloud Functions](https://cloud.google.com/functions/docs)
   - [Cloud Storage](https://cloud.google.com/storage/docs)
   - [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
3. Validate IAM permissions and API enablement
4. Check Cloud Build logs for deployment issues

## Version Information

- **Infrastructure Manager**: Uses latest Google Cloud resource types
- **Terraform**: Compatible with Google Cloud Provider >= 4.0
- **Cloud Functions**: Uses Generation 2 runtime (Python 3.12)
- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12