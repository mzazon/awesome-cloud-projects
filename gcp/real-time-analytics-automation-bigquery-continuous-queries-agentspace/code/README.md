# Infrastructure as Code for Real-Time Analytics Automation with BigQuery Continuous Queries and Agentspace

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Analytics Automation with BigQuery Continuous Queries and Agentspace".

## Overview

This recipe deploys a comprehensive real-time analytics automation system that processes streaming data through BigQuery Continuous Queries, generates AI-powered insights using Agentspace, and orchestrates business responses via Cloud Workflows. The infrastructure enables autonomous decision-making by combining real-time data processing with intelligent AI agents.

## Architecture Components

- **BigQuery**: Dataset, tables, and continuous queries for real-time analytics
- **Pub/Sub**: Topics and subscriptions for event streaming
- **Cloud Workflows**: Business process automation and response orchestration
- **Agentspace**: AI agents for intelligent insight generation
- **IAM**: Service accounts and permissions for secure integration
- **Cloud Logging**: Centralized logging for monitoring and debugging

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts with comprehensive error handling

## Prerequisites

- Google Cloud Project with Owner or Editor permissions
- Google Cloud CLI (gcloud) installed and configured
- Active billing account enabled on the project
- Required APIs enabled:
  - BigQuery API
  - Pub/Sub API
  - Cloud Workflows API
  - AI Platform API
  - Cloud Build API
  - Cloud Logging API
- Agentspace access enabled in your Google Cloud organization
- For Terraform: Terraform CLI installed (version >= 1.5.0)
- Estimated cost: $5-15 for testing during recipe duration

## Quick Start

### Using Infrastructure Manager

```bash
# Set environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create analytics-automation \
    --location=${REGION} \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --gcs-source=gs://your-bucket/infrastructure-manager/main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment status
gcloud infra-manager deployments describe analytics-automation \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned infrastructure changes
terraform plan -var="project_id=$(gcloud config get-value project)" \
                -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=$(gcloud config get-value project)" \
                 -var="region=us-central1"

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure with interactive prompts
./scripts/deploy.sh

# Or deploy with environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
./scripts/deploy.sh
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | Current project | Yes |
| `REGION` | Deployment region | us-central1 | Yes |
| `DATASET_NAME` | BigQuery dataset name | realtime_analytics | No |
| `RANDOM_SUFFIX` | Unique suffix for resources | Auto-generated | No |

### Terraform Variables

The Terraform implementation supports the following variables:

```hcl
variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "The region for resource deployment"
  type        = string
  default     = "us-central1"
}

variable "dataset_name" {
  description = "BigQuery dataset name for analytics"
  type        = string
  default     = "realtime_analytics"
}

variable "enable_agentspace" {
  description = "Enable Agentspace AI agent integration"
  type        = bool
  default     = true
}

variable "continuous_query_timeout" {
  description = "Timeout for continuous query operations in seconds"
  type        = number
  default     = 3600
}
```

### Infrastructure Manager Parameters

The Infrastructure Manager implementation accepts these input values:

```yaml
inputValues:
  project_id: "your-project-id"
  region: "us-central1"
  dataset_name: "realtime_analytics"
  enable_monitoring: true
  agentspace_config:
    agent_name: "RealTimeAnalyticsAgent"
    capabilities: ["anomaly_analysis", "recommendation_generation"]
```

## Testing the Deployment

### Verify Infrastructure

```bash
# Check BigQuery dataset and tables
bq ls --project_id=${PROJECT_ID} ${DATASET_NAME}

# Verify Pub/Sub topics
gcloud pubsub topics list --filter="name:raw-events OR name:insights"

# Check Cloud Workflows
gcloud workflows list --location=${REGION}

# Verify continuous query job
bq ls -j --max_results=10 | grep continuous
```

### Test Data Pipeline

```bash
# Generate test data using the provided simulation script
python scripts/simulate_data.py ${PROJECT_ID} raw-events-$(openssl rand -hex 3) 50

# Monitor real-time processing
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as event_count, MAX(timestamp) as latest_event 
     FROM \`${PROJECT_ID}.${DATASET_NAME}.processed_events\`"

# Check generated insights
bq query --use_legacy_sql=false \
    "SELECT insight_type, confidence, COUNT(*) as insight_count
     FROM \`${PROJECT_ID}.${DATASET_NAME}.insights\`
     GROUP BY insight_type, confidence"
```

### Validate AI Agent Integration

```bash
# Check Agentspace service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.members:agentspace-analytics@${PROJECT_ID}.iam.gserviceaccount.com"

# Test workflow execution with sample insight
gcloud workflows execute analytics-automation-$(openssl rand -hex 3) \
    --data='{"insight": {"insight_id": "test-001", "confidence": 0.95}}' \
    --location=${REGION}
```

## Monitoring and Observability

### Cloud Logging

View system logs to monitor pipeline performance:

```bash
# View workflow execution logs
gcloud logging read "resource.type=workflow AND severity>=INFO" \
    --limit=50 --format=json

# Monitor BigQuery job logs
gcloud logging read "resource.type=bigquery_dataset AND protoPayload.methodName=jobservice.insert" \
    --limit=20

# Check Pub/Sub message processing
gcloud logging read "resource.type=pubsub_topic" --limit=30
```

### Performance Metrics

```bash
# Monitor BigQuery slot usage
bq query --use_legacy_sql=false \
    "SELECT job_id, creation_time, total_slot_ms
     FROM \`${PROJECT_ID}\`.region-${REGION}.INFORMATION_SCHEMA.JOBS
     WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
     ORDER BY creation_time DESC"

# Check Pub/Sub message backlog
gcloud pubsub subscriptions describe raw-events-bq-sub \
    --format="value(numUndeliveredMessages)"
```

## Troubleshooting

### Common Issues

#### Continuous Query Not Starting
```bash
# Check BigQuery job permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.roles:roles/bigquery.jobUser"

# Verify dataset existence and permissions
bq show ${PROJECT_ID}:${DATASET_NAME}
```

#### Pub/Sub Message Delivery Issues
```bash
# Check subscription configuration
gcloud pubsub subscriptions describe raw-events-bq-sub

# Test topic publishing permissions
gcloud pubsub topics test-iam-permissions raw-events \
    --permissions=pubsub.messages.publish
```

#### Workflow Execution Failures
```bash
# Get detailed workflow execution logs
gcloud workflows executions describe EXECUTION_ID \
    --workflow=analytics-automation \
    --location=${REGION}

# Check service account permissions
gcloud iam service-accounts get-iam-policy \
    agentspace-analytics@${PROJECT_ID}.iam.gserviceaccount.com
```

### Debug Commands

```bash
# Enable debug logging for deployments
export CLOUDSDK_CORE_VERBOSITY=debug

# Validate Infrastructure Manager configuration
gcloud infra-manager deployments validate \
    --location=${REGION} \
    --service-account=infra-manager@${PROJECT_ID}.iam.gserviceaccount.com

# Check Terraform state for issues
terraform state list
terraform state show [resource_name]
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete analytics-automation \
    --location=${REGION} \
    --delete-policy=DELETE

# Verify cleanup completion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Plan destruction to review resources to be deleted
terraform plan -destroy \
    -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"

# Destroy infrastructure
terraform destroy \
    -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script with confirmation prompts
./scripts/destroy.sh

# Force cleanup without prompts (use with caution)
export FORCE_CLEANUP=true
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify BigQuery resources are removed
bq ls --project_id=${PROJECT_ID}

# Check Pub/Sub topics are deleted
gcloud pubsub topics list

# Confirm workflows are removed
gcloud workflows list --location=${REGION}

# Verify service accounts are deleted
gcloud iam service-accounts list \
    --filter="email:agentspace-analytics@${PROJECT_ID}.iam.gserviceaccount.com"
```

## Customization

### Modifying Continuous Query Logic

The continuous query can be customized by editing the SQL in the deployment files:

```sql
-- Example: Add additional anomaly detection methods
WITH enhanced_detection AS (
  SELECT *,
    -- Z-score based detection
    ABS(value - AVG(value) OVER w) / STDDEV(value) OVER w as z_score,
    -- Interquartile range detection
    CASE WHEN value < PERCENTILE_CONT(0.25) OVER w - 1.5 * 
             (PERCENTILE_CONT(0.75) OVER w - PERCENTILE_CONT(0.25) OVER w)
         OR value > PERCENTILE_CONT(0.75) OVER w + 1.5 * 
             (PERCENTILE_CONT(0.75) OVER w - PERCENTILE_CONT(0.25) OVER w)
         THEN 1 ELSE 0 END as iqr_outlier
  FROM processed_events
  WINDOW w AS (PARTITION BY user_id ORDER BY timestamp 
               ROWS BETWEEN 19 PRECEDING AND CURRENT ROW)
)
```

### Extending AI Agent Capabilities

Configure additional Agentspace capabilities by modifying the agent configuration:

```json
{
  "agent_name": "EnhancedAnalyticsAgent",
  "capabilities": [
    "anomaly_analysis",
    "recommendation_generation",
    "predictive_modeling",
    "sentiment_analysis",
    "trend_forecasting"
  ],
  "models": {
    "primary": "gemini-pro",
    "fallback": "text-bison"
  }
}
```

### Workflow Customization

Extend the Cloud Workflows definition to include additional business logic:

```yaml
# Add external API integration
- call_external_system:
    call: http.post
    args:
      url: "https://api.your-system.com/alerts"
      headers:
        Authorization: ${"Bearer " + sys.get_env("API_TOKEN")}
      body:
        alert_type: ${insight_data.insight_type}
        confidence: ${insight_data.confidence}
        timestamp: ${insight_data.generated_at}
```

## Security Considerations

### IAM Best Practices

- Service accounts follow principle of least privilege
- Cross-service authentication uses Google Cloud IAM
- API keys and tokens are managed through Secret Manager
- Network access is restricted using VPC Service Controls where applicable

### Data Protection

- BigQuery datasets use Google-managed encryption by default
- Pub/Sub messages are encrypted in transit and at rest
- Audit logging is enabled for all resource access
- Data retention policies are configured per business requirements

### Monitoring and Alerting

```bash
# Set up security monitoring
gcloud logging sinks create security-sink \
    bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/security_logs \
    --log-filter='protoPayload.authenticationInfo.principalEmail!="" AND severity>=WARNING'

# Configure anomaly detection alerts
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/security-policy.yaml
```

## Cost Optimization

### Resource Sizing

- BigQuery slots are managed automatically with on-demand pricing
- Pub/Sub message retention is optimized for cost (default 7 days)
- Cloud Workflows execution time is minimized through efficient logic
- Continuous queries are designed to process only recent data

### Monitoring Costs

```bash
# Monitor BigQuery costs
bq query --use_legacy_sql=false \
    "SELECT project_id, SUM(total_bytes_processed) as total_bytes
     FROM \`${PROJECT_ID}\`.region-${REGION}.INFORMATION_SCHEMA.JOBS
     WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
     GROUP BY project_id"

# Check Pub/Sub usage
gcloud pubsub topics describe raw-events \
    --format="value(messageStoragePolicy.allowedPersistenceRegions)"
```

## Support and Resources

### Documentation Links

- [BigQuery Continuous Queries](https://cloud.google.com/bigquery/docs/continuous-queries-introduction)
- [Agentspace Documentation](https://cloud.google.com/ai-platform/docs/agentspace)
- [Cloud Workflows Guide](https://cloud.google.com/workflows/docs)
- [Pub/Sub Best Practices](https://cloud.google.com/pubsub/docs/best-practices)
- [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Community Resources

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - Google Cloud](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Google Cloud Architecture Center](https://cloud.google.com/architecture)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Open an issue in the recipe repository with deployment logs

---

**Note**: This infrastructure code is generated from the recipe "Real-Time Analytics Automation with BigQuery Continuous Queries and Agentspace". Refer to the original recipe for detailed implementation guidance and business context.