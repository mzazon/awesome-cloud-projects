# Infrastructure as Code for Multi-Agent Content Workflows with Gemini 2.5 Reasoning and Cloud Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Agent Content Workflows with Gemini 2.5 Reasoning and Cloud Workflows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for creating:
  - Cloud Storage buckets
  - Cloud Workflows
  - Cloud Functions (2nd gen)
  - Service accounts and IAM policies
  - Vertex AI resources
- Required APIs enabled:
  - Vertex AI API (`aiplatform.googleapis.com`)
  - Cloud Workflows API (`workflows.googleapis.com`)
  - Cloud Functions API (`cloudfunctions.googleapis.com`)
  - Cloud Storage API (`storage.googleapis.com`)
  - Eventarc API (`eventarc.googleapis.com`)
  - Cloud Run API (`run.googleapis.com`)
  - Speech-to-Text API (`speech.googleapis.com`)
  - Vision API (`vision.googleapis.com`)

## Architecture Overview

This solution deploys a sophisticated multi-agent content processing pipeline that:

- **Ingests diverse content types** (text, images, videos) via Cloud Storage
- **Orchestrates specialized AI agents** using Cloud Workflows
- **Processes content intelligently** through Vertex AI and specialized APIs
- **Synthesizes insights** using Gemini 2.5's advanced reasoning capabilities
- **Generates comprehensive business intelligence** with cross-modal analysis

### Key Components

- **Cloud Storage**: Content ingestion and results storage
- **Cloud Functions**: Event-driven workflow triggers
- **Cloud Workflows**: Multi-agent orchestration engine
- **Vertex AI**: Gemini 2.5 Pro for reasoning and analysis
- **Vision API**: Image content analysis
- **Speech-to-Text API**: Audio and video transcript extraction
- **Service Accounts**: Secure inter-service communication

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Clone or navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Initialize and deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/content-workflows \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infrastructure-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-config-bucket/infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the complete infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: "us-central1")
- `bucket_name_suffix`: Suffix for storage bucket names (default: random)
- `workflow_name`: Name for the Cloud Workflow (default: "content-analysis-workflow")
- `function_name_suffix`: Suffix for Cloud Function names (default: random)

### Terraform Variables

Edit `terraform/terraform.tfvars` or pass variables via command line:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# Optional customizations
bucket_name_suffix = "custom-suffix"
workflow_name = "my-content-workflow"
enable_deletion_protection = false
gemini_model = "gemini-2.5-pro"
```

### Environment Variables for Scripts

```bash
export PROJECT_ID="your-project-id"              # Required
export REGION="us-central1"                      # Required
export ZONE="us-central1-a"                      # Optional
export BUCKET_NAME_SUFFIX="custom"               # Optional
export WORKFLOW_NAME="content-analysis"          # Optional
export ENABLE_APIS="true"                        # Optional
```

## Post-Deployment Testing

After deployment, test the multi-agent workflow:

```bash
# Set your deployed bucket name
export BUCKET_NAME="content-intelligence-your-suffix"

# Create test content
echo "Sample business proposal: Our new AI-powered product leverages machine learning to revolutionize customer service." > test-content.txt

# Upload content to trigger processing
gsutil cp test-content.txt gs://${BUCKET_NAME}/input/

# Monitor workflow executions
gcloud workflows executions list \
    --workflow=content-analysis-workflow \
    --location=${REGION}

# Check for results (wait 2-3 minutes for processing)
gsutil ls gs://${BUCKET_NAME}/results/

# Download and review analysis results
gsutil cp gs://${BUCKET_NAME}/results/test-content.txt_analysis.json ./
cat test-content.txt_analysis.json | jq '.'
```

## Monitoring and Observability

### View Workflow Execution Logs

```bash
# Get latest execution ID
EXECUTION_ID=$(gcloud workflows executions list \
    --workflow=content-analysis-workflow \
    --location=${REGION} \
    --limit=1 \
    --format="value(name.basename())")

# View detailed execution logs
gcloud workflows executions describe ${EXECUTION_ID} \
    --workflow=content-analysis-workflow \
    --location=${REGION}
```

### Monitor API Usage and Costs

```bash
# Check Vertex AI API usage
gcloud logging read 'resource.type="aiplatform.googleapis.com/Endpoint"' \
    --limit=50 \
    --format='table(timestamp,jsonPayload.request_id,jsonPayload.model_name)'

# Monitor Cloud Functions invocations
gcloud functions logs read content-trigger-function \
    --region=${REGION} \
    --limit=10
```

## Security Considerations

This implementation follows Google Cloud security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **API Security**: All API calls use proper authentication and authorization
- **Data Encryption**: Data is encrypted in transit and at rest
- **Network Security**: Functions use secure HTTPS endpoints
- **Audit Logging**: All operations are logged for compliance

### Service Account Permissions

The deployment creates a dedicated service account with these roles:
- `roles/aiplatform.user`: Access Vertex AI APIs
- `roles/workflows.invoker`: Execute workflows
- `roles/storage.objectAdmin`: Manage storage objects
- `roles/speech.editor`: Access Speech-to-Text API
- `roles/vision.editor`: Access Vision API

## Cost Optimization

### Estimated Costs (Per 1000 Content Items)

- **Vertex AI (Gemini 2.5 Pro)**: $15-30 (varies by content complexity)
- **Vision API**: $1-3 (for image processing)
- **Speech-to-Text API**: $2-5 (for audio/video content)
- **Cloud Functions**: $0.50-1 (execution time)
- **Cloud Workflows**: $0.10-0.25 (step executions)
- **Cloud Storage**: $0.20-0.50 (storage and operations)

### Cost Optimization Tips

1. **Content Filtering**: Implement pre-processing filters to avoid analyzing irrelevant content
2. **Batch Processing**: Process multiple items in single workflow executions when possible
3. **Intelligent Routing**: Route content to appropriate agents based on content type detection
4. **Result Caching**: Cache frequently accessed analysis results
5. **Lifecycle Policies**: Set up automatic deletion of old content and results

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable aiplatform.googleapis.com workflows.googleapis.com
   ```

2. **Permission Denied Errors**
   ```bash
   # Verify service account has required roles
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:content-intelligence-sa@${PROJECT_ID}.iam.gserviceaccount.com"
   ```

3. **Workflow Execution Failures**
   ```bash
   # Check workflow execution details
   gcloud workflows executions describe EXECUTION_ID \
       --workflow=content-analysis-workflow \
       --location=${REGION}
   ```

4. **Function Trigger Issues**
   ```bash
   # Verify Cloud Function configuration
   gcloud functions describe content-trigger-function --region=${REGION}
   ```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Enable debug logging for workflows
gcloud logging read 'resource.type="workflows.googleapis.com/Workflow"' \
    --limit=20 \
    --format='table(timestamp,severity,jsonPayload.message)'
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/content-workflows
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify cleanup completion
gsutil ls gs://content-intelligence-* 2>/dev/null || echo "All buckets cleaned up"
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
gcloud workflows delete content-analysis-workflow --location=${REGION} --quiet
gcloud functions delete content-trigger-function --region=${REGION} --quiet
gsutil -m rm -r gs://content-intelligence-*
gcloud iam service-accounts delete content-intelligence-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Customization

### Adding New Content Types

1. **Extend the workflow definition** to handle new content types
2. **Create specialized agent subworkflows** for new content analysis
3. **Update the Cloud Function trigger** to recognize new file types
4. **Modify the reasoning engine prompts** to incorporate new content insights

### Enhancing AI Capabilities

1. **Tune Gemini parameters** for specific use cases
2. **Implement custom prompts** for domain-specific analysis
3. **Add new AI services** like Translation API or Document AI
4. **Create feedback loops** for continuous model improvement

### Integration Patterns

1. **API Gateway**: Add Cloud Endpoints for external API access
2. **Pub/Sub Integration**: Use Pub/Sub for asynchronous processing
3. **BigQuery Analytics**: Store analysis results in BigQuery for reporting
4. **Cloud Scheduler**: Implement batch processing schedules

## Support and Documentation

- **Recipe Documentation**: Refer to the complete recipe markdown file
- **Google Cloud Documentation**: [Cloud Workflows](https://cloud.google.com/workflows/docs), [Vertex AI](https://cloud.google.com/vertex-ai/docs)
- **API References**: [Gemini API](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/gemini), [Vision API](https://cloud.google.com/vision/docs), [Speech-to-Text API](https://cloud.google.com/speech-to-text/docs)
- **Best Practices**: [Google Cloud Architecture Center](https://cloud.google.com/architecture)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes thoroughly in a development environment
2. Follow Google Cloud best practices and security guidelines
3. Update documentation for any configuration changes
4. Validate that all IaC implementations remain synchronized

## License

This infrastructure code is provided as-is for educational and reference purposes. Ensure compliance with your organization's policies and Google Cloud terms of service.