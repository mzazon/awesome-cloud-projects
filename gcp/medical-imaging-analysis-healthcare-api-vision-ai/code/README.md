# Infrastructure as Code for Medical Imaging Analysis with Cloud Healthcare API and Vision AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Medical Imaging Analysis with Cloud Healthcare API and Vision AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an automated medical imaging analysis pipeline that:

- Stores DICOM medical images in Cloud Healthcare API
- Processes images using Vision AI for anomaly detection
- Provides HIPAA-compliant data handling
- Generates structured medical reports
- Enables scalable, event-driven processing

## Prerequisites

### Required Tools
- Google Cloud CLI (`gcloud`) installed and configured
- Terraform >= 1.5.0 (for Terraform deployment)
- Bash shell (for script deployment)

### Required Permissions
- Healthcare API Admin (`roles/healthcare.datasetAdmin`)
- Cloud Functions Developer (`roles/cloudfunctions.developer`)
- Storage Admin (`roles/storage.admin`)
- Vision AI Developer (`roles/ml.developer`)
- Pub/Sub Admin (`roles/pubsub.admin`)
- Service Account Admin (`roles/iam.serviceAccountAdmin`)

### Prerequisites Verification
```bash
# Verify gcloud is authenticated
gcloud auth list

# Check required APIs are enabled
gcloud services list --enabled --filter="name:(healthcare.googleapis.com OR vision.googleapis.com OR cloudfunctions.googleapis.com)"

# Verify permissions
gcloud projects get-iam-policy $(gcloud config get-value project)
```

### Cost Considerations
Estimated monthly costs for moderate usage:
- Cloud Healthcare API: $50-100 (depends on data volume)
- Vision AI: $20-50 (per 1000 images analyzed)
- Cloud Functions: $10-25 (based on processing frequency)
- Cloud Storage: $5-15 (for image staging)
- Pub/Sub: $5-10 (for event messaging)

## Quick Start

### Environment Setup
```bash
# Set your project ID
export PROJECT_ID="your-medical-imaging-project"
export REGION="us-central1"

# Ensure project is set
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
```

### Using Infrastructure Manager (Recommended for GCP)
```bash
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply medical-imaging-deployment \
    --location=${REGION} \
    --service-account=terraform@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe medical-imaging-deployment \
    --location=${REGION}
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh

# Follow prompts for project configuration
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `dataset_id` | Healthcare dataset name | `medical-imaging-dataset` | No |
| `dicom_store_id` | DICOM store identifier | `medical-dicom-store` | No |
| `fhir_store_id` | FHIR store identifier | `medical-fhir-store` | No |
| `function_name` | Cloud Function name | `medical-image-processor` | No |
| `bucket_suffix` | Storage bucket suffix | `random-6-chars` | No |
| `enable_monitoring` | Enable monitoring/alerting | `true` | No |

### Customization Examples

#### Terraform Variables File
```bash
# Create terraform.tfvars
cat > terraform/terraform.tfvars << EOF
project_id = "my-healthcare-project"
region = "us-east1"
dataset_id = "hospital-imaging-data"
dicom_store_id = "radiology-dicom"
fhir_store_id = "radiology-fhir"
enable_monitoring = true
EOF
```

#### Infrastructure Manager Input Values
```bash
# Set custom input values
gcloud infra-manager deployments apply medical-imaging-deployment \
    --location=${REGION} \
    --service-account=terraform@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},region=us-east1,dataset_id=hospital-imaging"
```

## Deployment Verification

### Check Healthcare API Resources
```bash
# Verify healthcare dataset
gcloud healthcare datasets list --location=${REGION}

# Check DICOM store
gcloud healthcare dicom-stores list \
    --dataset=medical-imaging-dataset \
    --location=${REGION}

# Verify FHIR store
gcloud healthcare fhir-stores list \
    --dataset=medical-imaging-dataset \
    --location=${REGION}
```

### Validate Cloud Function
```bash
# Check function deployment
gcloud functions describe medical-image-processor \
    --region=${REGION} \
    --gen2

# Test function with sample trigger
gcloud functions call medical-image-processor \
    --region=${REGION} \
    --gen2 \
    --data='{"test": "validation"}'
```

### Verify Pub/Sub Configuration
```bash
# Check topic creation
gcloud pubsub topics list --filter="name:medical-image-processing"

# Verify subscription
gcloud pubsub subscriptions list --filter="name:medical-image-processor-sub"
```

### Test Storage Access
```bash
# List created buckets
gsutil ls -p ${PROJECT_ID} | grep medical-imaging

# Check bucket permissions
gsutil iam get gs://medical-imaging-bucket-*
```

## Monitoring and Maintenance

### View Logs
```bash
# Cloud Function logs
gcloud functions logs read medical-image-processor \
    --region=${REGION} \
    --gen2 \
    --limit=50

# Healthcare API audit logs
gcloud logging read 'resource.type="healthcare_dataset"' \
    --limit=20 \
    --format="table(timestamp,severity,textPayload)"
```

### Monitoring Dashboard
```bash
# Create custom dashboard (if monitoring enabled)
gcloud monitoring dashboards list --filter="displayName:Medical"
```

### Performance Metrics
```bash
# Function execution metrics
gcloud functions metrics list --region=${REGION}

# Storage usage metrics
gsutil du -s gs://medical-imaging-bucket-*
```

## Security Considerations

### HIPAA Compliance
- Healthcare API provides HIPAA-compliant storage
- All data encrypted in transit and at rest
- Audit logging enabled for all operations
- Access controls follow principle of least privilege

### IAM Best Practices
- Service accounts use minimal required permissions
- No overprivileged roles assigned
- Regular access review recommended
- Encryption keys managed by Google Cloud KMS

### Network Security
- Private Google Access enabled for enhanced security
- VPC firewall rules restrict unnecessary access
- Healthcare API uses private endpoints

## Troubleshooting

### Common Issues

#### Healthcare API Access Denied
```bash
# Check Healthcare API enablement
gcloud services list --enabled --filter="name:healthcare.googleapis.com"

# Enable if needed
gcloud services enable healthcare.googleapis.com
```

#### Function Deployment Failures
```bash
# Check function source code
gcloud functions describe medical-image-processor \
    --region=${REGION} \
    --gen2 \
    --format="get(sourceArchiveUrl)"

# Review build logs
gcloud functions logs read medical-image-processor \
    --region=${REGION} \
    --gen2 \
    --execution-id=EXECUTION_ID
```

#### Storage Permission Issues
```bash
# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.members:medical-imaging-sa*"
```

#### Pub/Sub Message Delivery Issues
```bash
# Check subscription backlog
gcloud pubsub subscriptions describe medical-image-processor-sub \
    --format="get(numUndeliveredMessages)"

# Review dead letter queue (if configured)
gcloud pubsub topics list --filter="name:medical-image-processing-dlq"
```

### Debug Mode
```bash
# Enable debug logging for Terraform
export TF_LOG=DEBUG
terraform apply

# Enable verbose gcloud output
gcloud functions deploy medical-image-processor --verbosity=debug
```

## Cleanup

### Using Infrastructure Manager
```bash
cd infrastructure-manager/

# Delete the deployment
gcloud infra-manager deployments delete medical-imaging-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Remove Terraform state
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts
```bash
cd scripts/

# Run cleanup script
./destroy.sh

# Follow prompts for resource deletion confirmation
```

### Manual Cleanup Verification
```bash
# Verify healthcare resources removed
gcloud healthcare datasets list --location=${REGION}

# Check function deletion
gcloud functions list --region=${REGION} --filter="name:medical-image*"

# Verify storage cleanup
gsutil ls -p ${PROJECT_ID} | grep medical-imaging

# Check Pub/Sub cleanup
gcloud pubsub topics list --filter="name:medical-image*"
```

## Advanced Usage

### Integration with Existing Systems
```bash
# Connect to existing VPC
terraform apply -var="vpc_name=existing-healthcare-vpc"

# Use existing service account
terraform apply -var="service_account_email=existing-sa@project.iam.gserviceaccount.com"
```

### Multi-Region Deployment
```bash
# Deploy to multiple regions
for region in us-central1 us-east1 europe-west1; do
    terraform apply -var="region=${region}" -var="project_id=${PROJECT_ID}"
done
```

### Custom AI Models
```bash
# Deploy with custom Vision AI model
terraform apply -var="vision_model_path=gs://my-bucket/custom-medical-model"
```

## Support and Resources

### Documentation Links
- [Google Cloud Healthcare API](https://cloud.google.com/healthcare-api/docs)
- [Cloud Vision API](https://cloud.google.com/vision/docs)
- [HIPAA Compliance Guide](https://cloud.google.com/security/compliance/hipaa)
- [Medical Imaging Best Practices](https://cloud.google.com/healthcare-api/docs/how-tos/dicom)

### Support Channels
- Google Cloud Support (for infrastructure issues)
- Healthcare API Forum (for API-specific questions)
- Recipe Repository Issues (for IaC problems)

### Contributing
For improvements to this infrastructure code:
1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the same license as the parent recipe repository.