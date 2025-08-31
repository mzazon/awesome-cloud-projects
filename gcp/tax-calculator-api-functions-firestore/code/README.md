# Infrastructure as Code for Tax Calculator API with Cloud Functions and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Tax Calculator API with Cloud Functions and Firestore". This serverless solution provides a scalable API for tax calculations with persistent storage for calculation history.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Overview

This solution deploys a serverless tax calculation API on Google Cloud Platform using:

- **Cloud Functions**: Serverless compute for tax calculation and history retrieval
- **Firestore**: NoSQL document database for storing calculation history
- **Cloud Storage**: Function source code storage and logging
- **Cloud IAM**: Security and access management
- **Cloud Logging**: Function monitoring and debugging

## Architecture

The deployed infrastructure creates a serverless API with two endpoints:

1. **Tax Calculator Function**: POST endpoint for calculating federal income tax
2. **Calculation History Function**: GET endpoint for retrieving user's calculation history

Both functions automatically scale based on demand and integrate with Firestore for data persistence.

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Account**: With billing enabled
2. **Google Cloud CLI**: Installed and authenticated
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   
   # Authenticate and set project
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

3. **Terraform**: Version 1.5.0 or later
   ```bash
   # Install Terraform
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

4. **Required Permissions**: Your Google Cloud account needs the following roles:
   - Cloud Functions Admin
   - Firestore Service Agent
   - Storage Admin
   - Project IAM Admin
   - Service Usage Admin

5. **Estimated Cost**: $0.00-$2.00 per month for development usage

> **Note**: This solution uses serverless services that scale to zero, minimizing costs during development.

## Quick Start

### Using Infrastructure Manager (Recommended)

Google Cloud Infrastructure Manager is the native IaC solution that provides built-in state management and integration with Google Cloud services.

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments apply \
    projects/PROJECT_ID/locations/REGION/deployments/tax-calculator \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --gcs-source=GCS_BUCKET_PATH/main.yaml

# Monitor deployment status
gcloud infra-manager deployments describe \
    projects/PROJECT_ID/locations/REGION/deployments/tax-calculator
```

### Using Terraform

Terraform provides a consistent workflow across multiple cloud providers with extensive module support.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Configure variables (create terraform.tfvars)
cat > terraform.tfvars << EOF
project_id = "your-gcp-project-id"
region     = "us-central1"
environment = "dev"

# Optional customizations
function_name_prefix = "tax-calc"
calculator_function_memory = 256
history_function_memory = 128
allow_unauthenticated = true
EOF

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# Get function URLs from output
CALC_URL=$(terraform output -raw tax_calculator_function_url)
HISTORY_URL=$(terraform output -raw calculation_history_function_url)
```

### Using Bash Scripts

Automated deployment scripts that use Google Cloud CLI commands for rapid prototyping and testing.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployment
curl -X POST "$(gcloud functions describe tax-calculator --format='value(httpsTrigger.url)')" \
     -H "Content-Type: application/json" \
     -d '{"income": 65000, "filing_status": "single", "user_id": "test_user"}'
```

## Validation & Testing

After deployment, validate the infrastructure:

```bash
# Test tax calculation endpoint
curl -X POST "$CALC_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "income": 75000,
    "filing_status": "single",
    "deductions": 15000,
    "user_id": "test_user"
  }'

# Test calculation history endpoint
curl "$HISTORY_URL?user_id=test_user&limit=5"

# Verify Firestore collections
gcloud firestore collections list

# Check function logs
gcloud functions logs read tax-calculator --limit=10
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `infrastructure-manager/main.yaml` file to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `function_memory`: Memory allocation for functions (default: 256MB)
- `function_timeout`: Timeout for functions (default: 60s)

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `firestore_location_id` | Firestore database location | `us-central` | No |
| `function_name_prefix` | Prefix for function names | `tax-calculator` | No |
| `calculator_function_memory` | Memory for calculator function (MB) | `256` | No |
| `history_function_memory` | Memory for history function (MB) | `128` | No |
| `calculator_function_timeout` | Timeout for calculator function (seconds) | `60` | No |
| `history_function_timeout` | Timeout for history function (seconds) | `30` | No |
| `calculator_max_instances` | Max instances for calculator function | `10` | No |
| `history_max_instances` | Max instances for history function | `5` | No |
| `min_instances` | Min instances (0 for scale-to-zero) | `0` | No |
| `python_runtime` | Python runtime version | `python312` | No |
| `allow_unauthenticated` | Allow unauthenticated access | `true` | No |
| `environment` | Environment name | `dev` | No |
| `enable_apis` | Enable required GCP APIs | `true` | No |
| `delete_protection` | Enable deletion protection | `false` | No |

### Script Variables

Set environment variables before running bash scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_MEMORY="256MB"
export FUNCTION_TIMEOUT="60s"
```

### Environment-Specific Configurations

#### Development
```hcl
environment = "dev"
allow_unauthenticated = true
delete_protection = false
min_instances = 0
```

#### Production
```hcl
environment = "prod"
allow_unauthenticated = false
delete_protection = true
min_instances = 1
calculator_max_instances = 100
history_max_instances = 50
```

## Security Considerations

### Authentication
- **Development**: Functions allow unauthenticated access for testing
- **Production**: Disable `allow_unauthenticated` and implement proper authentication

### IAM and Permissions
- Functions use the default App Engine service account
- Minimal required permissions are granted
- Firestore security rules should be configured for production

### Data Protection
- All data is encrypted at rest and in transit
- Firestore provides ACID transactions
- Enable deletion protection for production databases

## Monitoring and Logging

### Cloud Logging
Function logs are automatically captured and can be viewed:
```bash
gcloud logging read "resource.type=cloud_function" --limit 50
```

### Cloud Monitoring
Set up monitoring dashboards and alerts:
```bash
# View function metrics
gcloud monitoring dashboards list
```

### Cost Monitoring
Track costs and set up budget alerts:
```bash
gcloud billing budgets list
```

## Maintenance

### Updating Function Code
1. Modify source code in `function-source/`
2. Run `terraform apply` to deploy changes

### Scaling Configuration
Adjust function memory and instance limits based on usage patterns:
```hcl
calculator_function_memory = 512  # Increase for better performance
calculator_max_instances = 50     # Increase for higher concurrency
```

### Database Maintenance
- Firestore automatically handles backups and maintenance
- Monitor document counts and storage usage
- Implement data retention policies as needed

## Troubleshooting

### Common Issues

#### 1. API Not Enabled Error
```bash
# Enable required APIs manually
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable firestore.googleapis.com
gcloud services enable cloudbuild.googleapis.com
```

#### 2. Permission Denied
```bash
# Check current user permissions
gcloud auth list
gcloud projects get-iam-policy YOUR_PROJECT_ID
```

#### 3. Function Deployment Timeout
```bash
# Check build logs
gcloud functions logs read FUNCTION_NAME --region REGION
```

#### 4. Firestore Access Issues
```bash
# Verify Firestore database exists
gcloud firestore databases describe --database="(default)"
```

### Getting Help

1. **Function Logs**: Check Cloud Logging for function errors
2. **Terraform Logs**: Use `terraform apply -debug` for detailed output
3. **GCP Console**: View resources in the Google Cloud Console
4. **Documentation**: Refer to Google Cloud documentation for specific services

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    projects/PROJECT_ID/locations/REGION/deployments/tax-calculator
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" \
                  -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list
gcloud firestore databases list
```

### Manual Cleanup (if needed)
```bash
# Delete functions
gcloud functions delete FUNCTION_NAME --region REGION

# Delete Firestore database (cannot be undone)
gcloud firestore databases delete --database="(default)"

# Delete storage bucket
gsutil rm -r gs://BUCKET_NAME
```

## Cost Optimization

### Serverless Benefits
- Functions scale to zero when not in use
- Pay only for actual usage (invocations and compute time)
- Firestore charges based on operations and storage

### Optimization Tips
1. **Right-size Memory**: Use appropriate memory allocation for each function
2. **Monitor Usage**: Set up billing alerts and cost monitoring
3. **Implement Caching**: Reduce Firestore operations where possible
4. **Use Compression**: Optimize function packaging and reduce cold starts

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud documentation for each service
3. Use `terraform plan` to validate configurations before applying
4. Monitor function logs for runtime issues

## Development Workflow

### Local Development

```bash
# Install Functions Framework
pip install functions-framework

# Run function locally
functions-framework --target=calculate_tax --source=function_source/

# Test locally
curl -X POST http://localhost:8080 \
     -H "Content-Type: application/json" \
     -d '{"income": 50000, "user_id": "dev_user"}'
```

### CI/CD Integration

The IaC can be integrated with Cloud Build for automated deployments:

```yaml
# cloudbuild.yaml example
steps:
  - name: 'hashicorp/terraform'
    entrypoint: 'sh'
    args:
      - '-c'
      - |
        cd terraform/
        terraform init
        terraform plan
        terraform apply -auto-approve
```

## Extending the Solution

Common enhancement patterns:

1. **Multi-Region Deployment**: Deploy functions to multiple regions for global availability
2. **API Gateway**: Add Cloud Endpoints for advanced API management
3. **Monitoring Dashboard**: Create custom dashboards in Cloud Monitoring
4. **Data Analytics**: Export Firestore data to BigQuery for analysis
5. **Batch Processing**: Add Cloud Scheduler for periodic tax data updates

## Support and Documentation

- **Recipe Documentation**: See the original recipe markdown file
- **Google Cloud Functions**: [Official Documentation](https://cloud.google.com/functions/docs)
- **Firestore**: [Official Documentation](https://cloud.google.com/firestore/docs)
- **Infrastructure Manager**: [Official Documentation](https://cloud.google.com/infrastructure-manager/docs)
- **Terraform Google Provider**: [Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

---

*Generated by IaC Generator v1.3 for recipe "Tax Calculator API with Cloud Functions and Firestore"*