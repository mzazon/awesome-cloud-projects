# Infrastructure as Code for Carbon-Efficient Batch Processing with Cloud Batch and Sustainability Intelligence

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Carbon-Efficient Batch Processing with Cloud Batch and Sustainability Intelligence".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud CLI) installed and configured (version 400.0.0 or later)
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Batch service management
  - Pub/Sub topic and subscription management
  - Cloud Storage bucket management
  - Cloud Monitoring metrics management
  - Cloud Functions deployment
  - Service account management
- Basic understanding of carbon footprint tracking and sustainability metrics
- Estimated cost: $25-50 USD for complete implementation and testing

## Quick Start

### Using Infrastructure Manager

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/carbon-batch-deployment \
    --service-account=${SERVICE_ACCOUNT_EMAIL} \
    --git-source-repo="https://github.com/your-org/your-repo" \
    --git-source-directory="gcp/carbon-efficient-batch-processing-batch-sustainability-intelligence/code/infrastructure-manager" \
    --git-source-ref="main"
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"  # Choose a high CFE% region

# Deploy the complete solution
./scripts/deploy.sh
```

## Solution Architecture

This IaC deploys a comprehensive carbon-efficient batch processing system including:

### Core Components

- **Cloud Batch Jobs**: Managed batch computing with carbon-aware configuration
- **Pub/Sub Messaging**: Event-driven coordination between components
- **Cloud Storage**: Secure storage for job scripts, results, and carbon data
- **Cloud Monitoring**: Custom metrics for carbon footprint tracking
- **Cloud Functions**: Carbon-aware scheduler for intelligent workload orchestration

### Sustainability Features

- **Regional Optimization**: Automatic deployment to high CFE% regions
- **Carbon Monitoring**: Real-time tracking of carbon impact metrics
- **Intelligent Scheduling**: Dynamic workload placement based on carbon intensity
- **Preemptible Instances**: Cost and carbon-efficient compute resources
- **Adaptive Processing**: Workload intensity modulation based on regional carbon data

## Configuration Options

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-gcp-project-id"          # Required: GCP Project ID
export REGION="us-central1"                      # Required: Deployment region (recommend high CFE% regions)
export ZONE="us-central1-a"                      # Required: Deployment zone
export ENABLE_CARBON_ALERTS="true"               # Optional: Enable carbon impact alerting
export CARBON_THRESHOLD="0.5"                    # Optional: Carbon impact threshold (kgCO2e)
export JOB_PARALLELISM="3"                       # Optional: Batch job task count
export USE_PREEMPTIBLE="true"                    # Optional: Use preemptible instances
```

### Regional Considerations

For optimal carbon efficiency, deploy in regions with high carbon-free energy (CFE) percentages:

- **us-central1**: ~85% CFE, recommended for US workloads
- **europe-west1**: ~92% CFE, optimal for European workloads  
- **asia-northeast1**: ~45% CFE, consider alternatives for Asia-Pacific

### Terraform Variables

Key variables available in the Terraform implementation:

```hcl
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resource deployment"
  type        = string
  default     = "us-central1"
}

variable "carbon_threshold" {
  description = "Carbon impact threshold for alerting (kgCO2e)"
  type        = number
  default     = 0.5
}

variable "enable_preemptible" {
  description = "Use preemptible instances for cost and carbon efficiency"
  type        = bool
  default     = true
}

variable "batch_task_count" {
  description = "Number of parallel tasks in batch job"
  type        = number
  default     = 3
}
```

## Deployment Process

### 1. Pre-deployment Setup

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Set project and enable required APIs
gcloud config set project ${PROJECT_ID}
gcloud services enable batch.googleapis.com pubsub.googleapis.com \
    monitoring.googleapis.com cloudfunctions.googleapis.com \
    storage.googleapis.com cloudbilling.googleapis.com
```

### 2. Infrastructure Deployment

Choose your preferred deployment method from the Quick Start section above.

### 3. Post-deployment Verification

```bash
# Verify batch job configuration
gcloud batch jobs list --location=${REGION}

# Check Pub/Sub topics and subscriptions
gcloud pubsub topics list
gcloud pubsub subscriptions list

# Verify Cloud Storage bucket
gsutil ls -la gs://carbon-batch-data-*

# Test carbon scheduler function
curl -X POST $(gcloud functions describe carbon-scheduler --region=${REGION} --format="value(httpsTrigger.url)") \
    -H "Content-Type: application/json" \
    -d '{"project_id": "'${PROJECT_ID}'", "topic_name": "carbon-events"}'
```

## Monitoring and Observability

### Carbon Footprint Metrics

The solution deploys custom Cloud Monitoring metrics:

- `custom.googleapis.com/batch/carbon_impact`: Carbon impact per job (kgCO2e)
- `custom.googleapis.com/batch/cfe_percentage`: Regional CFE percentage
- `custom.googleapis.com/batch/energy_efficiency`: Processing efficiency ratio

### Access Monitoring Dashboard

```bash
# View carbon metrics
gcloud monitoring metrics list --filter="metric.type:custom.googleapis.com/batch/"

# Query recent carbon impact data
gcloud monitoring time-series list \
    --filter='metric.type="custom.googleapis.com/batch/carbon_impact"' \
    --interval-start-time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
```

### Alerting Configuration

The infrastructure includes optional alerting for:

- High carbon impact threshold breaches
- Low CFE% region usage warnings
- Batch job carbon efficiency degradation

## Testing the Solution

### 1. Submit a Carbon-Aware Batch Job

```bash
# Generate unique job name
JOB_NAME="carbon-test-job-$(date +%s)"

# Submit test job (using deployed batch configuration)
gcloud batch jobs submit ${JOB_NAME} \
    --location=${REGION} \
    --config=batch_job_config.json
```

### 2. Monitor Carbon Intelligence

```bash
# Watch job progress
watch -n 30 "gcloud batch jobs describe ${JOB_NAME} --location=${REGION} --format='value(status.state)'"

# Monitor carbon events in Pub/Sub
gcloud pubsub subscriptions pull carbon-events-subscription --max-messages=5
```

### 3. Validate Carbon Data Collection

```bash
# Check stored results in Cloud Storage
gsutil ls -la gs://carbon-batch-data-*/results/

# View carbon impact logs
gcloud logging read "resource.type=batch_job AND resource.labels.job_id=${JOB_NAME}" --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/carbon-batch-deployment
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify resource cleanup
gcloud batch jobs list --location=${REGION}
gcloud pubsub topics list
gsutil ls gs://carbon-batch-data-* 2>/dev/null || echo "Storage cleaned up successfully"
```

### Manual Cleanup Verification

```bash
# Verify all resources are removed
echo "Checking for remaining resources..."

# Check batch jobs
REMAINING_JOBS=$(gcloud batch jobs list --location=${REGION} --format="value(name)" | wc -l)
echo "Remaining batch jobs: ${REMAINING_JOBS}"

# Check Pub/Sub resources
REMAINING_TOPICS=$(gcloud pubsub topics list --format="value(name)" | grep carbon | wc -l)
echo "Remaining carbon topics: ${REMAINING_TOPICS}"

# Check Cloud Functions
REMAINING_FUNCTIONS=$(gcloud functions list --regions=${REGION} --format="value(name)" | grep carbon | wc -l)
echo "Remaining carbon functions: ${REMAINING_FUNCTIONS}"

# Check storage buckets
REMAINING_BUCKETS=$(gsutil ls | grep carbon-batch | wc -l)
echo "Remaining carbon storage buckets: ${REMAINING_BUCKETS}"
```

## Customization

### Extending Carbon Intelligence

1. **Multi-Regional Deployment**: Modify terraform variables to deploy across multiple regions for global carbon optimization
2. **Advanced Scheduling**: Extend the carbon scheduler function to integrate with weather APIs for renewable energy forecasting
3. **ML-Powered Optimization**: Integrate with Vertex AI for predictive carbon intensity modeling
4. **Custom Carbon Metrics**: Add industry-specific carbon accounting metrics to the monitoring system

### Integration Options

1. **CI/CD Integration**: Include IaC deployment in your CI/CD pipeline with carbon impact validation
2. **Enterprise Governance**: Extend with Cloud Asset Inventory for organization-wide carbon tracking
3. **Cost Optimization**: Integrate with Cloud Billing APIs for carbon-cost correlation analysis
4. **Compliance Reporting**: Add automated sustainability report generation for corporate requirements

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
   ```bash
   gcloud services list --enabled | grep -E "(batch|pubsub|monitoring|functions|storage)"
   ```

2. **Insufficient Permissions**: Verify IAM roles include:
   - `roles/batch.jobsEditor`
   - `roles/pubsub.editor`
   - `roles/storage.admin`
   - `roles/monitoring.editor`
   - `roles/cloudfunctions.developer`

3. **Regional Quota Limits**: Check and request quota increases if needed:
   ```bash
   gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)"
   ```

4. **Carbon Data Access**: Ensure Carbon Footprint API access is properly configured

### Support Resources

- [Google Cloud Batch Documentation](https://cloud.google.com/batch/docs)
- [Google Cloud Carbon Footprint](https://cloud.google.com/carbon-footprint)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Google Cloud Sustainability](https://cloud.google.com/sustainability)

## Security Considerations

- All resources use least-privilege IAM principles
- Pub/Sub topics include appropriate access controls
- Cloud Storage buckets implement encryption at rest
- Batch jobs run with minimal required permissions
- Cloud Functions use secure environment variable handling

## Cost Management

- Preemptible instances reduce compute costs by up to 80%
- Regional optimization can reduce data transfer costs
- Carbon-efficient scheduling often correlates with cost optimization
- Monitor usage with Cloud Billing alerts and budgets

For detailed cost estimation, use the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) with the resource specifications from your chosen IaC implementation.

## Support

For issues with this infrastructure code, refer to:
1. The original recipe documentation
2. Google Cloud provider documentation
3. Terraform Google Cloud provider documentation
4. Google Cloud support channels

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **Terraform Google Provider**: ~> 5.0
- **Infrastructure Manager**: Latest stable
- **Minimum gcloud CLI**: 400.0.0