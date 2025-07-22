# Infrastructure as Code for Event-Driven Data Synchronization

This directory contains Terraform Infrastructure as Code (IaC) implementation for the recipe "Event-Driven Data Synchronization with Cloud Datastore and Cloud Pub/Sub".

## Architecture Overview

This infrastructure creates a complete event-driven data synchronization system using:

- **Cloud Datastore**: Primary data store with strong consistency
- **Cloud Pub/Sub**: Event messaging and distribution
- **Cloud Functions**: Serverless event processing
- **Cloud Logging**: Comprehensive audit logging
- **Cloud Monitoring**: Dashboard and alerting

## Prerequisites

1. **Google Cloud Project**: Active GCP project with billing enabled
2. **Google Cloud CLI**: `gcloud` CLI installed and configured
3. **Terraform**: Version 1.5.0 or later
4. **Permissions**: IAM roles for creating resources:
   - `roles/datastore.owner`
   - `roles/pubsub.admin`
   - `roles/cloudfunctions.admin`
   - `roles/logging.admin`
   - `roles/monitoring.admin`
   - `roles/storage.admin`
   - `roles/iam.serviceAccountAdmin`

## Quick Start

### 1. Initialize Terraform

```bash
# Clone the repository and navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your project settings
nano terraform.tfvars
```

**Required Variables:**
- `project_id`: Your GCP project ID
- `region`: GCP region (e.g., "us-central1")
- `zone`: GCP zone (e.g., "us-central1-a")

### 3. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check the outputs
terraform output

# Test the system using the provided commands
terraform output publisher_command
terraform output function_logs_command
```

## Configuration Options

### Core Configuration

```hcl
# terraform.tfvars
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"
environment = "dev"
```

### Pub/Sub Configuration

```hcl
# Message retention and processing
message_retention_duration = "604800s"  # 7 days
ack_deadline_seconds       = 60
max_delivery_attempts      = 5
```

### Cloud Functions Configuration

```hcl
# Function specifications
sync_function_memory = 256
function_timeout     = 60
max_instances       = 10
function_runtime    = "python39"
```

### Monitoring Configuration

```hcl
# Enable monitoring and alerting
enable_monitoring           = true
create_monitoring_dashboard = true
notification_email         = "your-email@example.com"
```

## Key Features

### 1. Event-Driven Architecture
- Pub/Sub topics for reliable message delivery
- Automatic scaling based on message volume
- Dead letter queue for error handling

### 2. Data Synchronization
- Intelligent conflict resolution
- Version tracking and audit trails
- External system integration support

### 3. Monitoring and Observability
- Real-time monitoring dashboard
- Comprehensive audit logging
- Automated alerting for failures

### 4. Security and Compliance
- Least privilege IAM roles
- Data sanitization in audit logs
- Compliance logging for regulatory requirements

## Resource Overview

### Created Resources

| Resource Type | Count | Purpose |
|---------------|--------|---------|
| Pub/Sub Topics | 2-5 | Event messaging (main + DLQ + external) |
| Pub/Sub Subscriptions | 3 | Message processing (sync, audit, DLQ) |
| Cloud Functions | 2 | Event processing (sync + audit) |
| Cloud Datastore | 1 | Primary data store |
| IAM Service Account | 1 | Function execution identity |
| Cloud Storage Bucket | 1 | Function source code |
| Monitoring Dashboard | 1 | System observability |
| Alert Policies | 2 | Failure notifications |

### Estimated Costs

**Development Environment:**
- Datastore: $1-5/month (based on operations)
- Pub/Sub: $1-3/month (based on messages)
- Cloud Functions: $3-10/month (based on invocations)
- Cloud Storage: <$1/month (function source)
- Cloud Logging: $1-5/month (based on volume)
- **Total: ~$6-24/month**

**Production Environment:**
- Estimate 3-5x development costs based on volume
- Use cost monitoring and budgets for control

## Testing the Infrastructure

### 1. Publish Test Messages

```bash
# Use the generated command from outputs
terraform output -raw publisher_command | bash
```

### 2. Monitor Function Execution

```bash
# View function logs
terraform output -raw function_logs_command | bash

# Check subscription status
gcloud pubsub subscriptions list --project=$(terraform output -raw project_id)
```

### 3. Query Datastore

```bash
# View synchronized entities
terraform output -raw datastore_query_command | bash
```

### 4. Access Monitoring Dashboard

```bash
# Get dashboard URL
terraform output monitoring_dashboard_url
```

## Customization

### Adding External Sync

```hcl
# In terraform.tfvars
enable_external_sync = true
```

This creates additional Pub/Sub topics for external system integration.

### Scaling Configuration

```hcl
# Adjust based on expected load
max_instances = 50
sync_function_memory = 512
```

### Security Hardening

```hcl
# Enable comprehensive audit logging
enable_audit_logging = true

# Add custom labels for resource organization
labels = {
  managed-by = "terraform"
  purpose    = "event-driven-sync"
  team       = "data-platform"
  compliance = "gdpr"
}
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy $(terraform output -raw project_id)
   ```

2. **Function Deployment Failures**
   ```bash
   # Check function logs
   gcloud functions logs read $(terraform output -raw sync_function_name) --region=$(terraform output -raw region)
   ```

3. **Message Processing Issues**
   ```bash
   # Check subscription status
   gcloud pubsub subscriptions describe $(terraform output -raw sync_subscription_name)
   ```

### Debugging Commands

```bash
# View all resources
terraform show

# Check resource dependencies
terraform graph | dot -Tpng > graph.png

# Validate configuration
terraform validate
```

## Maintenance

### Updates and Upgrades

```bash
# Update provider versions
terraform init -upgrade

# Plan updates
terraform plan

# Apply updates
terraform apply
```

### Backup and Recovery

```bash
# Export Terraform state
terraform state pull > terraform.tfstate.backup

# Export Datastore entities (if needed)
gcloud datastore export gs://your-backup-bucket/datastore-backup
```

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
gcloud datastore databases delete --database=<database-id>
gcloud pubsub topics delete <topic-name>
gcloud storage buckets delete <bucket-name>
```

## Support

For issues with this infrastructure code:

1. Check the [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
2. Review the [original recipe documentation](../../../event-driven-data-synchronization-datastore-pub-sub.md)
3. Consult [Google Cloud documentation](https://cloud.google.com/docs)

## Advanced Configuration

### Multi-Region Deployment

```hcl
# Configure for multi-region
variable "regions" {
  default = ["us-central1", "us-east1", "europe-west1"]
}

# Deploy across regions (requires module modification)
```

### Custom Function Code

To deploy custom function code:

1. Modify files in `function_templates/`
2. Update `main.tf` source archives
3. Run `terraform apply`

### Integration with CI/CD

```yaml
# Example GitHub Actions workflow
name: Deploy Infrastructure
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v1
      - name: Terraform Apply
        run: |
          terraform init
          terraform apply -auto-approve
```

---

**Note**: This infrastructure follows Google Cloud best practices for security, monitoring, and cost optimization. Adjust configurations based on your specific requirements and compliance needs.