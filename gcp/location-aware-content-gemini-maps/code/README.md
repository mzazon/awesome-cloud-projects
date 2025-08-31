# Infrastructure as Code for Location-Aware Content Generation with Gemini and Maps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Location-Aware Content Generation with Gemini and Maps".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Appropriate IAM permissions for:
  - Cloud Functions (create, deploy, delete)
  - Cloud Storage (create buckets, manage objects)
  - Vertex AI (access models, manage endpoints)
  - Service Accounts (create, manage IAM bindings)
  - Project management (enable APIs, configure billing)
- Billing account configured outside the European Economic Area (EEA)
- Python 3.12+ for local testing and validation

> **Important**: Google Maps grounding requires specific billing permissions and is currently in Preview with geographic restrictions. Ensure your billing account meets the requirements for accessing this feature.

## Architecture Overview

The infrastructure deploys:
- **Cloud Functions Gen2**: Serverless compute for content generation API
- **Cloud Storage**: Bucket for storing generated content with versioning
- **Service Account**: IAM identity with appropriate permissions for Maps grounding
- **API Enablement**: Required Google Cloud APIs for Vertex AI and Maps integration

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create location-content-deployment \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/terraform.tfvars"

# Check deployment status
gcloud infra-manager deployments describe location-content-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id"

# View outputs
terraform output
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

# Test the deployment
./scripts/test.sh
```

## Configuration Variables

### Infrastructure Manager / Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `generate-location-content` | No |
| `bucket_name_suffix` | Unique suffix for storage bucket | Random 6-char string | No |
| `service_account_name` | Service account name | `location-content-sa` | No |
| `function_memory` | Function memory allocation | `512Mi` | No |
| `function_timeout` | Function timeout in seconds | `60` | No |
| `max_instances` | Maximum function instances | `10` | No |

### Environment Variables for Scripts

```bash
# Required
export PROJECT_ID="your-project-id"

# Optional (with defaults)
export REGION="us-central1"
export ZONE="us-central1-a"
```

## Testing the Deployment

After successful deployment, test the content generation API:

```bash
# Get the function URL
FUNCTION_URL=$(gcloud functions describe generate-location-content \
    --region=${REGION} \
    --format="value(serviceConfig.uri)")

# Test content generation
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "location": "Golden Gate Bridge, San Francisco",
      "content_type": "travel",
      "audience": "photographers"
    }' | python3 -m json.tool
```

Expected response includes:
- Generated content using Maps grounding
- Location and content type information
- Grounding sources (if available)
- Timestamp and model information

## Monitoring and Logs

### View Function Logs

```bash
# View recent function logs
gcloud functions logs read generate-location-content \
    --region=${REGION} \
    --limit=50

# Follow logs in real-time
gcloud functions logs tail generate-location-content \
    --region=${REGION}
```

### Monitor Cloud Storage

```bash
# List generated content files
gsutil ls -la gs://location-content-*/content/

# View a specific content file
gsutil cat gs://location-content-*/content/[filename].json | python3 -m json.tool
```

### Function Metrics

```bash
# View function metrics in Cloud Console
gcloud functions describe generate-location-content \
    --region=${REGION} \
    --format="table(name,status,runtime,serviceConfig.environmentVariables)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete location-content-deployment \
    --location=${REGION} \
    --delete-policy=DELETE
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Security Considerations

### IAM Permissions

The deployed service account includes these roles:
- `roles/viewer`: Basic project access
- `roles/aiplatform.user`: Vertex AI model access
- `roles/storage.admin`: Cloud Storage management

### Maps Grounding Requirements

- Billing account must be outside the European Economic Area (EEA)
- Service account requires proper authentication for Maps API access
- Function uses default authentication for Maps grounding integration

### Best Practices Implemented

- Least privilege IAM roles
- Cloud Storage versioning enabled
- Function memory and timeout limits configured
- CORS headers for web integration
- Comprehensive error handling in function code

## Customization

### Modifying Content Types

Edit the `main.py` in the function source to add new content types:

```python
prompts = {
    'marketing': '...',
    'travel': '...',
    'business': '...',
    'your_custom_type': 'Your custom prompt template...'
}
```

### Adjusting Function Configuration

Update terraform variables or Infrastructure Manager inputs:

```hcl
# In terraform/variables.tf or terraform.tfvars
function_memory = "1Gi"        # Increase memory
function_timeout = 120         # Extend timeout
max_instances = 20             # Allow more concurrent instances
```

### Adding Authentication

To require authentication, modify the deployment:

```bash
# Remove --allow-unauthenticated flag
gcloud functions deploy generate-location-content \
    --trigger=http \
    # ... other flags without --allow-unauthenticated
```

## Troubleshooting

### Common Issues

1. **Maps Grounding Access Denied**
   - Verify billing account is outside EEA
   - Check service account permissions
   - Ensure Vertex AI API is enabled

2. **Function Deployment Fails**
   - Verify all required APIs are enabled
   - Check service account exists and has proper roles
   - Ensure Cloud Build API is enabled for deployment

3. **Storage Access Issues**
   - Verify bucket permissions
   - Check service account has `storage.admin` role
   - Ensure bucket name is globally unique

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:(functions|storage|aiplatform|cloudbuild)"

# Verify service account
gcloud iam service-accounts describe location-content-sa@${PROJECT_ID}.iam.gserviceaccount.com

# Test function locally (requires Functions Framework)
functions-framework --target=generate_location_content --debug
```

## Cost Estimation

Estimated costs for moderate usage (1000 requests/month):
- **Cloud Functions**: $0.10-0.50/month (invocations + compute time)
- **Cloud Storage**: $0.02-0.05/month (storage + operations)
- **Vertex AI**: $2-10/month (Gemini API calls with Maps grounding)

> **Note**: Maps grounding may incur additional charges compared to standard Gemini usage. Monitor your billing dashboard for actual costs.

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review Google Cloud Function troubleshooting guides
3. Consult Vertex AI and Maps grounding documentation
4. Use `gcloud` CLI help commands for specific issues

## Additional Resources

- [Google Maps Grounding Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/grounding/grounding-with-google-maps)
- [Cloud Functions Gen2 Documentation](https://cloud.google.com/functions/docs/2nd-gen)
- [Vertex AI Gemini Models](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/gemini)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)