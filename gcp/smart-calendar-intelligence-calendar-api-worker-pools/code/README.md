# Infrastructure as Code for Smart Calendar Intelligence with Cloud Calendar API and Cloud Run Worker Pools

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Calendar Intelligence with Cloud Calendar API and Cloud Run Worker Pools".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code platform
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud Platform account with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Appropriate IAM permissions for:
  - Cloud Run (Admin)
  - Cloud Tasks (Admin)
  - Cloud Scheduler (Admin)
  - Vertex AI (User)
  - BigQuery (Admin)
  - Cloud Storage (Admin)
  - Artifact Registry (Admin)
  - IAM (Admin)
- Google Workspace account for Calendar API access (optional for testing)
- Docker installed for local container builds (if using manual deployment)

## Estimated Costs

- **Development/Testing**: $15-25 USD per month
- **Production**: $50-150 USD per month (depending on usage volume)

> **Note**: Costs primarily come from Vertex AI model usage, BigQuery storage/queries, and Cloud Run execution time.

## Quick Start

### Using Infrastructure Manager (Recommended)

Infrastructure Manager provides Google Cloud's native infrastructure as code experience with built-in state management and integration with Cloud Console.

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="calendar-intelligence"

# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/terraform.tfvars"
```

### Using Terraform

Terraform provides declarative infrastructure management with comprehensive state tracking and plan/apply workflows.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" \
                -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" \
                 -var="region=us-central1"

# Note important outputs
terraform output calendar_api_url
terraform output worker_pool_name
terraform output task_queue_name
```

### Using Bash Scripts

Bash scripts provide direct CLI-based deployment following the recipe's step-by-step approach.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required configuration:
# - Project ID
# - Region
# - Calendar API credentials path
```

## Configuration Options

### Common Variables

All implementations support these configuration options:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Google Cloud Region | `us-central1` | No |
| `zone` | Google Cloud Zone | `us-central1-a` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `calendar_api_enabled` | Enable Calendar API integration | `true` | No |
| `worker_pool_max_instances` | Maximum worker pool instances | `10` | No |
| `task_queue_max_concurrent` | Maximum concurrent tasks | `10` | No |
| `bigquery_location` | BigQuery dataset location | `US` | No |

### Infrastructure Manager Configuration

Create `infrastructure-manager/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
environment = "dev"
worker_pool_max_instances = 5
task_queue_max_concurrent = 5
```

### Terraform Configuration

Create `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
environment = "prod"
worker_pool_max_instances = 10
task_queue_max_concurrent = 10
bigquery_location = "US"
calendar_api_enabled = true
```

## Deployment Architecture

The infrastructure creates:

1. **Artifact Registry Repository** - Container image storage
2. **Cloud Run Worker Pool** - Serverless calendar analysis processing
3. **Cloud Run Service** - API for triggering analysis tasks
4. **Cloud Tasks Queue** - Reliable task distribution
5. **Cloud Scheduler Jobs** - Automated daily analysis
6. **BigQuery Dataset & Tables** - Analytics and insights storage
7. **Cloud Storage Bucket** - Model artifacts and temporary data
8. **IAM Service Accounts** - Secure service authentication
9. **Vertex AI Configuration** - AI model access and configuration

## Post-Deployment Configuration

### 1. Calendar API Setup

```bash
# Create service account for Calendar API access
gcloud iam service-accounts create calendar-api-access \
    --description="Service account for Calendar API access" \
    --display-name="Calendar API Access"

# Download service account key (store securely)
gcloud iam service-accounts keys create calendar-service-account.json \
    --iam-account=calendar-api-access@${PROJECT_ID}.iam.gserviceaccount.com
```

### 2. Configure Google Workspace Domain Delegation

For organization-wide calendar access:

1. Go to Google Admin Console → Security → API Controls
2. Add the service account client ID with Calendar API scope
3. Grant domain-wide delegation permissions

### 3. Test the Deployment

```bash
# Get API service URL
export API_URL=$(gcloud run services describe calendar-intelligence-api \
    --region=${REGION} \
    --format="value(status.url)")

# Test health endpoint
curl -X GET "${API_URL}/health"

# Trigger test analysis
curl -X POST "${API_URL}/trigger-analysis" \
    -H "Content-Type: application/json" \
    -d '{"calendar_ids": ["primary"]}'
```

### 4. Monitor Resources

```bash
# Check worker pool status
gcloud beta run worker-pools describe calendar-intelligence-worker \
    --region=${REGION}

# Monitor task queue
gcloud tasks queues describe calendar-tasks \
    --location=${REGION}

# View BigQuery data
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.calendar_analytics.calendar_insights\` LIMIT 5"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" \
                   -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion
gcloud projects list --filter="projectId:calendar-ai-*"
```

### Manual Cleanup (if needed)

```bash
# Delete any remaining resources
gcloud beta run worker-pools delete calendar-intelligence-worker --region=${REGION} --quiet
gcloud run services delete calendar-intelligence-api --region=${REGION} --quiet
gcloud tasks queues delete calendar-tasks --location=${REGION} --quiet
gcloud scheduler jobs delete calendar-daily-analysis --location=${REGION} --quiet
bq rm -r -f ${PROJECT_ID}:calendar_analytics
gsutil -m rm -r gs://calendar-intelligence-${PROJECT_ID}
gcloud artifacts repositories delete calendar-intelligence --location=${REGION} --quiet
```

## Customization

### Adding New Calendar Analysis Features

1. **Custom AI Prompts**: Modify `src/calendar_worker.py` to include specialized analysis prompts
2. **Additional APIs**: Extend worker to integrate with Gmail, Drive, or other Workspace APIs
3. **Enhanced Analytics**: Add custom BigQuery views and Looker Studio dashboards
4. **Notification System**: Integrate Cloud Pub/Sub for real-time alerts

### Scaling Configuration

```hcl
# For high-volume organizations
worker_pool_max_instances = 50
task_queue_max_concurrent = 25
bigquery_location = "US"  # or region-specific for data residency

# For cost optimization
worker_pool_max_instances = 3
task_queue_max_concurrent = 3
```

### Security Enhancements

```bash
# Enable VPC Service Controls (enterprise)
gcloud access-context-manager perimeters create calendar-intelligence-perimeter \
    --title="Calendar Intelligence Security Perimeter"

# Configure private Google Access
gcloud compute networks subnets update default \
    --region=${REGION} \
    --enable-private-ip-google-access
```

## Troubleshooting

### Common Issues

**Permission Errors:**
```bash
# Grant additional IAM roles
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:your-email@domain.com" \
    --role="roles/run.admin"
```

**Container Build Failures:**
```bash
# Enable Cloud Build API
gcloud services enable cloudbuild.googleapis.com

# Check build logs
gcloud builds list --limit=5
```

**Calendar API Access Issues:**
```bash
# Verify service account permissions
gcloud iam service-accounts get-iam-policy \
    calendar-api-access@${PROJECT_ID}.iam.gserviceaccount.com
```

**Worker Pool Not Scaling:**
```bash
# Check Cloud Tasks queue depth
gcloud tasks list --queue=calendar-tasks --location=${REGION}

# Monitor worker pool metrics
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=calendar-intelligence-worker"
```

### Debug Commands

```bash
# View deployment logs
gcloud logging read "resource.type=gce_instance AND logName=projects/${PROJECT_ID}/logs/deployments"

# Check service connectivity
gcloud run services proxy calendar-intelligence-api --port=8080

# Validate Vertex AI access
gcloud ai models list --region=${REGION}
```

## Performance Optimization

### Worker Pool Tuning

- **CPU**: Increase for AI model processing
- **Memory**: 2Gi minimum for Vertex AI workloads
- **Concurrency**: Match task queue settings
- **Timeout**: Extend for large calendar analysis

### BigQuery Optimization

- **Partitioning**: Partition tables by processed_date
- **Clustering**: Cluster by calendar_id for user queries
- **Slots**: Reserve slots for predictable workloads

### Cost Management

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT} \
    --display-name="Calendar Intelligence Budget" \
    --budget-amount=100USD

# Monitor resource usage
gcloud logging read "resource.type=cloud_run_revision" --limit=50
```

## Support

- **Recipe Documentation**: Refer to the original recipe for architectural details
- **Google Cloud Documentation**: [Cloud Run](https://cloud.google.com/run/docs), [Vertex AI](https://cloud.google.com/vertex-ai/docs)
- **Community Support**: [Google Cloud Community](https://cloud.google.com/community)
- **Enterprise Support**: [Google Cloud Support](https://cloud.google.com/support)

## Security Considerations

- Service accounts use least-privilege IAM roles
- All data is encrypted at rest and in transit
- Calendar API access requires proper domain delegation
- BigQuery datasets include access controls
- Container images are scanned for vulnerabilities

## Compliance

This infrastructure can be configured to meet various compliance requirements:

- **GDPR**: Configure data retention policies in BigQuery
- **HIPAA**: Enable audit logging and data encryption
- **SOC 2**: Implement access controls and monitoring
- **FedRAMP**: Use assured workloads and security controls