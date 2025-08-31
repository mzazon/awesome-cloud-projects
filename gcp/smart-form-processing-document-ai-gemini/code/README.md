# Infrastructure as Code for Smart Form Processing with Document AI and Gemini

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Form Processing with Document AI and Gemini".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions deployment
  - Document AI processor creation
  - Cloud Storage bucket management
  - Vertex AI service access
  - Service account management
- For Terraform: Terraform CLI installed (version 1.0+)
- For Infrastructure Manager: `gcloud` CLI with Infrastructure Manager API enabled

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

Infrastructure Manager is Google Cloud's managed Infrastructure as Code service that natively supports Terraform configurations with enhanced Google Cloud integration.

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/YOUR_PROJECT_ID/locations/us-central1/deployments/smart-form-processing \
    --service-account YOUR_SERVICE_ACCOUNT@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe projects/YOUR_PROJECT_ID/locations/us-central1/deployments/smart-form-processing
```

### Using Terraform

Terraform provides a declarative approach to infrastructure management with excellent Google Cloud provider support and state management capabilities.

```bash
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review planned infrastructure changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the infrastructure configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify deployment with outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct control over resource creation using Google Cloud CLI commands with comprehensive error handling and validation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud functions describe process-form --region=$REGION
```

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage Buckets**: Input and output buckets for form processing
- **Document AI Processor**: Form parser for intelligent data extraction
- **Cloud Functions**: Serverless processing pipeline
- **IAM Roles**: Service accounts and permissions for secure operation
- **Vertex AI Integration**: Gemini model access for data validation

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    type: string
    description: "Google Cloud Project ID"
  region:
    type: string
    description: "Deployment region"
    default: "us-central1"
  function_memory:
    type: string
    description: "Cloud Function memory allocation"
    default: "1024MB"
```

### Terraform Variables

Customize deployment in `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
environment = "production"
function_timeout = 540
max_instances = 10
bucket_storage_class = "STANDARD"
```

### Bash Script Environment Variables

Set these variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export ENVIRONMENT="prod"  # Optional: affects resource naming
```

## Testing the Deployment

After successful deployment, test the form processing pipeline:

```bash
# Upload a test form (supported formats: PDF, images)
gsutil cp test-documents/sample_form.pdf gs://forms-input-[SUFFIX]/

# Monitor Cloud Function logs
gcloud functions logs read process-form --region=$REGION --limit=20

# Check processed results
gsutil ls gs://forms-output-[SUFFIX]/processed/
gsutil cp gs://forms-output-[SUFFIX]/processed/sample_form_results.json .
cat sample_form_results.json | jq '.gemini_analysis.confidence_score'
```

## Monitoring and Observability

The deployment includes built-in monitoring capabilities:

```bash
# View Cloud Function metrics
gcloud functions describe process-form --region=$REGION --format="value(status)"

# Monitor Document AI usage
gcloud logging read "resource.type=document_ai_processor" --limit=10

# Check Vertex AI API calls
gcloud logging read "resource.type=vertex_ai" --limit=10
```

## Security Features

The infrastructure implements security best practices:

- **Least Privilege IAM**: Service accounts with minimal required permissions
- **Encryption**: Data encrypted in transit and at rest
- **Private Access**: Functions use private Google APIs when possible
- **Audit Logging**: Comprehensive audit trails for compliance
- **Network Security**: Restricted network access where applicable

## Cost Optimization

Estimated costs for processing 1000 forms/month:

- **Document AI**: ~$15-30 (varies by document complexity)
- **Vertex AI Gemini**: ~$10-25 (depends on prompt length)
- **Cloud Functions**: ~$5-10 (execution time based)
- **Cloud Storage**: ~$1-5 (storage and transfer)

**Total**: Approximately $30-70/month for moderate usage

Cost optimization features included:

- Automatic scaling based on demand
- Intelligent instance management
- Storage lifecycle policies
- Optimized function memory allocation

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/YOUR_PROJECT_ID/locations/us-central1/deployments/smart-form-processing

# Verify resources are removed
gcloud infra-manager deployments list
```

### Using Terraform

```bash
cd terraform/

# Preview resources to be destroyed
terraform plan -destroy -var="project_id=YOUR_PROJECT_ID"

# Destroy all infrastructure
terraform destroy -var="project_id=YOUR_PROJECT_ID"

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify manual cleanup if needed
gcloud functions list --regions=$REGION
gcloud storage buckets list --filter="name ~ forms-"
```

## Troubleshooting

### Common Issues

**Document AI Processor Creation Fails**
```bash
# Check API enablement
gcloud services list --enabled --filter="name:documentai.googleapis.com"

# Verify region availability
gcloud documentai processors list --location=$REGION
```

**Cloud Function Deployment Errors**
```bash
# Check required APIs
gcloud services list --enabled --filter="name:(cloudfunctions|cloudbuild).googleapis.com"

# Review function logs
gcloud functions logs read process-form --region=$REGION
```

**Permission Denied Errors**
```bash
# Check service account permissions
gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --filter="bindings.members ~ serviceAccount"

# Verify API enablement
gcloud services list --enabled
```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# For Terraform
export TF_LOG=DEBUG
terraform apply

# For gcloud commands
gcloud functions deploy process-form --verbosity=debug

# For bash scripts
export DEBUG=true
./scripts/deploy.sh
```

## Customization

### Adding Custom Document Types

Modify the Cloud Function to support additional document formats:

1. Update `terraform/variables.tf` to include new document types
2. Modify function code in deployment to handle additional MIME types
3. Add corresponding Document AI processor types

### Scaling Configuration

Adjust performance settings:

```hcl
# In terraform/variables.tf
variable "function_max_instances" {
  description = "Maximum Cloud Function instances"
  type        = number
  default     = 50  # Increase for higher throughput
}

variable "function_memory" {
  description = "Function memory allocation"
  type        = string
  default     = "2048MB"  # Increase for complex documents
}
```

### Integration with External Systems

The infrastructure supports integration with:

- **Pub/Sub**: For event-driven workflows
- **BigQuery**: For analytics and reporting
- **Cloud Workflows**: For complex processing pipelines
- **Firebase**: For real-time notifications

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../smart-form-processing-document-ai-gemini.md)
2. Check [Google Cloud Documentation](https://cloud.google.com/docs)
3. Consult [Document AI documentation](https://cloud.google.com/document-ai/docs)
4. Review [Vertex AI documentation](https://cloud.google.com/vertex-ai/docs)
5. Access [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Version Information

- **Recipe Version**: 1.1
- **Infrastructure Manager**: Uses latest Google Cloud resource types
- **Terraform**: Compatible with Google Provider 4.0+
- **Google Cloud APIs**: Uses current stable API versions
- **Last Updated**: 2025-07-12

---

*This infrastructure code is automatically generated from the recipe specification and follows Google Cloud best practices for security, scalability, and cost optimization.*