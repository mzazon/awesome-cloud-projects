# Infrastructure as Code for Real-Time Document Intelligence Pipelines with Cloud Storage and Document AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Document Intelligence Pipelines with Cloud Storage and Document AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) v450.0.0 or later installed and configured
- Terraform v1.5+ (for Terraform implementation)
- Active Google Cloud project with billing enabled
- Required APIs enabled: Document AI, Pub/Sub, Cloud Storage, Cloud Functions
- Appropriate IAM permissions for resource creation:
  - Document AI Admin
  - Cloud Functions Admin
  - Pub/Sub Admin
  - Storage Admin
  - Service Account Admin

## Quick Start

### Using Infrastructure Manager (Recommended)

```bash
cd infrastructure-manager/

# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create doc-intelligence-pipeline \
    --location=${REGION} \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe doc-intelligence-pipeline \
    --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Test the pipeline (optional)
./scripts/test-pipeline.sh
```

## Architecture Overview

This infrastructure creates a real-time document processing pipeline with the following components:

- **Cloud Storage Bucket**: Secure document ingestion with event notifications
- **Document AI Processor**: Machine learning-powered document analysis
- **Pub/Sub Topics**: Event-driven messaging for scalable processing
- **Cloud Functions**: Serverless document processing and result consumption
- **IAM Service Accounts**: Secure service-to-service authentication
- **Firestore Database**: Real-time storage for processed document results

## Configuration Options

### Infrastructure Manager Variables

```yaml
# infrastructure-manager/main.yaml
variables:
  project_id:
    type: string
    description: "Google Cloud Project ID"
  
  region:
    type: string
    default: "us-central1"
    description: "Deployment region"
  
  processor_type:
    type: string
    default: "FORM_PARSER_PROCESSOR"
    description: "Document AI processor type"
  
  enable_versioning:
    type: boolean
    default: true
    description: "Enable bucket versioning for audit trails"
```

### Terraform Variables

```hcl
# terraform/variables.tf
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Deployment region"
  type        = string
  default     = "us-central1"
}

variable "processor_display_name" {
  description = "Display name for Document AI processor"
  type        = string
  default     = "invoice-processor"
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "512Mi"
}
```

## Testing the Pipeline

After deployment, test the document intelligence pipeline:

```bash
# Upload a test document
echo "Invoice Number: INV-12345
Date: $(date +%Y-%m-%d)
Amount: $1,250.00
Customer: ABC Corporation" > test-invoice.txt

# Upload to trigger processing
gsutil cp test-invoice.txt gs://documents-${RANDOM_SUFFIX}/invoices/

# Monitor function logs
gcloud functions logs read process-document --region=${REGION} --limit=10

# Check Firestore for results
gcloud firestore collections documents list processed_documents
```

## Monitoring and Observability

The infrastructure includes monitoring capabilities:

```bash
# View Cloud Function metrics
gcloud functions describe process-document --region=${REGION}

# Monitor Pub/Sub subscription metrics
gcloud pubsub subscriptions describe process-docs-subscription

# Check Document AI usage
gcloud documentai processors list --location=us
```

## Security Considerations

The infrastructure implements security best practices:

- **Least Privilege IAM**: Service accounts with minimal required permissions
- **Bucket Security**: Uniform bucket-level access and versioning enabled
- **VPC Integration**: Functions deployed with VPC connector (when configured)
- **Secret Management**: Sensitive configuration stored in Secret Manager
- **Audit Logging**: Cloud Audit Logs enabled for compliance tracking

## Cost Optimization

Monitor and optimize costs with these considerations:

- **Document AI**: Charges per page processed (~$1.50 per 1,000 pages)
- **Cloud Functions**: Pay-per-invocation with automatic scaling
- **Cloud Storage**: Standard storage class with lifecycle policies
- **Pub/Sub**: First 10GB of messages per month are free

```bash
# Set up billing alerts
gcloud alpha billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Document Intelligence Budget" \
    --budget-amount=100USD
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete doc-intelligence-pipeline \
    --location=${REGION} \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Clean up state files
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
gcloud functions list
gcloud pubsub topics list
gsutil ls
```

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**
   ```bash
   # Check function source code
   gcloud functions describe process-document --region=${REGION}
   
   # Review build logs
   gcloud functions logs read process-document --region=${REGION}
   ```

2. **Document AI Processing Errors**
   ```bash
   # Verify processor exists
   gcloud documentai processors list --location=us
   
   # Check API quotas
   gcloud services list --enabled | grep documentai
   ```

3. **Pub/Sub Message Delivery Issues**
   ```bash
   # Check subscription status
   gcloud pubsub subscriptions describe process-docs-subscription
   
   # Pull messages manually
   gcloud pubsub subscriptions pull process-docs-subscription --auto-ack
   ```

### Performance Tuning

Optimize pipeline performance:

```bash
# Increase function memory for large documents
gcloud functions deploy process-document \
    --memory=1Gi \
    --timeout=540s

# Configure concurrent executions
gcloud functions deploy process-document \
    --max-instances=50 \
    --min-instances=1
```

## Extensions and Customization

### Adding Document Classification

Extend the pipeline with document type classification:

```python
# Add to function code
from google.cloud import documentai_v1

def classify_document(document_content):
    """Classify document type before processing"""
    # Implementation for document classification
    pass
```

### Integrating with BigQuery

Store results in BigQuery for analytics:

```bash
# Create BigQuery dataset
bq mk --dataset ${PROJECT_ID}:document_analytics

# Create table for processed documents
bq mk --table ${PROJECT_ID}:document_analytics.processed_docs \
    source_file:STRING,pages:INTEGER,form_fields:JSON,processed_at:TIMESTAMP
```

### Adding Workflow Automation

Connect to Cloud Workflows for business process automation:

```yaml
# workflow.yaml
main:
  steps:
    - process_document:
        call: googleapis.documentai.v1.projects.locations.processors.process
        args:
          name: ${processor_name}
          document: ${document}
```

## Support and Documentation

- [Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

## Contributing

To contribute improvements to this infrastructure:

1. Test changes in a development project
2. Validate with both Infrastructure Manager and Terraform
3. Update documentation and examples
4. Ensure security best practices are maintained

## License

This infrastructure code is provided under the same license as the parent recipe repository.