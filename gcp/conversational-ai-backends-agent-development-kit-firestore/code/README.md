# Infrastructure as Code for Conversational AI Backends with Agent Development Kit and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Conversational AI Backends with Agent Development Kit and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys a complete conversational AI backend system featuring:

- **Agent Development Kit (ADK)**: Google's framework for building intelligent conversational agents
- **Cloud Functions**: Serverless API endpoints for conversation processing
- **Firestore**: NoSQL database for persistent conversation memory and user context
- **Cloud Storage**: Object storage for conversation artifacts and training data
- **Vertex AI**: AI/ML platform integration for natural language processing
- **Cloud Monitoring**: Performance tracking and analytics

## Prerequisites

### Required Tools
- Google Cloud CLI (`gcloud`) installed and configured
- Terraform >= 1.0 (for Terraform implementation)
- Python 3.10+ with pip
- Node.js 18+ (for Cloud Functions development)

### Google Cloud Setup
- Google Cloud project with billing enabled
- Required APIs enabled:
  - Vertex AI API
  - Cloud Functions API
  - Cloud Firestore API
  - Cloud Storage API
  - Cloud Build API
  - Cloud Run API
- Appropriate IAM permissions for resource creation

### Authentication
```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set your project
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}
```

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code.

```bash
# Navigate to Infrastructure Manager implementation
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/conversational-ai \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/us-central1/deployments/conversational-ai
```

### Using Terraform

```bash
# Navigate to Terraform implementation
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud functions list --regions=us-central1
gcloud firestore databases list
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export FUNCTION_NAME="chat-processor-$(openssl rand -hex 3)"
export BUCKET_NAME="${PROJECT_ID}-conversations-$(openssl rand -hex 3)"
export FIRESTORE_DATABASE="chat-conversations"
```

### Terraform Variables

Key variables in `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "1GB"
}

variable "firestore_location" {
  description = "Firestore database location"
  type        = string
  default     = "us-central1"
}
```

Create a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region     = "us-central1"
```

## Deployment Outputs

After successful deployment, you'll receive:

### Infrastructure Manager Outputs
- Firestore database name and location
- Cloud Storage bucket name
- Cloud Functions URLs for API endpoints
- Service account details

### Terraform Outputs
```bash
# View all outputs
terraform output

# Specific outputs
terraform output chat_function_url
terraform output history_function_url
terraform output firestore_database
terraform output storage_bucket
```

### Bash Script Outputs
```bash
# Function URLs are displayed after deployment
echo "Chat API URL: https://us-central1-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
echo "History API URL: https://us-central1-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}-history"
```

## Testing the Deployment

### API Endpoint Testing

```bash
# Test conversation processing
curl -X POST "https://us-central1-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}" \
    -H "Content-Type: application/json" \
    -d '{
      "user_id": "test_user_123",
      "message": "Hello, can you help me with project planning?",
      "session_id": "test_session_1"
    }'

# Test conversation history retrieval
curl -X GET "https://us-central1-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}-history?user_id=test_user_123"
```

### Infrastructure Validation

```bash
# Verify Firestore database
gcloud firestore databases describe --database=${FIRESTORE_DATABASE}

# Check Cloud Functions
gcloud functions describe ${FUNCTION_NAME} --region=${REGION}

# Verify Cloud Storage bucket
gsutil ls -la gs://${BUCKET_NAME}/
```

## Cost Estimation

Estimated monthly costs for moderate usage (varies by conversation volume):

| Service | Estimated Cost |
|---------|---------------|
| Cloud Functions (10,000 invocations) | $5-10 |
| Firestore (1GB storage, 100K operations) | $15-25 |
| Cloud Storage (10GB) | $2-5 |
| Vertex AI (Gemini API usage) | $20-50 |
| **Total Estimated** | **$42-90/month** |

> **Note**: Costs may vary significantly based on conversation volume, model usage, and data storage requirements.

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/conversational-ai

# Verify deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Functions
gcloud functions delete ${FUNCTION_NAME} --region=${REGION} --quiet
gcloud functions delete ${FUNCTION_NAME}-history --region=${REGION} --quiet

# Delete Firestore database
gcloud firestore databases delete ${FIRESTORE_DATABASE} --quiet

# Delete Cloud Storage bucket
gsutil -m rm -r gs://${BUCKET_NAME}

# Clean up environment variables
unset PROJECT_ID REGION ZONE FUNCTION_NAME BUCKET_NAME FIRESTORE_DATABASE
```

## Customization

### Scaling Configuration

Modify Cloud Functions scaling in your IaC:

```yaml
# Infrastructure Manager
resources:
  - name: chat-processor
    type: gcp-types/cloudfunctions-v1:projects.locations.functions
    properties:
      availableMemoryMb: 1024
      timeout: 60s
      maxInstances: 100
```

```hcl
# Terraform
resource "google_cloudfunctions_function" "chat_processor" {
  available_memory_mb = 1024
  timeout            = 60
  max_instances      = 100
}
```

### Security Hardening

- Enable VPC Service Controls for additional security
- Configure IAM policies with least privilege access
- Enable audit logging for all services
- Set up Cloud Armor for DDoS protection

### Monitoring Enhancement

```bash
# Create custom dashboards
gcloud monitoring dashboards create --config-from-file=monitoring_dashboard.json

# Set up alerting policies
gcloud alpha monitoring policies create --policy-from-file=alerting_policy.yaml
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Ensure proper IAM roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/editor"
   ```

2. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   ```

3. **Function Deployment Failures**
   ```bash
   # Check function logs
   gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}
   ```

4. **Firestore Connection Issues**
   ```bash
   # Verify Firestore database exists
   gcloud firestore databases list
   ```

### Getting Help

- Check function logs: `gcloud functions logs read FUNCTION_NAME`
- Monitor deployment: `gcloud infra-manager deployments describe DEPLOYMENT_NAME`
- Terraform debugging: `TF_LOG=DEBUG terraform apply`

## Advanced Features

### Multi-Region Deployment

Extend the deployment for global availability:

```hcl
# terraform/multi-region.tf
locals {
  regions = ["us-central1", "europe-west1", "asia-southeast1"]
}

resource "google_cloudfunctions_function" "chat_processor" {
  for_each = toset(local.regions)
  
  name     = "${var.function_name}-${each.value}"
  location = each.value
  # ... other configuration
}
```

### Continuous Integration

Integrate with Cloud Build for automated deployments:

```yaml
# cloudbuild.yaml
steps:
  - name: 'hashicorp/terraform:latest'
    entrypoint: 'sh'
    args:
      - '-c'
      - |
        cd terraform/
        terraform init
        terraform plan
        terraform apply -auto-approve
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation: `../conversational-ai-backends-agent-development-kit-firestore.md`
2. Check Google Cloud documentation:
   - [Cloud Functions](https://cloud.google.com/functions/docs)
   - [Firestore](https://cloud.google.com/firestore/docs)
   - [Agent Development Kit](https://cloud.google.com/vertex-ai/generative-ai/docs/agent-development-kit)
3. Terraform Google Provider: [Registry Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. Infrastructure Manager: [Google Cloud Documentation](https://cloud.google.com/infrastructure-manager/docs)

## License

This infrastructure code is provided as-is for educational and development purposes. Review and modify according to your organization's requirements before production deployment.