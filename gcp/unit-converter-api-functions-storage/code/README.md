# Infrastructure as Code for Unit Converter API with Cloud Functions and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Unit Converter API with Cloud Functions and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (or use Cloud Shell)
- Google Cloud project with billing enabled
- Appropriate permissions for the following services:
  - Cloud Functions
  - Cloud Storage
  - Cloud Build
  - Infrastructure Manager (for Infrastructure Manager deployment)
- Basic understanding of serverless architecture and HTTP APIs
- Estimated cost: $0.01-0.05 for testing (includes Cloud Functions invocations and Cloud Storage)

> **Note**: Cloud Functions includes 2 million free invocations per month, making this recipe essentially free for development and testing purposes.

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses standard Terraform configuration language while providing additional Google Cloud integrations and managed state.

```bash
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID=$(gcloud config get-value project)

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/unit-converter-api \
    --service-account=${PROJECT_ID}@appspot.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/us-central1/deployments/unit-converter-api
```

### Using Terraform

Terraform provides multi-cloud infrastructure management with extensive provider support and state management capabilities.

```bash
cd terraform/

# Initialize Terraform with Google Cloud provider
terraform init

# Review planned infrastructure changes
terraform plan

# Deploy infrastructure
terraform apply

# View deployed resources and outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a simple deployment option that mirrors the manual recipe steps with added automation and error handling.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Test the deployed function (optional)
# The script will provide the function URL for testing
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `terraform.tfvars` file in the `infrastructure-manager/` directory:

```hcl
project_id = "your-project-id"
region = "us-central1"
function_name = "unit-converter"
bucket_name_suffix = "conversion-history"
```

### Terraform Variables

Edit the `terraform.tfvars` file in the `terraform/` directory or set environment variables:

```bash
# Using environment variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"
export TF_VAR_function_name="unit-converter"
export TF_VAR_bucket_name_suffix="conversion-history"
```

### Bash Script Configuration

The bash scripts use environment variables that can be customized:

```bash
# Set custom values before running deploy.sh
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="unit-converter"
export BUCKET_NAME="your-project-conversion-history"
```

## Deployed Resources

This infrastructure creates the following Google Cloud resources:

- **Cloud Storage Bucket**: Stores conversion history with uniform bucket-level access
- **Cloud Function**: HTTP-triggered serverless function for unit conversions
- **IAM Bindings**: Appropriate permissions for function to access storage
- **Service APIs**: Enables required Google Cloud APIs (Cloud Functions, Storage, Build)

## Testing the Deployment

After successful deployment, test the unit converter API:

```bash
# Get the function URL (provided in deployment outputs)
FUNCTION_URL=$(gcloud functions describe unit-converter --region=us-central1 --format="value(httpsTrigger.url)")

# Test temperature conversion
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"value": 25, "from_unit": "celsius", "to_unit": "fahrenheit"}'

# Test length conversion
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"value": 10, "from_unit": "meters", "to_unit": "feet"}'

# Test weight conversion
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"value": 5, "from_unit": "kilograms", "to_unit": "pounds"}'
```

Expected responses include converted values, original inputs, and timestamps.

## Monitoring and Observability

Monitor your deployed infrastructure using Google Cloud Console:

- **Cloud Functions**: View invocation metrics, logs, and errors
- **Cloud Storage**: Monitor bucket usage and access patterns
- **Cloud Logging**: Search function logs and conversion history
- **Cloud Monitoring**: Set up alerts for function errors or high latency

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment using Infrastructure Manager
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/unit-converter-api
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
```

## Customization

### Adding New Unit Types

To add support for additional unit conversions:

1. Modify the `main.py` function code in your deployment
2. Add new conversion logic to the `perform_conversion()` function
3. Update the `get_conversion_type()` function for proper categorization
4. Redeploy using your chosen IaC method

### Scaling Configuration

Adjust Cloud Function scaling parameters by modifying:

- **Memory allocation**: 128MB to 8GB (affects pricing)
- **Timeout**: Up to 540 seconds for long-running conversions
- **Concurrency**: Maximum concurrent executions per instance
- **Maximum instances**: Control scaling limits for cost management

### Security Enhancements

For production deployments, consider:

- **Cloud Endpoints**: Add API key authentication and rate limiting
- **Cloud Armor**: Implement DDoS protection and security policies
- **VPC Connector**: Deploy function in private network
- **Secret Manager**: Store sensitive configuration data
- **Cloud IAM**: Implement fine-grained access controls

## Cost Optimization

- **Cloud Functions**: 2 million free invocations per month
- **Cloud Storage**: $0.020/GB/month for standard storage
- **Cloud Build**: 120 build-minutes per day included
- **Data Transfer**: Free within same region

Use Cloud Billing budgets and alerts to monitor costs and set spending limits.

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your account has necessary IAM roles
2. **API Not Enabled**: Verify required APIs are enabled in your project
3. **Function Timeout**: Increase timeout for complex conversions
4. **Storage Access**: Check bucket permissions and IAM bindings

### Debugging

```bash
# View function logs
gcloud functions logs read unit-converter --region=us-central1

# Check function status
gcloud functions describe unit-converter --region=us-central1

# List storage bucket contents
gcloud storage ls gs://your-bucket-name/conversions/
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Consult the Infrastructure Manager, Terraform, or bash script documentation
4. Review Google Cloud status page for service outages

## Security Considerations

- Function is deployed with `--allow-unauthenticated` for public API access
- Storage bucket uses uniform bucket-level access for consistent permissions
- Conversion history contains no sensitive data (only numerical values and units)
- CORS headers are configured for web browser compatibility
- All data transfer uses HTTPS encryption

For production use, implement authentication, input validation, and rate limiting as needed for your security requirements.