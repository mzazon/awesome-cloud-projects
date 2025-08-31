# Infrastructure as Code for Age Calculator API with Cloud Run and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Age Calculator API with Cloud Run and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 400.0.0 or later)
- Google Cloud account with billing enabled
- Appropriate permissions for resource creation:
  - Cloud Run Admin
  - Storage Admin
  - Project IAM Admin
  - Service Usage Admin
- Docker installed locally (for optional container testing)

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Set environment variables
export PROJECT_ID="age-calc-api-$(date +%s)"
export REGION="us-central1"

# Create and configure project
gcloud projects create ${PROJECT_ID} --name="Age Calculator API Project"
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable config.googleapis.com \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    storage.googleapis.com

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/age-calculator \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/"
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Set required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for project configuration
```

## Infrastructure Components

This recipe deploys the following Google Cloud resources:

- **Cloud Run Service**: Serverless container hosting the Flask API
- **Cloud Storage Bucket**: Request logging and data persistence
- **IAM Service Account**: Secure access between services
- **IAM Bindings**: Least privilege access controls
- **Application Source**: Containerized Flask application with age calculation logic

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

- `project_id`: Google Cloud project identifier
- `region`: Deployment region (default: us-central1)
- `service_name`: Cloud Run service name
- `bucket_name`: Storage bucket name (auto-generated with random suffix)
- `memory_limit`: Container memory allocation (default: 512Mi)
- `cpu_limit`: Container CPU allocation (default: 1000m)

### Terraform Variables

Configure in `terraform/terraform.tfvars` or via environment variables:

```bash
# Required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"

# Optional customizations
export TF_VAR_service_name="age-calculator-api"
export TF_VAR_memory_limit="512Mi"
export TF_VAR_cpu_limit="1000m"
export TF_VAR_max_instances="10"
export TF_VAR_timeout="300s"
```

### Bash Script Configuration

Modify variables in `scripts/deploy.sh`:

```bash
# Deployment configuration
SERVICE_NAME="age-calculator-api"
REGION="us-central1"
MEMORY_LIMIT="512Mi"
CPU_LIMIT="1000m"
MAX_INSTANCES="10"
```

## Testing the Deployment

After successful deployment, test the API endpoints:

```bash
# Get service URL (replace with your actual service URL)
SERVICE_URL=$(gcloud run services describe age-calculator-api \
    --region us-central1 \
    --format 'value(status.url)')

# Test health check
curl -X GET "${SERVICE_URL}/health" \
    -H "Content-Type: application/json"

# Test age calculation
curl -X POST "${SERVICE_URL}/calculate-age" \
    -H "Content-Type: application/json" \
    -d '{"birth_date": "1990-05-15T00:00:00Z"}'
```

Expected responses:

**Health Check**:
```json
{
  "service": "age-calculator-api",
  "status": "healthy"
}
```

**Age Calculation**:
```json
{
  "age_days": 15,
  "age_months": 7,
  "age_years": 34,
  "birth_date": "1990-05-15T00:00:00+00:00",
  "calculated_at": "2025-07-23T10:30:45.123456+00:00",
  "total_days": 12682
}
```

## Monitoring and Logging

### View Cloud Run Logs

```bash
# Stream service logs
gcloud logs tail "resource.type=cloud_run_revision AND resource.labels.service_name=age-calculator-api"

# View logs in Cloud Console
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=age-calculator-api" \
    --limit 50 \
    --format json
```

### View Request Logs in Storage

```bash
# List request logs
gsutil ls -r gs://age-calc-logs-*/requests/

# View recent log entry
LATEST_LOG=$(gsutil ls gs://age-calc-logs-*/requests/**/*.json | tail -1)
gsutil cat ${LATEST_LOG}
```

### Monitor Service Metrics

```bash
# View service metrics in Cloud Console
gcloud run services describe age-calculator-api \
    --region us-central1 \
    --format yaml
```

## Cleanup

### Using Infrastructure Manager (GCP)

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/age-calculator \
    --quiet

# Delete project (optional - removes all resources)
gcloud projects delete ${PROJECT_ID} --quiet
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for resource deletion
```

## Security Considerations

This implementation follows Google Cloud security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **HTTPS Only**: Cloud Run enforces HTTPS for all traffic
- **Private Container Registry**: Uses Google Cloud Build for secure image building
- **Request Logging**: All API requests are logged for audit purposes
- **Resource Isolation**: Each deployment uses unique resource names

## Cost Optimization

The architecture includes several cost optimization features:

- **Cloud Run Serverless**: Pay only for actual request processing time
- **Storage Lifecycle Management**: Automatic transition to cheaper storage classes
- **Resource Limits**: CPU and memory limits prevent cost overruns
- **Auto-scaling**: Services scale to zero when not in use

Estimated monthly costs for light usage (< 1000 requests):
- Cloud Run: $0.00 (within free tier)
- Cloud Storage: $0.05-$0.50
- **Total**: < $1.00/month

## Troubleshooting

### Common Issues

**Build Failures**:
```bash
# Check build logs
gcloud builds list --limit=5
gcloud builds log [BUILD_ID]
```

**Permission Errors**:
```bash
# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check service account permissions
gcloud iam service-accounts get-iam-policy [SERVICE_ACCOUNT_EMAIL]
```

**Storage Access Issues**:
```bash
# Verify bucket permissions
gsutil iam get gs://[BUCKET_NAME]

# Test storage access
gsutil ls gs://[BUCKET_NAME]
```

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
# Set debug environment variables
export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account.json"

# Enable verbose logging
gcloud config set core/verbosity debug
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../age-calculator-api-run-storage.md)
2. Refer to [Google Cloud Run documentation](https://cloud.google.com/run/docs)
3. Consult [Google Cloud Storage documentation](https://cloud.google.com/storage/docs)
4. Review [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
5. Check [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development project
2. Validate all IaC implementations work correctly
3. Update documentation to reflect changes
4. Ensure security best practices are maintained