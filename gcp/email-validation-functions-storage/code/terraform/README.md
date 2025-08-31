# Email Validation with Cloud Functions - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying the "Email Validation with Cloud Functions and Cloud Storage" solution on Google Cloud Platform.

## Architecture Overview

This Terraform configuration deploys:

- **Cloud Functions (2nd Gen)**: Serverless email validation API with Python runtime
- **Cloud Storage**: Bucket for storing validation logs with lifecycle management
- **IAM Service Account**: Dedicated service account with least-privilege access
- **Logging Integration**: Cloud Logging for monitoring and debugging
- **Cost Optimization**: Lifecycle policies for automatic storage class transitions

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK** installed and configured
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** installed (version >= 1.0)
   ```bash
   terraform version
   ```

3. **Required permissions** in your Google Cloud project:
   - Cloud Functions Developer
   - Storage Admin
   - Service Account Admin
   - IAM Admin
   - Project Editor (or equivalent custom role)

4. **Billing enabled** on your Google Cloud project

5. **APIs that will be automatically enabled**:
   - Cloud Functions API
   - Cloud Build API
   - Cloud Storage API
   - Cloud Logging API
   - Cloud Run API

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file and customize for your environment:

```bash
# Review available variables
cat variables.tf

# Create terraform.tfvars file with your customizations
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Customize function configuration
function_name    = "email-validator"
function_memory  = "256M"
function_timeout = 60
max_instances    = 10

# Enable cost optimization
enable_cost_optimization = true
lifecycle_age_nearline   = 30
lifecycle_age_delete     = 365

# Security settings
allow_unauthenticated_invocations = true
enable_uniform_bucket_access      = true
enable_versioning                 = true

# Labels for resource organization
labels = {
  environment = "production"
  application = "email-validation"
  team        = "platform"
  managed-by  = "terraform"
}
EOF
```

### 3. Plan the Deployment

```bash
terraform plan
```

Review the planned changes to ensure everything looks correct.

### 4. Deploy the Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

### 5. Test the Deployment

After successful deployment, test the email validation API:

```bash
# Get the function URL from Terraform output
FUNCTION_URL=$(terraform output -raw function_url)

# Test with a valid email
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"email":"test@gmail.com"}' \
  $FUNCTION_URL

# Test with an invalid email
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"email":"invalid-email"}' \
  $FUNCTION_URL
```

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `function_name` | Cloud Function name | `email-validator` | No |

### Performance Tuning

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `function_memory` | Memory allocation | `256M` | 128M-8192M |
| `function_timeout` | Execution timeout | `60` seconds | 1-540 seconds |
| `max_instances` | Max parallel instances | `10` | 1-1000 |
| `min_instances` | Min warm instances | `0` | 0-100 |

### Cost Optimization

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_cost_optimization` | Enable lifecycle policies | `true` |
| `lifecycle_age_nearline` | Days to NEARLINE transition | `30` |
| `lifecycle_age_delete` | Days to deletion | `365` |
| `storage_class` | Initial storage class | `STANDARD` |

### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `allow_unauthenticated_invocations` | Allow public access | `true` |
| `enable_uniform_bucket_access` | Uniform bucket access | `true` |
| `enable_versioning` | Object versioning | `true` |

## Outputs

After deployment, Terraform provides useful outputs:

```bash
# View all outputs
terraform output

# Get specific outputs
terraform output function_url
terraform output logs_bucket_name
terraform output test_curl_command
```

### Key Outputs

- `function_url`: HTTP endpoint for email validation
- `logs_bucket_name`: Cloud Storage bucket for validation logs
- `test_curl_command`: Ready-to-use test commands
- `cloud_logging_link`: Direct link to function logs in GCP Console

## Monitoring and Observability

### View Function Logs

```bash
# Using gcloud CLI
gcloud functions logs read email-validator --region=us-central1

# Using Terraform output link
terraform output cloud_logging_link
```

### View Validation Logs in Storage

```bash
# List validation logs
BUCKET_NAME=$(terraform output -raw logs_bucket_name)
gsutil ls -r gs://$BUCKET_NAME/validations/

# View a specific log file
gsutil cat gs://$BUCKET_NAME/validations/YYYY/MM/DD/timestamp.json
```

### Performance Metrics

Monitor function performance in the [GCP Console](https://console.cloud.google.com/functions):
- Invocations per second
- Execution time
- Memory usage
- Error rate

## Cost Management

### Estimated Costs

Based on the following usage patterns:

- **10,000 function invocations/month**: ~$0.004
- **1 GB validation logs/month**: ~$0.020 (STANDARD) → ~$0.010 (NEARLINE after 30 days)
- **Cloud Logging**: First 50 GB free

**Total estimated monthly cost**: < $0.05 for typical development usage

### Cost Optimization Features

1. **Automatic Storage Transitions**: Logs move to NEARLINE after 30 days
2. **Automatic Deletion**: Logs deleted after 365 days (configurable)
3. **Efficient Function Sizing**: Optimized memory and timeout settings
4. **Minimal Warm Instances**: Default to 0 to minimize idle costs

## Security Considerations

### Production Hardening

For production deployments, consider:

1. **Disable unauthenticated access**:
   ```hcl
   allow_unauthenticated_invocations = false
   ```

2. **Implement API authentication**:
   - Use API keys or JWT tokens
   - Configure Cloud Endpoints or API Gateway

3. **Network security**:
   ```hcl
   # Restrict function ingress
   ingress_settings = "ALLOW_INTERNAL_ONLY"
   ```

4. **Audit logging**:
   - Enable Cloud Audit Logs
   - Configure log exports to BigQuery

### IAM Best Practices

The configuration follows security best practices:
- Dedicated service account with minimal permissions
- No default compute service account usage
- Principle of least privilege

## Troubleshooting

### Common Issues

1. **API not enabled errors**:
   ```bash
   # Manually enable required APIs
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

2. **Permission denied errors**:
   ```bash
   # Check your IAM permissions
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   ```

3. **Function source code issues**:
   ```bash
   # Verify function source files are created
   ls -la function-source/
   ```

4. **Storage bucket access issues**:
   ```bash
   # Check bucket IAM
   gsutil iam get gs://BUCKET_NAME
   ```

### Debug Function Issues

```bash
# View function details
gcloud functions describe email-validator --region=us-central1 --gen2

# Test function locally (requires Functions Framework)
cd function-source/
functions-framework --target=validate_email --debug
```

## Advanced Configuration

### Custom Domain Setup

To use a custom domain:

1. Configure Cloud Load Balancer
2. Set up SSL certificates
3. Route traffic to the function URL

### API Rate Limiting

Implement rate limiting using:
- Cloud Endpoints
- API Gateway
- Cloud Armor (for DDoS protection)

### Multi-Region Deployment

For global deployment:

```hcl
# Deploy to multiple regions
module "email_validator_us" {
  source = "./modules/email-validator"
  region = "us-central1"
  # ... other variables
}

module "email_validator_europe" {
  source = "./modules/email-validator"
  region = "europe-west1"
  # ... other variables
}
```

## Cleanup

To remove all deployed resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete:
- The Cloud Function
- All validation logs in Cloud Storage
- The service account and IAM bindings

## Support

For issues with this Terraform configuration:

1. Check the [original recipe documentation](../email-validation-functions-storage.md)
2. Review [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
3. Consult [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)

## Contributing

When modifying this configuration:

1. Follow Terraform best practices
2. Update variable descriptions and validation
3. Test changes in a development environment
4. Update this README with any new features or requirements

## License

This infrastructure code is provided as-is under the same license as the parent recipe repository.