# Infrastructure as Code for Financial Compliance Monitoring with AML AI and BigQuery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Financial Compliance Monitoring with AML AI and BigQuery".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 450.0.0 or later)
- Google Cloud project with billing enabled
- Owner or Editor permissions on the target project
- Basic understanding of BigQuery, ML, and financial compliance concepts
- Estimated cost: $50-100 for BigQuery processing, ML training, and Cloud Functions execution

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/aml-compliance-deployment \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="inputs.yaml"
```

### Using Terraform

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export TF_VAR_project_id=${PROJECT_ID}

# Initialize and apply Terraform configuration
cd terraform/
terraform init
terraform plan -var="project_id=${PROJECT_ID}"
terraform apply -var="project_id=${PROJECT_ID}"
```

### Using Bash Scripts

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Make scripts executable and deploy
chmod +x scripts/deploy.sh scripts/destroy.sh
./scripts/deploy.sh
```

## Configuration Variables

### Infrastructure Manager Variables (inputs.yaml)

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `dataset_name`: BigQuery dataset name (default: aml_compliance_data)
- `bucket_name_suffix`: Unique suffix for storage bucket
- `enable_monitoring`: Enable Cloud Monitoring (default: true)

### Terraform Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `dataset_name`: BigQuery dataset name (default: aml_compliance_data)
- `enable_versioning`: Enable storage bucket versioning (default: true)

## Deployed Resources

This infrastructure creates the following Google Cloud resources:

### Data & Analytics
- **BigQuery Dataset**: `aml_compliance_data` with tables for transactions and compliance alerts
- **BigQuery ML Model**: `aml_detection_model` for suspicious transaction detection
- **Cloud Storage Bucket**: Secure storage for compliance reports with versioning enabled

### Compute & Functions
- **Cloud Functions**: 
  - Alert processing function (2nd gen, Python 3.11)
  - Compliance report generator (2nd gen, Python 3.11)
- **Cloud Scheduler**: Daily compliance report generation job

### Messaging & Events
- **Pub/Sub Topic**: `aml-alerts` for real-time alert processing
- **Pub/Sub Subscription**: Alert processing subscription

### Security & Monitoring
- **IAM Service Accounts**: Dedicated service accounts with least privilege access
- **IAM Bindings**: Proper permissions for BigQuery, Storage, and Functions
- **Cloud Monitoring**: Metrics and alerting for compliance workflows

## Architecture Overview

The deployed infrastructure implements a complete AML compliance monitoring system:

1. **Data Ingestion**: Transaction data flows into BigQuery tables
2. **ML Analysis**: BigQuery ML models analyze patterns for suspicious activity
3. **Alert Processing**: Pub/Sub and Cloud Functions handle real-time alerts
4. **Compliance Reporting**: Automated daily reports stored in Cloud Storage
5. **Monitoring**: Cloud Monitoring tracks system health and compliance metrics

## Post-Deployment Setup

After infrastructure deployment, complete these steps:

1. **Load Sample Data** (if testing):
   ```bash
   # Upload sample transaction data to BigQuery
   bq load --source_format=NEWLINE_DELIMITED_JSON \
       ${PROJECT_ID}:aml_compliance_data.transactions \
       sample_transactions.json
   ```

2. **Train ML Model**:
   ```bash
   # Execute ML model training query
   bq query --use_legacy_sql=false < ml_model_training.sql
   ```

3. **Test Alert Processing**:
   ```bash
   # Send test alert to Pub/Sub
   echo '{"transaction_id":"TEST001","risk_score":0.9}' | \
       gcloud pubsub topics publish aml-alerts --message=-
   ```

4. **Verify Scheduler Job**:
   ```bash
   # Check scheduler job status
   gcloud scheduler jobs describe daily-compliance-report
   ```

## Security Considerations

### Data Protection
- All BigQuery datasets encrypted with Google-managed keys
- Cloud Storage buckets configured with secure access controls
- IAM policies follow least privilege principle

### Access Controls
- Service accounts with minimal required permissions
- Cloud Functions run with dedicated service accounts
- Bucket access restricted to compliance team and automation

### Compliance Features
- Audit logging enabled for all resource access
- Data retention policies configured for regulatory requirements
- Versioning enabled for compliance report storage

## Monitoring & Alerting

### Built-in Monitoring
- Cloud Functions execution metrics and error rates
- BigQuery job performance and cost monitoring
- Pub/Sub message processing latency
- Cloud Scheduler job success/failure rates

### Custom Metrics
- AML alert processing volume
- Compliance report generation status
- ML model prediction accuracy
- False positive rates

### Recommended Alerts
- Failed compliance report generation
- High alert processing latency
- BigQuery job failures
- Unusual transaction volume patterns

## Cost Optimization

### Resource Sizing
- Cloud Functions configured with optimal memory allocation (256MB-512MB)
- BigQuery tables use partitioning for cost-effective queries
- Cloud Storage lifecycle policies for report retention

### Cost Monitoring
- Budget alerts configured for BigQuery ML training costs
- Storage costs tracked with detailed breakdowns
- Function execution costs monitored per invocation

### Optimization Tips
- Use BigQuery partitioning on transaction timestamp
- Implement table clustering on frequently queried fields
- Configure Cloud Storage lifecycle policies for old reports
- Monitor ML model retraining frequency

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **BigQuery Quota Exceeded**:
   ```bash
   # Check current BigQuery usage
   bq ls -j --max_results=10
   ```

3. **Function Deployment Failures**:
   ```bash
   # Check function logs
   gcloud functions logs read process-aml-alerts --gen2 --limit=50
   ```

4. **Pub/Sub Message Backlog**:
   ```bash
   # Monitor subscription metrics
   gcloud pubsub subscriptions describe aml-alerts-subscription
   ```

### Debugging Commands

```bash
# View BigQuery job history
bq ls -j --max_results=20

# Check Cloud Function status
gcloud functions describe process-aml-alerts --gen2

# Monitor Pub/Sub metrics
gcloud monitoring metrics list --filter="resource.type=pubsub_topic"

# Check scheduler job execution
gcloud scheduler jobs describe daily-compliance-report
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/aml-compliance-deployment
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete BigQuery dataset
bq rm -r -f ${PROJECT_ID}:aml_compliance_data

# Delete Cloud Storage bucket
gsutil -m rm -r gs://aml-reports-*

# Delete Cloud Functions
gcloud functions delete process-aml-alerts --gen2 --quiet
gcloud functions delete compliance-report-generator --gen2 --quiet

# Delete Pub/Sub resources
gcloud pubsub subscriptions delete aml-alerts-subscription --quiet
gcloud pubsub topics delete aml-alerts --quiet

# Delete Cloud Scheduler job
gcloud scheduler jobs delete daily-compliance-report --quiet
```

## Customization

### Extending the Solution

1. **Additional ML Models**: Add more sophisticated ML models in BigQuery ML
2. **Real-time Processing**: Integrate with Dataflow for stream processing
3. **External Integrations**: Add connectors to external AML systems
4. **Enhanced Reporting**: Create custom dashboards with Looker Studio
5. **Multi-region Deployment**: Deploy across multiple regions for redundancy

### Configuration Examples

```yaml
# Custom inputs.yaml for Infrastructure Manager
project_id: "my-aml-project"
region: "us-east1"
dataset_name: "custom_aml_data"
bucket_name_suffix: "prod-2025"
enable_monitoring: true
alert_notification_email: "compliance@company.com"
```

```bash
# Custom Terraform variables
export TF_VAR_project_id="my-aml-project"
export TF_VAR_region="us-east1"
export TF_VAR_dataset_name="custom_aml_data"
export TF_VAR_enable_versioning=true
export TF_VAR_retention_days=2555  # 7 years for compliance
```

## Compliance & Regulatory Support

### Supported Frameworks
- Bank Secrecy Act (BSA) / Anti-Money Laundering (AML)
- Financial Action Task Force (FATF) recommendations
- EU Anti-Money Laundering Directives
- SOX compliance for financial reporting

### Audit Features
- Complete audit trail through Cloud Audit Logs
- Immutable compliance report storage
- Detailed transaction lineage tracking
- Regulatory report export capabilities

### Data Retention
- Configurable retention policies for compliance data
- Automated archival to cost-effective storage classes
- Legal hold capabilities for ongoing investigations
- Secure deletion for data subject requests

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for solution architecture details
2. **Google Cloud Documentation**: [Financial Services Solutions](https://cloud.google.com/solutions/financial-services)
3. **BigQuery ML**: [Machine Learning Documentation](https://cloud.google.com/bigquery/docs/bigqueryml)
4. **Infrastructure Manager**: [Google Cloud Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
5. **Terraform Google Provider**: [Official Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Version History

- **v1.0**: Initial Infrastructure Manager, Terraform, and Bash implementations
- **v1.1**: Added enhanced monitoring and cost optimization features
- **Recipe Version**: 1.1 (Financial Compliance Monitoring with AML AI and BigQuery)