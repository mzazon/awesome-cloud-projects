# Data Pipeline Recovery with Dataform and Cloud Tasks - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a comprehensive data pipeline recovery system on Google Cloud Platform. The solution automatically detects Dataform workflow failures and orchestrates intelligent remediation through Cloud Tasks and Cloud Functions.

## 🏗️ Architecture Overview

The infrastructure deploys the following components:

- **Dataform Repository**: ELT workflow definitions and execution
- **BigQuery Dataset**: Data storage and pipeline monitoring tables
- **Cloud Tasks Queue**: Reliable recovery task execution with retry logic
- **Cloud Functions**: Pipeline controller, recovery worker, and notification handler
- **Cloud Monitoring**: Failure detection and automated alerting
- **Pub/Sub**: Notification distribution and event messaging
- **IAM Service Accounts**: Least privilege access control

## 📋 Prerequisites

Before deploying this infrastructure, ensure you have:

- **Google Cloud Project** with billing enabled
- **Terraform** >= 1.5.0 installed
- **gcloud CLI** configured with appropriate permissions
- **Project Owner** or equivalent IAM permissions for:
  - Dataform, Cloud Functions, Cloud Tasks, BigQuery
  - Cloud Monitoring, Pub/Sub, IAM, Storage

## 🚀 Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd gcp/data-pipeline-recovery-dataform-tasks/code/terraform/

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your project details
vim terraform.tfvars
```

### 2. Initialize Terraform

```bash
# Initialize Terraform backend and providers
terraform init

# Validate configuration
terraform validate

# Review planned changes
terraform plan
```

### 3. Deploy Infrastructure

```bash
# Deploy all resources
terraform apply

# Confirm deployment when prompted
# Type 'yes' to proceed
```

### 4. Verify Deployment

```bash
# Check deployment outputs
terraform output

# Test pipeline failure simulation (from outputs)
curl -X POST [CONTROLLER_FUNCTION_URL] \
  -H "Content-Type: application/json" \
  -d '{"incident": {"resource": {"labels": {"pipeline_id": "test-001"}}, "condition_name": "sql_error", "state": "OPEN"}}'

# Monitor recovery tasks
gcloud tasks list --queue=[QUEUE_NAME] --location=[REGION]
```

## ⚙️ Configuration

### Required Variables

Edit `terraform.tfvars` with your specific configuration:

```hcl
# Project Configuration
project_id = "your-gcp-project-id"
region     = "us-central1"
environment = "dev"

# Notification Settings
notification_recipients = [
  "admin@company.com",
  "ops-team@company.com"
]

# Resource Scaling
function_max_instances = 10
task_queue_max_concurrent_dispatches = 5

# Monitoring
enable_monitoring_alerts = true
```

### Optional Customizations

The following variables can be customized in `terraform.tfvars`:

```hcl
# Resource Naming (auto-suffixed for uniqueness)
dataform_repository_name = "pipeline-recovery-repo"
bigquery_dataset_name = "pipeline_monitoring"
task_queue_name = "recovery-queue"

# Cloud Tasks Configuration
task_queue_max_attempts = 5
task_queue_max_retry_duration_hours = 1
task_queue_min_backoff_seconds = 30
task_queue_max_backoff_seconds = 300

# Function Configuration  
function_min_instances = 0
function_max_instances = 10

# BigQuery Configuration
bigquery_table_expiration_days = 90

# Resource Labels
labels = {
  team        = "data-engineering"
  cost_center = "analytics"
  application = "pipeline-recovery"
}
```

## 📊 Outputs and Verification

After successful deployment, Terraform provides comprehensive outputs:

### Key Infrastructure Outputs

- **Dataform Repository**: Repository name and console URL
- **BigQuery Dataset**: Dataset ID and table information
- **Cloud Functions**: Function names and trigger URLs
- **Cloud Tasks Queue**: Queue details and console URL
- **Monitoring**: Alert policy and notification channel IDs

### Testing Commands

The outputs include ready-to-use commands for testing:

```bash
# Test pipeline failure simulation
[Generated curl command from outputs]

# List recovery tasks in queue
[Generated gcloud command from outputs]

# Insert test data into BigQuery
[Generated bq command from outputs]
```

## 🔧 Advanced Configuration

### Backend Configuration

For production deployments, configure remote state storage:

```hcl
# In versions.tf, uncomment and configure:
terraform {
  backend "gcs" {
    bucket  = "your-terraform-state-bucket"
    prefix  = "data-pipeline-recovery/terraform.tfstate"
  }
}
```

### Multi-Environment Setup

Deploy to multiple environments using workspace:

```bash
# Create environment-specific workspaces
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# Switch between environments
terraform workspace select prod

# Use environment-specific variable files
terraform apply -var-file="prod.tfvars"
```

### VPC Configuration

For enhanced security, configure VPC connectivity:

```hcl
# In terraform.tfvars
enable_vpc_connector = true
vpc_connector_name = "your-vpc-connector"
enable_private_google_access = true
```

## 📈 Monitoring and Observability

### Cloud Monitoring

The deployment automatically configures:

- **Alert Policy**: Detects Dataform pipeline failures
- **Log Metrics**: Tracks pipeline execution status
- **Notification Channels**: Webhook integration with recovery system

### Log Analysis

Monitor system operation through Cloud Logging:

```bash
# View controller function logs
gcloud logs read "resource.type=cloud_function AND resource.labels.function_name=[CONTROLLER_FUNCTION_NAME]" --limit=50

# View recovery worker logs
gcloud logs read "resource.type=cloud_function AND resource.labels.function_name=[WORKER_FUNCTION_NAME]" --limit=50

# View task queue operations
gcloud logs read "resource.type=cloud_tasks_queue" --limit=50
```

### Metrics and Dashboards

Key metrics to monitor:

- Pipeline failure frequency and types
- Recovery success rates by strategy
- Task queue performance and backlog
- Function execution duration and error rates
- Notification delivery success rates

## 🛠️ Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services list --enabled
   ```

2. **Permission Denied**: Verify service account permissions
   ```bash
   gcloud projects get-iam-policy [PROJECT_ID]
   ```

3. **Function Deployment Failed**: Check function source code and dependencies
   ```bash
   gcloud functions logs read [FUNCTION_NAME] --limit=50
   ```

4. **Task Queue Issues**: Verify queue configuration and permissions
   ```bash
   gcloud tasks queues describe [QUEUE_NAME] --location=[REGION]
   ```

### Debug Mode

Enable enhanced logging for troubleshooting:

```hcl
# In terraform.tfvars
enable_enhanced_logging = true
task_queue_logging_sampling_ratio = 1.0
```

## 💰 Cost Optimization

### Estimated Costs

The infrastructure has an estimated monthly cost of $14-68 USD based on:

- **Cloud Functions**: $5-20 (execution frequency dependent)
- **Cloud Tasks**: $1-5 (task volume dependent)  
- **BigQuery**: $5-25 (data volume dependent)
- **Cloud Monitoring**: $1-10 (metrics volume dependent)
- **Cloud Storage**: $1-3 (function source storage)
- **Pub/Sub**: $1-5 (message volume dependent)

### Cost Control Measures

The deployment includes several cost optimization features:

- Function auto-scaling with configurable limits
- BigQuery table expiration policies
- Storage lifecycle management
- Resource labeling for cost tracking

## 🔄 Maintenance

### Updates

Keep the infrastructure updated:

```bash
# Update Terraform providers
terraform init -upgrade

# Plan and apply updates
terraform plan
terraform apply
```

### Backup and Recovery

Important considerations:

- **State File**: Ensure Terraform state is backed up
- **Function Code**: Source code is versioned in Cloud Storage
- **Configuration**: Keep `terraform.tfvars` in version control (without secrets)

## 🔐 Security Best Practices

### Implemented Security Measures

- **IAM**: Least privilege service accounts
- **Encryption**: Data encrypted at rest and in transit
- **Network**: Private Google Access for enhanced security
- **Monitoring**: Comprehensive audit logging
- **Access Control**: Function ingress restrictions

### Additional Security Considerations

For production deployments:

- Enable VPC Service Controls
- Implement Cloud Armor for HTTP endpoints
- Use Customer Managed Encryption Keys (CMEK)
- Configure Binary Authorization for function deployments
- Implement network security policies

## 📚 Additional Resources

- [Google Cloud Dataform Documentation](https://cloud.google.com/dataform/docs)
- [Cloud Tasks Best Practices](https://cloud.google.com/tasks/docs/best-practices)
- [Cloud Functions Security Guide](https://cloud.google.com/functions/docs/securing)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [BigQuery Best Practices](https://cloud.google.com/bigquery/docs/best-practices)

## 🤝 Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Terraform and Google Cloud documentation
3. Examine Cloud Logging for detailed error information
4. Verify all prerequisites are met

---

**Note**: This infrastructure is designed for production use with enterprise-grade reliability patterns. Customize the configuration based on your specific requirements and security policies.