# Infrastructure as Code for Automated Code Documentation with Gemini and Cloud Build

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Code Documentation with Gemini and Cloud Build".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate permissions for resource creation:
  - Vertex AI User
  - Cloud Build Editor
  - Storage Admin
  - Cloud Functions Admin
  - Service Account Admin
  - Project IAM Admin
- For Terraform: Terraform CLI (>= 1.5.0) installed

## Architecture Overview

This solution deploys:
- Cloud Storage bucket for documentation storage
- Cloud Functions for AI-powered documentation processing
- Cloud Build pipeline for automated documentation generation
- Service accounts with appropriate IAM permissions
- Eventarc triggers for notifications
- Optional documentation website hosting

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable cloudbuild.googleapis.com \
    storage.googleapis.com \
    cloudfunctions.googleapis.com \
    aiplatform.googleapis.com \
    config.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/doc-automation \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/us-central1/deployments/doc-automation
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id"

# Apply the configuration
terraform apply -var="project_id=your-project-id"

# View outputs
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

# Follow the script prompts for configuration
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `bucket_name`: Custom bucket name for documentation storage
- `function_memory`: Memory allocation for Cloud Functions (default: 512MB)

### Terraform Variables

Set these variables in `terraform/terraform.tfvars` or via CLI:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
bucket_name        = "custom-docs-bucket"
function_memory    = "512MB"
function_timeout   = "300s"
build_trigger_name = "custom-doc-trigger"
```

### Environment Variables for Scripts

Required for bash deployment:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customizations
export BUCKET_NAME="custom-docs-bucket"
export FUNCTION_NAME="custom-doc-processor"
```

## Testing the Deployment

After deployment, test the documentation generation:

```bash
# Get the Cloud Function URL
FUNCTION_URL=$(gcloud functions describe doc-processor \
    --region=us-central1 \
    --format="value(serviceConfig.uri)")

# Test with sample code
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
      "repo_path": "test.py",
      "file_content": "def hello_world():\n    \"\"\"Print hello world\"\"\"\n    print(\"Hello, World!\")",
      "doc_type": "api"
    }'

# Manually trigger a documentation build
gcloud builds triggers run doc-automation-manual

# Check generated documentation
gsutil ls -r gs://your-docs-bucket/
```

## Accessing Generated Documentation

1. **Cloud Storage Console**: Navigate to your documentation bucket in the Google Cloud Console
2. **Documentation Website**: If deployed, access at `https://storage.googleapis.com/your-bucket-name/website/index.html`
3. **CLI Access**: Use `gsutil` commands to download and view documentation

```bash
# List all generated documentation
gsutil ls -r gs://your-docs-bucket/

# Download API documentation
gsutil cp gs://your-docs-bucket/api/* ./local-docs/

# View documentation index
gsutil cat gs://your-docs-bucket/index.md
```

## Integration with Source Control

### GitHub Integration

1. Connect your repository in the Cloud Build console
2. Update the build trigger to use your repository
3. Configure webhook triggers for automatic documentation generation

### Manual Trigger Setup

For manual testing without repository integration:

```bash
# Create a sample repository structure for testing
mkdir -p test-repo
cd test-repo

# Add sample Python files
cat > app.py << 'EOF'
def calculate_sum(a, b):
    """Calculate the sum of two numbers.
    
    Args:
        a (int): First number
        b (int): Second number
    
    Returns:
        int: Sum of a and b
    """
    return a + b

class DataProcessor:
    """Process and transform data."""
    
    def __init__(self, data_source):
        self.data_source = data_source
    
    def process(self):
        """Process the data from source."""
        pass
EOF

# Trigger documentation generation
gcloud builds submit . --config=../cloudbuild.yaml
```

## Cost Optimization

Expected monthly costs (moderate usage):

- **Vertex AI Gemini API**: $3-8 (based on token usage)
- **Cloud Functions**: $1-3 (execution time and invocations)
- **Cloud Storage**: $1-2 (documentation storage)
- **Cloud Build**: $1-2 (build minutes)

### Cost Optimization Tips

1. **Optimize Gemini Usage**: Cache common documentation patterns
2. **Function Memory**: Adjust memory allocation based on actual usage
3. **Storage Lifecycle**: Implement lifecycle policies for older documentation versions
4. **Build Frequency**: Configure triggers to avoid unnecessary builds

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/doc-automation

# Verify cleanup
gcloud infra-manager deployments list
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

### Manual Cleanup

If automated cleanup fails, manually remove resources:

```bash
# Delete Cloud Functions
gcloud functions delete doc-processor --region=us-central1 --quiet
gcloud functions delete doc-notifier --region=us-central1 --quiet

# Delete build triggers
gcloud builds triggers delete doc-automation-manual --quiet

# Delete storage bucket
gsutil -m rm -r gs://your-docs-bucket

# Delete service accounts
gcloud iam service-accounts delete doc-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Troubleshooting

### Common Issues

**Function Deployment Fails**
- Verify APIs are enabled: `gcloud services list --enabled`
- Check service account permissions
- Ensure sufficient quotas for Cloud Functions

**Gemini API Errors**
- Verify Vertex AI API is enabled
- Check project quotas for Vertex AI
- Ensure service account has `aiplatform.user` role

**Build Trigger Issues**
- Verify Cloud Build API is enabled
- Check repository connection status
- Review build logs for detailed error messages

**Storage Access Issues**
- Verify bucket exists and is accessible
- Check service account storage permissions
- Review bucket IAM policies

### Debug Commands

```bash
# Check API status
gcloud services list --enabled --filter="name:aiplatform.googleapis.com OR name:cloudbuild.googleapis.com"

# View function logs
gcloud functions logs read doc-processor --region=us-central1 --limit=50

# Check build history
gcloud builds list --limit=10

# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --filter="bindings.members:doc-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```

## Security Considerations

### Service Account Security

- Uses least-privilege access principles
- Separate service accounts for different functions
- No overly broad permissions granted

### API Security

- Cloud Functions use IAM-based authentication
- No hardcoded credentials in code
- Secure environment variable handling

### Data Security

- Documentation stored in private Cloud Storage bucket
- Encryption at rest enabled by default
- Access controls through IAM policies

## Customization Examples

### Custom Documentation Prompts

Edit the Cloud Function code to customize AI prompts:

```python
# In main.py, modify prompts for different documentation styles
api_prompt = """
Generate comprehensive API documentation following your organization's standards.
Include detailed examples and error handling patterns.
...
"""
```

### Additional File Types

Extend the solution to support more file types:

```yaml
# In cloudbuild.yaml, add more file extensions
find . -name "*.py" -o -name "*.js" -o -name "*.go" -o -name "*.java" -o -name "*.ts"
```

### Integration with External Tools

Add integrations with documentation tools:

```bash
# Example: Swagger/OpenAPI generation
- name: 'gcr.io/cloud-builders/curl'
  entrypoint: 'bash'
  args:
    - '-c'
    - |
      # Generate OpenAPI spec from code
      swagger-codegen generate -i api-spec.yaml -l html2 -o docs/
```

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation:
   - [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
   - [Cloud Build Documentation](https://cloud.google.com/build/docs)
   - [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
4. Check Google Cloud status page for service issues

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any new features
4. Ensure backward compatibility where possible

## License

This infrastructure code is provided as-is for educational and development purposes. Refer to your organization's policies for production usage.