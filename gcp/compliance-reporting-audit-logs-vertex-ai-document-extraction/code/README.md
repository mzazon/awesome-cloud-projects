# Infrastructure as Code for Compliance Reporting with Cloud Audit Logs and Vertex AI Document Extraction

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Compliance Reporting with Cloud Audit Logs and Vertex AI Document Extraction".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an automated compliance reporting system that:

- Collects comprehensive audit data using Cloud Audit Logs
- Processes compliance documents with Vertex AI Document AI
- Stores documents and reports securely in Cloud Storage
- Generates automated compliance reports via Cloud Scheduler
- Provides real-time monitoring and alerting capabilities

## Prerequisites

### Required Tools

- Google Cloud CLI installed and configured (version 450.0.0 or later)
- Terraform (version 1.0+) for Terraform deployments
- Appropriate Google Cloud project with billing enabled
- Bash shell environment for script execution

### Required Permissions

Your Google Cloud account needs the following IAM roles:

- `roles/owner` or a combination of:
  - `roles/storage.admin`
  - `roles/documentai.editor`
  - `roles/cloudfunctions.developer`
  - `roles/cloudscheduler.admin`
  - `roles/logging.admin`
  - `roles/monitoring.editor`
  - `roles/iam.serviceAccountAdmin`

### Cost Considerations

Estimated monthly costs for processing 10,000 documents:

- Cloud Storage: $20-50 (depending on retention)
- Document AI: $50-150 (based on processing volume)
- Cloud Functions: $10-30 (based on execution frequency)
- Cloud Scheduler: $1-5
- Logging and Monitoring: $20-50

**Total estimated cost: $150-300/month**

## Quick Start

### Environment Setup

```bash
# Set your Google Cloud project
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Authenticate with Google Cloud
gcloud auth login
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
```

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/compliance-reporting \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/compliance-reporting
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud functions list
gcloud storage buckets list
```

## Configuration Options

### Key Variables

| Variable | Description | Default Value | Required |
|----------|-------------|---------------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Google Cloud region for resources | `us-central1` | Yes |
| `audit_bucket_name` | Name for audit logs storage bucket | `audit-logs-${random_suffix}` | No |
| `compliance_bucket_name` | Name for compliance documents bucket | `compliance-docs-${random_suffix}` | No |
| `processor_display_name` | Display name for Document AI processor | `compliance-processor-${random_suffix}` | No |
| `schedule_expression` | Cron expression for report generation | `0 9 * * MON` | No |
| `function_memory` | Memory allocation for Cloud Functions | `512MB` | No |
| `function_timeout` | Timeout for Cloud Functions | `300s` | No |

### Customization Examples

#### Custom Report Schedule

```bash
# Weekly reports on Fridays at 2 PM
terraform apply -var="schedule_expression=0 14 * * FRI"
```

#### Enhanced Processing Resources

```bash
# Increase function resources for large document volumes
terraform apply -var="function_memory=1024MB" -var="function_timeout=540s"
```

#### Multi-Region Deployment

```bash
# Deploy to multiple regions for high availability
terraform apply -var="region=us-east1"
terraform apply -var="region=europe-west1"
```

## Post-Deployment Validation

### Verify Infrastructure Components

```bash
# Check Cloud Storage buckets
gcloud storage buckets list --filter="name:audit-logs OR name:compliance-docs"

# Verify Document AI processors
gcloud ai document-processors list --location=${REGION}

# Check Cloud Functions
gcloud functions list --filter="name:compliance"

# Verify Cloud Scheduler jobs
gcloud scheduler jobs list --filter="name:compliance"
```

### Test Document Processing

```bash
# Upload a test document
echo "Sample compliance policy document" > test-policy.txt
gcloud storage cp test-policy.txt gs://$(terraform output -raw compliance_bucket_name)/policies/

# Monitor processing logs
gcloud functions logs read compliance-processor --limit=10
```

### Validate Report Generation

```bash
# Trigger manual report generation
curl -X POST "$(terraform output -raw report_function_url)" \
    -H "Content-Type: application/json" \
    -d '{"report_type":"manual"}'

# Check generated reports
gcloud storage ls gs://$(terraform output -raw compliance_bucket_name)/reports/
```

## Monitoring and Troubleshooting

### View Function Logs

```bash
# Document processing function logs
gcloud functions logs read compliance-processor --limit=50

# Report generation function logs
gcloud functions logs read compliance-report-generator --limit=50

# Analytics function logs
gcloud functions logs read compliance-log-analytics --limit=50
```

### Monitor Resource Usage

```bash
# Check storage usage
gcloud storage du gs://$(terraform output -raw audit_bucket_name)
gcloud storage du gs://$(terraform output -raw compliance_bucket_name)

# View function execution metrics
gcloud functions describe compliance-processor --region=${REGION}
```

### Common Issues and Solutions

#### Document Processing Failures

```bash
# Check Document AI processor status
gcloud ai document-processors describe $(terraform output -raw processor_id) --location=${REGION}

# Verify bucket permissions
gcloud storage buckets get-iam-policy gs://$(terraform output -raw compliance_bucket_name)
```

#### Scheduler Job Issues

```bash
# Check scheduler job status
gcloud scheduler jobs describe $(terraform output -raw scheduler_job_name) --location=${REGION}

# View scheduler logs
gcloud logging read "resource.type=cloud_scheduler_job"
```

## Security Considerations

### Data Protection

- All storage buckets use Google-managed encryption by default
- Document AI processing occurs within Google Cloud's secure environment
- Audit logs are stored with versioning and lifecycle management
- Access is controlled via IAM roles and service accounts

### Access Control

- Service accounts follow principle of least privilege
- Functions use dedicated service accounts with minimal permissions
- Storage buckets have restricted public access
- Monitoring provides visibility into all access patterns

### Compliance Features

- Immutable audit logs support regulatory requirements
- Document processing maintains chain of custody
- Automated report generation includes audit trails
- Monitoring alerts on compliance violations

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/compliance-reporting

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
gcloud functions list
gcloud storage buckets list
gcloud scheduler jobs list
```

### Manual Cleanup Verification

```bash
# Check for remaining resources
gcloud ai document-processors list --location=${REGION}
gcloud logging sinks list
gcloud monitoring policies list
gcloud iam service-accounts list --filter="email:compliance"
```

## Advanced Configuration

### Custom Document Processors

To add specialized Document AI processors for specific document types:

```bash
# Create additional processors via Terraform
terraform apply -var="enable_contract_processor=true" -var="enable_policy_processor=true"
```

### Enhanced Monitoring

```bash
# Enable additional monitoring features
terraform apply -var="enable_advanced_monitoring=true" -var="alert_email=compliance@company.com"
```

### Multi-Framework Support

```bash
# Configure for multiple compliance frameworks
terraform apply -var="compliance_frameworks=[\"SOC2\",\"ISO27001\",\"HIPAA\"]"
```

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Example GitHub Actions workflow
name: Deploy Compliance Infrastructure
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: google-github-actions/setup-gcloud@v1
      - name: Deploy Infrastructure
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

### API Integration

```bash
# Example API call to trigger report generation
curl -X POST "${FUNCTION_URL}" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    -d '{"framework":"SOC2","format":"pdf"}'
```

## Support and Documentation

### Additional Resources

- [Original Recipe Documentation](../compliance-reporting-audit-logs-vertex-ai-document-extraction.md)
- [Google Cloud Audit Logs Documentation](https://cloud.google.com/logging/docs/audit)
- [Vertex AI Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)

### Community Support

- [Google Cloud Community](https://cloud.google.com/community)
- [Terraform Google Provider Issues](https://github.com/hashicorp/terraform-provider-google/issues)
- [Google Cloud Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Professional Support

For enterprise deployments requiring professional support:

- [Google Cloud Professional Services](https://cloud.google.com/consulting)
- [Google Cloud Support Plans](https://cloud.google.com/support)
- [Certified Google Cloud Partners](https://cloud.google.com/partners)

---

**Note**: This infrastructure code implements the complete compliance reporting solution described in the recipe. For questions about specific configurations or troubleshooting, refer to the original recipe documentation or Google Cloud's official documentation.