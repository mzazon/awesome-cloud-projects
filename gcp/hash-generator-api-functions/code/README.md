# Infrastructure as Code for Hash Generator API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hash Generator API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud Project with billing enabled
- Appropriate IAM permissions for Cloud Functions deployment:
  - Cloud Functions Developer
  - Service Account User
  - Cloud Build Editor (for deployment)
- APIs enabled in your project:
  - Cloud Functions API
  - Cloud Build API
  - Cloud Logging API

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

Infrastructure Manager provides Google Cloud's native infrastructure as code solution with built-in state management and integration with Google Cloud services.

```bash
# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/hash-generator \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/hash-generator
```

> **Note**: Infrastructure Manager requires a service account with appropriate permissions. The deployment will create and configure the necessary Cloud Function automatically.

### Using Terraform

Terraform provides a declarative approach to infrastructure management with excellent state tracking and change planning capabilities.

```bash
# Navigate to Terraform configuration
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure changes
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# Verify the deployment
terraform show
```

### Using Bash Scripts

Bash scripts provide a straightforward deployment approach using Google Cloud CLI commands, closely following the original recipe steps.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for project configuration and deploy the Cloud Function
# Follow the prompts to set PROJECT_ID and REGION
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
# Project and region configuration
project_id: "your-project-id"
region: "us-central1"

# Function configuration
function_name: "hash-generator"
memory_mb: 256
timeout_seconds: 60
python_runtime: "python312"

# Security settings
allow_unauthenticated: true  # Set to false for authenticated access
```

### Terraform Variables

Customize deployment by modifying `terraform/terraform.tfvars` or passing variables:

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region = "us-central1"
function_name = "hash-generator"
memory_mb = 256
timeout_seconds = 60
allow_unauthenticated = true
EOF

# Apply with custom configuration
terraform apply -var-file="terraform.tfvars"
```

### Bash Script Configuration

Modify environment variables in `scripts/deploy.sh`:

```bash
# Edit configuration variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="hash-generator"
export MEMORY="256MB"
export TIMEOUT="60s"
```

## Testing the Deployment

After successful deployment, test the Hash Generator API:

```bash
# Get the function URL (varies by deployment method)
# For Infrastructure Manager:
FUNCTION_URL=$(gcloud functions describe hash-generator --region=us-central1 --format="value(httpsTrigger.url)")

# For Terraform:
FUNCTION_URL=$(terraform output -raw function_url)

# For Bash scripts:
# URL will be displayed in deployment output

# Test the API with sample data
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"text": "Hello, World!"}'

# Expected response:
# {
#   "input": "Hello, World!",
#   "hashes": {
#     "md5": "65a8e27d8879283831b664bd8b7f0ad4",
#     "sha256": "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f",
#     "sha512": "374d794a95cdcfd8b35993185fef9ba368f160d8daf432d08ba9f1ed1e5abe6cc69291e0fa2fe0006a52570ef18c19def4e617c33ce52ef0a6e5fbe318cb0387"
#   },
#   "input_length": 13,
#   "timestamp": "unknown"
# }
```

## Validation and Monitoring

### Verify Function Deployment

```bash
# Check function status
gcloud functions describe hash-generator --region=us-central1

# View function logs
gcloud functions logs read hash-generator --region=us-central1 --limit=10

# Monitor function metrics
gcloud monitoring metrics list --filter="resource.type=cloud_function"
```

### Load Testing

Test the function's performance and scaling behavior:

```bash
# Simple load test using Apache bench (if installed)
ab -n 100 -c 10 -p test-payload.json -T 'application/json' ${FUNCTION_URL}

# Create test payload file
echo '{"text": "Load test data"}' > test-payload.json
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/hash-generator

# Confirm deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Confirm resources are deleted
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deletion
# Follow the prompts to remove all created resources
```

## Cost Optimization

### Free Tier Considerations

Google Cloud Functions provides generous free tier limits:
- 2 million invocations per month
- 400,000 GB-seconds of compute time
- 200,000 GHz-seconds of compute time

### Cost Monitoring

```bash
# Monitor function costs
gcloud billing budgets list --billing-account=YOUR_BILLING_ACCOUNT

# Set up budget alerts for Cloud Functions
gcloud billing budgets create \
    --billing-account=YOUR_BILLING_ACCOUNT \
    --display-name="Hash Generator Function Budget" \
    --budget-amount=10USD
```

## Security Considerations

### IAM and Authentication

The default deployment allows unauthenticated access for demonstration purposes. For production use:

```bash
# Deploy with authentication required
# Modify the deployment to set allow_unauthenticated: false

# Create a service account for clients
gcloud iam service-accounts create hash-generator-client \
    --display-name="Hash Generator API Client"

# Grant Cloud Functions Invoker role
gcloud functions add-iam-policy-binding hash-generator \
    --region=us-central1 \
    --member="serviceAccount:hash-generator-client@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudfunctions.invoker"
```

### Network Security

```bash
# Configure VPC connector for private network access (optional)
gcloud compute networks vpc-access connectors create hash-generator-connector \
    --region=us-central1 \
    --subnet=default \
    --subnet-project=${PROJECT_ID} \
    --min-instances=2 \
    --max-instances=3
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # View detailed build logs
   gcloud builds log BUILD_ID
   ```

2. **Permission denied errors**:
   ```bash
   # Verify required APIs are enabled
   gcloud services list --enabled | grep -E "(functions|cloudbuild|logging)"
   
   # Check IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Function not responding**:
   ```bash
   # Check function logs for errors
   gcloud functions logs read hash-generator --region=us-central1
   
   # Verify function is active
   gcloud functions describe hash-generator --region=us-central1
   ```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# Set debug logging for gcloud commands
export CLOUDSDK_CORE_VERBOSITY=debug

# Enable function debug logging
gcloud functions deploy hash-generator \
    --set-env-vars DEBUG=true \
    --runtime python312 \
    --region=us-central1
```

## Customization

### Adding Custom Hash Algorithms

Modify the function source code to support additional hash algorithms:

```python
# Add to main.py in function source
import bcrypt
from passlib.hash import argon2

# Extend hash generation
bcrypt_hash = bcrypt.hashpw(text_bytes, bcrypt.gensalt()).decode('utf-8')
argon2_hash = argon2.hash(input_text)
```

### Scaling Configuration

Adjust function scaling parameters:

```bash
# Update function with custom scaling
gcloud functions deploy hash-generator \
    --min-instances=1 \
    --max-instances=100 \
    --runtime=python312 \
    --region=us-central1
```

### Environment-Specific Deployments

Use different configurations for development, staging, and production:

```bash
# Development deployment
terraform workspace new development
terraform apply -var-file="environments/development.tfvars"

# Production deployment  
terraform workspace new production
terraform apply -var-file="environments/production.tfvars"
```

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Example GitHub Actions workflow
name: Deploy Hash Generator Function
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
      - name: Deploy Function
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

### Application Integration

```python
# Python client example
import requests
import json

def generate_hashes(text):
    """Generate hashes using the deployed Cloud Function"""
    function_url = "https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/hash-generator"
    
    response = requests.post(
        function_url,
        headers={"Content-Type": "application/json"},
        json={"text": text}
    )
    
    return response.json()

# Usage
result = generate_hashes("Hello, World!")
print(f"SHA256: {result['hashes']['sha256']}")
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe in `../hash-generator-api-functions.md`
2. **Google Cloud Documentation**: [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
3. **Terraform Provider**: [Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Infrastructure Manager**: [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Additional Resources

- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)
- [Terraform Google Cloud Examples](https://github.com/terraform-google-modules)
- [Infrastructure Manager Samples](https://github.com/GoogleCloudPlatform/infrastructure-manager-samples)