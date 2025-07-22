# Infrastructure as Code for Data Privacy Compliance with Cloud Data Loss Prevention and Security Command Center

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Privacy Compliance with Cloud Data Loss Prevention and Security Command Center".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code platform
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Data Loss Prevention API
  - Security Command Center API
  - Cloud Functions
  - Pub/Sub
  - Cloud Storage
  - Cloud Logging
  - Cloud Monitoring
  - IAM Service Account management
- Basic understanding of data privacy regulations (GDPR, CCPA, HIPAA)
- Estimated cost: $50-100/month for moderate data volumes

> **Note**: Security Command Center requires Standard or Premium tier for full DLP integration and advanced threat detection capabilities.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/privacy-compliance \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-terraform-state-bucket/privacy-compliance/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Initialize and deploy
cd terraform/
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Deploy infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys a comprehensive data privacy compliance system that includes:

### Core Components

- **Cloud Data Loss Prevention (DLP)**
  - Inspection templates for PII, PHI, and financial data detection
  - Scan jobs for continuous monitoring of Cloud Storage resources
  - Custom information type detectors for organization-specific data patterns

- **Security Command Center Integration**
  - Custom source for DLP findings aggregation
  - Automated finding creation and categorization
  - Notification configurations for high-severity violations

- **Automated Response System**
  - Cloud Functions for real-time finding processing
  - Pub/Sub messaging for reliable event distribution
  - Workload Identity for secure service authentication

- **Monitoring and Alerting**
  - Custom metrics for compliance tracking
  - Cloud Monitoring dashboards for visibility
  - Alerting policies for proactive incident response

### Data Flow

1. **Data Ingestion**: Sample sensitive data uploaded to Cloud Storage
2. **Continuous Scanning**: DLP jobs scan data sources on schedule
3. **Finding Processing**: Violations detected and classified by severity
4. **Centralized Monitoring**: Findings aggregated in Security Command Center
5. **Automated Response**: Functions trigger remediation based on severity
6. **Compliance Reporting**: Metrics and alerts provide ongoing visibility

## Configuration

### Infrastructure Manager Variables

Key configuration options in `main.yaml`:

```yaml
# Project and location settings
project_id: "your-project-id"
region: "us-central1"

# DLP configuration
dlp_inspection_template_name: "privacy-compliance-template"
scan_schedule: "0 */6 * * *"  # Every 6 hours

# Security severity thresholds
high_risk_info_types: 
  - "US_SOCIAL_SECURITY_NUMBER"
  - "CREDIT_CARD_NUMBER"
  - "US_HEALTHCARE_NPI"

# Notification settings
alert_email: "security-team@your-organization.com"
```

### Terraform Variables

Key configuration options in `terraform.tfvars`:

```hcl
# Project configuration
project_id = "your-project-id"
region     = "us-central1"

# Resource naming
bucket_suffix     = "privacy-scan-data"
function_name     = "privacy-compliance-processor"
topic_name        = "privacy-findings"

# DLP scanning configuration
scan_schedule     = "0 */6 * * *"
min_likelihood    = "POSSIBLE"
max_findings      = 100

# Security Command Center
scc_source_name   = "Privacy Compliance Scanner"
organization_id   = "123456789"

# Monitoring configuration
enable_monitoring = true
alert_threshold   = 1
```

### Script Configuration

Environment variables for bash scripts:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ORGANIZATION_ID="123456789"

# Optional customization
export BUCKET_SUFFIX="privacy-scan-data"
export FUNCTION_NAME="privacy-compliance-processor"
export SCAN_SCHEDULE="0 */6 * * *"
```

## Post-Deployment Configuration

### 1. Security Command Center Setup

After deployment, configure Security Command Center:

```bash
# Enable Security Command Center (if not already enabled)
gcloud services enable securitycenter.googleapis.com

# Verify source creation
gcloud scc sources list --organization=${ORGANIZATION_ID}

# Configure notification channels (email, Slack, etc.)
gcloud scc notifications create critical-privacy-alerts \
    --organization=${ORGANIZATION_ID} \
    --pubsub-topic=projects/${PROJECT_ID}/topics/privacy-findings \
    --filter='severity="HIGH" AND category="DATA_LEAK"'
```

### 2. Test Data Setup

Upload test data to validate the system:

```bash
# Create sample sensitive data file
cat > test_data.txt << 'EOF'
Customer: John Doe
SSN: 123-45-6789
Email: john.doe@example.com
Credit Card: 4111-1111-1111-1111
Phone: (555) 123-4567
Medical Record: Patient ID 12345
DOB: 1985-03-15
EOF

# Upload to monitored bucket
gsutil cp test_data.txt gs://privacy-scan-data-${RANDOM_SUFFIX}/
```

### 3. Monitoring Dashboard

Access the monitoring dashboard:

```bash
# View custom metrics in Cloud Monitoring
gcloud monitoring metrics list --filter="metric.type:custom.googleapis.com/dlp"

# Check function logs
gcloud functions logs read privacy-compliance-processor --region=${REGION}
```

## Validation and Testing

### 1. Verify DLP Configuration

```bash
# List DLP inspection templates
gcloud dlp inspect-templates list --location=${REGION}

# Check DLP job status
gcloud dlp jobs list --location=${REGION}
```

### 2. Test Function Processing

```bash
# Trigger manual DLP scan
gcloud dlp jobs create \
    --location=${REGION} \
    --job-file=dlp-job-config.json

# Monitor Pub/Sub messages
gcloud pubsub subscriptions pull privacy-findings-subscription \
    --limit=5 --auto-ack
```

### 3. Verify Security Command Center Integration

```bash
# Check for findings in Security Command Center
gcloud scc findings list \
    --organization=${ORGANIZATION_ID} \
    --filter="category='DATA_LEAK'"

# Verify notifications are configured
gcloud scc notifications list --organization=${ORGANIZATION_ID}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/privacy-compliance
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Cancel running DLP jobs
gcloud dlp jobs cancel --location=${REGION} --job-filter="state:RUNNING"

# Delete test data
gsutil -m rm -r gs://privacy-scan-data-*/

# Remove local files
rm -f test_data.txt dlp-job-config.json
```

## Security Considerations

### IAM and Access Control

- **Principle of Least Privilege**: Service accounts have minimal required permissions
- **Workload Identity**: Eliminates need for service account keys
- **Resource-level Permissions**: Fine-grained access controls on all resources

### Data Protection

- **Encryption at Rest**: All data encrypted using Google-managed keys
- **Encryption in Transit**: TLS encryption for all API communications
- **Access Logging**: Comprehensive audit trails for all access

### Compliance Features

- **Data Residency**: Resources deployed in specified region
- **Retention Policies**: Configurable data retention for logs and findings
- **Audit Trails**: Complete audit logs for compliance reporting

## Troubleshooting

### Common Issues

#### DLP Jobs Failing

```bash
# Check DLP job status and errors
gcloud dlp jobs describe JOB_ID --location=${REGION}

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}
```

#### Function Processing Errors

```bash
# View detailed function logs
gcloud functions logs read privacy-compliance-processor \
    --region=${REGION} \
    --start-time=2025-01-01T00:00:00Z

# Check function configuration
gcloud functions describe privacy-compliance-processor --region=${REGION}
```

#### Security Command Center Integration Issues

```bash
# Verify organization access
gcloud organizations list

# Check source permissions
gcloud scc sources get-iam-policy SOURCE_ID --organization=${ORGANIZATION_ID}
```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Set debug environment variables
export DEBUG=true
export LOG_LEVEL=DEBUG

# Redeploy with debug settings
./scripts/deploy.sh
```

## Cost Optimization

### Resource Optimization

- **Function Memory**: Adjust based on actual usage patterns
- **DLP Scan Frequency**: Balance compliance needs with cost
- **Storage Classes**: Use appropriate storage classes for different data types
- **Log Retention**: Configure retention policies to manage costs

### Monitoring Costs

```bash
# View current costs by service
gcloud billing budgets list --billing-account=${BILLING_ACCOUNT}

# Set up budget alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT} \
    --display-name="Privacy Compliance Budget" \
    --budget-amount=100USD
```

## Extending the Solution

### Additional Data Sources

Add support for additional data sources:

- **BigQuery**: Extend DLP scanning to BigQuery datasets
- **Cloud SQL**: Include database scanning capabilities
- **Datastore**: Add NoSQL database monitoring

### Enhanced Automation

Implement advanced automation features:

- **Automatic Quarantine**: Move sensitive files to secure storage
- **Data Subject Requests**: Automate GDPR/CCPA request processing
- **Compliance Reporting**: Generate automated compliance reports

### Integration Options

Connect with external systems:

- **SIEM Integration**: Export findings to external SIEM platforms
- **Ticketing Systems**: Create automated incident tickets
- **Notification Channels**: Integrate with Slack, Teams, or PagerDuty

## Support and Documentation

### Official Documentation

- [Google Cloud DLP Documentation](https://cloud.google.com/dlp/docs)
- [Security Command Center Documentation](https://cloud.google.com/security-command-center/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)

### Best Practices

- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)
- [Data Loss Prevention Best Practices](https://cloud.google.com/dlp/docs/best-practices)
- [Security Command Center Best Practices](https://cloud.google.com/security-command-center/docs/best-practices)

### Community Resources

- [Google Cloud Community](https://cloud.google.com/community)
- [Google Cloud Architecture Center](https://cloud.google.com/architecture)
- [Google Cloud Training](https://cloud.google.com/training)

For issues with this infrastructure code, refer to the original recipe documentation or file an issue in the repository.