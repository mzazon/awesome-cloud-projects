# Infrastructure as Code for Healthcare Data Compliance Workflows with Cloud Healthcare API and Cloud Tasks

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Healthcare Data Compliance Workflows with Cloud Healthcare API and Cloud Tasks".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for Healthcare API, Cloud Tasks, Cloud Functions, and related services
- Python 3.9+ for Cloud Functions (if customizing function code)
- Basic understanding of FHIR standards and healthcare compliance requirements

### Required APIs

The following APIs will be enabled during deployment:

- Cloud Healthcare API
- Cloud Tasks API
- Cloud Functions API
- Cloud Storage API
- Pub/Sub API
- BigQuery API
- Cloud Logging API
- Cloud Monitoring API

### IAM Permissions

Your Google Cloud account needs the following roles:

- `roles/healthcare.admin` - For Healthcare API resources
- `roles/cloudtasks.admin` - For Cloud Tasks queues
- `roles/cloudfunctions.admin` - For Cloud Functions deployment
- `roles/storage.admin` - For Cloud Storage buckets
- `roles/pubsub.admin` - For Pub/Sub topics and subscriptions
- `roles/bigquery.admin` - For BigQuery datasets and tables
- `roles/logging.admin` - For audit logging configuration
- `roles/monitoring.editor` - For alerting and monitoring

### Cost Considerations

Estimated daily costs for development/testing:
- Cloud Healthcare API: ~$5-10 (based on FHIR operations)
- Cloud Tasks: ~$1-3 (based on task execution)
- Cloud Functions: ~$2-5 (based on invocations)
- Cloud Storage: ~$1-2 (based on storage and operations)
- BigQuery: ~$1-3 (based on data storage and queries)
- Other services: ~$5-10

**Total estimated cost: $15-25 per day**

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set your project ID
export PROJECT_ID="your-healthcare-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Initialize deployment
gcloud infra-manager deployments apply healthcare-compliance-deployment \
    --location=${REGION} \
    --config=main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Set your project ID and region
export PROJECT_ID="your-healthcare-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-healthcare-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
    
  region:
    description: "Google Cloud region"
    type: string
    default: "us-central1"
    
  healthcare_dataset_id:
    description: "Healthcare dataset identifier"
    type: string
    default: "healthcare-dataset"
    
  enable_monitoring:
    description: "Enable Cloud Monitoring alerts"
    type: bool
    default: true
    
  retention_days:
    description: "Compliance data retention period"
    type: number
    default: 2555  # 7 years for healthcare compliance
```

### Terraform Variables

Customize `terraform/terraform.tfvars` or use command-line variables:

```bash
# Example terraform.tfvars
project_id = "your-healthcare-project-id"
region = "us-central1"
healthcare_dataset_id = "healthcare-dataset"
fhir_store_id = "fhir-store"
enable_monitoring = true
retention_days = 2555
compliance_notification_email = "compliance@yourorganization.com"
```

### Environment Variables for Scripts

Set these variables before running bash scripts:

```bash
export PROJECT_ID="your-healthcare-project-id"
export REGION="us-central1"
export HEALTHCARE_DATASET_ID="healthcare-dataset"
export FHIR_STORE_ID="fhir-store"
export COMPLIANCE_EMAIL="compliance@yourorganization.com"
```

## Deployment Architecture

The infrastructure creates the following resources:

### Core Healthcare Infrastructure
- **Healthcare Dataset**: HIPAA-compliant container for healthcare data
- **FHIR Store**: RESTful API for clinical data following HL7 FHIR R4 standard
- **Cloud Storage Bucket**: Secure storage for compliance artifacts and reports

### Processing & Workflow Management
- **Cloud Tasks Queue**: Reliable background processing for compliance workflows
- **Cloud Functions**: Serverless processors for compliance validation and audit
- **Pub/Sub Topic**: Event-driven notifications for FHIR resource changes

### Analytics & Monitoring
- **BigQuery Dataset**: Scalable analytics for compliance reporting
- **Cloud Monitoring**: Real-time alerting for compliance violations
- **Cloud Audit Logs**: Comprehensive audit trail for all operations

### Security Features
- **IAM Roles**: Least-privilege access controls
- **Encryption**: Data encrypted at rest and in transit
- **VPC**: Network isolation for sensitive healthcare data
- **Audit Logging**: Comprehensive logging for HIPAA compliance

## Validation & Testing

After deployment, verify the infrastructure:

### 1. Check Healthcare API Resources

```bash
# List healthcare datasets
gcloud healthcare datasets list --location=${REGION}

# Verify FHIR store configuration
gcloud healthcare fhir-stores describe ${FHIR_STORE_ID} \
    --dataset=${HEALTHCARE_DATASET_ID} \
    --location=${REGION}
```

### 2. Test FHIR Operations

```bash
# Create a test patient resource
FHIR_STORE_URL="https://healthcare.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/datasets/${HEALTHCARE_DATASET_ID}/fhirStores/${FHIR_STORE_ID}/fhir"

curl -X POST "${FHIR_STORE_URL}/Patient" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/fhir+json" \
    -d '{
      "resourceType": "Patient",
      "name": [{"family": "Test", "given": ["Patient"]}],
      "gender": "unknown",
      "birthDate": "2000-01-01"
    }'
```

### 3. Verify Compliance Processing

```bash
# Check Cloud Functions status
gcloud functions list --regions=${REGION}

# Verify Cloud Tasks queue
gcloud tasks queues list --location=${REGION}

# Check BigQuery compliance tables
bq ls ${PROJECT_ID}:healthcare_compliance
```

### 4. Test Monitoring and Alerting

```bash
# Check monitoring policies
gcloud alpha monitoring policies list

# Verify notification channels
gcloud alpha monitoring channels list
```

## Security Considerations

### HIPAA Compliance

This infrastructure follows HIPAA best practices:

- **BAA Required**: Ensure you have a Business Associate Agreement with Google Cloud
- **Data Encryption**: All data encrypted at rest and in transit
- **Access Controls**: Least-privilege IAM roles implemented
- **Audit Logging**: Comprehensive logging for all PHI access
- **Network Security**: VPC isolation and secure communication

### Security Best Practices

1. **Regular Security Reviews**: Conduct quarterly security assessments
2. **Access Monitoring**: Monitor all access to healthcare data
3. **Incident Response**: Implement procedures for security incidents
4. **Data Minimization**: Only collect necessary PHI data
5. **Regular Updates**: Keep all components updated with security patches

### Compliance Monitoring

The infrastructure provides:

- **Real-time Alerts**: Immediate notification of high-risk events
- **Audit Trails**: Complete logging of all data access
- **Compliance Reports**: Automated generation of regulatory reports
- **Risk Scoring**: Automated assessment of data access patterns

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
2. **IAM Permissions**: Verify your account has necessary roles
3. **Resource Limits**: Check project quotas for Cloud Functions and Tasks
4. **Network Connectivity**: Ensure proper VPC and firewall configurations

### Debugging Commands

```bash
# Check deployment status
gcloud deployment-manager deployments describe healthcare-compliance

# View Cloud Function logs
gcloud functions logs read compliance-processor --region=${REGION}

# Check Cloud Tasks queue status
gcloud tasks queues describe compliance-queue --location=${REGION}

# Verify BigQuery table creation
bq show ${PROJECT_ID}:healthcare_compliance.compliance_events
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete healthcare-compliance-deployment \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete healthcare resources
gcloud healthcare fhir-stores delete ${FHIR_STORE_ID} \
    --dataset=${HEALTHCARE_DATASET_ID} \
    --location=${REGION} \
    --quiet

gcloud healthcare datasets delete ${HEALTHCARE_DATASET_ID} \
    --location=${REGION} \
    --quiet

# Delete Cloud Functions
gcloud functions delete compliance-processor --region=${REGION} --quiet

# Delete Cloud Tasks queue
gcloud tasks queues delete compliance-queue --location=${REGION} --quiet

# Delete storage bucket
gsutil -m rm -r gs://healthcare-compliance-${PROJECT_ID}-*

# Delete BigQuery dataset
bq rm -r -f ${PROJECT_ID}:healthcare_compliance
```

## Customization

### Adding Custom Compliance Rules

1. **Modify Cloud Functions**: Edit function code to add custom validation logic
2. **Update BigQuery Schema**: Add fields for custom compliance metrics
3. **Configure Alerting**: Create custom monitoring policies
4. **Extend Reporting**: Add custom compliance reports

### Integration with External Systems

1. **EHR Integration**: Connect with existing Electronic Health Record systems
2. **Identity Providers**: Integrate with enterprise identity management
3. **Audit Systems**: Connect with existing audit and compliance tools
4. **Notification Systems**: Integrate with enterprise notification platforms

### Performance Optimization

1. **Function Scaling**: Adjust Cloud Functions concurrency settings
2. **Task Queue Tuning**: Optimize Cloud Tasks queue parameters
3. **BigQuery Partitioning**: Configure table partitioning for better performance
4. **Caching**: Implement caching for frequently accessed data

## Support and Documentation

### Google Cloud Resources

- [Cloud Healthcare API Documentation](https://cloud.google.com/healthcare-api/docs)
- [Cloud Tasks Documentation](https://cloud.google.com/tasks/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [HIPAA Compliance Guide](https://cloud.google.com/security/compliance/hipaa)

### Healthcare Standards

- [HL7 FHIR R4 Specification](https://www.hl7.org/fhir/R4/)
- [HIPAA Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/index.html)
- [Healthcare Data Standards](https://www.healthit.gov/topic/standards-technology)

### Compliance Resources

- [Google Cloud Compliance](https://cloud.google.com/security/compliance)
- [Healthcare Compliance Best Practices](https://cloud.google.com/solutions/healthcare-life-sciences)
- [FHIR Implementation Guide](https://cloud.google.com/healthcare-api/docs/how-tos/fhir)

## License

This infrastructure code is provided as-is for educational and reference purposes. Ensure compliance with your organization's policies and applicable healthcare regulations before deploying in production environments.

## Contributing

To contribute improvements to this infrastructure code:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

For issues or questions, please refer to the original recipe documentation or create an issue in the repository.