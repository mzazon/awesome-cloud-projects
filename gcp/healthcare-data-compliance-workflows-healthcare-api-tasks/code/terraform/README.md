# Healthcare Data Compliance Workflows with Cloud Healthcare API and Cloud Tasks - Terraform Implementation

This Terraform configuration deploys a comprehensive healthcare data compliance solution on Google Cloud Platform, implementing automated PHI access validation, audit workflows, and compliance monitoring using Cloud Healthcare API, Cloud Tasks, Cloud Functions, and Cloud Audit Logs.

## Architecture Overview

The solution deploys the following components:

- **Cloud Healthcare API**: HIPAA-compliant FHIR store for healthcare data
- **Cloud Tasks**: Reliable queue for compliance processing workflows
- **Cloud Functions**: Serverless processing for compliance validation and audit
- **Cloud Pub/Sub**: Event-driven notifications for FHIR store changes
- **Cloud Storage**: Secure storage for compliance artifacts and reports
- **BigQuery**: Analytics platform for compliance reporting and insights
- **Cloud Monitoring**: Alerting and monitoring for compliance violations

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: A GCP project with billing enabled
2. **Google Cloud CLI**: Install and configure `gcloud` CLI
3. **Terraform**: Install Terraform >= 1.0
4. **IAM Permissions**: Ensure your account has the following roles:
   - Project Editor or Owner
   - Healthcare API Admin
   - Cloud Functions Admin
   - Cloud Tasks Admin
   - Storage Admin
   - BigQuery Admin
   - Pub/Sub Admin
   - Monitoring Admin

5. **Business Associate Agreement (BAA)**: Execute a BAA with Google Cloud before processing real PHI data

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/healthcare-data-compliance-workflows-healthcare-api-tasks/code/terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Resource configuration
resource_prefix = "healthcare-compliance"
environment     = "dev"

# Healthcare API settings
healthcare_dataset_location = "us-central1"
fhir_version               = "R4"
enable_update_create       = true

# Function configuration
function_runtime     = "python39"
function_memory      = 512
function_timeout     = 540
function_max_instances = 10

# Storage configuration
storage_class = "STANDARD"
storage_lifecycle_age_nearline = 30
storage_lifecycle_age_coldline = 365

# Monitoring configuration
enable_monitoring_alerts = true
notification_email      = "your-compliance-team@example.com"
alert_threshold_value   = 3

# Labels
labels = {
  managed_by    = "terraform"
  project_type  = "healthcare-compliance"
  compliance    = "hipaa"
  environment   = "dev"
}
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

After successful deployment, verify the resources:

```bash
# Check Healthcare dataset
gcloud healthcare datasets list --location=us-central1

# Check FHIR store
gcloud healthcare fhir-stores list --dataset=<dataset-name> --location=us-central1

# Check Cloud Functions
gcloud functions list --region=us-central1

# Check BigQuery dataset
bq ls
```

## Configuration

### Required Variables

| Variable | Description | Type | Required |
|----------|-------------|------|----------|
| `project_id` | GCP project ID | `string` | Yes |
| `region` | GCP region for resources | `string` | Yes |

### Optional Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `resource_prefix` | Prefix for resource names | `string` | `"healthcare-compliance"` |
| `environment` | Environment name | `string` | `"dev"` |
| `fhir_version` | FHIR version for store | `string` | `"R4"` |
| `function_runtime` | Cloud Functions runtime | `string` | `"python39"` |
| `function_memory` | Memory allocation (MB) | `number` | `512` |
| `function_timeout` | Function timeout (seconds) | `number` | `540` |
| `storage_class` | Storage class for bucket | `string` | `"STANDARD"` |
| `enable_monitoring_alerts` | Enable monitoring alerts | `bool` | `true` |
| `notification_email` | Email for alerts | `string` | `"compliance@example.com"` |

See `variables.tf` for a complete list of configurable options.

## Outputs

After deployment, the following outputs will be available:

### Healthcare API
- `healthcare_dataset_id`: Healthcare dataset ID
- `fhir_store_id`: FHIR store ID
- `fhir_store_endpoint`: FHIR store API endpoint

### Cloud Functions
- `compliance_processor_function_name`: Main compliance processor function
- `compliance_audit_function_name`: Audit processing function
- `compliance_audit_function_url`: Audit function HTTP endpoint

### Storage and Analytics
- `compliance_bucket_name`: Compliance artifacts bucket
- `bigquery_dataset_id`: BigQuery dataset for analytics
- `compliance_events_table_id`: Compliance events table
- `audit_trail_table_id`: Audit trail table

### Example Commands
- `example_fhir_create_command`: Sample FHIR resource creation
- `example_bigquery_query`: Sample compliance analytics query

## Testing the Solution

### 1. Create a Test FHIR Resource

Use the output command to create a test patient:

```bash
# Get the example command from Terraform output
terraform output example_fhir_create_command

# Execute the command to create a test patient
curl -X POST "https://healthcare.googleapis.com/v1/projects/PROJECT_ID/locations/us-central1/datasets/DATASET_ID/fhirStores/FHIR_STORE_ID/fhir/Patient" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/fhir+json" \
  -d '{
    "resourceType": "Patient",
    "id": "test-patient-001",
    "name": [{"family": "Doe", "given": ["John"]}],
    "gender": "male",
    "birthDate": "1990-01-01"
  }'
```

### 2. Verify Compliance Processing

Check that the compliance event was processed:

```bash
# Check Cloud Functions logs
gcloud functions logs read FUNCTION_NAME --region=us-central1 --limit=10

# Check BigQuery for compliance events
bq query --use_legacy_sql=false 'SELECT * FROM `PROJECT_ID.DATASET_ID.compliance_events` ORDER BY timestamp DESC LIMIT 5'

# Check Cloud Storage for compliance artifacts
gsutil ls -r gs://BUCKET_NAME/compliance-events/
```

### 3. Test Pub/Sub Processing

Send a test message to trigger compliance processing:

```bash
# Get the example command from Terraform output
terraform output example_pubsub_test_command

# Execute the test command
gcloud pubsub topics publish TOPIC_NAME \
  --message='{"resourceName":"Patient/test-patient-001","eventType":"CREATE","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}'
```

### 4. Verify Monitoring

Check that monitoring alerts are configured:

```bash
# List monitoring policies
gcloud alpha monitoring policies list

# Check notification channels
gcloud alpha monitoring channels list
```

## Security Considerations

This implementation follows healthcare security best practices:

1. **HIPAA Compliance**: Uses Google Cloud Healthcare API with HIPAA compliance
2. **Encryption**: Enables encryption at rest and in transit
3. **Access Control**: Implements least privilege IAM policies
4. **Audit Logging**: Comprehensive audit trail for all PHI access
5. **Network Security**: Uses VPC and firewall rules where applicable
6. **Data Retention**: Configurable retention policies for compliance data

### Important Security Notes

- **BAA Required**: Execute a Business Associate Agreement with Google Cloud
- **Real PHI**: Never use real PHI data in development/testing environments
- **Access Review**: Regularly review and audit access permissions
- **Monitoring**: Monitor all compliance alerts and investigate anomalies
- **Incident Response**: Implement incident response procedures for compliance violations

## Compliance Features

### Automated Compliance Monitoring
- Real-time PHI access validation
- Risk scoring for healthcare operations
- Automated audit trail generation
- Compliance violation detection

### Audit Capabilities
- Comprehensive event logging
- Detailed audit reports for high-risk events
- BigQuery analytics for compliance insights
- Automated compliance reporting

### Monitoring and Alerting
- Real-time monitoring of compliance metrics
- Automated alerts for high-risk events
- Integration with existing monitoring systems
- Customizable alert thresholds

## Cost Optimization

### Estimated Costs
- **Development/Testing**: $15-25 per day
- **Production**: Varies based on data volume and processing frequency

### Cost Optimization Features
- **Storage Lifecycle**: Automatic transition to cheaper storage classes
- **Function Scaling**: Pay-per-use serverless functions
- **BigQuery**: On-demand querying with slot reservations for predictable workloads
- **Monitoring**: Efficient alerting to minimize notification costs

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable healthcare.googleapis.com
   gcloud services enable cloudtasks.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Add required roles
   gcloud projects add-iam-policy-binding PROJECT_ID \
     --member="user:YOUR_EMAIL" \
     --role="roles/healthcare.admin"
   ```

3. **Function Deployment Failures**
   ```bash
   # Check function logs
   gcloud functions logs read FUNCTION_NAME --region=REGION
   
   # Verify service account permissions
   gcloud projects get-iam-policy PROJECT_ID
   ```

4. **BigQuery Access Issues**
   ```bash
   # Verify dataset exists
   bq ls
   
   # Check table schema
   bq show PROJECT_ID:DATASET_ID.TABLE_ID
   ```

### Debugging Steps

1. **Check Terraform State**
   ```bash
   terraform state list
   terraform state show RESOURCE_NAME
   ```

2. **Verify Resource Creation**
   ```bash
   gcloud healthcare datasets list --location=us-central1
   gcloud functions list --region=us-central1
   gcloud tasks queues list --location=us-central1
   ```

3. **Review Logs**
   ```bash
   # Cloud Functions logs
   gcloud functions logs read FUNCTION_NAME --region=REGION
   
   # Audit logs
   gcloud logging read "protoPayload.serviceName=healthcare.googleapis.com" --limit=10
   ```

## Maintenance

### Regular Maintenance Tasks

1. **Update Dependencies**
   ```bash
   # Update Terraform providers
   terraform init -upgrade
   
   # Update function dependencies
   # Edit function_templates/requirements.txt and redeploy
   ```

2. **Monitor Compliance**
   ```bash
   # Check compliance metrics
   bq query --use_legacy_sql=false 'SELECT compliance_level, COUNT(*) FROM `PROJECT_ID.DATASET_ID.audit_trail` GROUP BY compliance_level'
   
   # Review high-risk events
   bq query --use_legacy_sql=false 'SELECT * FROM `PROJECT_ID.DATASET_ID.compliance_events` WHERE risk_score >= 4'
   ```

3. **Clean Up Old Data**
   ```bash
   # Review storage usage
   gsutil du -h gs://BUCKET_NAME
   
   # Clean up old compliance artifacts (if appropriate)
   gsutil rm -r gs://BUCKET_NAME/compliance-events/2023/
   ```

### Scaling Considerations

- **High Volume**: Increase function memory and max instances
- **Multi-Region**: Deploy across multiple regions for disaster recovery
- **Data Retention**: Adjust BigQuery and Storage lifecycle policies
- **Performance**: Monitor function execution times and optimize code

## Support

For issues with this infrastructure:

1. **Check Documentation**: Review Google Cloud Healthcare API documentation
2. **Terraform Issues**: Consult Terraform Google Cloud Provider documentation
3. **Healthcare Compliance**: Refer to Google Cloud HIPAA compliance guides
4. **Function Issues**: Check Cloud Functions troubleshooting guides

## Cleanup

To remove all resources:

```bash
# Destroy all resources
terraform destroy

# Verify cleanup
gcloud healthcare datasets list --location=us-central1
gcloud functions list --region=us-central1
gsutil ls
```

**Warning**: This will permanently delete all healthcare data and compliance artifacts. Ensure you have appropriate backups before proceeding.

## Additional Resources

- [Google Cloud Healthcare API Documentation](https://cloud.google.com/healthcare-api/docs)
- [HIPAA Compliance on Google Cloud](https://cloud.google.com/security/compliance/hipaa)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [BigQuery for Healthcare Analytics](https://cloud.google.com/healthcare-api/docs/how-tos/bigquery)
- [Cloud Tasks Documentation](https://cloud.google.com/tasks/docs)