# Infrastructure as Code for Text Case Converter API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Text Case Converter API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- A Google Cloud Project with billing enabled
- Appropriate IAM permissions for creating Cloud Functions and enabling APIs
- Python 3.11+ for local development (optional)

### Required APIs

The following APIs will be automatically enabled during deployment:
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses YAML configuration files.

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments create text-case-converter \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-config-bucket/main.yaml" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe text-case-converter \
    --location=${REGION}
```

### Using Terraform

Terraform provides a consistent workflow across multiple cloud providers with extensive community support.

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a simple deployment option that mirrors the original recipe steps.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# Test the deployed function
curl -X POST $(./scripts/get-function-url.sh) \
    -H "Content-Type: application/json" \
    -d '{"text": "hello world", "case_type": "upper"}'
```

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment accepts the following input values:

- `project_id`: Your Google Cloud Project ID (required)
- `region`: Deployment region (default: us-central1)
- `function_name`: Name of the Cloud Function (default: text-case-converter)
- `memory_mb`: Memory allocation in MB (default: 128)
- `timeout_seconds`: Function timeout in seconds (default: 60)

### Terraform Variables

Configure the deployment by setting these variables:

```hcl
# In terraform.tfvars or via command line
project_id = "your-project-id"
region = "us-central1"
function_name = "text-case-converter"
memory_mb = 128
timeout_seconds = 60
enable_logging = true
```

### Environment Variables for Scripts

The bash scripts use these environment variables:

```bash
export PROJECT_ID="your-project-id"          # Required: Your GCP project
export REGION="us-central1"                  # Optional: Deployment region
export FUNCTION_NAME="text-case-converter"   # Optional: Function name
```

## API Usage

Once deployed, the function provides a REST API for text case conversion:

### Endpoint

```
POST https://{region}-{project}.cloudfunctions.net/{function_name}
```

### Request Format

```json
{
  "text": "Hello World Example",
  "case_type": "camel"
}
```

### Response Format

```json
{
  "original": "Hello World Example",
  "case_type": "camel", 
  "converted": "helloWorldExample"
}
```

### Supported Case Types

- `upper`, `uppercase`: UPPERCASE TEXT
- `lower`, `lowercase`: lowercase text
- `title`, `titlecase`: Title Case Text
- `capitalize`: Capitalized text
- `camel`, `camelcase`: camelCaseText
- `pascal`, `pascalcase`: PascalCaseText
- `snake`, `snakecase`: snake_case_text
- `kebab`, `kebabcase`: kebab-case-text

## Testing

### Basic Functionality Test

```bash
# Test uppercase conversion
curl -X POST $FUNCTION_URL \
    -H "Content-Type: application/json" \
    -d '{"text": "hello world", "case_type": "upper"}'

# Test camelCase conversion
curl -X POST $FUNCTION_URL \
    -H "Content-Type: application/json" \
    -d '{"text": "hello world example", "case_type": "camel"}'
```

### Error Handling Test

```bash
# Test missing required fields
curl -X POST $FUNCTION_URL \
    -H "Content-Type: application/json" \
    -d '{"case_type": "upper"}'

# Test invalid case type
curl -X POST $FUNCTION_URL \
    -H "Content-Type: application/json" \
    -d '{"text": "test", "case_type": "invalid"}'
```

## Monitoring and Logging

### View Function Logs

```bash
# View recent logs
gcloud functions logs read ${FUNCTION_NAME} \
    --region=${REGION} \
    --limit=50

# Follow logs in real-time
gcloud functions logs tail ${FUNCTION_NAME} \
    --region=${REGION}
```

### Function Metrics

```bash
# Get function details
gcloud functions describe ${FUNCTION_NAME} \
    --region=${REGION}

# View function metrics in Cloud Console
echo "https://console.cloud.google.com/functions/details/${REGION}/${FUNCTION_NAME}/metrics?project=${PROJECT_ID}"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete text-case-converter \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list --regions=${REGION}
```

## Security Considerations

### Function Security

- The function is deployed with `--allow-unauthenticated` for public API access
- CORS headers are configured to allow cross-origin requests
- Input validation prevents malicious payloads
- Error handling prevents information disclosure

### IAM Permissions

Minimum required permissions for deployment:

```yaml
# For deployment service account
roles/cloudfunctions.developer
roles/iam.serviceAccountUser
roles/serviceusage.serviceUsageAdmin
roles/storage.objectViewer  # For Cloud Build
```

### Network Security

- HTTPS-only endpoint (enforced by Cloud Functions)
- No VPC configuration (uses default network)
- No static IP assignment (dynamic scaling)

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   # Ensure proper IAM roles
   gcloud projects add-iam-policy-binding $PROJECT_ID \
       --member="user:$(gcloud config get-value account)" \
       --role="roles/cloudfunctions.developer"
   ```

2. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

3. **Function Deployment Timeout**
   ```bash
   # Check build logs
   gcloud builds list --limit=5
   ```

### Debugging

```bash
# Test function locally (requires Functions Framework)
pip install functions-framework
functions-framework --target=text_case_converter --source=main.py --port=8080

# Test local function
curl -X POST http://localhost:8080 \
    -H "Content-Type: application/json" \
    -d '{"text": "test", "case_type": "upper"}'
```

## Cost Optimization

### Free Tier Usage

Cloud Functions provides generous free tier limits:
- 2 million invocations per month
- 400,000 GB-seconds of compute time
- 200,000 GHz-seconds of CPU time
- 5 GB network egress per month

### Cost Monitoring

```bash
# View current month usage
gcloud billing accounts list
gcloud billing projects describe $PROJECT_ID

# Set up budget alerts (optional)
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Functions Budget" \
    --budget-amount=10USD
```

## Performance Tuning

### Memory Allocation

Adjust memory based on usage patterns:
- 128MB: Sufficient for text processing (default)
- 256MB: Better performance for large text inputs
- 512MB+: Only needed for complex processing

### Timeout Configuration

- Default: 60 seconds (adequate for text processing)
- Minimum: 1 second
- Maximum: 540 seconds (9 minutes)

### Cold Start Optimization

- Keep function warm with scheduled invocations
- Minimize import statements
- Use global variables for reusable objects

## Support and Documentation

### Official Documentation

- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Community Resources

- [Cloud Functions Samples](https://github.com/GoogleCloudPlatform/cloud-functions-samples)
- [Terraform Google Examples](https://github.com/terraform-google-modules)
- [Stack Overflow - Google Cloud Functions](https://stackoverflow.com/questions/tagged/google-cloud-functions)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation
4. Search community forums and Stack Overflow

## Customization

### Extending the Function

To add new case conversion types:

1. Edit the `convert_case()` function in `main.py`
2. Add new case handlers to the `case_handlers` dictionary
3. Implement custom conversion logic
4. Update tests and documentation

### Adding Authentication

To require API keys:

1. Remove `--allow-unauthenticated` from deployment
2. Add API key validation in the function
3. Configure IAM roles for authorized users
4. Update client applications with authentication headers

### Integrating with Other Services

Common integration patterns:
- **Pub/Sub**: Trigger conversions from message queue
- **Cloud Storage**: Process text files automatically
- **Firestore**: Store conversion history
- **Cloud Scheduler**: Periodic batch processing

---

This infrastructure code provides a production-ready deployment of the Text Case Converter API with comprehensive monitoring, security, and scalability features built-in.