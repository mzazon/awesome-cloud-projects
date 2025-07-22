# Terraform Infrastructure for Workflow Automation with Google Workspace Flows

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete workflow automation solution using Google Workspace Flows, Service Extensions, Cloud Functions, and Pub/Sub.

## Architecture Overview

The solution deploys the following Google Cloud resources:

- **Cloud Storage**: Document storage with lifecycle management
- **Cloud Functions**: Serverless processing for document analysis, approval handling, notifications, and analytics
- **Pub/Sub**: Message orchestration with dead letter queues
- **Service Account**: Secure access management with least privilege principles
- **Monitoring**: Cloud Monitoring dashboard and custom metrics
- **Logging**: Structured logging and log sinks

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (gcloud CLI)
- [Node.js](https://nodejs.org/) >= 18 (for Cloud Functions)

### Required Permissions

Your Google Cloud user account or service account needs the following IAM roles:

- `roles/owner` (for initial setup) OR the following granular roles:
  - `roles/resourcemanager.projectCreator`
  - `roles/serviceusage.serviceUsageAdmin`
  - `roles/iam.serviceAccountAdmin`
  - `roles/storage.admin`
  - `roles/cloudfunctions.admin`
  - `roles/pubsub.admin`
  - `roles/monitoring.admin`
  - `roles/logging.admin`

### Google Cloud Setup

1. **Create or select a Google Cloud Project**:
   ```bash
   gcloud projects create your-project-id --name="Workflow Automation"
   gcloud config set project your-project-id
   ```

2. **Enable billing** for the project through the [Google Cloud Console](https://console.cloud.google.com/billing).

3. **Authenticate with Google Cloud**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
environment             = "dev"
resource_name_prefix    = "workflow-automation"
storage_bucket_location = "US"
function_memory         = 512
function_timeout        = 540

# Notification settings
notification_email = "admin@yourcompany.com"
workspace_domain   = "yourcompany.com"

# Feature flags
enable_monitoring   = true
enable_logging      = true
enable_dead_letter  = true

# Labels for resource organization
labels = {
  environment = "dev"
  project     = "workflow-automation"
  team        = "your-team"
  cost-center = "your-cost-center"
}
```

### 3. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

After successful deployment, verify the resources:

```bash
# Check Cloud Functions
gcloud functions list --region=us-central1

# Check Pub/Sub topics
gcloud pubsub topics list

# Check Storage buckets
gsutil ls

# Test the document processor function
curl -X POST "$(terraform output -raw document_processor_function_url)" \
  -H "Content-Type: application/json" \
  -d '{
    "fileName": "test-document.pdf",
    "bucketName": "'$(terraform output -raw storage_bucket_name)'",
    "metadata": {
      "document_type": "invoice",
      "department": "finance",
      "priority": "high"
    }
  }'
```

## Configuration Options

### Variable Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | ✅ |
| `region` | Google Cloud region | `us-central1` | ❌ |
| `zone` | Google Cloud zone | `us-central1-a` | ❌ |
| `environment` | Environment name | `dev` | ❌ |
| `resource_name_prefix` | Resource name prefix | `workflow-automation` | ❌ |
| `function_memory` | Cloud Function memory (MB) | `512` | ❌ |
| `function_timeout` | Cloud Function timeout (seconds) | `540` | ❌ |
| `enable_monitoring` | Enable Cloud Monitoring | `true` | ❌ |
| `enable_logging` | Enable Cloud Logging | `true` | ❌ |
| `enable_dead_letter` | Enable dead letter queues | `true` | ❌ |

### Environment-Specific Configurations

#### Development Environment
```hcl
environment = "dev"
function_memory = 256
enable_monitoring = true
enable_logging = true
```

#### Staging Environment
```hcl
environment = "staging"
function_memory = 512
enable_monitoring = true
enable_logging = true
```

#### Production Environment
```hcl
environment = "prod"
function_memory = 1024
function_timeout = 540
enable_monitoring = true
enable_logging = true
enable_dead_letter = true
pubsub_message_retention_duration = "2678400s"  # 31 days
```

## Post-Deployment Configuration

### 1. Google Workspace Flows Setup

After deployment, configure Google Workspace Flows:

1. Access the [Google Workspace Flows admin panel](https://admin.google.com/ac/flows)
2. Create a new flow using the provided endpoint URLs from Terraform outputs
3. Configure the flow trigger for Google Drive file uploads
4. Set up Gemini AI analysis steps
5. Configure approval routing and notifications

### 2. Service Account Permissions

Grant additional permissions for Google Workspace integration:

```bash
# Get the service account email from Terraform output
SERVICE_ACCOUNT=$(terraform output -raw service_account_email)

# Grant Google Workspace API access (requires domain admin)
gcloud projects add-iam-policy-binding your-project-id \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/admin.directory.user.readonly"
```

### 3. Google Sheets Integration

If using Google Sheets for workflow tracking:

1. Create a Google Sheets document for workflow tracking
2. Share the sheet with the service account email
3. Update the Cloud Functions with the sheet ID:

```bash
# Update function environment variables
gcloud functions deploy $(terraform output -raw approval_webhook_function_name) \
  --update-env-vars="TRACKING_SHEET_ID=your-sheet-id"
```

### 4. Google Chat Integration

For Google Chat notifications:

1. Create a Google Chat space
2. Add the service account as a bot to the space
3. Get the space ID and update notification configurations

## Monitoring and Observability

### Cloud Monitoring Dashboard

Access the deployed monitoring dashboard:

```bash
# Get dashboard URL
echo "https://console.cloud.google.com/monitoring/dashboards/custom/$(terraform output -raw monitoring_dashboard_id)"
```

### Key Metrics to Monitor

- **Document Processing Volume**: Function execution count
- **Processing Latency**: Function execution duration
- **Error Rate**: Failed function executions
- **Pub/Sub Message Lag**: Message processing delays
- **Storage Usage**: Bucket size and object count

### Alerting Policies

Set up alerting for critical metrics:

```bash
# Create alerting policy for function errors
gcloud alpha monitoring policies create --policy-from-file=monitoring/alert-policies.yaml
```

### Log Analysis

View structured logs in Cloud Logging:

```bash
# View function logs
gcloud logging read "resource.type=cloud_function AND severity>=ERROR" --limit=50

# View workflow analytics
gcloud logging read "labels.component=workflow-analytics" --limit=20
```

## Security Considerations

### IAM Best Practices

- Use least privilege principle for service account permissions
- Regularly audit IAM roles and permissions
- Enable IAM condition-based access when possible

### Network Security

- Consider using VPC Service Controls for additional security
- Implement Cloud Armor for DDoS protection if needed
- Use private Google Access for internal resources

### Data Protection

- Enable Cloud KMS encryption for sensitive data
- Implement Data Loss Prevention (DLP) scanning
- Configure retention policies for compliance

## Cost Optimization

### Resource Optimization

- Monitor Cloud Function memory usage and adjust allocations
- Review storage lifecycle policies regularly
- Use sustained use discounts for predictable workloads

### Cost Monitoring

```bash
# Set up budget alerts
gcloud billing budgets create \
  --billing-account=YOUR_BILLING_ACCOUNT \
  --display-name="Workflow Automation Budget" \
  --budget-amount=100USD \
  --threshold-rule=percent=90,basis=CURRENT_SPEND
```

## Troubleshooting

### Common Issues

1. **Function Deployment Failures**
   ```bash
   # Check function deployment status
   gcloud functions describe FUNCTION_NAME --region=us-central1
   
   # View function logs
   gcloud functions logs read FUNCTION_NAME --region=us-central1
   ```

2. **Pub/Sub Message Delivery Issues**
   ```bash
   # Check subscription status
   gcloud pubsub subscriptions describe SUBSCRIPTION_NAME
   
   # Pull messages manually for debugging
   gcloud pubsub subscriptions pull SUBSCRIPTION_NAME --auto-ack
   ```

3. **Permission Errors**
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy your-project-id \
     --flatten="bindings[].members" \
     --filter="bindings.members:serviceAccount:YOUR_SERVICE_ACCOUNT"
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Update function with debug logging
gcloud functions deploy FUNCTION_NAME \
  --update-env-vars="DEBUG=true,LOG_LEVEL=debug"
```

## Cleanup

To destroy all resources:

```bash
# Plan destruction
terraform plan -destroy

# Destroy all resources
terraform destroy

# Clean up local files
rm -f terraform.tfstate*
rm -f .terraform.lock.hcl
rm -rf .terraform/
```

## Support and Contributing

### Getting Help

- Review the [Google Cloud Documentation](https://cloud.google.com/docs)
- Check [Terraform Google Provider docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- Consult the original recipe documentation

### Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update variable descriptions and documentation
3. Validate Terraform formatting: `terraform fmt`
4. Validate configuration: `terraform validate`
5. Update version constraints as needed

## Version Information

- **Terraform Version**: >= 1.0
- **Google Provider Version**: ~> 5.0
- **Node.js Runtime**: nodejs20
- **Last Updated**: 2025-01-12

This infrastructure code is designed to be production-ready with security best practices, monitoring, and scalability built-in. Customize the variables and configuration to match your specific requirements and compliance needs.