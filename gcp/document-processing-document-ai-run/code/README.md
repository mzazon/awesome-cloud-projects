# Infrastructure as Code for Document Processing Workflows with Document AI and Cloud Run

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Document Processing Workflows with Document AI and Cloud Run".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Document AI API management
  - Cloud Run service deployment
  - Cloud Storage bucket creation
  - Pub/Sub topic and subscription management
  - Service account creation and IAM policy binding
- Docker installed (for local container building, optional)
- Terraform >= 1.0 (for Terraform implementation)

## Architecture Overview

This solution creates an automated document processing pipeline that:

1. Accepts document uploads to Cloud Storage
2. Triggers processing via Pub/Sub notifications
3. Processes documents using Document AI Form Parser
4. Runs serverless processing logic on Cloud Run
5. Stores structured results back to Cloud Storage

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for infrastructure as code, providing native integration with Google Cloud services.

```bash
# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create document-processing-deployment \
    --location=${REGION} \
    --source-blueprint=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe document-processing-deployment \
    --location=${REGION}
```

### Using Terraform

Terraform provides a declarative approach to infrastructure management with strong state management capabilities.

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct CLI-based deployment with step-by-step execution.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
gcloud run services list --region=${REGION}
gcloud documentai processors list --location=${REGION}
```

## Configuration

### Environment Variables

All implementations support these configuration options:

| Variable | Description | Default |
|----------|-------------|---------|
| `PROJECT_ID` | Google Cloud project ID | Required |
| `REGION` | Deployment region | `us-central1` |
| `BUCKET_NAME` | Storage bucket name | Auto-generated |
| `PROCESSOR_DISPLAY_NAME` | Document AI processor name | Auto-generated |
| `CLOUDRUN_SERVICE` | Cloud Run service name | `document-processor` |
| `PUBSUB_TOPIC` | Pub/Sub topic name | `document-processing` |

### Terraform Variables

Customize your deployment by creating a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region     = "us-central1"

# Optional customizations
cloudrun_service_name = "my-document-processor"
bucket_prefix        = "my-company-docs"
processor_type       = "FORM_PARSER_PROCESSOR"
max_instances        = 20
memory_limit         = "2Gi"
cpu_limit           = "2"
```

### Infrastructure Manager Variables

For Infrastructure Manager, modify the input values in your deployment command:

```bash
gcloud infra-manager deployments create document-processing-deployment \
    --location=${REGION} \
    --source-blueprint=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION},cloudrun_service_name=my-processor"
```

## Testing the Deployment

After successful deployment, test the document processing pipeline:

1. **Upload a test document:**
   ```bash
   # Create a test document
   echo "Sample Invoice - Invoice #12345, Amount: $150.00" > test-invoice.txt
   
   # Upload to trigger processing
   gsutil cp test-invoice.txt gs://[BUCKET_NAME]/
   ```

2. **Monitor processing:**
   ```bash
   # Check Cloud Run logs
   gcloud logging read "resource.type=cloud_run_revision" --limit=10
   
   # Check for processed results
   gsutil ls gs://[BUCKET_NAME]/processed/
   ```

3. **View extracted data:**
   ```bash
   # Download and view processing results
   gsutil cat gs://[BUCKET_NAME]/processed/test-invoice.txt.json
   ```

## Monitoring and Observability

The deployed infrastructure includes built-in monitoring capabilities:

- **Cloud Run metrics**: Request count, latency, error rate
- **Document AI usage**: Processing volume and success rate
- **Pub/Sub metrics**: Message delivery and processing lag
- **Storage metrics**: Upload volume and processing throughput

Access monitoring data through:

```bash
# View Cloud Run service details
gcloud run services describe document-processor --region=${REGION}

# Check recent logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=document-processor" --limit=20
```

## Cost Optimization

This solution follows cost optimization best practices:

- **Cloud Run**: Scales to zero when not processing documents
- **Document AI**: Pay-per-document processing model
- **Cloud Storage**: Standard storage class with lifecycle policies
- **Pub/Sub**: Minimal cost for message delivery

Estimated costs for 1000 documents/month:
- Document AI Form Parser: ~$1.50
- Cloud Run: ~$0.50
- Cloud Storage: ~$0.10
- Pub/Sub: ~$0.05
- **Total**: ~$2.15/month

## Security Features

The implementation includes several security best practices:

- **Service Account**: Least-privilege access with specific IAM roles
- **API Security**: Document AI and Cloud Run secured with service accounts
- **Network Security**: Private service communication where possible
- **Data Encryption**: Encryption at rest and in transit for all data

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete document-processing-deployment \
    --location=${REGION} \
    --delete-policy=DELETE
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud run services list --region=${REGION}
gcloud documentai processors list --location=${REGION}
```

## Troubleshooting

### Common Issues

1. **Document AI Processor Creation Fails**
   ```bash
   # Ensure Document AI API is enabled
   gcloud services enable documentai.googleapis.com
   
   # Check quota limits
   gcloud compute project-info describe --format="yaml(quotas)"
   ```

2. **Cloud Run Deployment Fails**
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Verify Cloud Run API is enabled
   gcloud services enable run.googleapis.com
   ```

3. **Pub/Sub Message Delivery Issues**
   ```bash
   # Check subscription configuration
   gcloud pubsub subscriptions describe document-worker
   
   # Verify push endpoint URL
   gcloud run services describe document-processor --region=${REGION}
   ```

### Debug Commands

```bash
# Check all required APIs are enabled
gcloud services list --enabled --filter="name:(documentai.googleapis.com OR run.googleapis.com OR pubsub.googleapis.com OR storage.googleapis.com)"

# Verify resource creation
gcloud documentai processors list --location=${REGION}
gcloud run services list --region=${REGION}
gcloud pubsub topics list
gcloud storage buckets list
```

## Customization

### Adding Specialized Processors

To use specialized Document AI processors (Invoice, Receipt, Contract):

1. **Terraform**: Update the `processor_type` variable in `terraform/variables.tf`
2. **Infrastructure Manager**: Modify the processor type in `main.yaml`
3. **Scripts**: Change the processor type in the deployment script

```bash
# Example: Use Invoice Parser instead of Form Parser
export PROCESSOR_TYPE="INVOICE_PROCESSOR"
```

### Scaling Configuration

Adjust Cloud Run scaling parameters:

```bash
# Terraform: Modify variables.tf
max_instances = 50
min_instances = 1
memory_limit  = "4Gi"
cpu_limit    = "4"

# Infrastructure Manager: Update main.yaml scaling section
# Scripts: Modify Cloud Run deployment parameters
```

### Multi-Region Deployment

For disaster recovery, deploy across multiple regions:

```bash
# Deploy to multiple regions
export REGIONS=("us-central1" "us-east1" "europe-west1")

for region in "${REGIONS[@]}"; do
    export REGION=$region
    ./scripts/deploy.sh
done
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: 
   - [Document AI Documentation](https://cloud.google.com/document-ai/docs)
   - [Cloud Run Documentation](https://cloud.google.com/run/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
3. **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest)

## Contributing

When modifying this infrastructure code:

1. Test changes in a development project first
2. Follow Google Cloud best practices for security and cost optimization
3. Update documentation for any new configuration options
4. Validate generated code syntax before committing

## Version Information

- **Infrastructure Manager**: Compatible with Google Cloud Infrastructure Manager
- **Terraform**: Requires Terraform >= 1.0 with Google Provider >= 4.0
- **Google Cloud APIs**: Uses current stable API versions
- **Recipe Version**: 1.0
- **Generated**: 2025-07-12