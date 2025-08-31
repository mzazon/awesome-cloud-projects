# BMI Calculator API - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying the BMI Calculator API on Google Cloud Platform. The solution creates a serverless HTTP API using Cloud Functions that calculates Body Mass Index (BMI) and stores calculation history in Cloud Storage.

## Architecture Overview

The infrastructure deploys the following components:

- **Cloud Function (Gen 2)**: Serverless HTTP API for BMI calculations
- **Cloud Storage Bucket**: Durable storage for calculation history
- **Service Account**: Dedicated identity for secure function execution
- **IAM Policies**: Least-privilege access controls
- **Pub/Sub Topic**: Event notifications for calculation events
- **Cloud Monitoring**: Error alerting and observability

## Prerequisites

1. **Google Cloud Platform Account**: Active GCP account with billing enabled
2. **Terraform**: Version 1.0 or later installed locally
3. **Google Cloud CLI**: Authenticated and configured with appropriate permissions
4. **Required Permissions**: The deploying user/service account needs:
   - `Project Editor` or equivalent custom role with:
     - Cloud Functions Admin
     - Storage Admin
     - Service Account Admin
     - Pub/Sub Admin
     - Monitoring Admin

## Required APIs

The following Google Cloud APIs will be automatically enabled:

- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Artifact Registry API (`artifactregistry.googleapis.com`)
- Cloud Run API (`run.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the Terraform directory
cd ./gcp/bmi-calculator-functions-storage/code/terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your project-specific values:

```hcl
# Required variables
project_id = "your-gcp-project-id"

# Optional customizations (defaults shown)
region               = "us-central1"
zone                = "us-central1-a"
function_name       = "bmi-calculator"
bucket_name_prefix  = "bmi-history"
function_runtime    = "python311"
function_memory     = 256
function_timeout    = 60
storage_class       = "STANDARD"
allow_unauthenticated = true

# Custom labels
labels = {
  environment = "development"
  application = "bmi-calculator"
  managed-by  = "terraform"
  owner       = "your-team"
}
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Test the API

After deployment, use the function URL from the output:

```bash
# Get the function URL
FUNCTION_URL=$(terraform output -raw function_url)

# Test the BMI calculation API
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"height": 1.75, "weight": 70}' \
    | python3 -m json.tool
```

Expected response:
```json
{
  "timestamp": "2024-01-01T12:00:00.000000",
  "height": 1.75,
  "weight": 70,
  "bmi": 22.86,
  "category": "Normal weight"
}
```

## Configuration Options

### Function Configuration

| Variable | Description | Default | Valid Values |
|----------|-------------|---------|--------------|
| `function_name` | Name of the Cloud Function | `"bmi-calculator"` | Valid GCP resource name |
| `function_runtime` | Python runtime version | `"python311"` | `python37`, `python38`, `python39`, `python310`, `python311`, `python312` |
| `function_memory` | Memory allocation (MB) | `256` | `128`, `256`, `512`, `1024`, `2048`, `4096`, `8192` |
| `function_timeout` | Timeout in seconds | `60` | `1` to `540` |
| `allow_unauthenticated` | Allow public access | `true` | `true` or `false` |

### Storage Configuration

| Variable | Description | Default | Valid Values |
|----------|-------------|---------|--------------|
| `bucket_name_prefix` | Storage bucket name prefix | `"bmi-history"` | Valid bucket name |
| `storage_class` | Storage class | `"STANDARD"` | `STANDARD`, `NEARLINE`, `COLDLINE`, `ARCHIVE` |
| `bucket_lifecycle_rules` | Lifecycle management rules | Delete after 90 days | List of lifecycle rules |
| `cors_origins` | Allowed CORS origins | `["*"]` | List of origins |

### Geographic Configuration

| Variable | Description | Default | Valid Values |
|----------|-------------|---------|--------------|
| `region` | GCP region | `"us-central1"` | Valid GCP region |
| `zone` | GCP zone | `"us-central1-a"` | Valid GCP zone |

## API Usage

### Endpoint

```
POST https://[region]-[project-id].cloudfunctions.net/[function-name]
```

### Request Format

```json
{
  "height": 1.75,  // Height in meters (required)
  "weight": 70     // Weight in kilograms (required)
}
```

### Response Format

```json
{
  "timestamp": "2024-01-01T12:00:00.000000",  // Calculation timestamp
  "height": 1.75,                             // Input height
  "weight": 70,                               // Input weight
  "bmi": 22.86,                               // Calculated BMI
  "category": "Normal weight"                 // WHO BMI category
}
```

### Error Responses

```json
{
  "error": "Height and weight must be positive numbers"
}
```

### BMI Categories

- **Underweight**: BMI < 18.5
- **Normal weight**: 18.5 ≤ BMI < 25
- **Overweight**: 25 ≤ BMI < 30
- **Obese**: BMI ≥ 30

## Monitoring and Observability

### Cloud Monitoring

The deployment includes:

- **Error Rate Alert**: Triggers when function error rate exceeds 10%
- **Function Logs**: Available in Cloud Logging with structured logging
- **Metrics Dashboard**: Function invocations, duration, and error rates

### Accessing Logs

```bash
# View function logs
gcloud functions logs read bmi-calculator --region=us-central1

# View real-time logs
gcloud functions logs tail bmi-calculator --region=us-central1
```

### Storage Monitoring

```bash
# List calculation files
gsutil ls -r gs://$(terraform output -raw storage_bucket_name)/calculations/

# View a calculation file
gsutil cat gs://$(terraform output -raw storage_bucket_name)/calculations/[filename]
```

## Security Features

### Authentication and Authorization

- **Service Account**: Dedicated service account with minimal permissions
- **IAM Roles**: Principle of least privilege access
- **Public Access**: Configurable via `allow_unauthenticated` variable

### Data Security

- **Encryption**: Data encrypted at rest and in transit
- **Versioning**: Bucket versioning enabled for data protection
- **Lifecycle Management**: Automatic cleanup of old data
- **CORS**: Configurable cross-origin resource sharing

### Network Security

- **HTTPS Only**: All communication over TLS
- **VPC Egress**: Private ranges only for enhanced security
- **Input Validation**: Comprehensive input validation and sanitization

## Cost Optimization

### Free Tier Allowances

For typical development usage, this solution operates within GCP free tier:

- **Cloud Functions**: 2M requests, 400,000 GB-seconds per month
- **Cloud Storage**: 5GB storage per month
- **Cloud Monitoring**: 150MB logs per month
- **Pub/Sub**: 10GB messages per month

### Cost Management

- **Lifecycle Rules**: Automatic deletion of old calculation files
- **Memory Optimization**: Configurable function memory allocation
- **Timeout Configuration**: Optimal timeout settings to minimize costs

## Backup and Recovery

### Data Backup

- **Versioning**: Bucket versioning protects against accidental deletion
- **Cross-Region Replication**: Can be enabled for disaster recovery
- **Export Options**: Data can be exported to BigQuery for analysis

### Function Recovery

- **Source Code Backup**: Function source stored in Cloud Storage
- **Infrastructure as Code**: Complete infrastructure reproducible via Terraform
- **Configuration Management**: All settings version-controlled

## Maintenance

### Updates

```bash
# Update function code
terraform apply -replace=google_cloudfunctions2_function.bmi_calculator

# Update infrastructure
terraform plan
terraform apply
```

### Scaling

The solution automatically scales based on demand:

- **Auto-scaling**: 0 to 100 concurrent instances
- **Cold Start Optimization**: Gen 2 functions provide faster cold starts
- **Regional Deployment**: Can be deployed across multiple regions

## Cleanup

### Terraform Destroy

```bash
# Remove all resources
terraform destroy
```

### Manual Cleanup (if needed)

```bash
# Delete function
gcloud functions delete bmi-calculator --region=us-central1 --quiet

# Delete storage bucket
gsutil -m rm -r gs://[bucket-name]

# Delete service account
gcloud iam service-accounts delete [service-account-email] --quiet
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
2. **Permissions**: Verify deploying user has sufficient permissions
3. **Bucket Name Conflict**: Bucket names must be globally unique
4. **Function Timeout**: Increase timeout for slower operations

### Debug Commands

```bash
# Check function status
gcloud functions describe bmi-calculator --region=us-central1

# View function logs
gcloud functions logs read bmi-calculator --region=us-central1 --limit=50

# Test function locally
functions-framework --target=calculate_bmi --source=function-source/
```

## Support

For issues with this infrastructure:

1. Check the [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
2. Review [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
3. Consult [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
4. Check the original recipe documentation for implementation details

## License

This infrastructure code is provided as-is for educational and development purposes.