# Infrastructure as Code for Simple Visitor Counter with Cloud Functions and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Visitor Counter with Cloud Functions and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code platform
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Admin
  - Firestore Service Agent
  - Cloud Build Editor
  - Service Usage Admin
- Node.js 20 runtime (for local development and testing)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code using standard tools like Terraform with Google Cloud integration.

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/visitor-counter-deployment \
    --service-account SERVICE_ACCOUNT_EMAIL \
    --gcs-source gs://BUCKET_NAME/path/to/config \
    --input-values project_id=PROJECT_ID,region=REGION

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/visitor-counter-deployment
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs including function URL
terraform output function_url
```

### Using Bash Scripts

The bash scripts provide a simple deployment option that mirrors the manual recipe steps with automation and error handling.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required inputs:
# - Project ID (or auto-generate one)
# - Region (defaults to us-central1)
# - Function name (defaults to visit-counter)
```

## Architecture Overview

The infrastructure creates:

- **Cloud Function (Gen2)**: HTTP-triggered serverless function using Node.js 20 runtime
- **Firestore Database**: Native mode NoSQL database for storing visitor counts
- **IAM Bindings**: Appropriate service account permissions
- **API Services**: Required Google Cloud APIs (Cloud Functions, Firestore, Cloud Build)

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `visit-counter` | No |
| `function_memory` | Function memory allocation | `256` | No |
| `function_timeout` | Function timeout in seconds | `60` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `visit-counter` | No |
| `function_memory` | Function memory (MB) | `256` | No |
| `function_timeout` | Function timeout (seconds) | `60` | No |
| `firestore_location` | Firestore region | `us-central1` | No |

### Bash Script Environment Variables

The deploy script accepts these environment variables:

```bash
export PROJECT_ID="your-project-id"           # Optional: auto-generated if not set
export REGION="us-central1"                   # Optional: deployment region
export FUNCTION_NAME="visit-counter"          # Optional: function name
export FUNCTION_MEMORY="256MB"                # Optional: memory allocation
export FUNCTION_TIMEOUT="60s"                 # Optional: timeout duration
```

## Testing the Deployment

After successful deployment, test the visitor counter:

```bash
# Get the function URL (varies by deployment method)
# For Terraform:
FUNCTION_URL=$(terraform output -raw function_url)

# For bash scripts, the URL is displayed during deployment
# Or retrieve it manually:
FUNCTION_URL=$(gcloud functions describe visit-counter --region=us-central1 --format="value(serviceConfig.uri)")

# Test the counter
curl "${FUNCTION_URL}"
curl "${FUNCTION_URL}?page=home"
curl "${FUNCTION_URL}?page=about"

# Test with POST request
curl -X POST "${FUNCTION_URL}" \
     -H "Content-Type: application/json" \
     -d '{"page": "api-test"}'
```

Expected response format:
```json
{
  "page": "default",
  "visits": 1,
  "timestamp": "2025-01-27T10:30:00.000Z"
}
```

## Monitoring and Logging

### View Cloud Function Logs

```bash
# Stream function logs in real-time
gcloud functions logs tail visit-counter --region=us-central1

# View recent logs
gcloud functions logs read visit-counter --region=us-central1 --limit=50
```

### Monitor Firestore Usage

```bash
# View Firestore collections
gcloud firestore collections list

# Query counter documents
gcloud firestore documents list --collection-path=counters
```

### Check Function Metrics

Access Cloud Functions metrics in the Google Cloud Console:
- Invocations per minute
- Execution time
- Memory usage
- Error rate

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/visitor-counter-deployment

# Confirm deletion
gcloud infra-manager deployments list --location=REGION
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# - Delete the Cloud Function
# - Delete Firestore database
# - Optionally delete the entire project
# - Clean up local files
```

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Ensure required APIs are enabled
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable firestore.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   
   # Check IAM permissions
   gcloud projects get-iam-policy PROJECT_ID
   ```

2. **Function Deployment Failures**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=10
   
   # View specific build details
   gcloud builds describe BUILD_ID
   ```

3. **Firestore Access Issues**:
   ```bash
   # Verify Firestore is initialized
   gcloud firestore databases describe --database="(default)"
   
   # Check service account permissions
   gcloud projects get-iam-policy PROJECT_ID
   ```

### Validation Commands

```bash
# Verify function is deployed and accessible
gcloud functions describe visit-counter --region=us-central1

# Test function locally (if using Functions Framework)
cd terraform/function-source/
npm install
npm start

# In another terminal:
curl http://localhost:8080
```

## Cost Optimization

This solution is designed to be cost-effective:

- **Cloud Functions**: 2M free invocations per month
- **Firestore**: 20K free document writes per day
- **Estimated monthly cost**: $0.00-$0.50 for typical usage

Monitor costs:
```bash
# View current billing
gcloud billing projects describe PROJECT_ID

# Set up budget alerts (recommended)
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Visitor Counter Budget" \
    --budget-amount=5.00
```

## Security Considerations

The infrastructure implements these security practices:

- **Least Privilege IAM**: Function service account has minimal required permissions
- **Input Validation**: Function validates page parameters to prevent injection
- **CORS Configuration**: Proper cross-origin resource sharing headers
- **Error Handling**: Comprehensive error handling without information disclosure

For production deployments:

1. **Enable Authentication**:
   ```bash
   # Deploy with authentication required
   gcloud functions deploy visit-counter \
       --no-allow-unauthenticated
   ```

2. **Implement Rate Limiting**: Add Cloud Armor or custom rate limiting logic

3. **Enable Audit Logging**: Monitor function invocations and Firestore access

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation: `../visitor-counter-functions-firestore.md`
2. Check Google Cloud documentation:
   - [Cloud Functions](https://cloud.google.com/functions/docs)
   - [Firestore](https://cloud.google.com/firestore/docs)
   - [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
3. Validate permissions and enabled APIs
4. Review deployment logs for specific error messages

## Advanced Usage

### Multiple Environments

Deploy to different environments using variable files:

```bash
# Terraform with environment-specific variables
terraform apply -var-file="environments/staging.tfvars"
terraform apply -var-file="environments/production.tfvars"

# Infrastructure Manager with different configurations
gcloud infra-manager deployments apply \
    --input-values-file=environments/staging.yaml
```

### Custom Function Code

The infrastructure supports deploying custom function code:

1. Modify the function source in `terraform/function-source/` or `infrastructure-manager/function-source/`
2. Update package.json dependencies if needed
3. Redeploy using your chosen method

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy Visitor Counter
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: google-github-actions/auth@v1
        with:
          credentials_json: ${{ secrets.GCP_SA_KEY }}
      - run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```