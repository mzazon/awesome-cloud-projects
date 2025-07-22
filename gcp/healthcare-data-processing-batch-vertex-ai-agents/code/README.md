# Infrastructure as Code for Healthcare Data Processing with Cloud Batch and Vertex AI Agents

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Healthcare Data Processing with Cloud Batch and Vertex AI Agents".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Healthcare API Admin
  - Batch Admin
  - Vertex AI Admin
  - Storage Admin
  - Cloud Functions Admin
  - Monitoring Admin
  - Service Account Admin
- Healthcare data handling knowledge and HIPAA compliance understanding
- Estimated cost: $50-100 for testing with sample data

> **Warning**: This infrastructure processes healthcare data and requires strict adherence to HIPAA compliance. Ensure proper security controls, encryption, and access management before processing any real patient data.

## Quick Start

### Using Infrastructure Manager

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="healthcare-processing-$(date +%s)"

# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable healthcare.googleapis.com
gcloud services enable batch.googleapis.com
gcloud services enable aiplatform.googleapis.com

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars.example"
```

### Using Terraform

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `bucket_name` | Storage bucket name (auto-generated if not specified) | - | No |
| `dataset_id` | Healthcare API dataset ID | - | No |
| `fhir_store_id` | FHIR store identifier | - | No |
| `enable_monitoring` | Enable comprehensive monitoring | `true` | No |
| `enable_compliance_alerts` | Enable HIPAA compliance alerts | `true` | No |

### Security Configuration

The infrastructure implements several security measures:

- HIPAA-compliant Cloud Storage with versioning and audit logging
- IAM roles following least privilege principle
- Service accounts with minimal required permissions
- Encryption at rest and in transit for all healthcare data
- Audit logging for all data access and processing activities

### Customization

You can customize the deployment by:

1. **Modifying variables**: Edit `terraform.tfvars.example` or pass variables directly
2. **Adjusting batch job configuration**: Modify compute resources and scaling parameters
3. **Configuring AI agent parameters**: Customize healthcare analysis models and thresholds
4. **Setting up custom monitoring**: Add additional dashboards and alert policies

## Architecture Overview

The deployed infrastructure includes:

- **Cloud Storage**: HIPAA-compliant bucket for healthcare data ingestion
- **Cloud Healthcare API**: FHIR-compliant dataset and data store
- **Cloud Batch**: Scalable compute jobs for data processing
- **Vertex AI Agent Builder**: Intelligent medical record analysis
- **Cloud Functions**: Event-driven processing triggers
- **Cloud Monitoring**: Comprehensive observability and compliance tracking

## Post-Deployment Steps

1. **Upload sample data** to test the processing pipeline:
   ```bash
   gsutil cp sample_medical_record.json gs://your-bucket-name/test/
   ```

2. **Monitor processing** through Cloud Console:
   - Check Batch jobs in Cloud Console
   - Review Vertex AI agent performance
   - Monitor compliance alerts

3. **Validate FHIR data** in Healthcare API:
   ```bash
   gcloud healthcare fhir-stores list --dataset=your-dataset --location=your-region
   ```

## Monitoring and Compliance

The infrastructure includes:

- **Real-time monitoring dashboard** for processing metrics
- **HIPAA compliance alerts** for data governance
- **Audit logging** for regulatory requirements
- **Performance tracking** for optimization opportunities

Access monitoring through:
- Cloud Console Monitoring section
- Custom healthcare processing dashboard
- Alert policies for critical conditions

## Testing the Deployment

1. **Verify all services are running**:
   ```bash
   # Check Healthcare API dataset
   gcloud healthcare datasets describe your-dataset --location=your-region
   
   # Verify Cloud Function deployment
   gcloud functions describe healthcare-processor-trigger --region=your-region
   
   # Check monitoring dashboard
   gcloud monitoring dashboards list | grep -i healthcare
   ```

2. **Test data processing workflow**:
   ```bash
   # Upload test healthcare data
   echo '{"patient_id":"TEST123","encounter_date":"2025-07-12"}' > test_record.json
   gsutil cp test_record.json gs://your-bucket-name/test/
   
   # Monitor batch job creation
   gcloud batch jobs list --location=your-region
   ```

3. **Validate compliance monitoring**:
   ```bash
   # Check audit logs
   gcloud logging read "protoPayload.serviceName=\"healthcare.googleapis.com\"" --limit=10
   ```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
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

## Troubleshooting

### Common Issues

1. **API not enabled errors**:
   ```bash
   gcloud services enable healthcare.googleapis.com batch.googleapis.com aiplatform.googleapis.com
   ```

2. **Permission denied errors**:
   - Verify your account has the required IAM roles
   - Check service account permissions
   - Ensure billing is enabled on the project

3. **Batch job failures**:
   - Check Cloud Logging for detailed error messages
   - Verify compute quotas in your region
   - Review batch job configuration parameters

4. **Healthcare API access issues**:
   - Confirm FHIR store permissions
   - Verify dataset location matches deployment region
   - Check healthcare data format compliance

### Debug Commands

```bash
# Check service account permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Review batch job logs
gcloud batch jobs describe job-name --location=${REGION}

# Monitor function execution
gcloud functions logs read healthcare-processor-trigger --limit=50

# Validate healthcare resources
gcloud healthcare datasets list --location=${REGION}
```

## Cost Optimization

- **Batch jobs**: Use preemptible instances for non-urgent processing
- **Storage**: Implement lifecycle policies for archival
- **Monitoring**: Adjust log retention periods
- **AI processing**: Optimize batch sizes for cost efficiency

## Security Best Practices

1. **Data encryption**: All data encrypted at rest and in transit
2. **Access control**: Implement least privilege IAM policies
3. **Audit logging**: Comprehensive logging for compliance
4. **Network security**: Use VPC Service Controls for additional protection
5. **Regular reviews**: Monitor access patterns and permissions

## Support and Documentation

- [Cloud Healthcare API Documentation](https://cloud.google.com/healthcare-api/docs)
- [Vertex AI Agent Builder Guide](https://cloud.google.com/vertex-ai/docs/agent-builder)
- [Cloud Batch Documentation](https://cloud.google.com/batch/docs)
- [HIPAA Compliance on Google Cloud](https://cloud.google.com/security/compliance/hipaa)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support resources.

## Compliance Notes

This infrastructure is designed to support HIPAA compliance but does not automatically ensure compliance. Organizations must:

- Sign a Business Associate Agreement (BAA) with Google Cloud
- Implement appropriate administrative, physical, and technical safeguards
- Conduct regular security assessments and audits
- Train personnel on HIPAA requirements
- Maintain comprehensive documentation

> **Important**: Consult with your compliance team before processing real patient data.