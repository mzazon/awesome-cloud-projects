# Terraform Infrastructure for Multi-Cloud Resource Discovery

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete multi-cloud resource discovery system using Google Cloud Platform services including Cloud Location Finder, Pub/Sub, Cloud Functions, and Cloud Storage.

## 🏗️ Architecture Overview

The infrastructure deploys:

- **Cloud Location Finder API** integration for unified multi-cloud location data
- **Pub/Sub** topic and subscription for event-driven message processing
- **Cloud Functions** for serverless location data analysis and recommendations
- **Cloud Storage** bucket for storing location reports and analysis results
- **Cloud Scheduler** job for automated periodic discovery
- **Cloud Monitoring** dashboard and alerts for operational visibility
- **Service Account** with minimal required permissions following security best practices

## 📋 Prerequisites

### Required Tools

- [Google Cloud CLI (`gcloud`)](https://cloud.google.com/sdk/docs/install) version 400.0.0 or later
- [Terraform](https://www.terraform.io/downloads.html) version 1.5.0 or later
- Google Cloud Platform account with billing enabled

### Required Permissions

Your Google Cloud user account or service account needs the following IAM roles:

- `roles/owner` or `roles/editor` on the target project
- `roles/serviceusage.serviceUsageAdmin` (to enable APIs)
- `roles/iam.serviceAccountAdmin` (to create service accounts)
- `roles/resourcemanager.projectIamAdmin` (to assign IAM roles)

### Google Cloud APIs

The following APIs will be automatically enabled (if `enable_apis = true`):

- Cloud Location Finder API (`cloudlocationfinder.googleapis.com`)
- Cloud Pub/Sub API (`pubsub.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)

## 🚀 Quick Start

### 1. Configure Google Cloud CLI

```bash
# Authenticate with Google Cloud
gcloud auth login

# Set your default project (optional)
gcloud config set project YOUR_PROJECT_ID
```

### 2. Configure Terraform Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your configuration
nano terraform.tfvars
```

**Required variables:**
```hcl
project_id = "your-gcp-project-id"
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform (downloads providers and modules)
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check the status of deployed resources
terraform show

# Test the system by triggering manual discovery
gcloud pubsub topics publish $(terraform output -raw pubsub_topic_name) \
    --message='{"trigger":"manual_test","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'

# View function logs to confirm processing
terraform output management_commands
```

## 📁 File Structure

```
terraform/
├── main.tf                    # Main infrastructure resources
├── variables.tf               # Input variable definitions
├── outputs.tf                 # Output value definitions
├── versions.tf                # Terraform and provider version constraints
├── terraform.tfvars.example  # Example variable configuration
├── .gitignore                 # Git ignore patterns
├── README.md                  # This documentation
└── function/                  # Cloud Function source code
    ├── main.py               # Python function implementation
    └── requirements.txt      # Python dependencies
```

## ⚙️ Configuration Options

### Environment-Specific Configurations

**Development Environment:**
```hcl
environment     = "dev"
function_memory = 256
enable_monitoring = false
scheduler_frequency = "0 */12 * * *"  # Every 12 hours
```

**Staging Environment:**
```hcl
environment     = "staging"
function_memory = 512
enable_monitoring = true
scheduler_frequency = "0 */6 * * *"   # Every 6 hours
```

**Production Environment:**
```hcl
environment     = "prod"
function_memory = 1024
enable_monitoring = true
scheduler_frequency = "0 */4 * * *"   # Every 4 hours
alert_notification_channels = [
  "projects/your-project/notificationChannels/your-channel-id"
]
```

### Cost Optimization

```hcl
# Reduce costs for development environments
function_memory = 256              # Lower memory allocation
storage_class = "NEARLINE"        # Cheaper storage for less frequent access
scheduler_frequency = "0 0 * * *" # Once daily instead of every 6 hours
enable_monitoring = false         # Disable monitoring for dev environments
```

### High Performance Configuration

```hcl
# Optimize for performance and frequency
function_memory = 2048            # More memory for faster processing
storage_class = "STANDARD"       # Fastest storage access
scheduler_frequency = "0 */2 * * *" # Every 2 hours
pubsub_ack_deadline = 600        # Longer processing time allowance
```

## 📊 Monitoring and Observability

### Accessing the Monitoring Dashboard

```bash
# Get the dashboard URL
terraform output console_urls
```

### Key Metrics Tracked

- **Total Locations Discovered**: Number of multi-cloud locations identified
- **Function Execution Count**: Rate of successful function invocations
- **Pub/Sub Message Processing**: Message throughput and latency
- **Storage Usage**: Reports and data volume over time
- **Low-Carbon Regions**: Count of environmentally-friendly deployment options

### Alert Policies

The infrastructure creates alert policies for:

- **Function Failures**: Alerts when function execution errors exceed threshold
- **Message Processing Delays**: Alerts when Pub/Sub messages remain unprocessed
- **API Rate Limiting**: Alerts when Location Finder API limits are approached

### Useful Management Commands

```bash
# Trigger manual location discovery
$(terraform output -raw management_commands | jq -r .test_function_manually)

# View recent function logs  
$(terraform output -raw management_commands | jq -r .view_function_logs)

# List generated reports
$(terraform output -raw management_commands | jq -r .view_storage_reports)

# Check scheduler job status
$(terraform output -raw management_commands | jq -r .trigger_scheduler_job)
```

## 🔐 Security Considerations

### Service Account Permissions

The infrastructure creates a dedicated service account with minimal required permissions:

- `roles/pubsub.subscriber` - Read messages from Pub/Sub subscription
- `roles/storage.objectAdmin` - Read/write access to storage bucket only
- `roles/monitoring.metricWriter` - Write custom metrics to Cloud Monitoring
- `roles/cloudlocationfinder.viewer` - Read location data from Location Finder API

### Data Security

- **Uniform Bucket-Level Access**: Enabled by default for consistent security policies
- **Storage Versioning**: Enabled to protect against accidental data loss
- **Message Encryption**: Pub/Sub messages encrypted in transit and at rest
- **Function Environment**: Isolated execution environment with minimal network access

### Best Practices Implemented

- No hardcoded secrets or credentials in code
- Least privilege principle for all IAM assignments
- Resource-level IAM bindings instead of project-level where possible
- Automatic API enablement to reduce manual configuration errors

## 💰 Cost Estimation

### Monthly Cost Breakdown (USD)

| Service | Usage Pattern | Estimated Cost |
|---------|---------------|----------------|
| Cloud Functions | 120 invocations/month @ 512MB | $2-5 |
| Pub/Sub | 500 messages/month | $0.01-0.10 |
| Cloud Storage | 1GB with lifecycle policies | $1-3 |
| Cloud Scheduler | 1 job, 120 executions/month | $0.10 |
| Cloud Monitoring | Custom metrics and dashboard | $0-1 |
| **Total Estimated** | | **$3-9/month** |

> **Note**: Actual costs depend on usage patterns, data volumes, and selected configuration options.

### Cost Optimization Strategies

1. **Reduce Function Memory**: Use 256MB for development environments
2. **Adjust Scheduler Frequency**: Run discovery less frequently for non-critical environments  
3. **Storage Class Selection**: Use NEARLINE/COLDLINE for archival data
4. **Disable Monitoring**: Turn off monitoring for development environments
5. **Regional Selection**: Deploy in regions with lower compute costs

## 🛠️ Maintenance and Updates

### Updating the Infrastructure

```bash
# Pull latest changes
git pull origin main

# Review planned changes
terraform plan

# Apply updates
terraform apply
```

### Updating Function Code

Function code is automatically packaged and deployed when you run `terraform apply`. To update only the function:

```bash
# Modify function/main.py or function/requirements.txt
# Then apply changes
terraform apply -target=google_cloudfunctions_function.location_processor
```

### Monitoring Function Health

```bash
# Check function status
gcloud functions describe $(terraform output -raw function_name) \
    --region=$(terraform output -raw region)

# View recent function logs
gcloud functions logs read $(terraform output -raw function_name) \
    --region=$(terraform output -raw region) \
    --limit=50
```

## 🧹 Cleanup

### Destroy Individual Resources

```bash
# Remove monitoring resources only
terraform destroy -target=google_monitoring_dashboard.location_discovery_dashboard
terraform destroy -target=google_monitoring_alert_policy.function_failure_alert

# Remove function only (keeps data)
terraform destroy -target=google_cloudfunctions_function.location_processor
```

### Complete Infrastructure Removal

```bash
# Remove all resources (WARNING: This deletes all data)
terraform destroy

# Confirm deletion by typing 'yes' when prompted
```

### Manual Cleanup Steps

Some resources may require manual cleanup:

```bash
# Remove any remaining storage objects
gsutil -m rm -r gs://$(terraform output -raw storage_bucket_name)/*

# Disable APIs if no longer needed
gcloud services disable cloudlocationfinder.googleapis.com --force
```

## 🐛 Troubleshooting

### Common Issues

**Issue**: `Error enabling APIs`
```bash
# Solution: Ensure billing is enabled on the project
gcloud billing projects link YOUR_PROJECT_ID --billing-account=YOUR_BILLING_ACCOUNT
```

**Issue**: `Permission denied` during deployment
```bash
# Solution: Verify your user has sufficient permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:user:YOUR_EMAIL"
```

**Issue**: Function fails to process location data
```bash
# Solution: Check function logs for details
gcloud functions logs read $(terraform output -raw function_name) --region=$(terraform output -raw region)

# Verify API is enabled
gcloud services list --enabled --filter="name:cloudlocationfinder.googleapis.com"
```

**Issue**: No monitoring data appearing
```bash
# Solution: Wait 5-10 minutes for initial metrics, then check
gcloud monitoring metrics list --filter="metric.type:custom.googleapis.com/multicloud"
```

### Debug Mode

Enable detailed Terraform logging:

```bash
export TF_LOG=DEBUG
terraform apply
```

### Getting Support

1. Check the [original recipe documentation](../../../multi-cloud-resource-discovery-location-finder-pub-sub.md)
2. Review [Google Cloud Location Finder documentation](https://cloud.google.com/location-finder/docs)
3. Consult [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## 🔄 Integration with CI/CD

### GitHub Actions Example

```yaml
name: Deploy Multi-Cloud Discovery
on:
  push:
    branches: [main]
    paths: ['gcp/multi-cloud-resource-discovery-location-finder-pub-sub/code/terraform/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - uses: google-github-actions/setup-gcloud@v1
        with:
          service_account_key: ${{ secrets.GCP_SA_KEY }}
          project_id: ${{ secrets.GCP_PROJECT_ID }}
      
      - name: Terraform Init
        run: terraform init
        working-directory: gcp/multi-cloud-resource-discovery-location-finder-pub-sub/code/terraform
      
      - name: Terraform Plan
        run: terraform plan
        working-directory: gcp/multi-cloud-resource-discovery-location-finder-pub-sub/code/terraform
      
      - name: Terraform Apply
        run: terraform apply -auto-approve
        working-directory: gcp/multi-cloud-resource-discovery-location-finder-pub-sub/code/terraform
```

---

**📝 Note**: This infrastructure is designed for the multi-cloud resource discovery recipe. For production deployments, consider implementing additional security controls, backup strategies, and compliance measures specific to your organization's requirements.