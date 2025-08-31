# Infrastructure as Code for AI Content Validation with Vertex AI and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Content Validation with Vertex AI and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions
  - Cloud Storage
  - Vertex AI
  - Cloud Build
  - Service Account management
- For Terraform: Terraform CLI installed (version 1.0+)
- For Infrastructure Manager: Infrastructure Manager API enabled

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager provides Google Cloud's native infrastructure as code experience with state management and drift detection.

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="ai-content-validation"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

Terraform provides cross-cloud infrastructure management with extensive provider ecosystem support.

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

Bash scripts provide direct CLI-based deployment following the recipe's step-by-step approach.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage Buckets**: Input content storage and validation results storage
- **Cloud Function**: Serverless content validation processing with Vertex AI integration
- **IAM Service Accounts**: Secure access management for function execution
- **API Enablement**: Required Google Cloud APIs (Cloud Functions, Vertex AI, Cloud Storage)

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_memory = "512Mi"
function_timeout = "60s"
content_bucket_name = "content-input-custom"
results_bucket_name = "validation-results-custom"
```

### Terraform Variables

Available in `terraform/variables.tf`:

- `project_id`: Google Cloud Project ID
- `region`: Deployment region (default: us-central1)
- `function_memory`: Memory allocation for Cloud Function (default: 512Mi)
- `function_timeout`: Function execution timeout (default: 60s)
- `safety_threshold`: Vertex AI safety threshold configuration

### Bash Script Configuration

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_MEMORY="512Mi"
export FUNCTION_TIMEOUT="60s"
```

## Testing the Deployment

After successful deployment, test the content validation system:

```bash
# Create test content
echo "This is safe test content for validation." > test_content.txt

# Upload to content bucket (triggers validation)
gsutil cp test_content.txt gs://content-input-[SUFFIX]/

# Monitor function logs
gcloud functions logs read content-validator --region=${REGION} --limit=10

# Check validation results
gsutil ls gs://validation-results-[SUFFIX]/validation_results/
gsutil cat gs://validation-results-[SUFFIX]/validation_results/test_content_results.json
```

## Monitoring and Observability

### Function Metrics

```bash
# View function metrics
gcloud functions describe content-validator --region=${REGION}

# Monitor execution metrics
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=content-validator" --limit=20
```

### Storage Metrics

```bash
# Monitor bucket usage
gsutil du -sh gs://content-input-[SUFFIX]/
gsutil du -sh gs://validation-results-[SUFFIX]/
```

## Security Considerations

The infrastructure implements security best practices:

- **Least Privilege IAM**: Function service account has minimal required permissions
- **Private Storage**: Buckets configured with appropriate access controls
- **API Security**: Vertex AI safety filters with configurable thresholds
- **Audit Logging**: Cloud Audit Logs enabled for compliance tracking

## Cost Optimization

- **Function Memory**: Optimized for 512Mi memory allocation
- **Storage Classes**: Standard storage for active content, configurable lifecycle policies
- **API Usage**: Pay-per-request Vertex AI pricing with usage monitoring
- **Function Scaling**: Automatic scaling based on content volume

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
gcloud functions list --regions=${REGION}
gsutil ls gs://content-input-* gs://validation-results-*
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   gcloud services enable cloudfunctions.googleapis.com aiplatform.googleapis.com storage.googleapis.com
   ```

2. **Permission Denied**:
   ```bash
   gcloud auth application-default login
   gcloud config set project ${PROJECT_ID}
   ```

3. **Function Deployment Failed**:
   ```bash
   gcloud functions logs read content-validator --region=${REGION}
   ```

4. **Vertex AI Quota Exceeded**:
   ```bash
   gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)"
   ```

### Log Analysis

```bash
# Function execution logs
gcloud logging read "resource.type=cloud_function" --limit=50

# Storage access logs
gcloud logging read "resource.type=gcs_bucket" --limit=20

# Vertex AI API logs
gcloud logging read "resource.type=vertex_ai" --limit=10
```

## Customization

### Content Safety Thresholds

Modify safety settings in the function code:

```python
safety_settings = [
    SafetySetting(
        category=HarmCategory.HARM_CATEGORY_HATE_SPEECH,
        threshold=HarmBlockThreshold.BLOCK_LOW_AND_ABOVE  # More restrictive
    )
]
```

### Additional Content Types

Extend the function to support additional file formats:

```python
# Add support for PDF, DOCX, etc.
if file_name.endswith('.pdf'):
    content = extract_pdf_content(blob)
elif file_name.endswith('.docx'):
    content = extract_docx_content(blob)
```

### Notification Integration

Add Cloud Pub/Sub notifications for validation results:

```python
from google.cloud import pubsub_v1

def publish_validation_result(validation_result):
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(PROJECT_ID, 'validation-results')
    publisher.publish(topic_path, json.dumps(validation_result).encode())
```

## Performance Tuning

### Function Optimization

- **Memory Allocation**: Increase to 1Gi for large content processing
- **Timeout**: Extend to 120s for complex validation scenarios
- **Concurrency**: Configure max instances based on expected load

### Storage Optimization

- **Lifecycle Policies**: Automatically archive old validation results
- **Regional Buckets**: Use regional storage for better performance
- **Transfer Acceleration**: Enable for high-volume uploads

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Cloud Build configuration
steps:
  - name: 'gcr.io/cloud-builders/gcloud'
    args:
      - 'functions'
      - 'deploy'
      - 'content-validator'
      - '--source=.'
      - '--trigger-bucket=${_CONTENT_BUCKET}'
      - '--runtime=python312'
```

### Workflow Orchestration

```python
# Cloud Workflows integration
from google.cloud import workflows_v1

def trigger_validation_workflow(content_file):
    client = workflows_v1.WorkflowsClient()
    execution = client.create_execution(
        parent=f"projects/{PROJECT_ID}/locations/{REGION}/workflows/content-validation",
        execution={"argument": json.dumps({"file": content_file})}
    )
```

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud documentation:
   - [Cloud Functions](https://cloud.google.com/functions/docs)
   - [Vertex AI](https://cloud.google.com/vertex-ai/docs)
   - [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
3. Verify prerequisites and permissions
4. Check Cloud Console for detailed error messages

## Related Resources

- [Vertex AI Generative AI Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs/)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Responsible AI at Google Cloud](https://cloud.google.com/responsible-ai)
- [Infrastructure Manager Terraform Compatibility](https://cloud.google.com/infrastructure-manager/docs/terraform-compatibility)