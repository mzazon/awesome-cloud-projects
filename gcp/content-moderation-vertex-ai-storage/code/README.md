# Infrastructure as Code for Content Moderation with Vertex AI and Cloud Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Content Moderation with Vertex AI and Cloud Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Project Editor or Owner role
  - Service Account Admin role
  - Cloud Functions Admin role
  - Storage Admin role
  - Pub/Sub Admin role
  - Vertex AI User role
- For Terraform: Terraform CLI v1.0+ installed
- For Infrastructure Manager: Google Cloud Infrastructure Manager API enabled

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Enable the Infrastructure Manager API
gcloud services enable config.googleapis.com

# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/content-moderation \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/content-moderator-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/content-moderation-vertex-ai-storage/code/infrastructure-manager" \
    --git-source-ref="main"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/content-moderation
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy the example variables file and customize
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# Note the outputs for testing
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# Test the deployment (optional)
./scripts/test.sh

# View deployment status
./scripts/status.sh
```

## Architecture Overview

This implementation creates:

- **Cloud Storage Buckets**: Three buckets for incoming content, quarantined content, and approved content
- **Cloud Functions**: Two serverless functions for content moderation and quarantine notifications
- **Vertex AI Integration**: Gemini model for multimodal content analysis
- **Pub/Sub Topics**: Event-driven messaging for reliable content processing
- **IAM Service Accounts**: Secure service accounts with minimal required permissions
- **Eventarc Triggers**: Automatic function triggering on storage events

## Configuration Options

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `bucket_suffix` | Unique suffix for bucket names | Random | No |
| `function_memory` | Memory allocation for functions | `1024MB` | No |
| `function_timeout` | Function timeout in seconds | `540` | No |
| `max_instances` | Maximum function instances | `10` | No |
| `enable_notifications` | Enable quarantine notifications | `true` | No |

### Infrastructure Manager Parameters

The Infrastructure Manager implementation uses similar parameters defined in the YAML configuration file. Customize the `main.yaml` file to adjust:

- Resource naming conventions
- Memory and timeout settings
- IAM permissions
- Storage configurations

## Testing the Deployment

After deployment, test the content moderation system:

```bash
# Test with safe content
echo "This is a safe message about technology." > test-safe.txt
gsutil cp test-safe.txt gs://content-incoming-${BUCKET_SUFFIX}/

# Test with potentially harmful content
echo "This text contains inappropriate language that should be flagged." > test-harmful.txt
gsutil cp test-harmful.txt gs://content-incoming-${BUCKET_SUFFIX}/

# Wait for processing (30-60 seconds)
sleep 60

# Check results
gsutil ls gs://content-approved-${BUCKET_SUFFIX}/
gsutil ls gs://content-quarantine-${BUCKET_SUFFIX}/

# View function logs
gcloud functions logs read content-moderator-${BUCKET_SUFFIX} --region=${REGION}
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Content moderation function logs
gcloud functions logs read content-moderator-${BUCKET_SUFFIX} \
    --region=${REGION} \
    --limit=50

# Notification function logs
gcloud functions logs read quarantine-notifier-${BUCKET_SUFFIX} \
    --region=${REGION} \
    --limit=50
```

### Check Function Status

```bash
# List all functions
gcloud functions list --regions=${REGION}

# Describe specific function
gcloud functions describe content-moderator-${BUCKET_SUFFIX} \
    --region=${REGION}
```

### Monitor Storage Buckets

```bash
# Check bucket contents
gsutil ls -la gs://content-incoming-${BUCKET_SUFFIX}/
gsutil ls -la gs://content-approved-${BUCKET_SUFFIX}/
gsutil ls -la gs://content-quarantine-${BUCKET_SUFFIX}/

# View bucket notifications
gsutil notification list gs://content-incoming-${BUCKET_SUFFIX}/
```

### Vertex AI Usage

```bash
# Check Vertex AI API usage
gcloud ai operations list --region=${REGION}

# Monitor API quotas
gcloud logging read 'resource.type="consumed_api" AND protoPayload.serviceName="aiplatform.googleapis.com"' \
    --limit=10 \
    --format="table(timestamp, protoPayload.methodName, protoPayload.request.model)"
```

## Security Considerations

This implementation follows Google Cloud security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **Secure Storage**: Buckets are configured with appropriate access controls
- **Encryption**: All data is encrypted at rest and in transit
- **Audit Logging**: All operations are logged for compliance
- **Network Security**: Functions run in Google's secure environment

## Cost Optimization

To minimize costs:

1. **Storage Lifecycle**: Quarantine bucket has lifecycle policies for cost optimization
2. **Function Scaling**: Max instances limit prevents runaway costs
3. **Regional Deployment**: Resources deployed in single region
4. **Monitoring**: Set up billing alerts for cost monitoring

```bash
# Set up billing alerts
gcloud alpha billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Content Moderation Budget" \
    --budget-amount=50 \
    --threshold-rules-percent=0.5,0.8,1.0
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/content-moderation

# Wait for deletion to complete
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/content-moderation
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete remaining resources
gcloud functions delete content-moderator-${BUCKET_SUFFIX} --region=${REGION} --quiet
gcloud functions delete quarantine-notifier-${BUCKET_SUFFIX} --region=${REGION} --quiet
gsutil -m rm -r gs://content-incoming-${BUCKET_SUFFIX}
gsutil -m rm -r gs://content-approved-${BUCKET_SUFFIX}
gsutil -m rm -r gs://content-quarantine-${BUCKET_SUFFIX}
gcloud iam service-accounts delete content-moderator-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**
   - Check if all required APIs are enabled
   - Verify service account permissions
   - Ensure source code is properly structured

2. **Storage Triggers Not Working**
   - Verify Eventarc API is enabled
   - Check function trigger configuration
   - Ensure proper IAM permissions for Eventarc

3. **Vertex AI API Errors**
   - Enable Vertex AI API in your project
   - Check API quotas and limits
   - Verify service account has aiplatform.user role

4. **Permission Denied Errors**
   - Review IAM policies
   - Ensure service account has required roles
   - Check if APIs are enabled

### Getting Help

- Review the original recipe documentation
- Check Google Cloud documentation for specific services
- Use `gcloud help` for command assistance
- Check Cloud Console for detailed error messages

## Customization

### Extending the Solution

1. **Add More Content Types**: Modify functions to handle video, audio, or documents
2. **Custom AI Models**: Replace Gemini with custom AutoML models
3. **Integration APIs**: Add REST APIs for external system integration
4. **Advanced Workflows**: Implement human review workflows with Cloud Tasks
5. **Multi-language Support**: Add Cloud Translation API for global content

### Configuration Files

- `terraform/terraform.tfvars`: Terraform variable customization
- `infrastructure-manager/main.yaml`: Infrastructure Manager configuration
- `scripts/config.sh`: Bash script configuration

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation
4. Check the GitHub issues for known problems

## Version Information

- **Terraform Provider**: `google ~> 5.0`
- **Infrastructure Manager**: Latest available version
- **Cloud Functions Runtime**: Python 3.11
- **Vertex AI**: Gemini 1.5 Pro model
- **Generated**: 2025-07-12