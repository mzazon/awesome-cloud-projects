# Infrastructure as Code for Smart Code Documentation with Agent Development Kit and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Code Documentation with Agent Development Kit and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Vertex AI User
  - Cloud Functions Admin
  - Cloud Storage Admin
  - Service Usage Admin
  - Project IAM Admin

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI version 450.0.0 or later
- Infrastructure Manager API enabled

#### Terraform
- Terraform >= 1.5.0 installed
- Google Cloud provider >= 5.0.0

#### Python Development (for testing)
- Python 3.11+ for local ADK development
- Virtual environment tools (`venv` or `virtualenv`)

### Estimated Costs
- Cloud Functions: ~$5-10/month for moderate usage
- Cloud Storage: ~$1-3/month for documentation storage
- Vertex AI (Gemini): ~$10-15/month for analysis and generation
- **Total estimated monthly cost: $15-25**

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy the infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/adk-code-docs \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --git-source-repo=https://github.com/your-org/your-repo.git \
    --git-source-directory=gcp/smart-code-documentation-adk-functions/code/infrastructure-manager/ \
    --git-source-ref=main \
    --input-values=project_id=PROJECT_ID,region=REGION
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

The infrastructure deploys:

1. **Cloud Storage Buckets**:
   - Input bucket for code repositories (with Cloud Function trigger)
   - Output bucket for generated documentation
   - Temporary processing bucket for intermediate results

2. **Cloud Functions**:
   - ADK orchestrator function (Python 3.11 runtime)
   - Triggered by uploads to the input bucket
   - Configured with 1GB memory and 9-minute timeout

3. **IAM Configuration**:
   - Service accounts with minimal required permissions
   - Vertex AI access for Gemini model usage
   - Storage access for bucket operations

4. **Vertex AI Integration**:
   - Gemini 1.5 Pro model configuration
   - Regional endpoint setup (us-central1)

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
  function_memory:
    description: "Cloud Function memory allocation"
    type: string
    default: "1024Mi"
  function_timeout:
    description: "Cloud Function timeout in seconds"
    type: number
    default: 540
```

### Terraform Variables

Customize deployment via `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Deployment region"
  type        = string
  default     = "us-central1"
}

variable "random_suffix" {
  description = "Random suffix for resource names"
  type        = string
  default     = null
}
```

### Environment Variables for Scripts

Set these before running bash scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"              # Optional, defaults to us-central1
export RANDOM_SUFFIX=""                  # Optional, auto-generated if not set
export FUNCTION_MEMORY="1024Mi"          # Optional, defaults to 1024Mi
export FUNCTION_TIMEOUT="540"            # Optional, defaults to 540 seconds
```

## Testing the Deployment

### 1. Verify Infrastructure

```bash
# Check Cloud Function status
gcloud functions describe adk-code-documentation \
    --gen2 \
    --region=us-central1

# List created storage buckets
gcloud storage ls --project=YOUR_PROJECT_ID | grep -E "(code-input|docs-output|processing)"

# Verify IAM service account
gcloud iam service-accounts list --filter="displayName:ADK Documentation Service"
```

### 2. Test with Sample Code

```bash
# Create a simple test repository
mkdir test-repo
echo 'def hello(): return "Hello, World!"' > test-repo/main.py
cd test-repo && zip -r ../test-repo.zip . && cd ..

# Upload to input bucket (replace with your actual bucket name)
gcloud storage cp test-repo.zip gs://YOUR_PROJECT_ID-code-input-SUFFIX/

# Monitor function execution
gcloud functions logs read adk-code-documentation \
    --gen2 \
    --region=us-central1 \
    --limit=20

# Check for generated documentation
gcloud storage ls gs://YOUR_PROJECT_ID-docs-output-SUFFIX/test-repo.zip/
```

### 3. Download Generated Documentation

```bash
# Download the generated README.md
gcloud storage cp gs://YOUR_PROJECT_ID-docs-output-SUFFIX/test-repo.zip/README.md ./generated-docs.md

# View analysis summary
gcloud storage cp gs://YOUR_PROJECT_ID-docs-output-SUFFIX/test-repo.zip/analysis_summary.json ./summary.json
cat summary.json
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**:
   ```bash
   # Ensure proper IAM roles
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
       --member="user:your-email@domain.com" \
       --role="roles/cloudfunctions.admin"
   ```

2. **Function Timeout Issues**:
   ```bash
   # Increase timeout in terraform/main.tf or infrastructure-manager/main.yaml
   timeout = 540  # 9 minutes
   ```

3. **ADK Installation Issues**:
   ```bash
   # Check function logs for package installation errors
   gcloud functions logs read adk-code-documentation --gen2 --region=us-central1
   ```

4. **Vertex AI Access Issues**:
   ```bash
   # Verify Vertex AI API is enabled
   gcloud services list --enabled | grep aiplatform
   ```

### Debugging Steps

1. **Check Function Logs**:
   ```bash
   gcloud functions logs read adk-code-documentation \
       --gen2 \
       --region=us-central1 \
       --limit=50
   ```

2. **Verify Bucket Triggers**:
   ```bash
   gcloud functions describe adk-code-documentation \
       --gen2 \
       --region=us-central1 \
       --format="value(eventTrigger.trigger)"
   ```

3. **Test Local ADK Environment**:
   ```bash
   # Install ADK locally for testing
   python3 -m venv test-env
   source test-env/bin/activate
   pip install google-adk==1.0.0
   ```

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/adk-code-docs
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Function
gcloud functions delete adk-code-documentation --gen2 --region=us-central1 --quiet

# Delete Storage Buckets (replace with actual bucket names)
gcloud storage rm -r gs://YOUR_PROJECT_ID-code-input-SUFFIX
gcloud storage rm -r gs://YOUR_PROJECT_ID-docs-output-SUFFIX
gcloud storage rm -r gs://YOUR_PROJECT_ID-processing-SUFFIX

# Delete Service Account
gcloud iam service-accounts delete adk-docs-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com --quiet
```

## Performance Optimization

### Function Configuration

- **Memory**: Start with 1GB, increase to 2GB for large repositories
- **Timeout**: 9 minutes should handle most repositories; increase for very large codebases
- **Concurrency**: Default settings support moderate parallel processing

### Cost Optimization

1. **Function Scaling**:
   ```bash
   # Limit concurrent executions to control costs
   gcloud functions deploy adk-code-documentation \
       --gen2 \
       --max-instances=10 \
       --region=us-central1
   ```

2. **Storage Lifecycle**:
   ```bash
   # Set lifecycle policies for temporary storage
   gcloud storage buckets update gs://TEMP_BUCKET \
       --lifecycle-file=lifecycle.json
   ```

## Security Considerations

### IAM Best Practices

- Service accounts use minimal required permissions
- No broad IAM roles assigned
- Function-specific service account isolation

### Data Security

- All storage buckets use Google-managed encryption
- No public access to buckets
- Function logs exclude sensitive data

### Network Security

- Functions deployed in managed VPC
- No external ingress beyond Cloud Storage triggers
- Vertex AI access through private Google network

## Advanced Usage

### Custom ADK Agents

Extend the solution by modifying the function source:

1. **Add New Agent Types**:
   ```python
   # In main.py, add specialized agents
   security_agent = SecurityAnalysisAgent(project_id)
   performance_agent = PerformanceAnalysisAgent(project_id)
   ```

2. **Custom Documentation Templates**:
   ```python
   # Customize documentation format in documentation_agent.py
   def generate_custom_format(self, analysis_data):
       # Your custom logic here
   ```

### Integration with CI/CD

```bash
# Example GitHub Actions integration
curl -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"ref":"main"}' \
    https://api.github.com/repos/owner/repo/dispatches
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe documentation
2. **Google Cloud Documentation**: [Cloud Functions](https://cloud.google.com/functions/docs), [Vertex AI](https://cloud.google.com/vertex-ai/docs)
3. **ADK Documentation**: [Google ADK GitHub](https://github.com/google/adk)
4. **Community Support**: [Google Cloud Community](https://cloud.google.com/community)

## Contributing

To improve this infrastructure:

1. Fork the repository
2. Create feature branch
3. Test changes thoroughly
4. Submit pull request with detailed description

## License

This infrastructure code is provided under the same license as the original recipe documentation.