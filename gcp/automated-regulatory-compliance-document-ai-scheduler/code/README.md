# Infrastructure as Code for Automated Regulatory Compliance Reporting with Document AI and Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Regulatory Compliance Reporting with Document AI and Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code using YAML configuration
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Configuration Language (HCL)
- **Scripts**: Bash deployment and cleanup scripts for direct CLI-based provisioning

## Prerequisites

### General Requirements
- Google Cloud Project with Owner or Editor permissions
- Google Cloud CLI (gcloud) installed and configured
- Active billing account associated with your project
- Basic understanding of regulatory compliance workflows

### Tool-Specific Prerequisites

#### Infrastructure Manager
- `gcloud infra-manager` commands available (included in Cloud SDK)
- Service account with Infrastructure Manager Admin role

#### Terraform
- Terraform >= 1.0 installed ([Download Terraform](https://www.terraform.io/downloads))
- Google Cloud Provider for Terraform

#### Bash Scripts
- Bash shell environment (Linux, macOS, or WSL)
- `jq` command-line JSON processor
- `openssl` for generating random values

### Required APIs
The following Google Cloud APIs must be enabled:
- Document AI API (`documentai.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)

### Estimated Costs
- Document AI processing: ~$1.50 per 1,000 pages
- Cloud Functions: ~$0.40 per million requests
- Cloud Storage: ~$0.02 per GB per month
- Cloud Scheduler: $0.10 per job per month
- **Total estimated cost**: $15-30/month for moderate volume (1,000 documents/month)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager provides Google Cloud's native approach to infrastructure as code with built-in state management and Google Cloud integration.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/compliance-automation \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/compliance-automation
```

### Using Terraform

Terraform provides cross-cloud infrastructure management with extensive provider ecosystem and state management capabilities.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure changes
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View important outputs
terraform output
```

#### Terraform Variables

Key variables you can customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `input_bucket_name`: Name for document input bucket
- `processed_bucket_name`: Name for processed documents bucket  
- `reports_bucket_name`: Name for compliance reports bucket
- `processor_memory`: Memory allocation for document processor function (default: 1GB)
- `notification_email`: Email address for compliance alerts

### Using Bash Scripts

Bash scripts provide direct CLI-based provisioning with step-by-step resource creation and detailed logging.

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./deploy.sh

# The script will:
# 1. Enable required APIs  
# 2. Create Cloud Storage buckets
# 3. Deploy Document AI processor
# 4. Deploy Cloud Functions
# 5. Configure Cloud Scheduler jobs
# 6. Set up IAM permissions
# 7. Configure monitoring and alerting
```

## Architecture Overview

The deployed infrastructure creates the following components:

### Core Services
- **Document AI Processor**: Form parser for extracting structured data from compliance documents
- **Cloud Storage Buckets**: Secure storage for input documents, processed results, and generated reports
- **Cloud Functions**: Serverless processing for document analysis and report generation
- **Cloud Scheduler**: Automated job scheduling for compliance workflows

### Supporting Infrastructure
- **IAM Roles**: Service accounts and permissions for secure service integration
- **Cloud Monitoring**: Metrics, logging, and alerting for operational visibility
- **Cloud Logging**: Comprehensive audit trails for regulatory compliance

### Data Flow
1. Documents uploaded to input bucket trigger Cloud Function
2. Document AI extracts structured data and validates compliance
3. Processed results stored in structured format
4. Scheduled reports aggregate compliance data
5. Alerts notify stakeholders of violations or processing issues

## Validation & Testing

After deployment, validate the infrastructure:

### Test Document Processing
```bash
# Upload a sample document
gsutil cp sample_contract.pdf gs://your-input-bucket/

# Check processing results
gsutil ls gs://your-processed-bucket/processed/

# View extracted compliance data
gsutil cat gs://your-processed-bucket/processed/sample_contract_processed.json
```

### Test Report Generation
```bash
# Manually trigger report generation
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{"report_type": "daily"}' \
    "https://us-central1-your-project.cloudfunctions.net/report-generator-function"

# Check generated reports
gsutil ls gs://your-reports-bucket/reports/
```

### Verify Scheduler Jobs
```bash
# List active scheduler jobs
gcloud scheduler jobs list --location=us-central1

# Check job execution history
gcloud scheduler jobs describe compliance-scheduler-daily --location=us-central1
```

## Customization

### Document AI Configuration

Modify the Document AI processor type for specialized document processing:

```bash
# Available processor types
gcloud documentai processor-types list --location=us-central1

# Update processor type in your IaC configuration
# Examples: FORM_PARSER_PROCESSOR, INVOICE_PROCESSOR, CONTRACT_PROCESSOR
```

### Compliance Rules Customization

The Cloud Functions include configurable compliance validation rules. Customize these in the function source code:

- Required field validation
- Date format validation  
- Compliance keyword detection
- Industry-specific validation rules

### Scheduling Configuration

Modify scheduler jobs for different compliance reporting frequencies:

```bash
# Daily: "0 8 * * *" (8 AM daily)
# Weekly: "0 9 * * 1" (9 AM Monday)  
# Monthly: "0 10 1 * *" (10 AM first day of month)
# Quarterly: "0 10 1 */3 *" (10 AM first day of quarter)
```

### Monitoring and Alerting

Customize alerting thresholds and notification channels:

- Compliance violation thresholds
- Processing error rates
- Document volume anomalies
- Performance degradation alerts

## Security Considerations

### Data Protection
- Documents encrypted at rest and in transit
- VPC Service Controls for enhanced security perimeter
- Cloud KMS integration for envelope encryption
- IAM conditions for fine-grained access control

### Compliance Features
- Audit logging for all document processing activities
- Data residency controls for regulatory requirements
- HIPAA and FedRAMP compliant processing with Document AI
- Retention policies aligned with regulatory frameworks

### Access Controls
- Least privilege IAM roles for all service accounts
- Service-to-service authentication using Google Cloud IAM
- No long-lived credentials or API keys required
- Integration with Cloud Identity for user management

## Monitoring and Observability

### Cloud Monitoring Metrics
- Document processing throughput and latency
- Compliance violation rates and trends
- Function execution success rates
- Storage utilization and costs

### Cloud Logging
- Comprehensive audit trails for regulatory compliance
- Structured logging for efficient analysis
- Log-based metrics for custom alerting
- Integration with external SIEM systems

### Alerting Policies
- High compliance violation rates
- Document processing failures
- Scheduler job failures
- Resource quota approaching limits

## Cleanup

### Using Infrastructure Manager
```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/compliance-automation

# Verify cleanup completion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify state is clean
terraform show
```

### Using Bash Scripts
```bash
cd scripts/

# Run cleanup script
./destroy.sh

# The script will:
# 1. Delete Cloud Scheduler jobs
# 2. Remove Cloud Functions  
# 3. Delete Document AI processor
# 4. Remove Cloud Storage buckets and contents
# 5. Clean up IAM bindings
# 6. Delete monitoring resources
```

### Manual Cleanup Verification
```bash
# Verify no resources remain
gcloud functions list --regions=us-central1
gcloud scheduler jobs list --location=us-central1
gcloud documentai processors list --location=us-central1
gsutil ls

# Check for any remaining IAM bindings
gcloud projects get-iam-policy your-project-id
```

## Troubleshooting

### Common Issues

#### API Not Enabled Error
```bash
# Enable required APIs
gcloud services enable documentai.googleapis.com cloudfunctions.googleapis.com cloudscheduler.googleapis.com storage.googleapis.com
```

#### Permission Denied Errors
```bash
# Verify service account permissions
gcloud projects get-iam-policy your-project-id --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:serviceAccount"
```

#### Function Deployment Timeouts
```bash
# Check function logs for deployment issues
gcloud functions logs read document-processor --region=us-central1 --limit=50
```

#### Document Processing Failures
```bash
# Review Document AI processor quota and limits
gcloud documentai processors describe your-processor-id --location=us-central1

# Check Cloud Function error logs
gcloud logging read 'resource.type="cloud_function" AND severity="ERROR"' --limit=20
```

### Performance Optimization

#### Document Processing
- Batch document uploads for improved throughput
- Use appropriate Document AI processor types for document categories
- Configure function memory based on document size and complexity
- Implement retry logic for transient failures

#### Cost Optimization  
- Use Cloud Storage lifecycle policies for document archival
- Configure function concurrency limits to control costs
- Implement document deduplication before processing
- Monitor and optimize Document AI processor usage

## Support and Documentation

### Google Cloud Documentation
- [Document AI Documentation](https://cloud.google.com/document-ai/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Best Practices
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)
- [Serverless Computing Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Document AI Best Practices](https://cloud.google.com/document-ai/docs/best-practices)

### Community Resources
- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - Google Cloud Platform](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Google Cloud Slack Community](https://googlecloud-community.slack.com)

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud documentation for specific services.