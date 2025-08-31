# Infrastructure as Code for Smart Invoice Processing with Document AI and Workflows

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete smart invoice processing system on Google Cloud Platform. The solution uses Document AI for intelligent data extraction, Cloud Workflows for orchestration, Cloud Tasks for approval management, and Cloud Functions for notifications.

## Architecture Overview

The infrastructure creates:

- **Cloud Storage buckets** for document storage with organized folder structure
- **Document AI processor** for intelligent invoice data extraction
- **Cloud Workflows** for orchestrating the processing pipeline
- **Cloud Tasks queue** for reliable approval workflow management
- **Cloud Function** for email notifications and approval routing
- **Pub/Sub topics** for event-driven processing triggers
- **Eventarc triggers** for automated workflow execution
- **IAM service accounts** with least-privilege permissions
- **Monitoring and logging** for operational visibility

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Account**: Active account with billing enabled
2. **Google Cloud Project**: Existing project or permissions to create one
3. **Terraform**: Version 1.0 or later installed locally
4. **Google Cloud CLI**: Latest version (400.0.0+) installed and configured
5. **Required APIs**: The Terraform configuration will enable necessary APIs automatically
6. **IAM Permissions**: Your account needs the following roles:
   - Project Editor or Owner
   - Or custom roles with permissions for all services used

## Quick Start

### 1. Clone and Navigate to Directory

```bash
git clone <repository-url>
cd gcp/smart-invoice-processing-document-ai-workflows/code/terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment          = "prod"
resource_prefix      = "invoice-proc"
bucket_location      = "US"
bucket_storage_class = "STANDARD"

# Approval configuration
notification_emails = [
  "manager@yourcompany.com",
  "director@yourcompany.com", 
  "cfo@yourcompany.com"
]

approval_amount_thresholds = {
  manager_threshold   = 1000
  director_threshold  = 5000
  executive_threshold = 10000
}

# Resource configuration
cloud_function_memory_mb = 256
enable_monitoring       = true
enable_audit_logging    = true

# Custom labels
labels = {
  application = "invoice-processing"
  environment = "production"
  team        = "finance"
  managed-by  = "terraform"
}
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

After successful deployment, verify the system:

```bash
# Check the main outputs
terraform output

# Test file upload to trigger processing
gsutil cp sample-invoice.pdf gs://$(terraform output -raw invoice_storage_bucket_name)/incoming/
```

## Configuration Options

### Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `resource_prefix` | Prefix for resource names | `invoice-proc` | No |
| `bucket_location` | Cloud Storage bucket location | `US` | No |
| `bucket_storage_class` | Storage class for buckets | `STANDARD` | No |
| `notification_emails` | List of approval notification emails | See defaults | No |
| `approval_amount_thresholds` | Amount thresholds for approval levels | See defaults | No |
| `cloud_function_memory_mb` | Memory allocation for Cloud Function | `256` | No |
| `enable_monitoring` | Enable monitoring dashboard | `true` | No |
| `enable_audit_logging` | Enable audit logging | `true` | No |

### Approval Workflow Configuration

The system routes invoices for approval based on configurable amount thresholds:

- **Manager Approval**: Invoices below `manager_threshold`
- **Director Approval**: Invoices between `manager_threshold` and `director_threshold`
- **Executive Approval**: Invoices above `director_threshold`

### Storage Configuration

Cloud Storage buckets are organized with the following structure:

```
invoice-bucket/
├── incoming/     # Upload invoices here to trigger processing
├── processed/    # Successfully processed invoices
└── failed/       # Failed processing attempts with error metadata
```

## Usage Instructions

### Processing Invoices

1. **Upload Invoice PDFs** to the `incoming/` folder:
   ```bash
   gsutil cp invoice.pdf gs://BUCKET_NAME/incoming/
   ```

2. **Monitor Processing** through Cloud Console:
   - Workflows: Check execution status and logs
   - Cloud Functions: Review notification delivery logs
   - Cloud Tasks: Monitor approval queue status

3. **Review Results**:
   - Processed invoices move to `processed/` folder
   - Failed invoices move to `failed/` folder with error metadata
   - Approval notifications sent to configured email addresses

### Monitoring and Troubleshooting

Access monitoring dashboards and logs:

```bash
# View workflow executions
gcloud workflows executions list --workflow=WORKFLOW_NAME --location=REGION

# Check function logs
gcloud logging read "resource.type=cloud_function" --limit=10

# Monitor task queue
gcloud tasks queues describe QUEUE_NAME --location=REGION
```

Use the monitoring dashboard (if enabled) for real-time system health visibility.

## Customization

### Extending the Solution

1. **Custom Business Rules**: Modify the Cloud Function code to implement organization-specific validation and routing logic

2. **Integration with ERP Systems**: Add API calls in the workflow to integrate with existing enterprise systems

3. **Advanced Notification Channels**: Enhance the notification function to support Slack, Microsoft Teams, or SMS notifications

4. **Machine Learning Enhancements**: Add custom Document AI models for specialized invoice formats

5. **Compliance Features**: Implement additional audit logging and compliance reporting capabilities

### Modifying Approval Workflows

To customize approval routing:

1. Update `approval_amount_thresholds` in your `terraform.tfvars`
2. Modify the notification function logic in `function_source/main.py`
3. Adjust workflow business rules in `workflow_source/invoice_workflow.yaml`
4. Redeploy with `terraform apply`

## Security Considerations

This infrastructure implements several security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **Uniform Bucket Access**: Cloud Storage uses uniform bucket-level access control
- **Encrypted Communication**: All service-to-service communication uses TLS
- **Audit Logging**: Comprehensive logging for compliance and monitoring
- **Resource Isolation**: Resources are properly tagged and organized

### Additional Security Recommendations

1. **Network Security**: Consider implementing VPC-native networking for additional isolation
2. **Secret Management**: Use Secret Manager for sensitive configuration data
3. **API Security**: Implement API authentication for external integrations
4. **Data Encryption**: Enable customer-managed encryption keys (CMEK) for sensitive data

## Cost Optimization

The infrastructure includes several cost optimization features:

- **Lifecycle Policies**: Automatic deletion of old documents based on configurable retention
- **Right-Sized Resources**: Appropriate resource sizing for expected workloads
- **Serverless Architecture**: Pay-per-use pricing for compute resources
- **Storage Classes**: Configurable storage classes for cost-effective document archival

### Cost Monitoring

Monitor costs using:

- Google Cloud Billing console
- Cloud Monitoring dashboards
- Budget alerts and cost anomaly detection
- Resource usage reports

## Backup and Disaster Recovery

Consider implementing:

1. **Cross-Region Bucket Replication**: For critical document backup
2. **Configuration Backup**: Export Terraform state and configuration
3. **Workflow Versioning**: Maintain workflow definition versions
4. **Recovery Procedures**: Document recovery processes for each component

## Support and Maintenance

### Regular Maintenance Tasks

1. **Update Dependencies**: Keep Terraform providers and function dependencies current
2. **Review Logs**: Regular log analysis for performance and security insights
3. **Cost Review**: Monthly cost analysis and optimization opportunities
4. **Security Patches**: Apply security updates to function runtimes and dependencies

### Troubleshooting Common Issues

1. **Document AI Processing Failures**: Check processor configuration and document format compatibility
2. **Workflow Execution Errors**: Review workflow logs and validate input data
3. **Notification Delivery Issues**: Verify email configuration and function permissions
4. **Storage Access Problems**: Confirm IAM permissions and bucket policies

For additional support, refer to:
- [Google Cloud Documentation](https://cloud.google.com/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Document AI Documentation](https://cloud.google.com/document-ai/docs)

## Cleanup

To remove all resources created by this infrastructure:

```bash
# Destroy all resources
terraform destroy

# Confirm deletion when prompted
```

**Warning**: This will permanently delete all resources and data. Ensure you have backups of any important data before proceeding.

## Contributing

When contributing to this infrastructure:

1. Test changes in a development environment first
2. Follow Terraform best practices for resource naming and organization
3. Update documentation for any configuration changes
4. Validate security implications of modifications
5. Test the complete invoice processing workflow after changes