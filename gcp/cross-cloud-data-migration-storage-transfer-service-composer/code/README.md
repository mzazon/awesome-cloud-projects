# Infrastructure as Code for Cross-Cloud Data Migration with Cloud Storage Transfer Service and Cloud Composer

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Cloud Data Migration with Cloud Storage Transfer Service and Cloud Composer".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud Project with billing enabled
- Project Owner or Editor permissions
- Source cloud provider credentials (AWS S3 or Azure Blob Storage)
- Basic understanding of Apache Airflow concepts
- Estimated cost: $50-100 for Cloud Composer environment and transfer operations

### Required APIs

The following APIs must be enabled in your Google Cloud project:

- Cloud Composer API (`composer.googleapis.com`)
- Storage Transfer API (`storagetransfer.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI v400.0.0 or later
- Infrastructure Manager API enabled
- Appropriate IAM permissions for Infrastructure Manager

#### Terraform
- Terraform v1.0 or later
- Google Cloud Provider v4.0 or later
- Service account with appropriate permissions

## Quick Start

### Using Infrastructure Manager

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="cross-cloud-migration"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-config-bucket/infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export COMPOSER_ENV_NAME="data-migration-env"

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration

### Environment Variables

The following environment variables are used across all implementations:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | - | Yes |
| `REGION` | Google Cloud Region | `us-central1` | Yes |
| `COMPOSER_ENV_NAME` | Cloud Composer environment name | `data-migration-env` | Yes |
| `STAGING_BUCKET` | Staging bucket name | Generated | No |
| `TARGET_BUCKET` | Target bucket name | Generated | No |

### Terraform Variables

Key variables available for customization in `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud Region"
  type        = string
  default     = "us-central1"
}

variable "composer_env_name" {
  description = "Cloud Composer environment name"
  type        = string
  default     = "data-migration-env"
}

variable "composer_node_count" {
  description = "Number of nodes in Cloud Composer environment"
  type        = number
  default     = 3
}

variable "composer_disk_size" {
  description = "Disk size for Cloud Composer nodes"
  type        = string
  default     = "30GB"
}

variable "composer_machine_type" {
  description = "Machine type for Cloud Composer nodes"
  type        = string
  default     = "n1-standard-1"
}
```

## Architecture Overview

The infrastructure creates the following components:

### Storage Layer
- **Cloud Storage Buckets**: Staging and target buckets with versioning enabled
- **Lifecycle Policies**: Automated cleanup of staging data after 30 days
- **IAM Bindings**: Service account permissions for transfer operations

### Orchestration Layer
- **Cloud Composer Environment**: Managed Apache Airflow service
- **Airflow DAGs**: Workflow orchestration for migration pipeline
- **Environment Variables**: Configuration passed to Airflow workflows

### Transfer Layer
- **Storage Transfer Service**: Managed data transfer from external sources
- **Service Account**: Dedicated account for transfer operations
- **IAM Roles**: Least privilege permissions for secure operations

### Monitoring Layer
- **Cloud Logging**: Centralized log collection and analysis
- **Cloud Monitoring**: Real-time metrics and alerting
- **Log Sinks**: Automated log export to Cloud Storage

## Deployment Details

### Resource Creation Order

1. **Enable APIs**: Required Google Cloud APIs
2. **Create Storage**: Staging and target buckets with policies
3. **Create Service Account**: Transfer service account with IAM roles
4. **Deploy Composer**: Cloud Composer environment with configurations
5. **Configure Logging**: Log sinks and monitoring policies
6. **Deploy DAGs**: Airflow workflows for orchestration

### Security Configuration

- Service accounts follow least privilege principle
- Storage buckets use appropriate IAM policies
- Cloud Composer environment uses private IP networking
- All resources are created with proper resource-level permissions

### Monitoring and Logging

- Storage Transfer Service logs are automatically captured
- Cloud Composer operations are logged to Cloud Logging
- Custom alert policies monitor for transfer failures
- Log sinks export logs to Cloud Storage for retention

## Validation

After deployment, verify the infrastructure is working correctly:

### Check Cloud Composer Environment

```bash
# Verify Composer environment is running
gcloud composer environments describe ${COMPOSER_ENV_NAME} \
    --location ${REGION} \
    --format="table(state,config.nodeConfig.machineType)"

# Get Airflow web interface URL
gcloud composer environments describe ${COMPOSER_ENV_NAME} \
    --location ${REGION} \
    --format="get(config.airflowUri)"
```

### Verify Storage Buckets

```bash
# List created buckets
gsutil ls -p ${PROJECT_ID}

# Check bucket permissions
gsutil iam get gs://${STAGING_BUCKET}
gsutil iam get gs://${TARGET_BUCKET}
```

### Test Transfer Configuration

```bash
# List transfer jobs
gcloud transfer jobs list --format="table(name,status,description)"

# Check service account permissions
gcloud iam service-accounts get-iam-policy ${TRANSFER_SA_EMAIL}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Steps

If automated cleanup fails, manually remove resources:

1. **Delete Cloud Composer Environment**:
   ```bash
   gcloud composer environments delete ${COMPOSER_ENV_NAME} \
       --location ${REGION} --quiet
   ```

2. **Remove Storage Buckets**:
   ```bash
   gsutil -m rm -r gs://${STAGING_BUCKET}
   gsutil -m rm -r gs://${TARGET_BUCKET}
   ```

3. **Delete Service Account**:
   ```bash
   gcloud iam service-accounts delete ${TRANSFER_SA_EMAIL} --quiet
   ```

4. **Remove Log Sinks**:
   ```bash
   gcloud logging sinks delete storage-transfer-sink --quiet
   gcloud logging sinks delete composer-migration-sink --quiet
   ```

## Customization

### Modifying Cloud Composer Configuration

Edit the Composer environment settings in your chosen IaC tool:

- **Node Count**: Adjust based on workflow complexity
- **Machine Type**: Scale up for resource-intensive workflows
- **Disk Size**: Increase for larger Airflow installations
- **Environment Variables**: Add custom variables for DAG configuration

### Configuring Source Systems

Update the transfer job configuration to match your source systems:

#### AWS S3 Source
```json
{
  "awsS3DataSource": {
    "bucketName": "your-aws-bucket",
    "awsAccessKey": {
      "accessKeyId": "YOUR_ACCESS_KEY",
      "secretAccessKey": "YOUR_SECRET_KEY"
    }
  }
}
```

#### Azure Blob Storage Source
```json
{
  "azureBlobStorageDataSource": {
    "storageAccount": "your-storage-account",
    "container": "your-container",
    "azureCredentials": {
      "sasToken": "YOUR_SAS_TOKEN"
    }
  }
}
```

### Custom Airflow DAGs

The infrastructure deploys a basic migration DAG. Customize it by:

1. Modifying the DAG file in `scripts/migration_orchestrator.py`
2. Adding custom data validation logic
3. Integrating with additional Google Cloud services
4. Implementing custom retry and error handling

## Troubleshooting

### Common Issues

1. **Composer Environment Creation Fails**:
   - Check project quotas for Compute Engine
   - Verify all required APIs are enabled
   - Ensure sufficient IAM permissions

2. **Storage Transfer Job Fails**:
   - Verify source credentials are correct
   - Check network connectivity to source systems
   - Validate IAM permissions for transfer service account

3. **Airflow DAG Import Errors**:
   - Check Python syntax in DAG files
   - Verify all required imports are available
   - Review Airflow logs in Cloud Logging

### Debugging Commands

```bash
# Check Composer environment logs
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_name:composer" \
    --limit=50 --format=json

# View transfer job details
gcloud transfer jobs describe JOB_NAME

# Check service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:${TRANSFER_SA_EMAIL}"
```

## Cost Optimization

### Monitoring Costs

- Cloud Composer environment runs continuously - consider environment sizing
- Storage Transfer Service charges based on data volume
- Cloud Storage costs depend on storage class and access patterns
- Monitor usage through Google Cloud Console billing reports

### Optimization Strategies

1. **Right-size Composer Environment**: Use smallest machine type that meets performance requirements
2. **Implement Lifecycle Policies**: Automatically transition data to cheaper storage classes
3. **Schedule Transfer Jobs**: Run transfers during off-peak hours when possible
4. **Use Preemptible Instances**: For non-critical Composer workloads

## Security Best Practices

### IAM Configuration

- Use separate service accounts for different components
- Grant minimum required permissions
- Regularly audit IAM policies and bindings
- Enable Cloud Audit Logs for compliance

### Data Protection

- Enable encryption at rest for all storage buckets
- Use VPC Service Controls for additional network security
- Implement data classification and labeling
- Regular security assessments and penetration testing

### Network Security

- Configure Cloud Composer with private IP addresses
- Use VPC firewall rules to restrict access
- Implement network monitoring and intrusion detection
- Regular security updates and patching

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Consult Cloud Composer and Storage Transfer Service troubleshooting guides
4. Use Google Cloud Support for technical issues

### Useful Resources

- [Cloud Composer Documentation](https://cloud.google.com/composer/docs)
- [Storage Transfer Service Documentation](https://cloud.google.com/storage-transfer/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes thoroughly in a development environment
2. Follow Google Cloud best practices and security guidelines
3. Update documentation for any configuration changes
4. Validate with multiple deployment methods before submitting