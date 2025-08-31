# Infrastructure as Code for Recipe Generation and Meal Planning with Gemini and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Recipe Generation and Meal Planning with Gemini and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Vertex AI API access
  - Cloud Functions deployment
  - Cloud Storage bucket creation
  - IAM policy management
- Basic knowledge of serverless functions and AI services

### Required APIs

The following APIs must be enabled in your Google Cloud project:

- AI Platform API (`aiplatform.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)

## Quick Start

### Environment Setup

Before deploying any infrastructure, set up your environment variables:

```bash
# Set environment variables for GCP resources
export PROJECT_ID="recipe-ai-$(date +%s)"
export REGION="us-central1"
export ZONE="us-central1-a"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export BUCKET_NAME="recipe-storage-${RANDOM_SUFFIX}"
export FUNCTION_NAME_GEN="recipe-generator"
export FUNCTION_NAME_GET="recipe-retriever"

# Set default project and region
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}
```

### Using Infrastructure Manager (GCP)

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses Terraform under the hood with Google Cloud integration.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create a deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/recipe-ai-deployment \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/recipe-ai-deployment
```

### Using Terraform

Deploy the infrastructure using Terraform with the Google Cloud provider:

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform with required providers
terraform init

# Review the planned infrastructure changes
terraform plan -var="project_id=${PROJECT_ID}" \
               -var="region=${REGION}" \
               -var="bucket_name=${BUCKET_NAME}"

# Apply the infrastructure configuration
terraform apply -var="project_id=${PROJECT_ID}" \
                -var="region=${REGION}" \
                -var="bucket_name=${BUCKET_NAME}" \
                -auto-approve

# View important outputs
terraform output
```

### Using Bash Scripts

Deploy using the provided bash scripts for a simplified deployment experience:

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the infrastructure
./deploy.sh

# The script will prompt for required values or use environment variables
```

## Architecture Overview

This infrastructure deploys:

1. **Cloud Storage Bucket**: Stores generated recipes and user preferences with versioning enabled
2. **Cloud Functions**: Two serverless functions for recipe generation and retrieval
3. **Vertex AI Integration**: Configured access to Gemini AI models for recipe generation
4. **IAM Roles**: Proper service account permissions for secure service-to-service communication

## Resource Configuration

### Cloud Storage

- **Bucket Class**: Standard storage for optimal performance and cost
- **Location**: Regional bucket in specified region
- **Versioning**: Enabled for data protection
- **Access Control**: Configured for Cloud Functions service account access

### Cloud Functions

#### Recipe Generator Function
- **Runtime**: Python 3.11
- **Memory**: 512MB (optimized for AI processing)
- **Timeout**: 60 seconds
- **Trigger**: HTTP trigger with authentication disabled for testing
- **Environment Variables**: Project ID and bucket name

#### Recipe Retriever Function
- **Runtime**: Python 3.11
- **Memory**: 256MB (optimized for data retrieval)
- **Timeout**: 30 seconds
- **Trigger**: HTTP trigger with authentication disabled for testing
- **Environment Variables**: Bucket name

### IAM Configuration

- **Vertex AI User Role**: Enables Cloud Functions to access Gemini models
- **Storage Object Admin**: Allows Cloud Functions to read/write recipe data
- **Service Account**: Uses default App Engine service account for security

## Customization

### Variables

Each implementation supports the following customizable variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | N/A | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `bucket_name` | Cloud Storage bucket name | Auto-generated | No |
| `function_name_generator` | Recipe generator function name | `recipe-generator` | No |
| `function_name_retriever` | Recipe retriever function name | `recipe-retriever` | No |

### Terraform Variables

To customize the Terraform deployment, create a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region     = "us-west1"
bucket_name = "your-custom-bucket-name"

# Optional: Custom function configurations
function_generator_memory = "1024"
function_generator_timeout = "90"
```

### Infrastructure Manager Variables

For Infrastructure Manager deployments, modify the `terraform.tfvars` file in the infrastructure-manager directory with your specific values.

## Testing and Validation

After deployment, validate the infrastructure:

### Test Recipe Generation

```bash
# Get the generator function URL
GENERATOR_URL=$(gcloud functions describe ${FUNCTION_NAME_GEN} --format="value(httpsTrigger.url)")

# Test recipe generation
curl -X POST ${GENERATOR_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "ingredients": ["chicken breast", "broccoli", "garlic", "olive oil"],
        "dietary_restrictions": ["gluten-free"],
        "skill_level": "intermediate",
        "cuisine_type": "Mediterranean"
    }'
```

Expected output: JSON response with generated recipe including recipe ID, preparation steps, and cooking instructions.

### Test Recipe Retrieval

```bash
# Get the retriever function URL
RETRIEVER_URL=$(gcloud functions describe ${FUNCTION_NAME_GET} --format="value(httpsTrigger.url)")

# Test recipe retrieval
curl "${RETRIEVER_URL}?ingredient=chicken&limit=5"

# Test specific recipe retrieval (use ID from generation test)
curl "${RETRIEVER_URL}?recipe_id=recipe-20250712123000"
```

Expected output: Filtered recipe list and specific recipe details demonstrating search functionality.

### Verify Cloud Storage

```bash
# List generated recipes
gsutil ls gs://${BUCKET_NAME}/recipes/

# Check bucket configuration
gsutil ls -L -b gs://${BUCKET_NAME}
```

Expected output: List of recipe JSON files and sample recipe content showing proper storage integration.

## Monitoring and Logging

### Cloud Functions Logs

```bash
# View generator function logs
gcloud functions logs read ${FUNCTION_NAME_GEN} --limit 20

# View retriever function logs
gcloud functions logs read ${FUNCTION_NAME_GET} --limit 20
```

### Cloud Storage Monitoring

```bash
# Monitor storage usage
gcloud logging read "resource.type=gcs_bucket AND resource.labels.bucket_name=${BUCKET_NAME}" --limit 10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/recipe-ai-deployment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" \
                  -var="region=${REGION}" \
                  -var="bucket_name=${BUCKET_NAME}" \
                  -auto-approve
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run the cleanup script
./destroy.sh
```

### Manual Cleanup

If automated cleanup fails, manually remove resources:

```bash
# Delete Cloud Functions
gcloud functions delete ${FUNCTION_NAME_GEN} --quiet
gcloud functions delete ${FUNCTION_NAME_GET} --quiet

# Delete Cloud Storage bucket (removes all objects)
gsutil -m rm -r gs://${BUCKET_NAME}

# Optional: Delete the entire project
gcloud projects delete ${PROJECT_ID} --quiet
```

## Cost Considerations

### Estimated Monthly Costs (Moderate Usage)

- **Cloud Functions**: $1-3 (based on invocations and execution time)
- **Cloud Storage**: $1-2 (based on storage and operations)
- **Vertex AI (Gemini)**: $3-10 (based on API requests and token usage)
- **Total Estimated**: $5-15 per month

### Cost Optimization Tips

1. **Monitor Vertex AI Usage**: AI model calls are the primary cost driver
2. **Implement Caching**: Cache frequently requested recipes to reduce AI calls
3. **Storage Lifecycle**: Configure automatic deletion of old recipes if not needed
4. **Function Optimization**: Optimize function memory allocation based on actual usage

## Security Considerations

### IAM Best Practices

- Uses least privilege access for service accounts
- Separates permissions between generation and retrieval functions
- Follows Google Cloud security recommendations

### Data Protection

- Cloud Storage bucket versioning enabled for data protection
- No hardcoded credentials in function code
- Secure environment variable handling

### Network Security

- Functions use HTTPS endpoints for secure communication
- Default VPC configuration with Google Cloud security controls

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **IAM Permissions**: Verify service account has proper roles assigned
3. **Function Timeout**: Increase timeout if Vertex AI calls take longer than expected
4. **Storage Access**: Confirm bucket exists and service account has access

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# Verify IAM bindings
gcloud projects get-iam-policy ${PROJECT_ID}

# Test function deployment
gcloud functions describe ${FUNCTION_NAME_GEN}
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Verify all prerequisites are met
4. Review Cloud Logging for detailed error messages

## Additional Resources

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Gemini API Reference](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/gemini)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)