# Infrastructure as Code for URL Safety Validation using Web Risk and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "URL Safety Validation using Web Risk and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (create, deploy, delete)
  - Cloud Storage (create buckets, manage objects)
  - Web Risk API (enable and use)
  - Cloud Build (for function deployment)
  - IAM (manage service account permissions)
- Terraform installed (version >= 1.0) - for Terraform implementation
- Python 3.11+ - for function code
- Estimated cost: $0.50-$2.00 per 1,000 URL validations

## Architecture Overview

This solution deploys:
- Cloud Function for URL validation processing
- Cloud Storage buckets for audit logs and result caching
- IAM roles and permissions for Web Risk API access
- Lifecycle policies for cost optimization

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for infrastructure as code, providing native integration with Google Cloud services.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
export DEPLOYMENT_NAME="url-safety-validation"

# Create the deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/${DEPLOYMENT_NAME} \
    --service-account=$(gcloud config get-value account) \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/us-central1/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

Terraform provides declarative infrastructure management with state tracking and change planning.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Set required variables (create terraform.tfvars file)
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide imperative deployment with direct `gcloud` commands following the recipe steps.

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./deploy.sh

# Test the deployment (optional)
./test_deployment.sh
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:
- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `function_memory`: Cloud Function memory allocation (default: 256MB)
- `cache_retention_days`: Cache bucket lifecycle policy (default: 30 days)

### Terraform Variables

Available variables in `variables.tf`:
- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: "us-central1")
- `zone`: Deployment zone (default: "us-central1-a")
- `function_name_prefix`: Prefix for function name (default: "url-validator")
- `function_memory`: Memory allocation for Cloud Function (default: 256)
- `function_timeout`: Function timeout in seconds (default: 60)
- `cache_retention_days`: Days to retain cached results (default: 30)
- `enable_versioning`: Enable bucket versioning for audit logs (default: true)

### Script Variables

Environment variables for bash scripts:
- `PROJECT_ID`: Your Google Cloud project ID (required)
- `REGION`: Deployment region (default: us-central1)
- `ZONE`: Deployment zone (default: us-central1-a)
- `FUNCTION_NAME`: Custom function name (optional)

## Testing the Deployment

After deployment, test the URL validation function:

```bash
# Get the function URL
FUNCTION_URL=$(gcloud functions describe url-validator-* \
    --format="value(httpsTrigger.url)" \
    --region=${REGION})

# Test with a safe URL
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"url": "https://www.google.com"}' \
    | jq '.'

# Test with Google's malware test URL
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"url": "https://testsafebrowsing.appspot.com/s/malware.html"}' \
    | jq '.'

# Check audit logs
gsutil ls -r gs://url-validation-logs-${PROJECT_ID}/audit/

# Check cache storage
gsutil ls -r gs://url-validation-cache-${PROJECT_ID}/cache/
```

## Monitoring and Observability

View function logs and metrics:

```bash
# View function logs
gcloud functions logs read url-validator-* \
    --region=${REGION} \
    --limit=50

# View function metrics in Cloud Console
echo "Monitor function performance at:"
echo "https://console.cloud.google.com/functions/details/${REGION}/url-validator-*?project=${PROJECT_ID}"

# Check Web Risk API usage
gcloud logging read "resource.type=consumed_api AND protoPayload.serviceName=webrisk.googleapis.com" \
    --limit=10 \
    --format="table(timestamp,protoPayload.methodName,protoPayload.status.code)"
```

## Cost Optimization

The deployment includes several cost optimization features:

1. **Cloud Storage Lifecycle Policies**: Automatically delete cached results after 30 days
2. **Function Memory Optimization**: Uses 256MB memory allocation for optimal cost/performance
3. **Intelligent Caching**: Reduces Web Risk API calls through 24-hour result caching
4. **Pay-per-Request**: Serverless architecture scales to zero when not in use

Monitor costs with:

```bash
# View current month billing
gcloud billing budgets list

# Check Web Risk API usage
gcloud services list --enabled --filter="name:webrisk.googleapis.com"
```

## Security Considerations

The deployment follows security best practices:

- **Least Privilege IAM**: Function service account has minimal required permissions
- **API-only Access**: Web Risk API access restricted to function service account
- **Audit Logging**: All validation requests logged to Cloud Storage
- **HTTPS Only**: Function accessible only via HTTPS
- **Input Validation**: Function validates URL format and parameters

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/${DEPLOYMENT_NAME} \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Verify resources are deleted
gcloud functions list --regions=${REGION}
gsutil ls | grep url-validation
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure Web Risk API is enabled
   ```bash
   gcloud services enable webrisk.googleapis.com
   ```

2. **Insufficient Permissions**: Verify your account has required IAM roles
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Function Deployment Fails**: Check Cloud Build permissions
   ```bash
   gcloud services enable cloudbuild.googleapis.com
   ```

4. **Storage Access Denied**: Verify function service account permissions
   ```bash
   FUNCTION_SA=$(gcloud functions describe url-validator-* \
       --format="value(serviceAccountEmail)" --region=${REGION})
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:${FUNCTION_SA}"
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# View detailed function logs
gcloud functions logs read url-validator-* \
    --region=${REGION} \
    --severity=DEBUG

# Enable Cloud Trace for performance analysis
gcloud services enable cloudtrace.googleapis.com
```

## Customization

### Adding Custom Threat Types

Modify the function code to include additional Web Risk threat types:

```python
# In main.py, update threat_types list
threat_types = [
    webrisk_v1.ThreatType.MALWARE,
    webrisk_v1.ThreatType.SOCIAL_ENGINEERING,
    webrisk_v1.ThreatType.UNWANTED_SOFTWARE,
    # Add custom threat types here
]
```

### Custom Cache Duration

Adjust cache retention in the function logic:

```python
# Change cache validity period (currently 24 hours)
if (now - cache_time).total_seconds() < 7200:  # 2 hours
```

### Integration with External Systems

The function can be integrated with:
- **Slack**: Add webhook integration for threat notifications
- **Email**: Use SendGrid or similar for alert emails  
- **SIEM**: Forward audit logs to security information systems
- **API Gateway**: Add authentication and rate limiting

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud Function documentation: https://cloud.google.com/functions/docs
3. Consult Web Risk API documentation: https://cloud.google.com/web-risk/docs
4. Review Google Cloud best practices: https://cloud.google.com/architecture/framework

## Version Information

- Infrastructure Manager: Uses latest Google Cloud resource types
- Terraform: Compatible with Google Cloud Provider v4.0+
- Cloud Functions: Python 3.11 runtime
- Web Risk API: v1 (latest stable)

Last updated: 2025-07-12