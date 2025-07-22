# Infrastructure as Code for Content Syndication with Hierarchical Namespace Storage and Agent Development Kit

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Content Syndication with Hierarchical Namespace Storage and Agent Development Kit".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Python 3.10+ for Agent Development Kit
- Required APIs enabled:
  - Cloud Storage API
  - Vertex AI API
  - Cloud Workflows API
  - Cloud Functions API
  - Infrastructure Manager API (for Infrastructure Manager deployment)
- Appropriate IAM permissions:
  - Storage Admin
  - AI Platform Admin
  - Workflows Admin
  - Cloud Functions Admin
  - Service Account Admin

## Quick Start

### Using Infrastructure Manager

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/content-syndication \
    --config-file=main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Check deployment status
gcloud infra-manager deployments describe \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/content-syndication
```

### Using Terraform

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Apply the configuration
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud storage buckets list --filter="name:content-hns-*"
gcloud workflows list --location=${REGION}
gcloud functions list --filter="name:process-content"
```

## Architecture Overview

This infrastructure deploys:

- **Hierarchical Namespace Storage**: Cloud Storage bucket with HNS enabled for optimized file operations
- **Agent Development Kit Environment**: Python environment for intelligent content processing agents
- **Content Processing Agents**: AI agents for content analysis, routing, and quality assessment
- **Cloud Workflows**: Serverless orchestration for automated content processing
- **Cloud Functions**: Integration layer between storage events and agent processing
- **IAM Configuration**: Least-privilege service accounts and permissions

## Configuration Options

### Infrastructure Manager Variables

Customize your deployment by modifying the input values:

```yaml
# In main.yaml
inputValues:
  project_id: "your-project-id"
  region: "us-central1"
  bucket_name_prefix: "content-hns"
  workflow_name: "content-syndication-workflow"
  function_memory: "512MB"
  function_timeout: "300s"
  enable_monitoring: true
```

### Terraform Variables

Customize your deployment in `terraform.tfvars`:

```hcl
project_id          = "your-project-id"
region             = "us-central1"
zone               = "us-central1-a"
bucket_name_prefix = "content-hns"
workflow_name      = "content-syndication-workflow"
function_memory    = 512
function_timeout   = 300
labels = {
  environment = "development"
  purpose     = "content-syndication"
}
```

### Environment Variables for Scripts

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export BUCKET_PREFIX="content-hns"
export WORKFLOW_NAME="content-syndication-workflow"
export FUNCTION_MEMORY="512MB"
export FUNCTION_TIMEOUT="300s"
```

## Deployment Details

### Resources Created

1. **Storage Resources**:
   - Cloud Storage bucket with Hierarchical Namespace enabled
   - Organized folder structure for content pipeline
   - Bucket lifecycle policies for cost optimization

2. **Compute Resources**:
   - Cloud Function for content processing integration
   - Python runtime environment for Agent Development Kit
   - Appropriate memory and timeout configurations

3. **Workflow Resources**:
   - Cloud Workflows definition for automation
   - Event-driven triggers for content processing
   - Error handling and retry logic

4. **IAM Resources**:
   - Service accounts for each component
   - Least-privilege IAM bindings
   - Cross-service authentication configuration

5. **Monitoring Resources**:
   - Cloud Logging configuration
   - Performance monitoring setup
   - Alert policies for critical failures

### Post-Deployment Setup

After infrastructure deployment, complete these steps:

1. **Set up Agent Development Kit**:
   ```bash
   # Create virtual environment
   python -m venv adk-env
   source adk-env/bin/activate
   
   # Install dependencies
   pip install google-adk-agents google-cloud-storage google-cloud-aiplatform
   ```

2. **Configure environment variables**:
   ```bash
   export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
   export GOOGLE_CLOUD_REGION=${REGION}
   export STORAGE_BUCKET=$(terraform output -raw bucket_name)
   ```

3. **Test the deployment**:
   ```bash
   # Upload test content
   echo "Sample content" > test-file.txt
   gcloud storage cp test-file.txt gs://$(terraform output -raw bucket_name)/incoming/
   
   # Monitor workflow execution
   gcloud workflows executions list --workflow=$(terraform output -raw workflow_name) --location=${REGION}
   ```

## Testing the Solution

### Upload Test Content

```bash
# Create sample content files
echo "Sample video content metadata" > test-video.mp4
echo "Sample image content metadata" > test-image.jpg
echo "Sample document content" > test-document.pdf

# Upload to incoming folder
BUCKET_NAME=$(terraform output -raw bucket_name)
gcloud storage cp test-video.mp4 gs://${BUCKET_NAME}/incoming/
gcloud storage cp test-image.jpg gs://${BUCKET_NAME}/incoming/
gcloud storage cp test-document.pdf gs://${BUCKET_NAME}/incoming/
```

### Monitor Processing

```bash
# Check workflow executions
gcloud workflows executions list \
    --workflow=$(terraform output -raw workflow_name) \
    --location=${REGION}

# Check function logs
gcloud functions logs read process-content --limit=50

# Verify content organization
gcloud storage ls -r gs://${BUCKET_NAME}/
```

### Validate Agent Processing

```bash
# Check content categorization
gcloud storage ls gs://${BUCKET_NAME}/categorized/

# Review processing logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=process-content" \
    --limit=20 --format="table(timestamp,textPayload)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/content-syndication

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Clean up Terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
gcloud storage buckets list --filter="name:content-hns-*"
gcloud workflows list --location=${REGION}
gcloud functions list --filter="name:process-content"
```

### Manual Cleanup Verification

```bash
# Ensure all resources are removed
gcloud storage buckets list --filter="name:content-hns-*"
gcloud workflows list --location=${REGION}
gcloud functions list
gcloud iam service-accounts list --filter="email:content-*"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable storage.googleapis.com
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable workflows.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/storage.admin"
   ```

3. **Hierarchical Namespace Issues**:
   ```bash
   # Verify HNS is enabled
   gcloud storage buckets describe gs://${BUCKET_NAME} \
       --format="value(hierarchicalNamespace.enabled)"
   ```

4. **Agent Development Kit Issues**:
   ```bash
   # Check Python environment
   python --version
   pip list | grep google-adk-agents
   
   # Reinstall if needed
   pip install --upgrade google-adk-agents
   ```

### Debugging Commands

```bash
# Check Cloud Function status
gcloud functions describe process-content --region=${REGION}

# View detailed workflow execution
gcloud workflows executions describe EXECUTION_ID \
    --workflow=${WORKFLOW_NAME} \
    --location=${REGION}

# Monitor real-time logs
gcloud logging tail "resource.type=cloud_function"
```

## Cost Optimization

- **Storage Lifecycle**: Implement automatic transition to cheaper storage classes
- **Function Optimization**: Monitor function execution time and memory usage
- **Workflow Efficiency**: Optimize workflow logic to reduce execution time
- **Monitoring**: Set up billing alerts and cost monitoring

## Security Considerations

- Service accounts use least-privilege principles
- Storage bucket access is restricted to necessary services
- Cloud Function authentication is properly configured
- Workflow permissions are scoped appropriately
- All communication uses secure channels

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Validate API enablement and permissions
4. Monitor logs for detailed error information
5. Test with minimal example content first

## Additional Resources

- [Google Cloud Storage Hierarchical Namespace Documentation](https://cloud.google.com/storage/docs/hns-overview)
- [Agent Development Kit Guide](https://cloud.google.com/vertex-ai/generative-ai/docs/agent-development-kit/quickstart)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)