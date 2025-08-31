# Infrastructure as Code for Content Accessibility Compliance with Document AI and Gemini

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Content Accessibility Compliance with Document AI and Gemini".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Document AI API administration
  - Vertex AI API administration
  - Cloud Functions administration
  - Cloud Storage administration
  - Service account creation and management
- For Terraform: Terraform CLI (version >= 1.0) installed
- For Infrastructure Manager: Infrastructure Manager API enabled

## Quick Start

### Using Infrastructure Manager

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/accessibility-compliance \
    --service-account=projects/YOUR_PROJECT_ID/serviceAccounts/infra-manager@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --local-source=infrastructure-manager/

# Check deployment status
gcloud infra-manager deployments describe \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/accessibility-compliance
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
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

# View deployment status
gcloud functions list --regions=us-central1
gsutil ls
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Storage Bucket**: Stores uploaded documents and generated accessibility reports
- **Document AI Processor**: OCR processor for document layout analysis and text extraction
- **Cloud Function**: Serverless function orchestrating the accessibility analysis workflow
- **IAM Roles**: Service accounts and permissions for secure resource access
- **Vertex AI Configuration**: Gemini model access for WCAG compliance evaluation

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Google Cloud region"
    type: string
    default: "us-central1"
  bucket_name:
    description: "Cloud Storage bucket name for documents"
    type: string
```

### Terraform Variables

Edit `terraform/terraform.tfvars` or provide variables via command line:

```bash
# Create terraform.tfvars file
cat > terraform/terraform.tfvars << EOF
project_id = "your-project-id"
region = "us-central1"
bucket_name = "accessibility-docs-unique-suffix"
function_name = "accessibility-analyzer"
processor_display_name = "accessibility-processor"
EOF
```

### Bash Script Variables

Edit variables at the top of `scripts/deploy.sh`:

```bash
# Customizable variables
PROJECT_ID="${PROJECT_ID:-accessibility-compliance-$(date +%s)}"
REGION="${REGION:-us-central1}"
BUCKET_NAME="${BUCKET_NAME:-accessibility-docs-$(openssl rand -hex 3)}"
```

## Usage After Deployment

1. **Upload Documents for Analysis**:
   ```bash
   # Upload PDF documents to trigger accessibility analysis
   gsutil cp your-document.pdf gs://YOUR_BUCKET_NAME/uploads/
   ```

2. **Monitor Processing**:
   ```bash
   # View Cloud Function logs
   gcloud functions logs read YOUR_FUNCTION_NAME \
       --region=us-central1 \
       --limit=10
   ```

3. **Download Reports**:
   ```bash
   # List generated reports
   gsutil ls gs://YOUR_BUCKET_NAME/reports/
   
   # Download accessibility report
   gsutil cp gs://YOUR_BUCKET_NAME/reports/your-document.pdf_accessibility_report.pdf ./
   ```

## Cost Considerations

Estimated monthly costs for moderate usage (100 documents/month):

- **Document AI**: $1.50 per 1,000 pages processed
- **Vertex AI (Gemini)**: $0.000125 per 1K input tokens, $0.000375 per 1K output tokens
- **Cloud Functions**: $0.40 per million invocations + compute time
- **Cloud Storage**: $0.020 per GB/month for standard storage
- **Total estimated**: $5-15/month for 100 documents

> **Note**: Costs vary significantly based on document size, complexity, and processing frequency. Monitor usage through Google Cloud Billing.

## Security Features

- **Service Account Isolation**: Dedicated service accounts with minimal required permissions
- **IAM Least Privilege**: Functions run with only necessary API access
- **Encryption**: All data encrypted at rest and in transit
- **VPC Security**: Optional VPC connector for private network access
- **Audit Logging**: Cloud Audit Logs enabled for compliance tracking

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**:
   ```bash
   # Enable required APIs
   gcloud services enable documentai.googleapis.com
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   ```

2. **Permission Denied Errors**:
   ```bash
   # Check current user permissions
   gcloud auth list
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   ```

3. **Function Deployment Timeout**:
   ```bash
   # Check function status
   gcloud functions describe YOUR_FUNCTION_NAME --region=us-central1
   
   # View deployment logs
   gcloud functions logs read YOUR_FUNCTION_NAME --region=us-central1
   ```

4. **Document AI Processor Issues**:
   ```bash
   # List available processors
   gcloud documentai processors list --location=us-central1
   
   # Check processor status
   gcloud documentai processors describe PROCESSOR_ID --location=us-central1
   ```

### Validation Commands

```bash
# Verify all resources are created
gcloud functions list --regions=us-central1
gcloud documentai processors list --location=us-central1
gsutil ls
gcloud projects get-iam-policy YOUR_PROJECT_ID --flatten="bindings[].members" --format="table(bindings.role)"

# Test the pipeline
echo "Test content" > test.txt
gsutil cp test.txt gs://YOUR_BUCKET_NAME/uploads/test.pdf
sleep 30
gsutil ls gs://YOUR_BUCKET_NAME/reports/
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/YOUR_PROJECT_ID/locations/us-central1/deployments/accessibility-compliance \
    --quiet

# Verify deletion
gcloud infra-manager deployments list
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are deleted
gcloud functions list --regions=us-central1
gcloud documentai processors list --location=us-central1
gsutil ls
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Function
gcloud functions delete YOUR_FUNCTION_NAME --region=us-central1 --quiet

# Delete Document AI processor
gcloud documentai processors delete PROCESSOR_ID --location=us-central1 --quiet

# Delete storage bucket and contents
gsutil -m rm -r gs://YOUR_BUCKET_NAME

# Delete service accounts
gcloud iam service-accounts delete SERVICE_ACCOUNT_EMAIL --quiet
```

## Customization

### Adding Custom WCAG Rules

Modify the Cloud Function code in `main.py` to include additional WCAG success criteria:

```python
# Add custom accessibility rules to the Gemini prompt
custom_wcag_rules = """
5. Custom Compliance:
   - Industry-specific accessibility requirements
   - Regional compliance standards (Section 508, EN 301 549)
   - Custom organizational accessibility policies
"""
```

### Multi-Language Support

Configure Document AI for different languages:

```bash
# Create processors for specific languages
gcloud documentai processors create \
    --location=us-central1 \
    --display-name="accessibility-processor-spanish" \
    --type=OCR_PROCESSOR
```

### Integration with CI/CD

Add the accessibility check to your CI/CD pipeline:

```yaml
# Cloud Build example
- name: 'gcr.io/cloud-builders/gsutil'
  args: ['cp', 'document.pdf', 'gs://YOUR_BUCKET_NAME/uploads/']
- name: 'gcr.io/cloud-builders/gcloud'
  args: ['functions', 'logs', 'read', 'YOUR_FUNCTION_NAME', '--limit=5']
```

## Advanced Configuration

### High Availability Setup

```bash
# Deploy across multiple regions
export REGIONS=("us-central1" "us-east1" "europe-west1")

for region in "${REGIONS[@]}"; do
    # Deploy function to each region
    gcloud functions deploy accessibility-analyzer-${region} \
        --region=${region} \
        --source=.
done
```

### Batch Processing Configuration

```bash
# Configure for high-volume document processing
gcloud functions deploy YOUR_FUNCTION_NAME \
    --memory=2GiB \
    --timeout=540s \
    --max-instances=100 \
    --min-instances=1
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../content-accessibility-compliance-document-ai-gemini.md)
2. Review Google Cloud [Document AI documentation](https://cloud.google.com/document-ai/docs)
3. Consult [Vertex AI Gemini documentation](https://cloud.google.com/vertex-ai/docs/generative-ai)
4. Review [Cloud Functions documentation](https://cloud.google.com/functions/docs)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate with `terraform plan` or Infrastructure Manager preview
3. Update documentation for any new variables or outputs
4. Test cleanup procedures thoroughly

## License

This infrastructure code is provided under the same license as the original recipe content.