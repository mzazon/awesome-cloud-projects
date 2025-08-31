# Infrastructure as Code for AI Model Bias Detection with Vertex AI Monitoring and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI Model Bias Detection with Vertex AI Monitoring and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive automated bias detection system using:

- **Vertex AI Model Monitoring**: Tracks fairness metrics and data drift
- **Cloud Functions**: Intelligent alert processing and bias analysis
- **Cloud Scheduler**: Orchestrates regular bias audits
- **Cloud Logging**: Provides audit trails for compliance reporting
- **Cloud Storage**: Stores bias detection reports and datasets
- **Pub/Sub**: Enables reliable messaging for monitoring alerts

## Prerequisites

- Google Cloud project with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Owner or Editor permissions on the GCP project
- Understanding of machine learning concepts and bias detection
- Basic knowledge of Python programming and Google Cloud services

### Required APIs

The following APIs will be automatically enabled during deployment:

- AI Platform API (`aiplatform.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Pub/Sub API (`pubsub.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)

### Cost Estimation

Estimated cost for resources created during this deployment: **$10-25** (depending on usage patterns)

- Cloud Functions: $0.10-2.00 per month (based on invocations)
- Cloud Storage: $1-5 per month (for reports and datasets)
- Pub/Sub: $0.50-2.00 per month (for messaging)
- Cloud Scheduler: $0.10 per month (for scheduled jobs)
- Vertex AI Model Monitoring: $5-15 per month (based on monitoring frequency)

## Quick Start

### Using Infrastructure Manager

```bash
# Clone or navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/bias-detection-deployment \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="inputs.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/bias-detection-deployment
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform with Google Cloud provider
terraform init

# Review the planned infrastructure changes
terraform plan -var="project_id=your-gcp-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-gcp-project-id" -var="region=us-central1"

# View outputs (function URLs, bucket names, etc.)
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"

# Deploy the complete infrastructure
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create Cloud Storage bucket
# 3. Set up Pub/Sub messaging
# 4. Deploy Cloud Functions
# 5. Configure Cloud Scheduler
# 6. Set up monitoring configuration
```

## Configuration Options

### Environment Variables

| Variable | Description | Default Value | Required |
|----------|-------------|---------------|----------|
| `PROJECT_ID` | GCP Project ID | - | Yes |
| `REGION` | GCP Region for resources | `us-central1` | No |
| `ZONE` | GCP Zone for compute resources | `us-central1-a` | No |
| `BUCKET_NAME` | Cloud Storage bucket name | Auto-generated | No |
| `FUNCTION_NAME` | Bias detection function name | `bias-detection-processor` | No |
| `ALERT_FUNCTION_NAME` | Alert processing function name | `bias-alert-handler` | No |
| `REPORT_FUNCTION_NAME` | Report generation function name | `bias-report-generator` | No |
| `TOPIC_NAME` | Pub/Sub topic name | `model-monitoring-alerts` | No |
| `SCHEDULER_JOB_NAME` | Cloud Scheduler job name | `bias-audit-scheduler` | No |

### Terraform Variables

The Terraform implementation supports the following variables (defined in `variables.tf`):

```hcl
# Core configuration
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

# Function configuration
variable "bias_threshold" {
  description = "Threshold for bias alert severity"
  type        = number
  default     = 0.1
}

variable "audit_schedule" {
  description = "Cron schedule for bias audits"
  type        = string
  default     = "0 9 * * 1"  # Weekly on Mondays at 9 AM
}

# Monitoring configuration
variable "drift_threshold" {
  description = "Threshold for data drift detection"
  type        = number
  default     = 0.15
}
```

## Validation & Testing

After deployment, validate the infrastructure:

### 1. Verify Resource Creation

```bash
# Check Cloud Functions deployment
gcloud functions list --filter="name:bias-detection"

# Verify Cloud Storage bucket
gsutil ls -p ${PROJECT_ID}

# Check Pub/Sub topic
gcloud pubsub topics list --filter="name:model-monitoring-alerts"

# Verify Cloud Scheduler job
gcloud scheduler jobs list --location=${REGION}
```

### 2. Test Bias Detection Function

```bash
# Publish test message to trigger bias detection
gcloud pubsub topics publish model-monitoring-alerts \
    --message='{"model_name": "test-model", "drift_metric": 0.12, "alert_type": "drift", "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}'

# Check function execution logs
gcloud functions logs read bias-detection-processor --gen2 --limit=10
```

### 3. Test Alert Processing

```bash
# Get alert function URL and test with sample data
ALERT_FUNCTION_URL=$(gcloud functions describe bias-alert-handler --gen2 --region=${REGION} --format="value(serviceConfig.uri)")

curl -X POST "${ALERT_FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
      "bias_score": 0.13,
      "fairness_violations": ["Demographic parity violation"],
      "model_name": "test-model",
      "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
    }'
```

### 4. Verify Compliance Logging

```bash
# Check bias detection logs in Cloud Logging
gcloud logging read "resource.type=cloud_function AND jsonPayload.message:BIAS_ANALYSIS" \
    --limit=5 \
    --format="value(jsonPayload.message, timestamp)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/bias-detection-deployment
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all infrastructure
terraform destroy -var="project_id=your-gcp-project-id" -var="region=us-central1"

# Verify destruction
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Cloud Scheduler jobs
# 2. Remove Cloud Functions
# 3. Delete Pub/Sub resources
# 4. Remove Cloud Storage buckets
# 5. Clean up local files
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud functions list --filter="name:bias-detection"
gsutil ls -p ${PROJECT_ID}
gcloud pubsub topics list --filter="name:model-monitoring-alerts"
gcloud scheduler jobs list --location=${REGION}
```

## Customization

### Bias Detection Thresholds

Modify bias detection sensitivity by adjusting thresholds in the configuration:

```python
# In Cloud Function code (main.py)
def identify_violations(bias_scores):
    violations = []
    
    # Customize these thresholds based on your requirements
    if bias_scores['demographic_parity'] > 0.1:  # Adjust threshold
        violations.append('Demographic parity violation detected')
    
    if bias_scores['equalized_odds'] > 0.1:  # Adjust threshold
        violations.append('Equalized odds violation detected')
        
    return violations
```

### Audit Schedule

Modify the Cloud Scheduler cron expression to change audit frequency:

```bash
# Weekly audits (default)
--schedule="0 9 * * 1"

# Daily audits
--schedule="0 9 * * *"

# Monthly audits
--schedule="0 9 1 * *"
```

### Alert Routing

Customize alert processing by modifying the alert function to integrate with:

- Email notifications (via SendGrid or similar)
- Slack notifications (via webhooks)
- PagerDuty integration for critical alerts
- Jira ticket creation for bias violations

### Fairness Metrics

Extend the bias detection with additional fairness metrics:

```python
# Add intersectional fairness analysis
def calculate_intersectional_bias(data):
    # Implement analysis across multiple protected attributes
    pass

# Add individual fairness metrics
def calculate_individual_fairness(data):
    # Implement similarity-based fairness analysis
    pass
```

## Monitoring and Observability

### Cloud Monitoring Integration

The infrastructure includes comprehensive logging and monitoring:

- **Structured Logging**: All bias events logged with consistent schema
- **Custom Metrics**: Bias scores and violation counts tracked as metrics
- **Alert Policies**: Automated alerts for critical bias violations
- **Audit Trails**: Complete compliance logging for regulatory requirements

### Dashboard Creation

Create custom dashboards to visualize:

- Bias trends over time
- Model fairness scores
- Alert frequency and severity
- Compliance report generation status

## Security Considerations

### IAM Permissions

The infrastructure follows least privilege principles:

- Cloud Functions use service accounts with minimal required permissions
- Cloud Storage buckets have restricted access
- Pub/Sub topics use appropriate IAM bindings
- Audit logging captures all access and modifications

### Data Protection

- Sensitive demographic data is handled according to privacy regulations
- Encryption at rest and in transit for all data
- Audit trails for all bias detection activities
- Secure function-to-function communication

### Compliance Features

- Structured logging for regulatory reporting
- Audit trail generation for compliance verification
- Data governance controls for bias detection data
- Privacy-preserving bias analysis techniques

## Troubleshooting

### Common Issues

1. **Function Deployment Failures**
   ```bash
   # Check deployment logs
   gcloud functions logs read function-name --gen2
   
   # Verify required APIs are enabled
   gcloud services list --enabled
   ```

2. **Pub/Sub Message Processing Issues**
   ```bash
   # Check subscription status
   gcloud pubsub subscriptions describe bias-detection-sub
   
   # Monitor message flow
   gcloud pubsub topics list-subscriptions model-monitoring-alerts
   ```

3. **Cloud Scheduler Job Failures**
   ```bash
   # Check job execution history
   gcloud scheduler jobs describe bias-audit-scheduler --location=${REGION}
   
   # View job logs
   gcloud logging read "resource.type=cloud_scheduler_job"
   ```

### Performance Optimization

- **Function Memory**: Adjust Cloud Function memory allocation based on processing requirements
- **Batch Processing**: Implement batching for high-volume bias detection scenarios
- **Caching**: Use Cloud Memorystore for frequently accessed bias metrics
- **Parallel Processing**: Leverage Cloud Run for compute-intensive bias analysis

## Advanced Features

### Multi-Model Governance

Extend to monitor multiple models simultaneously:

```bash
# Deploy additional monitoring configurations
for model in model1 model2 model3; do
    gcloud ai-platform models create $model
    # Configure model-specific monitoring
done
```

### Real-time Dashboards

Integrate with BigQuery and Looker for advanced analytics:

```sql
-- Example BigQuery query for bias trends
SELECT 
    model_name,
    timestamp,
    bias_score,
    violations_count
FROM `project.dataset.bias_events`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
ORDER BY timestamp DESC;
```

### Automated Remediation

Extend with automated bias mitigation:

- Model retraining triggers
- Data rebalancing workflows
- Post-processing bias correction
- A/B testing for fairness improvements

## Support and Documentation

### Additional Resources

- [Vertex AI Model Monitoring Documentation](https://cloud.google.com/vertex-ai/docs/model-monitoring)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Responsible AI Documentation](https://cloud.google.com/responsible-ai)
- [ML Fairness Indicators](https://www.tensorflow.org/responsible_ai/fairness_indicators/guide)

### Getting Help

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud provider documentation
3. Consult Google Cloud support channels
4. Check community forums and Stack Overflow

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation accordingly
4. Validate security and compliance requirements

---

**Note**: This infrastructure implements production-ready bias detection with comprehensive monitoring, alerting, and compliance features. Customize thresholds and metrics based on your specific fairness requirements and regulatory constraints.