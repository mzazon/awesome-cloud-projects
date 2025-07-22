# Infrastructure as Code for Carbon-Aware Workload Orchestration

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Developing Carbon-Aware Workload Orchestration with Cloud Carbon Footprint and Cloud Workflows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts with comprehensive error handling

## Prerequisites

### Required Tools
- Google Cloud CLI (gcloud) version 400.0.0 or later installed and configured
- Terraform 1.5+ (for Terraform implementation)
- Basic understanding of BigQuery, Cloud Workflows, and serverless orchestration
- Appropriate Google Cloud project with billing enabled

### Required Permissions
- Owner or Editor permissions on the Google Cloud project
- BigQuery Admin or Data Editor role
- Cloud Functions Admin role
- Workflows Admin role
- Compute Admin role (for workload execution)
- Service Account Admin role
- Pub/Sub Admin role

### Cost Considerations
Estimated cost: $15-25 USD for running this implementation, including:
- BigQuery storage and query processing
- Cloud Functions execution
- Compute Engine instances for workload simulation
- Cloud Workflows execution
- Pub/Sub messaging
- Cloud Monitoring metrics

## Architecture Overview

This solution implements an intelligent workload orchestration system that:
- Analyzes carbon footprint data using BigQuery
- Makes scheduling decisions via Cloud Functions
- Orchestrates workloads through Cloud Workflows
- Provides monitoring and alerting for carbon metrics
- Automatically optimizes compute workloads for minimal environmental impact

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/carbon-aware-orchestration \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/infrastructure" \
    --git-source-directory="gcp/carbon-aware-workload-orchestration/infrastructure-manager" \
    --git-source-ref="main" \
    --input-values=project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Get important outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor deployment progress
gcloud logging read "resource.type=cloud_function" --limit=10
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | none | yes |
| `region` | Primary deployment region | `us-central1` | no |
| `dataset_name` | BigQuery dataset for carbon data | auto-generated | no |
| `enable_monitoring` | Enable comprehensive monitoring | `true` | no |
| `workflow_timeout` | Workflow execution timeout | `3600s` | no |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | string | none | yes |
| `region` | Primary deployment region | string | `us-central1` | no |
| `zone` | Primary deployment zone | string | `us-central1-a` | no |
| `dataset_name` | BigQuery dataset name | string | auto-generated | no |
| `enable_scheduler` | Enable Cloud Scheduler jobs | bool | `true` | no |
| `max_delay_hours` | Maximum workload delay for carbon optimization | number | `8` | no |
| `carbon_monitoring_interval` | Monitoring check interval in minutes | number | `30` | no |

### Script Environment Variables

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Optional customization variables
export ZONE="us-central1-a"
export DATASET_NAME="custom_carbon_dataset"
export MAX_DELAY_HOURS="12"
export ENABLE_MONITORING="true"
```

## Post-Deployment Verification

### 1. Verify Core Infrastructure

```bash
# Check BigQuery dataset
bq ls ${PROJECT_ID}:carbon_footprint_*

# Verify Cloud Functions
gcloud functions list --filter="name:workload-scheduler"

# Check Cloud Workflows
gcloud workflows list --location=${REGION}

# Verify Pub/Sub topics
gcloud pubsub topics list --filter="name:carbon-aware"
```

### 2. Test Carbon-Aware Scheduling

```bash
# Test the scheduling function
curl -X POST \
  "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/workload-scheduler-$(openssl rand -hex 3)" \
  -H "Content-Type: application/json" \
  -d '{
    "workload_type": "test",
    "urgency": "normal",
    "region": "us-central1"
  }'

# Execute test workflow
gcloud workflows execute carbon-aware-orchestrator-* \
  --data='{"workload_id":"test-001","workload_type":"test","urgency":"normal"}' \
  --location=${REGION}
```

### 3. Monitor System Health

```bash
# Check monitoring dashboard
echo "Monitor at: https://console.cloud.google.com/monitoring/dashboards"

# View recent logs
gcloud logging read "resource.type=cloud_function" \
  --limit=10 \
  --format="table(timestamp,severity,textPayload)"

# Check Pub/Sub message flow
gcloud pubsub subscriptions pull carbon-aware-workflow-sub \
  --limit=5 \
  --auto-ack
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/carbon-aware-orchestration \
    --delete-policy="DELETE"

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify state file cleanup
ls -la terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource cleanup
gcloud functions list
gcloud workflows list --location=${REGION}
gcloud pubsub topics list
```

### Manual Cleanup Verification

```bash
# Check for remaining resources
gcloud scheduler jobs list --location=${REGION}
gcloud monitoring policies list
gcloud iam service-accounts list --filter="email:carbon-footprint-sa@*"
bq ls --filter="datasetId:carbon_footprint_*"

# Remove any remaining BigQuery datasets
bq rm -r -f ${PROJECT_ID}:carbon_footprint_*

# Clean up monitoring dashboards and policies
gcloud alpha monitoring dashboards list --format="value(name)" | \
  xargs -I {} gcloud alpha monitoring dashboards delete {} --quiet
```

## Customization Guide

### Adding Custom Workload Types

1. **Modify Cloud Function Logic**:
   - Update `cloud-function-source/main.py`
   - Add new workload type handling in `make_scheduling_decision()`
   - Redeploy function with updated code

2. **Update Workflow Definition**:
   - Modify workflow YAML to handle new workload types
   - Add specific resource requirements for custom workloads
   - Update monitoring and logging for new types

3. **Extend BigQuery Analysis**:
   - Create additional views for workload-specific carbon analysis
   - Add custom metrics for new workload patterns
   - Update monitoring dashboards

### Integrating with Existing Workloads

1. **API Integration**:
   ```bash
   # Example: Trigger carbon-aware scheduling from existing system
   curl -X POST "${FUNCTION_URL}" \
     -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     -d '{"workload_id":"existing-job-123","workload_type":"data_processing"}'
   ```

2. **Pub/Sub Integration**:
   ```bash
   # Publish workload requests to trigger orchestration
   gcloud pubsub topics publish carbon-workload-requests \
     --message='{"workload_id":"batch-job","urgency":"low"}'
   ```

### Performance Optimization

1. **Function Memory Allocation**:
   - Increase memory for complex carbon analysis
   - Optimize for response time vs. cost

2. **BigQuery Optimization**:
   - Partition tables by date for better performance
   - Use clustering for frequently queried columns
   - Implement result caching for repeated queries

3. **Workflow Optimization**:
   - Implement parallel execution for independent tasks
   - Add workflow retry logic with exponential backoff
   - Cache carbon intensity data for short periods

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Grant additional permissions to service accounts
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
     --member="serviceAccount:carbon-footprint-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
     --role="roles/cloudsql.client"
   ```

2. **Function Timeout**:
   ```bash
   # Increase function timeout
   gcloud functions deploy workload-scheduler \
     --timeout=120s \
     --memory=512MB
   ```

3. **BigQuery Access Issues**:
   ```bash
   # Check dataset permissions
   bq show --format=prettyjson ${PROJECT_ID}:carbon_footprint_data
   
   # Grant BigQuery access to service account
   bq add-iam-policy-binding \
     --member="serviceAccount:carbon-footprint-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
     --role="roles/bigquery.dataViewer" \
     ${PROJECT_ID}:carbon_footprint_data
   ```

### Monitoring and Logging

1. **Enable Debug Logging**:
   ```bash
   # Set debug logging level for functions
   gcloud functions deploy workload-scheduler \
     --set-env-vars="LOG_LEVEL=DEBUG"
   ```

2. **Custom Metrics**:
   ```bash
   # Create custom metrics for monitoring
   gcloud logging metrics create carbon_decision_latency \
     --description="Latency of carbon scheduling decisions" \
     --log-filter="resource.type=cloud_function AND textPayload:carbon-aware"
   ```

3. **Alerting Setup**:
   ```bash
   # Create alerting policies for system health
   gcloud alpha monitoring policies create \
     --notification-channels=${NOTIFICATION_CHANNEL} \
     --display-name="Carbon Orchestration Health" \
     --policy-from-file=monitoring/alert-policy.json
   ```

## Security Considerations

### Service Account Security

- Service accounts follow principle of least privilege
- Workload Identity used for GKE integration
- Regular rotation of service account keys
- Audit logging enabled for all service account usage

### Network Security

- Private Google Access enabled for subnet communication
- VPC firewall rules restrict unnecessary access
- Cloud NAT used for outbound internet access from private resources
- Network monitoring enabled for traffic analysis

### Data Protection

- BigQuery datasets encrypted at rest with Google-managed keys
- Pub/Sub messages encrypted in transit
- Cloud Functions use VPC connectors for private communication
- Audit logs capture all data access patterns

## Integration Examples

### Kubernetes Integration

```yaml
# Example: CronJob that triggers carbon-aware scheduling
apiVersion: batch/v1
kind: CronJob
metadata:
  name: carbon-aware-batch-job
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: workload-trigger
            image: gcr.io/google.com/cloudsdktool/cloud-sdk:alpine
            command:
            - /bin/sh
            - -c
            - |
              gcloud workflows execute carbon-aware-orchestrator \
                --data='{"workload_id":"k8s-batch","workload_type":"analytics"}' \
                --location=us-central1
          restartPolicy: OnFailure
```

### Cloud Build Integration

```yaml
# cloudbuild.yaml - Trigger carbon-aware deployment
steps:
- name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    # Check carbon intensity before deployment
    response=$(curl -s -X POST "${_FUNCTION_URL}" \
      -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      -d '{"workload_type":"deployment","urgency":"high"}')
    
    if echo "$response" | grep -q "execute_immediately"; then
      echo "Proceeding with deployment - low carbon intensity"
      # Continue with deployment steps
    else
      echo "Delaying deployment for better carbon conditions"
      exit 1
    fi
substitutions:
  _FUNCTION_URL: 'https://us-central1-${PROJECT_ID}.cloudfunctions.net/workload-scheduler'
```

## Support and Resources

### Documentation Links
- [Google Cloud Carbon Footprint](https://cloud.google.com/carbon-footprint/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [BigQuery Best Practices](https://cloud.google.com/bigquery/docs/best-practices)
- [Infrastructure Manager Guide](https://cloud.google.com/infrastructure-manager/docs)

### Community Resources
- [Google Cloud Architecture Center](https://cloud.google.com/architecture)
- [Sustainability with Google Cloud](https://cloud.google.com/sustainability)
- [Carbon-Free Energy](https://cloud.google.com/sustainability/region-carbon)

### Getting Help
For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Google Cloud Status page for service issues
3. Consult provider documentation for specific services
4. Review Cloud Logging for detailed error messages
5. Use Google Cloud Support for production issues

### Contributing
To improve this implementation:
1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any modifications
4. Consider environmental impact of changes
5. Validate cost implications of modifications