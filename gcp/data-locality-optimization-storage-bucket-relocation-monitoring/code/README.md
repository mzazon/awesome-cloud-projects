# Infrastructure as Code for Data Locality Optimization with Cloud Storage Bucket Relocation and Cloud Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Locality Optimization with Cloud Storage Bucket Relocation and Cloud Monitoring".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate permissions for the following services:
  - Cloud Storage
  - Cloud Monitoring
  - Cloud Functions
  - Cloud Scheduler
  - Pub/Sub
  - Storage Transfer Service
- Basic understanding of data locality optimization concepts
- Estimated cost: $15-25 per month for monitoring, functions, and storage (excluding data transfer costs)

### Required APIs

The following Google Cloud APIs must be enabled in your project:

```bash
gcloud services enable storage.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudscheduler.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable storagetransfer.googleapis.com
```

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code, providing native integration with Google Cloud services and IAM.

```bash
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply data-locality-optimization \
    --location=${REGION} \
    --file=main.yaml \
    --inputs=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment status
gcloud infra-manager deployments describe data-locality-optimization \
    --location=${REGION}
```

### Using Terraform

Terraform provides a declarative approach to infrastructure management with state tracking and plan preview capabilities.

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a simple automation approach that closely follows the manual recipe steps.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required values:
# - Project ID (auto-detected from gcloud config)
# - Primary region (default: us-central1)
# - Secondary region (default: europe-west1)
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Primary region for resources | `us-central1` | Yes |
| `secondary_region` | Secondary region for optimization | `europe-west1` | No |
| `environment` | Environment label for resources | `production` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud project ID | `string` | - | Yes |
| `region` | Primary region for resources | `string` | `us-central1` | Yes |
| `secondary_region` | Secondary region for optimization | `string` | `europe-west1` | No |
| `bucket_name_prefix` | Prefix for storage bucket names | `string` | `data-locality-demo` | No |
| `environment` | Environment label for resources | `string` | `production` | No |
| `schedule_timezone` | Timezone for scheduled jobs | `string` | `America/New_York` | No |
| `analysis_schedule` | Cron schedule for analysis jobs | `string` | `0 2 * * *` | No |

### Script Configuration

The bash scripts use environment variables for configuration:

```bash
# Optional: Set custom values before running deploy.sh
export REGION="europe-west1"
export SECONDARY_REGION="asia-east1"
export ENVIRONMENT="staging"
export SCHEDULE_TIMEZONE="Europe/London"
```

## Deployed Resources

This infrastructure creates the following Google Cloud resources:

### Storage Resources
- **Cloud Storage Bucket**: Primary storage with monitoring labels and uniform access control
- **Bucket IAM Bindings**: Appropriate permissions for automation services

### Monitoring Resources
- **Custom Metrics**: Regional access latency tracking
- **Alert Policies**: High latency detection and notification
- **Monitoring Dashboards**: Visualization of access patterns and performance

### Compute Resources
- **Cloud Function**: Serverless logic for bucket relocation analysis
- **Function IAM Roles**: Service account with required permissions

### Automation Resources
- **Cloud Scheduler Job**: Periodic analysis trigger
- **Pub/Sub Topic**: Notification messaging
- **Pub/Sub Subscription**: Message handling for monitoring

### Networking
- **VPC Connector** (if required): Secure function networking
- **Firewall Rules** (if required): Controlled access policies

## Validation & Testing

After deployment, validate the infrastructure using these commands:

### Verify Storage Configuration
```bash
# Check bucket configuration
gsutil ls -L -b gs://[BUCKET_NAME]

# Verify bucket labels
gsutil label get gs://[BUCKET_NAME]
```

### Test Cloud Function
```bash
# Get function URL
FUNCTION_URL=$(gcloud functions describe bucket-relocator \
    --format="value(httpsTrigger.url)")

# Test function execution
curl -X GET ${FUNCTION_URL}
```

### Verify Monitoring Setup
```bash
# List custom metrics
gcloud monitoring metrics list \
    --filter="type:custom.googleapis.com/storage/regional_access_latency"

# Check alert policies
gcloud alpha monitoring policies list \
    --filter="displayName:Storage Access Latency Alert"
```

### Test Automation
```bash
# Check scheduler job
gcloud scheduler jobs describe locality-analyzer

# Test Pub/Sub messaging
gcloud pubsub subscriptions pull relocation-alerts-monitor --limit=5
```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete the deployment
gcloud infra-manager deployments delete data-locality-optimization \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# - Prompt for confirmation before destructive actions
# - Remove resources in dependency order
# - Verify successful deletion
# - Clean up local files
```

## Customization

### Modifying Monitoring Thresholds

To adjust performance monitoring thresholds:

1. **Infrastructure Manager**: Update the `alert_policy` configuration in `main.yaml`
2. **Terraform**: Modify the `google_monitoring_alert_policy` resource in `main.tf`
3. **Scripts**: Edit the alert policy JSON in `deploy.sh`

### Adding Additional Regions

To support more regions for optimization:

1. Add region variables to your chosen IaC tool
2. Update the Cloud Function logic to handle additional regions
3. Modify monitoring queries to include new regions

### Custom Access Pattern Analysis

To implement custom analysis logic:

1. Modify the Cloud Function source code in the IaC templates
2. Update function environment variables for new parameters
3. Adjust monitoring metrics for custom data points

## Monitoring and Observability

### Key Metrics to Monitor

- **Storage Access Latency**: Average response time by region
- **Request Volume**: Number of requests per region over time
- **Transfer Costs**: Data egress charges by destination region
- **Function Execution**: Relocation analysis function performance
- **Relocation Events**: Frequency and success rate of bucket relocations

### Dashboard Access

After deployment, access monitoring dashboards:

```bash
# Get monitoring dashboard URL
echo "https://console.cloud.google.com/monitoring/dashboards/custom/data-locality-optimization"
```

### Log Analysis

View function execution logs:

```bash
# Cloud Function logs
gcloud functions logs read bucket-relocator --limit=50

# Scheduler job logs
gcloud logging read "resource.type=cloud_scheduler_job AND resource.labels.job_id=locality-analyzer"
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure all required APIs are enabled and service accounts have appropriate IAM roles
2. **Function Timeout**: Increase function timeout in configuration if analysis takes longer than expected
3. **Monitoring Data Lag**: Custom metrics may take 5-10 minutes to appear in monitoring queries
4. **Bucket Relocation Limits**: Review [Cloud Storage relocation documentation](https://cloud.google.com/storage/docs/bucket-relocation/overview) for regional support and limitations

### Debug Commands

```bash
# Check service account permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Verify API enablement
gcloud services list --enabled

# Test function locally (if using Terraform)
cd terraform/function-source && python main.py
```

## Security Considerations

This infrastructure implements several security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **Uniform Bucket Access**: Consistent access control across all bucket objects
- **VPC Security**: Functions can be configured with VPC connectors for network isolation
- **Audit Logging**: All resource modifications are logged for compliance
- **Secret Management**: Sensitive configuration uses Google Secret Manager (if implemented)

### Security Validation

```bash
# Review IAM policies
gcloud iam service-accounts get-iam-policy [SERVICE_ACCOUNT_EMAIL]

# Check bucket permissions
gsutil iam get gs://[BUCKET_NAME]

# Audit function configuration
gcloud functions describe bucket-relocator --format="yaml"
```

## Cost Optimization

### Cost Monitoring

Track costs associated with this solution:

```bash
# View billing data for the project
gcloud billing accounts list
gcloud alpha billing budgets list --billing-account=[BILLING_ACCOUNT_ID]
```

### Cost Optimization Tips

1. **Function Memory**: Adjust Cloud Function memory allocation based on actual usage
2. **Monitoring Retention**: Configure appropriate retention periods for monitoring data
3. **Scheduler Frequency**: Optimize analysis frequency based on access pattern volatility
4. **Storage Classes**: Implement automatic storage class transitions for infrequently accessed data

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../data-locality-optimization-storage-bucket-relocation-monitoring.md)
2. Consult [Google Cloud documentation](https://cloud.google.com/docs)
3. Check [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. Review [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate against Google Cloud best practices
3. Update documentation accordingly
4. Ensure backward compatibility where possible

## License

This infrastructure code is provided under the same license as the parent recipe repository.