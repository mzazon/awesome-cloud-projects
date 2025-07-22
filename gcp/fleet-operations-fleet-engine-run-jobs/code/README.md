# Infrastructure as Code for Fleet Operations with Fleet Engine and Cloud Run Jobs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Fleet Operations with Fleet Engine and Cloud Run Jobs".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a modern fleet management platform that combines:
- **Fleet Engine** for real-time vehicle tracking and route optimization
- **Cloud Run Jobs** for serverless batch processing of fleet analytics
- **Cloud Scheduler** for automated processing workflows
- **BigQuery** for analytical data storage and insights
- **Firestore** for real-time fleet state management
- **Cloud Storage** for fleet data archival
- **Cloud Monitoring** for operational visibility

## Prerequisites

- Google Cloud account with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Terraform >= 1.0 (for Terraform implementation)
- Appropriate permissions for:
  - Fleet Engine API access
  - Cloud Run Jobs management
  - BigQuery dataset creation
  - Cloud Storage bucket management
  - Firestore database access
  - Cloud Scheduler job creation
  - IAM service account management

## Estimated Costs

- **Fleet Engine**: Usage-based pricing (varies by fleet size and API calls)
- **Cloud Run Jobs**: Pay-per-execution model (~$0.24/hour per vCPU)
- **BigQuery**: Storage (~$0.02/GB/month) + Query processing (~$5/TB)
- **Cloud Storage**: Standard storage (~$0.02/GB/month)
- **Firestore**: Document operations (~$0.18/100K operations)
- **Cloud Scheduler**: ~$0.10/job/month

**Total estimated cost**: $50-100/month for moderate fleet size (10-50 vehicles)

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-fleet-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments create fleet-operations-deployment \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infrastructure-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/fleet-operations-iac" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe fleet-operations-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-fleet-project-id"
export REGION="us-central1"
export FLEET_ENGINE_SA_EMAIL="fleet-engine-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Deploy the solution
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Configuration

### Environment Variables

The following environment variables are required:

```bash
# Core Project Configuration
export PROJECT_ID="your-fleet-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Fleet Engine Configuration
export FLEET_ENGINE_SA_EMAIL="fleet-engine-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Resource Naming
export ANALYTICS_JOB_NAME="fleet-analytics-${RANDOM_SUFFIX}"
export BUCKET_NAME="fleet-data-${RANDOM_SUFFIX}"
export DATASET_NAME="fleet_analytics"
```

### Terraform Variables

Key variables you can customize in `terraform.tfvars`:

```hcl
# Project Configuration
project_id = "your-fleet-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Fleet Engine Configuration
fleet_engine_sa_name = "fleet-engine-sa"
fleet_engine_sa_description = "Service account for Fleet Engine operations"

# Analytics Configuration
analytics_job_name = "fleet-analytics"
analytics_job_memory = "2Gi"
analytics_job_cpu = "1"
analytics_job_timeout = "3600s"

# Storage Configuration
bucket_name = "fleet-data"
dataset_name = "fleet_analytics"
dataset_description = "Fleet operations analytics dataset"

# Monitoring Configuration
enable_monitoring = true
enable_alerting = true
notification_email = "your-email@example.com"
```

## Deployment Details

### Infrastructure Manager Implementation

The Infrastructure Manager implementation includes:
- **main.yaml**: Primary infrastructure definition
- **Service Account**: Fleet Engine authentication
- **API Enablement**: All required Google Cloud APIs
- **Storage Resources**: Cloud Storage bucket with lifecycle policies
- **Analytics Pipeline**: BigQuery dataset and tables
- **Real-time Database**: Firestore with optimized indexes
- **Batch Processing**: Cloud Run Jobs with proper configuration
- **Scheduling**: Cloud Scheduler for automated processing
- **Monitoring**: Cloud Monitoring dashboards and alerts

### Terraform Implementation

The Terraform implementation includes:
- **main.tf**: Primary resource definitions
- **variables.tf**: Input variable definitions
- **outputs.tf**: Output values for verification
- **versions.tf**: Provider version constraints
- **terraform.tfvars.example**: Example configuration file

Key features:
- Modular design using official Google Cloud provider
- Proper resource dependencies and ordering
- Comprehensive variable validation
- Security best practices implementation
- Cost optimization configurations

### Bash Scripts Implementation

The bash scripts provide:
- **deploy.sh**: Complete deployment automation
- **destroy.sh**: Clean resource removal
- **verify.sh**: Deployment validation
- **monitor.sh**: Operational monitoring

Script features:
- Comprehensive error handling
- Progress indicators
- Prerequisite validation
- Safety confirmations
- Detailed logging

## Validation & Testing

### Verify Fleet Engine Configuration

```bash
# Test Fleet Engine API access
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "Content-Type: application/json" \
    "https://fleetengine.googleapis.com/v1/providers/${PROJECT_ID}/vehicles"

# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:fleet-engine-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```

### Test Analytics Pipeline

```bash
# Execute analytics job manually
gcloud run jobs execute ${ANALYTICS_JOB_NAME} \
    --region=${REGION} \
    --wait

# Check BigQuery tables
bq ls ${PROJECT_ID}:${DATASET_NAME}

# Verify Cloud Storage structure
gsutil ls -r gs://${BUCKET_NAME}/
```

### Monitor Scheduled Jobs

```bash
# Check scheduler job status
gcloud scheduler jobs list --location=${REGION}

# View job execution logs
gcloud logging read "resource.type=\"cloud_run_job\"" \
    --limit=10 \
    --format="table(timestamp,jsonPayload.message)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete fleet-operations-deployment \
    --location=${REGION} \
    --delete-policy=DELETE

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
./scripts/verify-cleanup.sh
```

## Operational Considerations

### Security Best Practices

- **Service Account**: Uses least-privilege IAM roles
- **API Keys**: Stored securely in Secret Manager
- **Network Security**: VPC-native resources where applicable
- **Audit Logging**: Comprehensive logging enabled
- **Access Control**: Role-based permissions

### Cost Optimization

- **Lifecycle Policies**: Automatic storage class transitions
- **Serverless Architecture**: Pay-per-use pricing model
- **Resource Scheduling**: Analytics jobs run on optimized schedules
- **Monitoring**: Cost alerting and budget controls

### Performance Optimization

- **Regional Deployment**: Resources deployed in same region
- **Batch Processing**: Efficient data processing patterns
- **Caching**: Firestore for real-time data access
- **Indexing**: Optimized database indexes

### Monitoring and Alerting

- **Custom Dashboards**: Fleet operations visibility
- **Alert Policies**: Proactive issue detection
- **Log Analysis**: Comprehensive application logging
- **Performance Metrics**: System and business metrics

## Troubleshooting

### Common Issues

1. **Fleet Engine API Access**
   - Verify API is enabled
   - Check service account permissions
   - Validate authentication tokens

2. **Cloud Run Job Failures**
   - Check job logs in Cloud Logging
   - Verify resource allocation
   - Validate environment variables

3. **BigQuery Access Issues**
   - Confirm dataset permissions
   - Check table schemas
   - Verify data location settings

4. **Firestore Connection Problems**
   - Validate database configuration
   - Check index creation status
   - Verify network connectivity

### Support Resources

- [Fleet Engine Documentation](https://developers.google.com/maps/documentation/mobility/fleet-engine)
- [Cloud Run Jobs Documentation](https://cloud.google.com/run/docs/create-jobs)
- [Google Cloud Terraform Provider](https://registry.terraform.io/providers/hashicorp/google/latest)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Customization

### Extending the Solution

1. **Add More Analytics Jobs**: Create additional Cloud Run Jobs for specific analytics
2. **Implement ML Models**: Integrate Vertex AI for predictive analytics
3. **Add Real-time Streaming**: Use Pub/Sub for real-time data ingestion
4. **Enhance Monitoring**: Add custom metrics and dashboards
5. **Implement Multi-region**: Deploy across multiple regions for high availability

### Integration Options

- **Mobile Apps**: Use Fleet Engine SDKs for mobile integration
- **Third-party Systems**: REST APIs for external system integration
- **Business Intelligence**: Connect BigQuery to BI tools
- **Notification Systems**: Integrate with email/SMS services

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Submit issues to the repository issue tracker

## License

This infrastructure code is provided under the same license as the parent recipe repository.