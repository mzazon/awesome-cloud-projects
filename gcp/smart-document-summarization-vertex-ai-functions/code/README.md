# Infrastructure as Code for Smart Document Summarization with Vertex AI and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Document Summarization with Vertex AI and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 450.0.0 or later)
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions deployment and management
  - Cloud Storage bucket creation and management
  - Vertex AI API access and model usage
  - Service account creation and IAM binding
  - Cloud Build API access
  - Eventarc trigger management
- Python 3.11+ runtime for local development (if customizing function code)
- Terraform 1.5+ (if using Terraform implementation)

## Cost Considerations

- **Cloud Functions**: Pay-per-invocation with generous free tier
- **Cloud Storage**: Standard storage pricing based on data volume
- **Vertex AI**: Usage-based pricing for Gemini model API calls
- **Cloud Build**: Build minutes for function deployment
- Estimated cost for testing: $5-15 (varies by document volume and AI model usage)

## Architecture Overview

This solution deploys:
- Cloud Storage bucket for document ingestion and summary storage
- Cloud Function (Gen 2) for document processing orchestration
- Vertex AI Gemini model integration for intelligent summarization
- IAM roles and permissions for secure service integration
- Cloud Storage event triggers for automated processing

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Update main.yaml with your project details if needed
# Deploy the infrastructure
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/doc-summarizer \
    --service-account="projects/$PROJECT_ID/serviceAccounts/deployment-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe projects/$PROJECT_ID/locations/$REGION/deployments/doc-summarizer
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Set required variables (or create terraform.tfvars)
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# View important outputs
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

# Deploy the complete solution
./deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create Cloud Storage bucket
# 3. Deploy Cloud Function with dependencies
# 4. Configure IAM permissions
# 5. Set up event triggers
# 6. Create sample test documents
```

## Testing the Deployment

After deployment, test the document summarization pipeline:

```bash
# Create a test document
cat > test_document.txt << 'EOF'
QUARTERLY BUSINESS REPORT - Q4 2024

Executive Summary:
This report presents the financial and operational performance for Q4 2024. 
Revenue increased by 15% compared to Q3, reaching $2.4 million. Key achievements 
include successful product launch, expansion into new markets, and improved 
customer satisfaction scores.

Financial Highlights:
- Total Revenue: $2,400,000 (15% increase)
- Net Profit: $360,000 (18% increase) 
- Operating Expenses: $1,890,000
- Customer Acquisition Cost: $120 (down from $145)

Strategic Initiatives:
1. Launched AI-powered customer service platform
2. Expanded operations to European markets
3. Implemented new data analytics infrastructure
4. Achieved ISO 27001 security certification
EOF

# Upload document to trigger processing
BUCKET_NAME=$(gcloud storage buckets list --filter="name:doc-summarizer-*" --format="value(name)")
gcloud storage cp test_document.txt gs://$BUCKET_NAME/

# Wait for processing (usually 30-60 seconds)
sleep 60

# Check for generated summary
gcloud storage ls gs://$BUCKET_NAME/*_summary.txt

# View the summary
gcloud storage cat gs://$BUCKET_NAME/test_document.txt_summary.txt
```

## Monitoring and Logging

Monitor the solution using Google Cloud Console:

```bash
# View Cloud Function logs
gcloud functions logs read summarize-document \
    --region=$REGION \
    --gen2 \
    --limit=20

# Monitor function metrics
gcloud functions describe summarize-document \
    --region=$REGION \
    --gen2 \
    --format="value(state,updateTime)"

# Check Vertex AI usage
gcloud logging read "resource.type=vertex_ai_endpoint" --limit=10
```

## Customization

### Function Configuration

Modify the Cloud Function behavior by updating:
- `main.py`: Core processing logic and AI prompts
- `requirements.txt`: Python dependencies
- Function memory, timeout, and scaling settings

### AI Model Configuration

Customize the Vertex AI integration:
- Model selection (Gemini 1.5 Pro vs Gemini 1.5 Flash)
- Prompt engineering for specific document types
- Token limits and content processing strategies

### Storage Configuration

Adjust storage settings:
- Bucket location and storage class
- Lifecycle policies for automatic cleanup
- Access controls and security settings

### Common Variables

Key variables that can be customized across all implementations:

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | Google Cloud Project ID | Required |
| `region` | Deployment region | `us-central1` |
| `bucket_name` | Storage bucket name | Auto-generated |
| `function_name` | Cloud Function name | `summarize-document` |
| `function_memory` | Function memory allocation | `1Gi` |
| `function_timeout` | Function timeout | `540s` |
| `max_instances` | Maximum function instances | `10` |

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/doc-summarizer \
    --quiet

# Verify resources are removed
gcloud storage buckets list --filter="name:doc-summarizer-*"
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
cd scripts/
./destroy.sh

# The script will:
# 1. Delete the Cloud Function
# 2. Remove the storage bucket and all contents
# 3. Clean up IAM bindings
# 4. Remove local test files
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   - Verify APIs are enabled: `gcloud services list --enabled`
   - Check IAM permissions for Cloud Build
   - Ensure Python 3.11 runtime is supported in your region

2. **Document processing not triggered**:
   - Verify Eventarc trigger: `gcloud eventarc triggers list`
   - Check function logs for errors
   - Ensure file is not in ignored list (summaries, ready.txt)

3. **Vertex AI authentication errors**:
   - Verify service account has `roles/aiplatform.user`
   - Check project ID environment variable
   - Ensure Vertex AI API is enabled

4. **Out of memory errors**:
   - Increase function memory allocation
   - Reduce document size or implement chunking
   - Optimize text extraction logic

### Performance Optimization

- Use Cloud Function concurrency settings for high-volume processing
- Implement batching for multiple documents
- Consider using Cloud Run for long-running or memory-intensive processing
- Optimize Vertex AI model selection based on document complexity

## Security Best Practices

- Function uses least-privilege service account permissions
- Storage bucket configured with appropriate access controls
- Vertex AI access limited to necessary models and operations
- All traffic encrypted in transit
- Function source code stored securely in Cloud Build

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation for context
2. Review Google Cloud documentation for specific services
3. Verify current API versions and service availability
4. Test with minimal examples to isolate issues

## Additional Resources

- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Generative AI Guide](https://cloud.google.com/vertex-ai/generative-ai/docs)
- [Cloud Storage Triggers Guide](https://cloud.google.com/functions/docs/calling/storage)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)