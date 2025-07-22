# Healthcare Data Processing with Cloud Batch and Vertex AI Agents - Terraform

This Terraform configuration deploys a complete healthcare data processing infrastructure on Google Cloud Platform, featuring HIPAA-compliant data handling, AI-powered analysis, and FHIR-standard medical record processing.

## Architecture Overview

The infrastructure includes:

- **HIPAA-compliant Cloud Storage** for secure medical record ingestion
- **Cloud Healthcare API** with FHIR R4 store for standardized data storage
- **Cloud Batch** for scalable processing job orchestration
- **Cloud Functions** for event-driven processing triggers
- **Vertex AI** integration for intelligent medical record analysis
- **Comprehensive monitoring** and compliance tracking
- **Audit logging** for regulatory compliance

## Prerequisites

1. **Google Cloud Project** with billing enabled
2. **Terraform** >= 1.5 installed
3. **gcloud CLI** installed and authenticated
4. Required **IAM permissions**:
   - Project Owner or Editor
   - Healthcare API Admin
   - Storage Admin
   - Cloud Functions Admin
   - Vertex AI User

## Required APIs

The following APIs will be automatically enabled:

- Healthcare API (`healthcare.googleapis.com`)
- Cloud Batch API (`batch.googleapis.com`)
- Vertex AI API (`aiplatform.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Eventarc API (`eventarc.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd gcp/healthcare-data-processing-batch-vertex-ai-agents/code/terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your configuration
vim terraform.tfvars
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 3. Verify Deployment

```bash
# Check the outputs
terraform output

# Test file upload (creates a sample medical record)
echo '{"patient_id":"TEST_001","encounter_date":"2025-01-15","diagnosis":"routine_checkup"}' > sample_record.json
gsutil cp sample_record.json gs://$(terraform output -raw healthcare_bucket_name)/test/

# Monitor batch job creation
gcloud batch jobs list --location=$(terraform output -raw region)
```

## Configuration

### Required Variables

```hcl
# terraform.tfvars
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"
```

### Optional Customization

```hcl
# Environment and naming
environment = "prod"
healthcare_bucket_prefix = "hipaa-medical-data"

# Resource scaling
batch_job_machine_type = "n2-standard-4"
function_max_instances = 20

# Compliance settings
healthcare_data_retention_days = 2920  # 8 years
enable_deletion_protection = true
```

See `terraform.tfvars.example` for complete configuration options.

## HIPAA Compliance Features

### Data Security
- **Encryption at rest** with Google-managed keys
- **Encryption in transit** with TLS 1.2+
- **Uniform bucket-level access** for enhanced security
- **Service account isolation** with least privilege

### Audit and Monitoring
- **Comprehensive audit logging** to BigQuery
- **Real-time compliance monitoring** with alerts
- **Data access tracking** for all healthcare resources
- **Automated compliance violation detection**

### Data Retention
- **7+ year retention** for healthcare data (configurable)
- **Versioning enabled** for data integrity
- **Lifecycle policies** for cost optimization
- **Secure deletion** after retention period

## Monitoring and Alerts

### Built-in Dashboards
- Healthcare processing metrics
- Batch job success rates
- FHIR store operations
- Compliance status tracking

### Alert Policies
- HIPAA compliance violations
- Batch job failures
- Resource quota exceeded
- Security anomalies

### Accessing Monitoring

```bash
# View monitoring dashboard
echo "Dashboard: https://console.cloud.google.com/monitoring/dashboards/custom/$(terraform output -raw monitoring_dashboard_id)"

# Check alert policies
gcloud alpha monitoring policies list --filter="displayName~'Healthcare'"
```

## Operations

### Processing Healthcare Data

1. **Upload medical records** to the healthcare data bucket:
   ```bash
   gsutil cp medical_record.json gs://$(terraform output -raw healthcare_bucket_name)/
   ```

2. **Monitor processing** through Cloud Functions logs:
   ```bash
   gcloud functions logs read $(terraform output -raw cloud_function_name) --limit=50
   ```

3. **View processed data** in the FHIR store:
   ```bash
   gcloud healthcare fhir-stores describe $(terraform output -raw fhir_store_name) \
     --dataset=$(terraform output -raw healthcare_dataset_name) \
     --location=$(terraform output -raw region)
   ```

### Compliance Monitoring

```bash
# View audit logs in BigQuery
bq query --use_legacy_sql=false "
SELECT timestamp, protoPayload.methodName, protoPayload.authenticationInfo
FROM \`$(terraform output -raw project_id).$(terraform output -raw healthcare_analytics_dataset_id).cloudaudit_googleapis_com_activity\`
WHERE resource.type = 'healthcare_dataset'
ORDER BY timestamp DESC
LIMIT 10"
```

### Troubleshooting

```bash
# Check batch job status
gcloud batch jobs describe JOB_NAME --location=$(terraform output -raw region)

# View Cloud Function errors
gcloud functions logs read $(terraform output -raw cloud_function_name) \
  --filter="severity>=ERROR" --limit=20

# Check API quotas
gcloud logging read "protoPayload.methodName:quota" --limit=10
```

## Cost Optimization

### Recommended Practices

1. **Use lifecycle policies** for long-term storage cost reduction
2. **Monitor batch job resource usage** and adjust machine types
3. **Set function timeout limits** to prevent overruns
4. **Use preemptible instances** for non-critical batch processing
5. **Implement data archival** after retention requirements

### Cost Monitoring

```bash
# View current month's costs
gcloud billing budgets list --billing-account=YOUR_BILLING_ACCOUNT

# Check resource usage
gcloud monitoring metrics list --filter="metric.type:compute"
```

## Security Best Practices

### Access Control
- Use **service accounts** with minimal required permissions
- Enable **audit logging** for all resource access
- Implement **VPC Service Controls** for sensitive environments
- Use **IAM conditions** for time-based access

### Data Protection
- Enable **DLP scanning** for PHI detection
- Use **customer-managed encryption keys** for enhanced security
- Implement **data loss prevention** policies
- Regular **security assessments** and compliance audits

## Backup and Disaster Recovery

### Automated Backups
- FHIR store data is automatically replicated
- Storage bucket versioning provides data recovery
- Audit logs stored in BigQuery for long-term retention

### Recovery Procedures
```bash
# Restore from bucket version
gsutil cp gs://bucket/object#generation gs://bucket/object

# Export FHIR data for backup
gcloud healthcare fhir-stores export gcs $(terraform output -raw fhir_store_name) \
  --dataset=$(terraform output -raw healthcare_dataset_name) \
  --location=$(terraform output -raw region) \
  --gcs-uri=gs://backup-bucket/fhir-export/
```

## Cleanup

### Destroy Infrastructure

⚠️ **Warning**: This will permanently delete all healthcare data and resources.

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy

# Confirm all resources are deleted
gcloud healthcare datasets list
gcloud storage buckets list --filter="name~healthcare"
```

### Partial Cleanup

```bash
# Delete only batch jobs
gcloud batch jobs delete JOB_NAME --location=$(terraform output -raw region)

# Clear storage bucket (keeping the bucket)
gsutil -m rm -r gs://$(terraform output -raw healthcare_bucket_name)/*
```

## Support and Documentation

- [Google Cloud Healthcare API Documentation](https://cloud.google.com/healthcare-api/docs)
- [Cloud Batch Documentation](https://cloud.google.com/batch/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [HIPAA Compliance on Google Cloud](https://cloud.google.com/security/compliance/hipaa)
- [FHIR Implementation Guide](https://cloud.google.com/healthcare-api/docs/concepts/fhir)

## Contributing

When modifying this configuration:

1. Test changes in a development environment first
2. Ensure HIPAA compliance requirements are maintained
3. Update documentation for any new features
4. Run `terraform validate` and `terraform plan` before applying
5. Consider the impact on existing healthcare data

## License

This Terraform configuration is provided as-is for educational and development purposes. Ensure compliance with your organization's security and regulatory requirements before using in production healthcare environments.