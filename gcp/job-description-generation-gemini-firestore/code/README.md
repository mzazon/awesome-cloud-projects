# Infrastructure as Code for Automated Job Description Generation with Gemini and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Job Description Generation with Gemini and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code platform
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Vertex AI API access and model usage
  - Firestore database creation and management
  - Cloud Functions deployment and management
  - Service Account creation and management
- For Terraform: Terraform CLI v1.0+ installed
- For Infrastructure Manager: gcloud components install config-connector

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/job-description-gen \
    --service-account projects/$PROJECT_ID/serviceAccounts/infra-manager@$PROJECT_ID.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="inputs.yaml"
```

### Using Terraform

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Initialize and deploy with Terraform
cd terraform/
terraform init
terraform plan -var="project_id=$PROJECT_ID" -var="region=$REGION"
terraform apply -var="project_id=$PROJECT_ID" -var="region=$REGION"
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Deployed

This infrastructure creates:

1. **Vertex AI Configuration**
   - Enables Vertex AI API
   - Configures Gemini model access
   - Sets up AI Platform quotas

2. **Firestore Database**
   - Native mode Firestore database
   - Collections for company culture data
   - Collections for job role templates
   - Collection for generated job descriptions

3. **Cloud Functions**
   - Job description generation function
   - Compliance validation function
   - HTTP triggers with CORS support
   - Proper IAM roles and permissions

4. **Service Accounts and IAM**
   - Cloud Function service accounts
   - Vertex AI access permissions
   - Firestore read/write permissions
   - Least privilege security model

5. **Networking and Security**
   - Function-level security configurations
   - API endpoint access controls
   - Secure service-to-service communication

## Customization

### Common Variables

All implementations support these customizable parameters:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `function_memory`: Memory allocation for Cloud Functions (default: 512MB)
- `function_timeout`: Timeout for Cloud Functions (default: 300s)
- `firestore_location`: Firestore database location (default: us-central1)

### Infrastructure Manager Customization

Edit `infrastructure-manager/inputs.yaml`:

```yaml
project_id: "your-project-id"
region: "us-central1"
function_memory: "512MB"
function_timeout: "300s"
firestore_location: "us-central1"
enable_compliance_validation: true
```

### Terraform Customization

Edit `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_memory = 512
function_timeout = 300
firestore_location = "us-central1"
enable_compliance_validation = true
```

### Bash Script Customization

Edit environment variables in `scripts/deploy.sh`:

```bash
# Deployment Configuration
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_MEMORY="512MB"
export FUNCTION_TIMEOUT="300s"
export FIRESTORE_LOCATION="us-central1"
```

## Post-Deployment Setup

After infrastructure deployment, initialize the data:

```bash
# Set your function URL (output from deployment)
export FUNCTION_URL="https://your-function-url"

# Initialize company culture data
python3 scripts/setup_sample_data.py

# Test the deployment
curl -X POST $FUNCTION_URL \
    -H "Content-Type: application/json" \
    -d '{"role_id": "software_engineer", "custom_requirements": "Experience with microservices"}'
```

## Monitoring and Observability

The infrastructure includes:

- **Cloud Functions Logs**: View function execution logs in Cloud Logging
- **Vertex AI Metrics**: Monitor model usage and performance
- **Firestore Metrics**: Track database operations and performance
- **IAM Audit Logs**: Security and access monitoring

Access monitoring:

```bash
# View Cloud Functions logs
gcloud functions logs read generate-job-description --region=$REGION

# Monitor Vertex AI usage
gcloud logging read "resource.type=vertex_ai_model" --limit=50

# Check Firestore operations
gcloud logging read "resource.type=firestore_database" --limit=50
```

## Cost Optimization

To optimize costs:

1. **Vertex AI**: Monitor token usage and implement caching for repeated requests
2. **Cloud Functions**: Use appropriate memory allocation and timeout settings
3. **Firestore**: Optimize query patterns and use compound indexes
4. **Networking**: Functions are deployed in the same region as Firestore

Estimated costs (USD per month):
- Vertex AI Gemini: $20-50 (based on usage)
- Cloud Functions: $5-15 (based on invocations)
- Firestore: $5-20 (based on operations and storage)

## Security Considerations

The infrastructure implements:

- **Least Privilege IAM**: Service accounts with minimal required permissions
- **API Security**: HTTP functions with proper CORS configuration
- **Data Encryption**: Firestore encryption at rest and in transit
- **Network Security**: Functions deployed in secure VPC when configured
- **Audit Logging**: Comprehensive audit trail for all operations

## Troubleshooting

### Common Issues

1. **Vertex AI API Not Enabled**
   ```bash
   gcloud services enable aiplatform.googleapis.com
   ```

2. **Insufficient IAM Permissions**
   ```bash
   # Add required roles to your account
   gcloud projects add-iam-policy-binding $PROJECT_ID \
       --member="user:your-email@domain.com" \
       --role="roles/aiplatform.user"
   ```

3. **Firestore Database Already Exists**
   ```bash
   # Check existing database mode
   gcloud firestore databases describe --project=$PROJECT_ID
   ```

4. **Cloud Function Deployment Errors**
   ```bash
   # Check function logs for detailed error messages
   gcloud functions logs read generate-job-description --region=$REGION --limit=10
   ```

### Support Commands

```bash
# Validate deployment
./scripts/validate_deployment.sh

# Check resource status
gcloud functions describe generate-job-description --region=$REGION
gcloud firestore databases describe --project=$PROJECT_ID

# Test connectivity
curl -X GET ${FUNCTION_URL}/health
```

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/job-description-gen
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=$PROJECT_ID" -var="region=$REGION"
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup Verification

Verify all resources are removed:

```bash
# Check Cloud Functions
gcloud functions list --regions=$REGION

# Check Firestore (requires manual deletion if not empty)
gcloud firestore databases describe --project=$PROJECT_ID

# Check enabled APIs (optional - you may want to keep these)
gcloud services list --enabled
```

## Development and Testing

### Local Development Setup

```bash
# Install Python dependencies for local testing
pip install -r requirements-dev.txt

# Set up local authentication
gcloud auth application-default login

# Run local tests
python -m pytest tests/ -v
```

### Integration Testing

```bash
# Run end-to-end tests
./scripts/run_integration_tests.sh

# Load test the functions
./scripts/load_test.sh --concurrent-users=10 --duration=60s
```

## CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Deploy Job Description Generator
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: google-github-actions/setup-gcloud@v1
        with:
          service_account_key: ${{ secrets.GCP_SA_KEY }}
          project_id: ${{ secrets.GCP_PROJECT_ID }}
      - name: Deploy with Terraform
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

## Extensions and Enhancements

The infrastructure supports easy extension for:

1. **Multi-language Support**: Add Cloud Translation API integration
2. **Advanced Analytics**: Include BigQuery for job posting performance analytics
3. **Workflow Integration**: Add Cloud Workflows for approval processes
4. **Mobile Support**: Deploy additional endpoints for mobile applications
5. **A/B Testing**: Implement feature flags with Cloud Deploy

## Version Compatibility

- **Google Cloud CLI**: 380.0.0+
- **Terraform Google Provider**: 4.84.0+
- **Infrastructure Manager**: Latest available
- **Python Runtime**: 3.11 (Cloud Functions)
- **Vertex AI Models**: Gemini 1.5 Flash

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../job-description-generation-gemini-firestore.md)
2. Review [Google Cloud Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
3. Consult [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. File issues in the repository issue tracker

## License

This infrastructure code is provided under the same license as the parent repository.