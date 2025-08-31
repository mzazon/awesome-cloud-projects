# Infrastructure as Code for Content Quality Scoring with Vertex AI and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Content Quality Scoring with Vertex AI and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (gcloud version 450.0.0+)
- Terraform installed (version 1.0+) for Terraform deployment
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions creation and management
  - Cloud Storage bucket creation and management
  - Vertex AI API access
  - Cloud Build service usage
  - Eventarc service usage
- Estimated cost: $2-5 for testing and initial deployment

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

Infrastructure Manager provides Google Cloud's recommended approach for infrastructure as code with native integration and Google Cloud Console support.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
export DEPLOYMENT_NAME="content-quality-scoring"

# Create deployment using gcloud
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/content-quality-scoring-vertex-ai-functions/code/infrastructure-manager" \
    --git-source-ref="main"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/us-central1/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive community support with Google Cloud provider modules.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct gcloud CLI execution with comprehensive error handling and progress tracking.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow prompts to configure project and region
# Scripts will create all required resources automatically
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Storage Buckets**: Input content bucket and analysis results bucket with versioning
- **Cloud Function**: Event-driven function for content analysis using Vertex AI
- **IAM Roles**: Service accounts and permissions for secure resource access
- **API Enablement**: Required Google Cloud APIs (Functions, Storage, Vertex AI, Build, Eventarc)
- **Event Triggers**: Storage event triggers for automatic content processing

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  bucket_suffix:
    description: "Unique suffix for bucket names"
    type: string
  function_memory:
    description: "Memory allocation for Cloud Function"
    type: string
    default: "512Mi"
  function_timeout:
    description: "Timeout for Cloud Function execution"
    type: string
    default: "540s"
```

### Terraform Variables

Customize deployment by editing `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
bucket_suffix = "unique-identifier"
function_memory = 512
function_timeout = 540
max_instances = 10
```

### Environment Variables for Scripts

Set these variables before running bash scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
```

## Deployment Details

### Resource Naming Convention

All resources use consistent naming with configurable suffixes:

- Content Bucket: `content-analysis-${BUCKET_SUFFIX}`
- Results Bucket: `quality-results-${BUCKET_SUFFIX}`
- Cloud Function: `analyze-content-quality`

### Security Configuration

- **Service Accounts**: Dedicated service account with minimal required permissions
- **IAM Bindings**: Least privilege access for Cloud Function to Storage and Vertex AI
- **API Security**: Functions use Google Cloud IAM for authentication
- **Storage Security**: Bucket-level IAM controls and versioning enabled

### Monitoring and Logging

- **Cloud Functions Logs**: Comprehensive logging for debugging and monitoring
- **Error Handling**: Robust error handling with detailed error messages
- **Performance Metrics**: Built-in Cloud Functions metrics and monitoring

## Testing the Deployment

After successful deployment, test the content analysis system:

```bash
# Upload sample content to trigger analysis
echo "This is a test article about cloud computing best practices..." > test-content.txt
gsutil cp test-content.txt gs://content-analysis-${BUCKET_SUFFIX}/

# Wait for processing (30-60 seconds)
sleep 60

# Check for analysis results
gsutil ls gs://quality-results-${BUCKET_SUFFIX}/

# Download and view results
gsutil cp gs://quality-results-${BUCKET_SUFFIX}/analysis_test-content.txt_*.json ./
cat analysis_test-content.txt_*.json | jq '.'
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/${DEPLOYMENT_NAME}

# Confirm deletion
gcloud infra-manager deployments list --location=us-central1 --project=${PROJECT_ID}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# Script will remove all created resources safely
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
   ```bash
   gcloud services list --enabled --project=${PROJECT_ID}
   ```

2. **Permission Denied**: Verify IAM permissions for deployment service account
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Function Deployment Failed**: Check Cloud Build logs for detailed error messages
   ```bash
   gcloud functions logs read analyze-content-quality --gen2 --region=${REGION}
   ```

4. **Vertex AI Quota**: Ensure sufficient Vertex AI quota for your project region
   ```bash
   gcloud compute quotas list --filter="service:aiplatform.googleapis.com"
   ```

### Debugging Steps

1. **Verify Resource Creation**:
   ```bash
   # Check Cloud Function status
   gcloud functions describe analyze-content-quality --gen2 --region=${REGION}
   
   # Check Storage buckets
   gsutil ls -p ${PROJECT_ID}
   
   # Verify API enablement
   gcloud services list --enabled | grep -E "(cloudfunctions|storage|aiplatform)"
   ```

2. **Monitor Function Execution**:
   ```bash
   # Real-time log monitoring
   gcloud functions logs tail analyze-content-quality --gen2 --region=${REGION}
   ```

3. **Test Vertex AI Access**:
   ```bash
   # Verify Vertex AI API access
   gcloud ai models list --region=${REGION}
   ```

## Cost Management

### Estimated Costs

- **Cloud Functions**: $0.0000004 per invocation + $0.0000025 per GB-second
- **Cloud Storage**: $0.02 per GB per month (Standard class)
- **Vertex AI Gemini**: $0.00025 per 1K input tokens, $0.0005 per 1K output tokens
- **Data Transfer**: Minimal for same-region operations

### Cost Optimization Tips

1. **Function Memory**: Adjust memory allocation based on actual usage patterns
2. **Storage Class**: Use appropriate storage classes for different retention needs
3. **Batch Processing**: Consider batching multiple files for analysis efficiency
4. **Monitoring**: Use Cloud Monitoring to track usage and optimize accordingly

## Advanced Configuration

### Custom Content Analysis Prompts

Modify the function code to customize analysis criteria:

```python
# In main.py, update the prompt template
prompt = f"""
Analyze the following content for your specific criteria:
- Brand voice consistency
- Industry-specific terminology
- Target audience alignment
...
"""
```

### Multi-Language Support

Enable multi-language content analysis:

```python
# Add language detection and processing
from google.cloud import translate_v2 as translate

# Detect content language and adjust analysis accordingly
```

### Integration with External Systems

Connect with existing content management systems:

```python
# Add webhook notifications or API integrations
# Send results to external dashboards or CMSs
```

## Support and Documentation

- **Google Cloud Functions**: [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- **Vertex AI Generative AI**: [Vertex AI Documentation](https://cloud.google.com/vertex-ai/generative-ai/docs)
- **Cloud Storage Events**: [Storage Event Triggers](https://cloud.google.com/storage/docs/pubsub-notifications)
- **Infrastructure Manager**: [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- **Terraform Google Provider**: [Terraform Registry](https://registry.terraform.io/providers/hashicorp/google/latest)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud's support resources.

## Contributing

To improve this infrastructure code:

1. Test changes in a separate project environment
2. Validate against Google Cloud best practices
3. Update documentation accordingly
4. Consider cost and security implications
5. Test cleanup procedures thoroughly

## License

This infrastructure code is provided as-is for educational and reference purposes. Ensure compliance with your organization's policies and Google Cloud terms of service.