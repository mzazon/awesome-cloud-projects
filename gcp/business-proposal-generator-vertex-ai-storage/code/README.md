# Infrastructure as Code for Business Proposal Generator with Vertex AI and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Business Proposal Generator with Vertex AI and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Storage (Admin)
  - Cloud Functions (Admin)
  - Vertex AI (User)
  - Service Account (Admin)
  - Cloud Build (Editor)
- Node.js 20+ (for Cloud Functions runtime)

## Architecture Overview

This solution deploys:
- 3 Cloud Storage buckets (templates, client data, generated proposals)
- Cloud Function with storage trigger for proposal generation
- IAM service account with appropriate permissions
- Vertex AI API integration for content generation

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/proposal-generator \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="inputs.yaml"
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id"

# Apply infrastructure
terraform apply -var="project_id=your-project-id"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/inputs.yaml`:

```yaml
project_id: "your-project-id"
region: "us-central1"
environment: "dev"
function_memory: "512Mi"
function_timeout: "540s"
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
project_id      = "your-project-id"
region          = "us-central1"
environment     = "dev"
function_memory = 512
function_timeout = 540
```

### Bash Script Variables

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ENVIRONMENT="dev"
export FUNCTION_MEMORY="512MB"
export FUNCTION_TIMEOUT="540s"
```

## Testing the Deployment

After deployment, test the proposal generation workflow:

1. **Upload a proposal template**:
   ```bash
   # Create sample template
   cat > proposal-template.txt << 'EOF'
   BUSINESS PROPOSAL TEMPLATE
   
   Dear {{CLIENT_NAME}},
   
   Thank you for considering our services for {{PROJECT_TYPE}}.
   
   PROJECT OVERVIEW:
   {{PROJECT_OVERVIEW}}
   
   SOLUTION APPROACH:
   {{SOLUTION_APPROACH}}
   
   TIMELINE: {{TIMELINE}}
   INVESTMENT: {{INVESTMENT}}
   
   Best regards,
   Business Development Team
   EOF
   
   # Upload to templates bucket
   gsutil cp proposal-template.txt gs://$(terraform output -raw templates_bucket_name)/
   ```

2. **Upload client data to trigger generation**:
   ```bash
   # Create sample client data
   cat > client-data.json << 'EOF'
   {
     "client_name": "TechCorp Solutions",
     "industry": "Financial Services",
     "project_type": "Digital Transformation Initiative",
     "requirements": [
       "Modernize legacy banking systems",
       "Implement cloud-native architecture",
       "Enhance mobile banking experience"
     ],
     "timeline": "6-month implementation",
     "budget_range": "$500K - $1M"
   }
   EOF
   
   # Upload to trigger function
   gsutil cp client-data.json gs://$(terraform output -raw client_data_bucket_name)/
   ```

3. **Check generated proposals**:
   ```bash
   # Wait for processing (30-60 seconds)
   sleep 60
   
   # List generated proposals
   gsutil ls gs://$(terraform output -raw output_bucket_name)/
   
   # Download and view generated proposal
   gsutil cp gs://$(terraform output -raw output_bucket_name)/proposal-* ./generated-proposal.txt
   cat generated-proposal.txt
   ```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Get function name from outputs
FUNCTION_NAME=$(terraform output -raw function_name)

# View recent logs
gcloud functions logs read ${FUNCTION_NAME} --limit 20
```

### Check Function Status

```bash
# Describe function details
gcloud functions describe ${FUNCTION_NAME} --region=${REGION}
```

### Monitor Storage Activity

```bash
# Check bucket contents
gsutil ls -la gs://$(terraform output -raw client_data_bucket_name)/
gsutil ls -la gs://$(terraform output -raw output_bucket_name)/
```

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/proposal-generator
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

## Cost Optimization

This solution uses pay-per-use services:

- **Cloud Storage**: ~$0.02/GB/month for standard storage
- **Cloud Functions**: ~$0.0000004 per invocation + compute time
- **Vertex AI**: ~$0.00025 per 1K characters for Gemini 1.5 Flash

### Cost Management Tips

1. Set up billing alerts in Google Cloud Console
2. Use Cloud Storage lifecycle policies for old proposals
3. Monitor Vertex AI usage in the AI Platform console
4. Consider using Cloud Scheduler for batch processing large volumes

## Security Considerations

The deployed infrastructure includes:

- IAM service account with minimal required permissions
- Private Cloud Function (no public HTTP trigger)
- Storage buckets with uniform bucket-level access
- Vertex AI API access restricted to the service account

### Additional Security Hardening

1. **Enable VPC Service Controls** for additional network security
2. **Configure Cloud KMS** for customer-managed encryption keys
3. **Set up Cloud Audit Logs** for compliance tracking
4. **Implement bucket-level IAM** for fine-grained access control

## Customization

### Modify AI Model Parameters

Edit the Cloud Function source to adjust Vertex AI settings:

```javascript
const generativeModel = vertexAI.getGenerativeModel({
  model: 'gemini-1.5-flash',
  generationConfig: {
    maxOutputTokens: 2048,
    temperature: 0.3,      // Lower = more consistent
    topP: 0.8,            // Nucleus sampling
    topK: 40              // Top-k sampling
  }
});
```

### Add Multiple Templates

Support different proposal types by organizing templates in subdirectories:

```bash
# Upload templates for different industries
gsutil cp tech-proposal-template.txt gs://${TEMPLATES_BUCKET}/technology/
gsutil cp finance-proposal-template.txt gs://${TEMPLATES_BUCKET}/finance/
gsutil cp healthcare-proposal-template.txt gs://${TEMPLATES_BUCKET}/healthcare/
```

### Integrate with External Systems

Extend the function to:
- Send notifications via Pub/Sub
- Store metadata in Firestore
- Integrate with CRM systems via webhooks
- Generate PDFs using additional services

## Troubleshooting

### Common Issues

1. **Function not triggering**:
   - Check bucket notifications: `gsutil notification list gs://bucket-name`
   - Verify IAM permissions for the service account
   - Check function logs for errors

2. **Vertex AI errors**:
   - Ensure Vertex AI API is enabled
   - Check service account has `aiplatform.user` role
   - Verify region supports Gemini models

3. **Permission denied errors**:
   - Review IAM bindings in the Cloud Console
   - Ensure service account has required Storage permissions
   - Check if APIs are enabled

### Getting Help

- Check the [Cloud Functions documentation](https://cloud.google.com/functions/docs)
- Review [Vertex AI troubleshooting guides](https://cloud.google.com/vertex-ai/docs/troubleshooting)
- Monitor the [Google Cloud Status page](https://status.cloud.google.com/)

## Support

For issues with this infrastructure code, refer to:
- Original recipe documentation
- [Google Cloud documentation](https://cloud.google.com/docs)
- [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)