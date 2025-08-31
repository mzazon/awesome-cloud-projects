# Infrastructure as Code for Email Validation with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Email Validation with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Required permissions:
  - Cloud Functions Developer
  - Storage Admin
  - IAM Admin (for service account management)
  - Project Editor (for enabling APIs)
- For Terraform: Terraform CLI installed (version >= 1.0)

## Architecture Overview

This infrastructure deploys:
- Cloud Functions (2nd generation) for email validation API
- Cloud Storage bucket for validation logs with lifecycle management
- IAM service account with appropriate permissions
- Required API enablements (Cloud Functions, Cloud Build, Cloud Storage)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code, providing native integration with Google Cloud services and APIs.

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export DEPLOYMENT_NAME="email-validation-deployment"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/cloudservices@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive community support with Google Cloud provider integration.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct CLI interaction and are ideal for learning and quick deployments.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployed function (optional)
./scripts/test.sh

# View deployment status
./scripts/status.sh
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"                    # Deployment region
export FUNCTION_NAME="email-validator"         # Cloud Function name
export BUCKET_NAME="email-validation-logs"     # Storage bucket name (will have random suffix)
```

### Terraform Variables

Customize deployment by modifying `terraform/terraform.tfvars`:

```hcl
project_id      = "your-project-id"
region          = "us-central1"
function_name   = "email-validator"
bucket_prefix   = "email-validation-logs"
function_memory = "256Mi"
function_timeout = 60
```

### Infrastructure Manager Variables

Customize deployment by modifying `infrastructure-manager/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
```

## Deployment Outputs

After successful deployment, you'll receive:

- **Function URL**: HTTPS endpoint for the email validation API
- **Bucket Name**: Cloud Storage bucket name for validation logs
- **Service Account**: Email of the function's service account
- **Project ID**: Deployed project identifier

## Testing the Deployment

### Test Email Validation API

```bash
# Test with valid email
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"email":"test@gmail.com"}' \
    ${FUNCTION_URL}

# Test with invalid email
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"email":"invalid-email"}' \
    ${FUNCTION_URL}
```

### Verify Log Storage

```bash
# List validation logs
gsutil ls -r gs://${BUCKET_NAME}/validations/

# View recent log entry
gsutil cat $(gsutil ls gs://${BUCKET_NAME}/validations/**/*.json | tail -1)
```

## Monitoring and Observability

### View Function Logs

```bash
# View Cloud Function logs
gcloud functions logs read ${FUNCTION_NAME} \
    --gen2 \
    --region ${REGION} \
    --limit 50
```

### Monitor Function Metrics

```bash
# View function invocation metrics
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=${FUNCTION_NAME}" \
    --limit 10 \
    --format="table(timestamp,severity,textPayload)"
```

## Cost Optimization

This deployment includes several cost optimization features:

- **Cloud Storage Lifecycle**: Automatic transition to cheaper storage classes after 30 days
- **Function Memory**: Optimized to 256Mi for email validation workload
- **Storage Location**: Regional storage for cost efficiency
- **Auto-cleanup**: Logs automatically deleted after 365 days

### Estimated Costs

- Cloud Functions: Free tier includes 2M invocations/month
- Cloud Storage: ~$0.020/GB/month for standard storage
- Cloud Build: 120 build-minutes/day free tier
- Total estimated cost for testing: $0.01-$0.50/month

## Security Features

- **IAM Best Practices**: Function service account has minimal required permissions
- **HTTPS Only**: All API endpoints use TLS encryption
- **Audit Logging**: All validation attempts are logged for compliance
- **Network Security**: Functions deployed with default VPC security
- **Data Privacy**: Email addresses are processed transiently with structured logging

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are deleted
./scripts/verify-cleanup.sh
```

### Manual Cleanup Verification

```bash
# Verify function deletion
gcloud functions list --gen2 --filter="name:${FUNCTION_NAME}"

# Verify bucket deletion
gsutil ls -p ${PROJECT_ID} | grep ${BUCKET_NAME}

# Check for any remaining resources
gcloud logging read "protoPayload.serviceName=cloudfunctions.googleapis.com" --limit=5
```

## Troubleshooting

### Common Issues

**Function Deployment Fails**
```bash
# Check API enablement
gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com OR name:cloudbuild.googleapis.com"

# Verify project permissions
gcloud projects get-iam-policy ${PROJECT_ID}
```

**Storage Access Denied**
```bash
# Verify service account permissions
gsutil iam get gs://${BUCKET_NAME}

# Check function service account
gcloud functions describe ${FUNCTION_NAME} --gen2 --region=${REGION} --format="value(serviceConfig.serviceAccountEmail)"
```

**Function Returns Errors**
```bash
# View detailed function logs
gcloud functions logs read ${FUNCTION_NAME} --gen2 --region=${REGION} --limit=10

# Test function locally (if source available)
functions-framework --target=validate_email --debug
```

### Debug Mode

Enable debug logging for deployments:

```bash
# For Terraform
export TF_LOG=DEBUG
terraform apply

# For gcloud commands
gcloud config set core/log_http true
```

## Customization

### Extending Email Validation

Modify the function source code to add:
- Integration with external email verification services
- Advanced regex patterns for specific domains
- Webhook notifications for validation results
- Rate limiting with Redis/Memorystore

### Storage Configuration

Customize Cloud Storage settings:
- Change lifecycle policies in `lifecycle.json`
- Modify bucket location and storage class
- Add bucket notifications for real-time processing
- Enable object versioning and retention policies

### Monitoring Enhancements

Add comprehensive monitoring:
- Custom Cloud Monitoring metrics
- Alerting policies for function failures
- Performance tracking dashboards
- Cost monitoring and budgets

## Integration Examples

### API Gateway Integration

```bash
# Create API Gateway configuration
gcloud api-gateway api-configs create email-validation-config \
    --api=email-validation-api \
    --openapi-spec=openapi.yaml
```

### CI/CD Pipeline Integration

```yaml
# Cloud Build configuration example
steps:
  - name: 'gcr.io/cloud-builders/gcloud'
    args: ['functions', 'deploy', '${_FUNCTION_NAME}', '--source', '.']
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: [Cloud Functions](https://cloud.google.com/functions/docs), [Cloud Storage](https://cloud.google.com/storage/docs)
3. **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Infrastructure Manager**: [Google Cloud Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Version Information

- **Infrastructure Manager**: Uses Google Cloud's native deployment engine
- **Terraform**: Compatible with Google Cloud Provider 4.0+
- **Cloud Functions**: 2nd generation runtime with Python 3.11
- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12

## Contributing

When updating this infrastructure code:

1. Test all deployment methods
2. Verify cleanup procedures
3. Update cost estimates
4. Validate security configurations
5. Update documentation for any changes