# Infrastructure as Code for Smart Invoice Processing with Document AI and Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Invoice Processing with Document AI and Workflows".

## Overview

This solution automates invoice processing using Google Cloud Document AI to extract structured data from PDF invoices, Cloud Workflows to orchestrate validation and approval routing, and Gmail API integration for automated notifications. The serverless architecture scales automatically and reduces invoice processing time from minutes to seconds.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure deploys the following Google Cloud resources:

- **Cloud Storage**: Invoice document storage with organized folder structure
- **Document AI**: Invoice parser processor for data extraction
- **Cloud Workflows**: Orchestration engine for processing pipeline
- **Cloud Tasks**: Queue management for approval workflows
- **Cloud Functions**: Email notification service
- **Pub/Sub**: Event-driven processing triggers
- **Eventarc**: Storage event triggers for automatic processing
- **IAM**: Service accounts and permissions for secure operation

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Project Editor role or custom roles for:
    - Document AI Admin
    - Workflows Admin
    - Cloud Tasks Admin
    - Cloud Functions Admin
    - Storage Admin
    - Pub/Sub Admin
    - Service Account Admin
- Gmail account or Google Workspace domain for testing notifications
- Sample PDF invoices for testing

### Cost Considerations

- Document AI Invoice Parser: $0.015 per page processed
- Other services: Minimal costs during testing (< $5 for typical usage)
- Review current pricing: https://cloud.google.com/document-ai/pricing

## Quick Start

### Set Environment Variables

```bash
# Set your Google Cloud project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export RESOURCE_SUFFIX="${RANDOM_SUFFIX}"
```

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create invoice-processing-${RESOURCE_SUFFIX} \
    --location=${REGION} \
    --source-yaml=main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION},resource_suffix=${RESOURCE_SUFFIX}

# Monitor deployment status
gcloud infra-manager deployments describe invoice-processing-${RESOURCE_SUFFIX} \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "${PROJECT_ID}"
region = "${REGION}"
resource_suffix = "${RESOURCE_SUFFIX}"
notification_emails = ["your-manager@company.com", "your-director@company.com", "your-cfo@company.com"]
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export RESOURCE_SUFFIX=$(openssl rand -hex 3)

# Deploy infrastructure
./deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| project_id | Google Cloud Project ID | - | Yes |
| region | Deployment region | us-central1 | No |
| resource_suffix | Unique suffix for resources | - | Yes |
| notification_emails | List of approver emails | [] | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| project_id | Google Cloud Project ID | string | - | Yes |
| region | Deployment region | string | us-central1 | No |
| zone | Deployment zone | string | us-central1-a | No |
| resource_suffix | Unique suffix for resources | string | - | Yes |
| notification_emails | List of approver email addresses | list(string) | [] | No |
| max_invoice_amount | Maximum invoice amount for processing | number | 50000 | No |
| task_queue_max_dispatches | Max task dispatches per second | number | 10 | No |

### Bash Script Environment Variables

Required environment variables for bash deployment:

```bash
export PROJECT_ID="your-project-id"           # Your GCP project
export REGION="us-central1"                   # Deployment region
export RESOURCE_SUFFIX="abc123"               # Unique suffix
export NOTIFICATION_EMAILS="email1,email2"    # Comma-separated emails (optional)
```

## Testing the Deployment

### 1. Upload Test Invoice

```bash
# Download sample invoice
curl -L "https://github.com/google/docai-samples/raw/main/invoice-parser/resources/invoice.pdf" \
    -o sample-invoice.pdf

# Upload to trigger processing
gsutil cp sample-invoice.pdf gs://invoice-processing-${RESOURCE_SUFFIX}/incoming/
```

### 2. Monitor Processing

```bash
# Check workflow executions
gcloud workflows executions list \
    --workflow=invoice-workflow-${RESOURCE_SUFFIX} \
    --location=${REGION}

# View task queue status
gcloud tasks queues describe approval-queue-${RESOURCE_SUFFIX} \
    --location=${REGION}

# Check function logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=send-approval-notification-${RESOURCE_SUFFIX}" \
    --limit=10
```

### 3. Verify Outputs

After successful deployment, you'll see:

- **Storage Bucket**: `gs://invoice-processing-${RESOURCE_SUFFIX}`
- **Document AI Processor**: Invoice parser in specified region
- **Workflow**: `invoice-workflow-${RESOURCE_SUFFIX}`
- **Function**: `send-approval-notification-${RESOURCE_SUFFIX}`
- **Task Queue**: `approval-queue-${RESOURCE_SUFFIX}`

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services enable documentai.googleapis.com workflows.googleapis.com cloudtasks.googleapis.com gmail.googleapis.com
   ```

2. **Permission Denied**: Verify IAM permissions
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Document AI Quota**: Check Document AI processing quotas
   ```bash
   gcloud services list --enabled --filter="name:documentai.googleapis.com"
   ```

4. **Workflow Execution Failed**: Check workflow execution details
   ```bash
   gcloud workflows executions describe EXECUTION_ID \
       --workflow=invoice-workflow-${RESOURCE_SUFFIX} \
       --location=${REGION}
   ```

### Log Analysis

```bash
# Workflow execution logs
gcloud logging read "resource.type=workflows.googleapis.com/Workflow" --limit=20

# Function execution logs
gcloud logging read "resource.type=cloud_function" --limit=20

# Document AI processing logs
gcloud logging read "resource.type=documentai.googleapis.com/Processor" --limit=20
```

## Customization

### Approval Logic

Modify the approval routing in the workflow definition:

- **Low amounts** (< $1,000): Manager approval
- **Medium amounts** ($1,000 - $4,999): Director approval  
- **High amounts** (≥ $5,000): Executive approval

Update the `determine_approval_routing` step in the workflow to customize thresholds.

### Notification Templates

Customize email templates in the Cloud Function code:

```python
# Edit notification-function/main.py
def send_email_notification(to_email, invoice_data, vendor, invoice_id, amount):
    subject = f"Custom Subject: {vendor} - ${amount}"
    body = f"""
    Custom email template here...
    """
```

### Processing Rules

Add custom validation rules in the workflow:

```yaml
- custom_validation:
    switch:
      - condition: ${invoice_data.supplier_name in ["blocked_vendor1", "blocked_vendor2"]}
        steps:
          - block_processing:
              # Custom blocking logic
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete invoice-processing-${RESOURCE_SUFFIX} \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud storage buckets list --filter="name:invoice-processing-*"
gcloud workflows list --location=${REGION}
gcloud functions list --region=${REGION}
gcloud tasks queues list --location=${REGION}
```

## Security Considerations

### IAM Best Practices

- Service accounts use least privilege principles
- Each service has minimal required permissions
- No overprivileged roles assigned

### Data Protection

- All data encrypted in transit and at rest
- Storage bucket configured with appropriate access controls
- No hardcoded credentials in code

### Network Security

- Functions use VPC connectors when needed
- Private IP addresses for internal communication
- Secure API endpoints with proper authentication

## Performance Optimization

### Scaling Configuration

- **Cloud Functions**: Auto-scaling based on demand
- **Workflows**: Concurrent execution support
- **Document AI**: Regional processing for low latency
- **Cloud Tasks**: Rate limiting to prevent overwhelming downstream systems

### Cost Optimization

- Use Cloud Storage lifecycle policies for processed invoices
- Monitor Document AI usage to optimize processing costs
- Implement batch processing for high-volume scenarios
- Consider caching frequently accessed data

## Support and Maintenance

### Monitoring

Set up monitoring for:

- Workflow execution success/failure rates
- Document AI processing accuracy
- Function execution latency
- Task queue processing delays

### Updates

Regular maintenance tasks:

- Update function dependencies
- Review and update approval thresholds
- Monitor API quota usage
- Update notification templates

### Backup and Recovery

- Storage bucket versioning enabled
- Workflow definitions stored in version control
- Regular testing of disaster recovery procedures

## Additional Resources

- [Google Cloud Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Cloud Tasks Documentation](https://cloud.google.com/tasks/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Check the GitHub repository for updates and known issues

For questions specific to your use case, consider consulting with Google Cloud Professional Services or certified partners.