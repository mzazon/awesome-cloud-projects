# Infrastructure as Code for Legal Document Analysis with Gemini Fine-Tuning and Document AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Legal Document Analysis with Gemini Fine-Tuning and Document AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an automated legal document analysis system that combines:
- Document AI for text extraction and OCR processing
- Gemini 2.5 Flash fine-tuning for legal domain expertise
- Cloud Functions for serverless orchestration
- Cloud Storage for document and result management
- Automated dashboard generation for legal review workflows

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Vertex AI Admin
  - Document AI Admin
  - Cloud Functions Admin
  - Storage Admin
  - Service Usage Admin
- Terraform (>= 1.0) for Terraform deployment
- Python 3.9+ for function development
- Estimated cost: $75-150 for training and processing (varies by document volume)

## Required APIs

The following Google Cloud APIs must be enabled:
- Vertex AI API (`aiplatform.googleapis.com`)
- Document AI API (`documentai.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Clone or navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments create legal-analysis-deployment \
    --location=${REGION} \
    --source-type=CONFIG \
    --config-file=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe legal-analysis-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./deploy.sh

# Monitor deployment (script will provide status updates)
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `bucket_suffix` | Unique suffix for bucket names | Random | No |
| `enable_versioning` | Enable bucket versioning | `true` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | `string` | - | Yes |
| `region` | Deployment region | `string` | `us-central1` | No |
| `zone` | Deployment zone | `string` | `us-central1-a` | No |
| `bucket_suffix` | Unique suffix for bucket names | `string` | Random | No |
| `function_memory` | Memory for Cloud Functions | `number` | `512` | No |
| `function_timeout` | Timeout for Cloud Functions | `number` | `300` | No |

## Deployment Process

### 1. Pre-deployment Validation

Before deploying, ensure:
- Google Cloud project exists and billing is enabled
- Required APIs are enabled (deployment scripts will enable them)
- IAM permissions are sufficient
- Region supports all required services

### 2. Resource Creation Order

The infrastructure creates resources in this order:
1. Cloud Storage buckets (documents, training data, results)
2. Document AI processor for legal document processing
3. Training dataset preparation and upload
4. Gemini model fine-tuning job submission
5. Cloud Functions for document processing and dashboard
6. IAM bindings and service account configurations

### 3. Fine-Tuning Process

The deployment includes:
- Automatic training dataset creation with legal document examples
- Gemini 2.5 Flash fine-tuning job submission
- Model training typically takes 45-90 minutes
- Training job monitoring and status updates

## Post-Deployment Steps

### 1. Verify Fine-Tuning Job

```bash
# Check tuning job status
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# List tuning jobs
gcloud ai model-garden models list \
    --region=${REGION} \
    --filter="displayName:legal-gemini-tuning*"

# Monitor specific job (replace JOB_ID with actual ID)
gcloud ai custom-jobs describe JOB_ID \
    --region=${REGION}
```

### 2. Test Document Processing

```bash
# Create a test legal document
cat > test_contract.txt << 'EOF'
CONSULTING AGREEMENT

This Agreement is entered into between ABC Corporation ("Company") and John Smith ("Consultant").

WHEREAS, the Company desires to engage the Consultant for strategic advisory services;

1. TERM: This Agreement shall commence on January 1, 2025 and continue for twelve (12) months.
2. COMPENSATION: Company shall pay Consultant $5,000 per month.
3. CONFIDENTIALITY: Consultant shall maintain confidentiality of all proprietary information.
EOF

# Upload test document (replace BUCKET_NAME with actual bucket)
gsutil cp test_contract.txt gs://BUCKET_NAME/
```

### 3. Generate Legal Dashboard

```bash
# Get dashboard function URL (replace with actual values)
export DASHBOARD_URL=$(gcloud functions describe legal-dashboard-generator \
    --gen2 \
    --region=${REGION} \
    --format="value(serviceConfig.uri)")

# Generate dashboard
curl -X GET ${DASHBOARD_URL}

# Download dashboard HTML
gsutil cp gs://BUCKET_NAME/legal_dashboard.html ./
```

## Monitoring and Logging

### Function Logs

```bash
# View document processor logs
gcloud functions logs read legal-document-processor \
    --gen2 \
    --region=${REGION} \
    --limit=50

# View dashboard generator logs
gcloud functions logs read legal-dashboard-generator \
    --gen2 \
    --region=${REGION} \
    --limit=20
```

### Storage Monitoring

```bash
# Monitor bucket contents
gsutil ls -la gs://LEGAL_DOCS_BUCKET/
gsutil ls -la gs://LEGAL_RESULTS_BUCKET/

# Check bucket sizes
gsutil du -sh gs://LEGAL_DOCS_BUCKET/
gsutil du -sh gs://LEGAL_RESULTS_BUCKET/
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete legal-analysis-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion of all resources
terraform show
```

### Using Bash Scripts

```bash
cd scripts/

# Run cleanup script
./destroy.sh

# Verify manual cleanup if needed
```

### Manual Cleanup (if needed)

```bash
# Stop any running tuning jobs
gcloud ai custom-jobs cancel JOB_ID --region=${REGION}

# Delete storage buckets with contents
gsutil -m rm -r gs://BUCKET_NAME

# Delete Document AI processors
gcloud documentai processors delete PROCESSOR_ID --location=${REGION}

# Delete Cloud Functions
gcloud functions delete FUNCTION_NAME --gen2 --region=${REGION}
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable aiplatform.googleapis.com documentai.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles (replace USER_EMAIL)
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:USER_EMAIL" \
       --role="roles/aiplatform.admin"
   ```

3. **Fine-Tuning Job Fails**
   ```bash
   # Check job details
   gcloud ai custom-jobs describe JOB_ID --region=${REGION}
   
   # Review training data format
   gsutil cat gs://TRAINING_BUCKET/legal_training_examples.jsonl | head -5
   ```

4. **Function Deployment Issues**
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # Review function source
   gcloud functions describe FUNCTION_NAME --gen2 --region=${REGION}
   ```

### Performance Optimization

1. **Function Memory**: Increase memory allocation for large documents
2. **Batch Processing**: Process multiple documents in single function invocation
3. **Caching**: Implement result caching for repeated document types
4. **Regional Deployment**: Deploy in region closest to users

## Security Considerations

### Data Protection

- All storage buckets use Google-managed encryption
- Function environment variables are encrypted
- Document processing maintains data residency
- Access logs are enabled for audit trails

### Access Control

- Service accounts follow least privilege principle
- Function-to-function authentication uses service accounts
- Storage access is restricted to processing functions
- Document AI processors have dedicated service accounts

### Compliance

- GDPR: Data processing controls and deletion capabilities
- SOC 2: Audit logging and access controls
- Legal Industry: Document confidentiality and integrity

## Cost Optimization

### Monitoring Costs

```bash
# View current billing
gcloud billing budgets list

# Check resource usage
gcloud logging read "resource.type=cloud_function" --limit=100
```

### Cost-Saving Recommendations

1. **Storage Lifecycle**: Implement intelligent tiering for processed documents
2. **Function Concurrency**: Optimize concurrent executions
3. **Model Caching**: Cache fine-tuned model responses for similar documents
4. **Batch Processing**: Process documents in batches to reduce function calls

## Advanced Configuration

### Custom Training Data

```bash
# Upload custom legal training examples
gsutil cp your_training_data.jsonl gs://TRAINING_BUCKET/

# Retrain model with new data
# (Update terraform variables or Infrastructure Manager config)
```

### Multi-Language Support

```bash
# Configure Document AI for multiple languages
# Update processor configuration in IaC templates
```

### Integration with Legal Systems

```bash
# Configure webhooks for legal practice management systems
# Add environment variables for external API endpoints
```

## Support and Documentation

- **Recipe Documentation**: See parent directory for complete recipe guide
- **Google Cloud Documentation**: [Cloud Functions](https://cloud.google.com/functions/docs), [Vertex AI](https://cloud.google.com/vertex-ai/docs), [Document AI](https://cloud.google.com/document-ai/docs)
- **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Infrastructure Manager**: [Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Contributing

To improve this infrastructure code:

1. Test changes in a development project
2. Validate with `terraform plan` or Infrastructure Manager preview
3. Update documentation for any new variables or outputs
4. Follow Google Cloud best practices and security guidelines

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Adapt according to your organization's requirements and security policies.