# Medical Imaging Analysis with Healthcare API and Vision AI - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete medical imaging analysis pipeline using Google Cloud Healthcare API and Vision AI services.

## Architecture Overview

The infrastructure deploys:

- **Healthcare API Dataset**: HIPAA-compliant container for medical data
- **DICOM Store**: Specialized storage for medical imaging data (DICOM format)
- **FHIR Store**: Storage for structured healthcare data and analysis results
- **Cloud Storage**: Staging area for image processing workflow
- **Cloud Functions**: Serverless processing engine for image analysis
- **Pub/Sub**: Event-driven messaging for pipeline coordination
- **Vision AI**: AI-powered image analysis and anomaly detection
- **Monitoring**: Comprehensive logging, metrics, and alerting

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Project**: With billing enabled and appropriate quotas
2. **Terraform**: Version 1.0 or later installed
3. **Google Cloud CLI**: Installed and authenticated
4. **Permissions**: Project Owner or Editor role, plus Healthcare API access
5. **APIs**: The required APIs will be enabled automatically during deployment

### Required Permissions

Your account needs the following roles:
- `roles/owner` or `roles/editor` (for resource creation)
- `roles/healthcare.datasetAdmin` (for Healthcare API resources)
- `roles/iam.serviceAccountAdmin` (for service account management)

## Quick Start

### 1. Clone and Navigate

```bash
cd terraform/
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
dataset_id              = "medical-imaging-dataset"
dicom_store_id         = "medical-dicom-store"
fhir_store_id          = "medical-fhir-store"
bucket_name_prefix     = "medical-imaging-bucket"
function_name          = "medical-image-processor"
service_account_name   = "medical-imaging-sa"

# Monitoring and alerting
enable_monitoring = true
alert_email      = "your-email@example.com"  # Optional

# Environment and labeling
environment = "dev"
common_labels = {
  project     = "medical-imaging-analysis"
  environment = "dev"
  managed-by  = "terraform"
  use-case    = "healthcare-ai"
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

After successful deployment, verify the resources:

```bash
# Check Healthcare dataset
terraform output verification_commands

# Use the output commands to verify each component
gcloud healthcare datasets describe medical-imaging-dataset --location=us-central1
```

## Configuration Options

### Healthcare API Configuration

```hcl
# Healthcare dataset and stores
variable "dataset_id" {
  description = "ID for the healthcare dataset"
  type        = string
  default     = "medical-imaging-dataset"
}

variable "fhir_version" {
  description = "FHIR version (DSTU2, STU3, or R4)"
  type        = string
  default     = "R4"
}
```

### Cloud Function Configuration

```hcl
# Function performance settings
variable "function_memory" {
  description = "Memory allocated to Cloud Function (MB)"
  type        = number
  default     = 512  # Options: 128, 256, 512, 1024, 2048, 4096, 8192
}

variable "function_timeout" {
  description = "Function timeout (seconds)"
  type        = number
  default     = 540  # Maximum: 540 seconds
}
```

### Storage Configuration

```hcl
# Storage settings
variable "bucket_storage_class" {
  description = "Storage class for the bucket"
  type        = string
  default     = "STANDARD"  # Options: STANDARD, NEARLINE, COLDLINE, ARCHIVE
}

variable "enable_bucket_versioning" {
  description = "Enable bucket versioning"
  type        = bool
  default     = true
}
```

## Security Features

### HIPAA Compliance

The infrastructure implements several security measures for HIPAA compliance:

1. **Encryption**: All data encrypted at rest and in transit
2. **Access Controls**: Principle of least privilege with IAM
3. **Audit Logging**: Comprehensive audit trails
4. **Network Security**: Private communication between services
5. **Data Classification**: Proper labeling and organization

### Service Account Security

```hcl
# Minimal required permissions
healthcare_admin    = "roles/healthcare.datasetAdmin"
ml_developer       = "roles/ml.developer"
storage_admin      = "roles/storage.objectAdmin"
functions_developer = "roles/cloudfunctions.developer"
pubsub_editor      = "roles/pubsub.editor"
logging_writer     = "roles/logging.logWriter"
```

## Monitoring and Alerting

### Enabled Metrics

- **Function Success Rate**: Successful image processing events
- **Function Failures**: Error rate and failure patterns
- **Processing Latency**: Time to process each image
- **Resource Utilization**: Memory and CPU usage

### Alert Policies

- **Function Failures**: Triggers when error rate exceeds threshold
- **Processing Delays**: Alerts on unusual processing times
- **Resource Exhaustion**: Monitors quota and limit usage

### Custom Monitoring

```hcl
# Enable additional monitoring
enable_monitoring = true
alert_email      = "admin@yourhealthcareorg.com"
```

## Cost Optimization

### Estimated Costs (Monthly)

| Service | Light Usage | Medium Usage | Heavy Usage |
|---------|-------------|--------------|-------------|
| Healthcare API | $0-10 | $10-50 | $50-200 |
| Cloud Functions | $0-5 | $5-25 | $25-100 |
| Cloud Storage | $0-5 | $5-20 | $20-100 |
| Vision AI | $1.50/1K images | $15/10K images | $150/100K images |
| Pub/Sub | $0-5 | $5-15 | $15-50 |
| **Total** | **$5-30** | **$40-125** | **$260-600** |

### Cost Optimization Features

1. **Lifecycle Policies**: Automatic data archival and deletion
2. **Function Scaling**: Pay-per-use serverless model
3. **Storage Classes**: Intelligent tiering for cost optimization
4. **Resource Limits**: Prevent runaway costs

## Testing and Validation

### Sample Data

The infrastructure includes sample DICOM metadata for testing:

```json
{
  "PatientID": "TEST001",
  "StudyDate": "20250112",
  "Modality": "CT",
  "StudyDescription": "Chest CT for routine screening"
}
```

### Testing Workflow

1. **Upload Test Images**: To the `incoming/` folder
2. **Monitor Processing**: Check function logs and metrics
3. **Verify Results**: Review FHIR store and processed folders
4. **Validate Alerts**: Test monitoring and alerting systems

### Validation Commands

```bash
# Check function logs
gcloud functions logs read medical-image-processor --region=us-central1 --gen2

# Verify FHIR resources
gcloud healthcare fhir-stores search medical-fhir-store \
  --dataset=medical-imaging-dataset \
  --location=us-central1 \
  --resource-type=DiagnosticReport

# Monitor Pub/Sub subscriptions
gcloud pubsub subscriptions describe medical-image-processor-sub
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure Healthcare API is enabled in your project
2. **Permissions**: Verify service account has required roles
3. **Quotas**: Check project quotas for Healthcare API and Vision AI
4. **Function Timeouts**: Increase timeout for large image processing
5. **Network Issues**: Verify VPC and firewall configurations

### Debug Commands

```bash
# Check function status
terraform output cloud_function_name
gcloud functions describe $(terraform output -raw cloud_function_name) --region=us-central1 --gen2

# Verify Healthcare API access
gcloud healthcare datasets list --location=us-central1

# Check storage bucket
gsutil ls -L gs://$(terraform output -raw storage_bucket_name)

# Monitor Pub/Sub
gcloud pubsub topics list
gcloud pubsub subscriptions list
```

### Logs and Monitoring

```bash
# Function logs
gcloud functions logs read medical-image-processor --region=us-central1 --gen2 --limit=50

# Healthcare API logs
gcloud logging read 'resource.type="gce_instance" AND logName="projects/PROJECT_ID/logs/healthcare"'

# Error tracking
gcloud error-reporting events list
```

## Cleanup

### Partial Cleanup (Keep Data)

```bash
# Remove compute resources but keep data
terraform destroy -target=google_cloudfunctions2_function.medical_image_processor
terraform destroy -target=google_pubsub_topic.medical_image_processing
```

### Complete Cleanup

```bash
# Remove all resources
terraform destroy

# Confirm removal
terraform state list  # Should be empty
```

### Manual Cleanup

If Terraform cleanup fails:

```bash
# Delete Healthcare resources
gcloud healthcare datasets delete medical-imaging-dataset --location=us-central1

# Delete storage bucket
gsutil rm -r gs://medical-imaging-bucket-*

# Delete function
gcloud functions delete medical-image-processor --region=us-central1 --gen2
```

## Production Considerations

### Security Hardening

1. **VPC Configuration**: Deploy in private VPC with restricted access
2. **KMS Encryption**: Use customer-managed encryption keys
3. **Access Logging**: Enable detailed access logs
4. **Network Security**: Implement Cloud Armor and firewall rules
5. **Secrets Management**: Use Secret Manager for sensitive data

### High Availability

1. **Multi-Region**: Deploy across multiple regions
2. **Backup Strategy**: Regular backups of Healthcare data
3. **Disaster Recovery**: Implement DR procedures
4. **Health Checks**: Comprehensive health monitoring

### Compliance

1. **BAA Requirements**: Execute Business Associate Agreement with Google
2. **Audit Trails**: Comprehensive logging and monitoring
3. **Data Retention**: Implement appropriate retention policies
4. **Access Controls**: Regular access reviews and updates

## Support and Resources

### Documentation Links

- [Google Cloud Healthcare API](https://cloud.google.com/healthcare-api/docs)
- [Cloud Vision AI](https://cloud.google.com/vision/docs)
- [Cloud Functions](https://cloud.google.com/functions/docs)
- [FHIR Implementation Guide](https://cloud.google.com/healthcare-api/docs/concepts/fhir)

### Getting Help

1. **Google Cloud Support**: For infrastructure and API issues
2. **Community Forums**: Stack Overflow, Reddit r/googlecloud
3. **Documentation**: Official Google Cloud documentation
4. **Professional Services**: Consider Google Cloud Professional Services for complex implementations

---

**Important**: This infrastructure handles medical data and must comply with HIPAA and other healthcare regulations. Ensure proper Business Associate Agreements (BAAs) are in place before processing real patient data.