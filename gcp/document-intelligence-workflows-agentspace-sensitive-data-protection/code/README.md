# Infrastructure as Code for Document Intelligence Workflows with Agentspace and Sensitive Data Protection

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Document Intelligence Workflows with Agentspace and Sensitive Data Protection".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for manual deployment

## Architecture Overview

This solution implements an intelligent enterprise document processing system that:

- Leverages Google Cloud Agentspace AI agents for document workflow orchestration
- Uses Document AI for intelligent content extraction and classification
- Implements Sensitive Data Protection (DLP) for automatic PII detection and redaction
- Coordinates processing through Cloud Workflows automation
- Provides comprehensive monitoring and audit capabilities for compliance

## Prerequisites

### Required Tools
- Google Cloud CLI (gcloud) version 480.0.0 or later
- Terraform 1.5+ (for Terraform deployment)
- Bash shell environment
- OpenSSL (for random string generation)

### Required Permissions
- Document AI Admin (`roles/documentai.admin`)
- Data Loss Prevention Admin (`roles/dlp.admin`)
- Workflows Admin (`roles/workflows.admin`)
- Storage Admin (`roles/storage.admin`)
- BigQuery Admin (`roles/bigquery.admin`)
- Cloud Logging Admin (`roles/logging.admin`)
- Cloud Monitoring Admin (`roles/monitoring.admin`)
- IAM Security Admin (`roles/iam.securityAdmin`)
- Service Account Admin (`roles/iam.serviceAccountAdmin`)

### Required APIs
The following APIs must be enabled in your Google Cloud project:
- Document AI API (`documentai.googleapis.com`)
- Data Loss Prevention API (`dlp.googleapis.com`)
- Cloud Workflows API (`workflows.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- BigQuery API (`bigquery.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)

### Cost Considerations
Estimated cost for 2 hours of testing: $150-300
- Document AI processing: ~$1.50 per 1,000 pages
- Sensitive Data Protection: ~$1.00 per GB scanned
- Cloud Workflows: ~$0.01 per 1,000 steps
- Storage costs: ~$0.02 per GB per month
- BigQuery storage and queries: ~$5 per TB per month

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended native IaC service that provides GitOps-style deployments with full integration into Google Cloud Console.

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/doc-intelligence-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/doc-intelligence-deployment
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive ecosystem support for infrastructure management.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

For manual deployment or educational purposes, use the provided bash scripts that mirror the recipe's step-by-step approach.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
gcloud projects describe ${PROJECT_ID}
gsutil ls gs://doc-*
```

## Configuration Options

### Environment Variables

All deployment methods support the following environment variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `ZONE` | Deployment zone | `us-central1-a` | No |
| `DLP_INSPECTION_CONFIDENCE` | DLP minimum confidence level | `POSSIBLE` | No |
| `ENABLE_AUDIT_LOGGING` | Enable comprehensive audit logging | `true` | No |
| `DOCUMENT_RETENTION_DAYS` | Document retention period | `90` | No |

### Terraform Variables

Key Terraform variables for customization:

```hcl
# terraform/terraform.tfvars.example
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# Document processing configuration
processor_display_name = "enterprise-doc-processor"
processor_type = "FORM_PARSER_PROCESSOR"

# DLP configuration
dlp_min_likelihood = "POSSIBLE"
dlp_max_findings = 1000

# Storage configuration
storage_class = "STANDARD"
lifecycle_age_days = 90

# Monitoring configuration
enable_monitoring = true
alert_notification_emails = ["admin@company.com"]

# Agentspace configuration
agentspace_agent_name = "DocumentIntelligenceAgent"
enable_natural_language_queries = true
```

## Post-Deployment Configuration

### 1. Agentspace Enterprise Setup

After infrastructure deployment, configure Agentspace Enterprise integration:

```bash
# Upload Agentspace configuration
gsutil cp agentspace-config.json gs://doc-audit-[suffix]/agentspace-config.json

# Configure agent permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:agentspace-doc-processor@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/aiplatform.user"
```

### 2. Test Document Processing

Upload a sample document to test the complete workflow:

```bash
# Create and upload test document
echo "Test document with email: john.doe@example.com and phone: (555) 123-4567" > test-doc.txt
gsutil cp test-doc.txt gs://doc-input-[suffix]/test-doc.txt

# Monitor workflow execution
gcloud workflows executions list --workflow=doc-intelligence-workflow-[suffix] --location=${REGION}
```

### 3. Configure Monitoring Alerts

Set up monitoring alerts for production use:

```bash
# Create notification channel
gcloud alpha monitoring channels create \
    --display-name="Document Processing Alerts" \
    --type=email \
    --channel-labels=email_address=admin@company.com

# Enable alerting policies
gcloud alpha monitoring policies list --filter="displayName:High-Risk Document Processing Alert"
```

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check Document AI processor
gcloud documentai processors list --location=${REGION}

# Verify DLP templates
gcloud dlp inspect-templates list

# Check Cloud Workflows
gcloud workflows list --location=${REGION}

# Validate storage buckets
gsutil ls -p ${PROJECT_ID}

# Test BigQuery dataset
bq ls ${PROJECT_ID}:document_intelligence
```

### Test Document Processing Pipeline

```bash
# Process a sample document
gcloud workflows run doc-intelligence-workflow-[suffix] \
    --data='{"document_path": "test-doc.txt", "document_content": "VGVzdCBkb2N1bWVudA=="}' \
    --location=${REGION}

# Check processing results
gsutil ls gs://doc-output-[suffix]/**

# Verify compliance tracking
bq query --use_legacy_sql=false \
    "SELECT * FROM \`${PROJECT_ID}.document_intelligence.compliance_summary\` LIMIT 5"
```

### Monitor System Health

```bash
# Check system logs
gcloud logging read "protoPayload.serviceName=\"documentai.googleapis.com\"" --limit=10

# View custom metrics
gcloud logging metrics list --filter="name:document_processing"

# Check audit logs
gsutil ls gs://doc-audit-[suffix]/audit-logs/
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/doc-intelligence-deployment \
    --delete-policy="DELETE"

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
gcloud projects describe ${PROJECT_ID}
gsutil ls gs://doc-* 2>/dev/null || echo "Storage buckets cleaned up successfully"
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
gcloud documentai processors delete [PROCESSOR_ID] --location=${REGION} --quiet
gcloud dlp inspect-templates delete [TEMPLATE_ID] --quiet
gcloud workflows delete [WORKFLOW_NAME] --location=${REGION} --quiet
gsutil -m rm -r gs://doc-input-* gs://doc-output-* gs://doc-audit-* 2>/dev/null
bq rm -r -f ${PROJECT_ID}:document_intelligence
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services list --enabled | grep -E "(documentai|dlp|workflows)"
   ```

2. **Insufficient Permissions**: Check IAM roles
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:user@example.com"
   ```

3. **Resource Quota Exceeded**: Check project quotas
   ```bash
   gcloud compute project-info describe --format="table(quotas.metric,quotas.usage,quotas.limit)"
   ```

4. **Agentspace Access Issues**: Verify enterprise licensing
   ```bash
   gcloud alpha agentspace agents list 2>/dev/null || echo "Agentspace access required"
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Set debug environment variable
export GOOGLE_CLOUD_DEBUG=true

# Enable verbose logging
export TF_LOG=DEBUG  # For Terraform
export GCLOUD_VERBOSITY=debug  # For gcloud commands
```

### Support Resources

- [Google Cloud Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Sensitive Data Protection Documentation](https://cloud.google.com/dlp/docs)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Agentspace Documentation](https://cloud.google.com/agentspace/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Security Considerations

### Data Protection
- All sensitive data is automatically detected and redacted using DLP
- Documents are encrypted at rest and in transit
- Access is controlled through IAM with least privilege principles
- Comprehensive audit logging tracks all data access

### Compliance Features
- GDPR compliance through automated PII detection and redaction
- HIPAA compliance with healthcare-specific DLP templates
- SOC 2 compliance through audit logging and access controls
- Configurable data retention policies

### Best Practices
- Regularly rotate service account keys
- Monitor audit logs for unusual access patterns
- Update DLP templates as new sensitive data types are identified
- Implement network security controls for production deployments

## Advanced Configuration

### Custom DLP Templates
Modify DLP templates for industry-specific requirements:

```bash
# Healthcare-specific template
cat > healthcare-dlp-template.json << 'EOF'
{
  "displayName": "Healthcare Document Scanner",
  "inspectConfig": {
    "infoTypes": [
      {"name": "MEDICAL_RECORD_NUMBER"},
      {"name": "US_HEALTHCARE_NPI"},
      {"name": "DATE_OF_BIRTH"},
      {"name": "PERSON_NAME"}
    ]
  }
}
EOF
```

### Multi-Region Deployment
Configure multi-region deployment for high availability:

```bash
# Set additional regions
export REGIONS="us-central1,us-east1,europe-west1"

# Deploy to multiple regions
for region in ${REGIONS//,/ }; do
    gcloud workflows deploy doc-intelligence-workflow \
        --source=workflow.yaml \
        --location=${region}
done
```

### Integration with External Systems
Connect to enterprise systems:

```bash
# Configure Workspace integration
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:agentspace-doc-processor@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/drive.readonly"

# Set up API Gateway for external access
gcloud api-gateway gateways create document-processing-gateway \
    --api=document-processing-api \
    --api-config=document-processing-config \
    --location=${REGION}
```

## Performance Optimization

### Scaling Configuration
Optimize for high-volume processing:

```bash
# Configure parallel processing
export MAX_CONCURRENT_WORKFLOWS=100
export BATCH_SIZE=10

# Enable autoscaling for Cloud Functions
gcloud functions deploy document-classifier \
    --min-instances=1 \
    --max-instances=100 \
    --concurrency=1000
```

### Cost Optimization
Implement cost controls:

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Document Processing Budget" \
    --budget-amount=1000USD \
    --threshold-rules-percent=90
```

## Customization

### Adding New Document Types
Extend the solution for additional document types:

1. Create specialized Document AI processors
2. Update DLP templates for domain-specific sensitive data
3. Modify Agentspace agent configuration
4. Update workflow routing logic

### Integration Examples
Sample integrations for common use cases:

```bash
# Salesforce integration
gcloud functions deploy salesforce-document-sync \
    --runtime=python39 \
    --trigger-topic=document-processed \
    --set-env-vars=SALESFORCE_URL=${SALESFORCE_URL}

# SharePoint integration  
gcloud functions deploy sharepoint-document-sync \
    --runtime=python39 \
    --trigger-topic=document-processed \
    --set-env-vars=SHAREPOINT_URL=${SHAREPOINT_URL}
```

For additional customization options, refer to the variable definitions in each implementation directory and the original recipe documentation.