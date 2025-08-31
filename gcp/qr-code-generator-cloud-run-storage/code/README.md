# Infrastructure as Code for QR Code Generator with Cloud Run and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "QR Code Generator with Cloud Run and Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (or Cloud Shell access)
- Google Cloud Platform account with billing enabled
- Appropriate IAM permissions for:
  - Cloud Run service deployment
  - Cloud Storage bucket creation and management
  - Cloud Build API usage
  - Service account management
- Basic understanding of containerization and REST APIs
- Estimated cost: $0.10-0.50 for testing (minimal Cloud Run and Cloud Storage usage)

> **Note**: Cloud Run provides 2 million requests per month in the free tier, making this solution cost-effective for development and testing.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for deploying infrastructure using YAML configuration files.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create qr-generator-deployment \
    --location=${REGION} \
    --source=infrastructure-manager/main.yaml \
    --labels=recipe=qr-generator

# Monitor deployment status
gcloud infra-manager deployments describe qr-generator-deployment \
    --location=${REGION}
```

### Using Terraform

Terraform provides a declarative approach to infrastructure management with state tracking and planning capabilities.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" \
               -var="region=us-central1"

# Apply infrastructure changes
terraform apply -var="project_id=your-project-id" \
                -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

Automated deployment scripts provide a simple way to deploy the complete solution using Google Cloud CLI commands.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts to configure project ID and region
# Script will handle all resource creation and configuration
```

## Architecture Overview

The infrastructure deploys the following Google Cloud resources:

- **Cloud Run Service**: Containerized QR code generation API with automatic scaling
- **Cloud Storage Bucket**: Persistent storage for generated QR code images
- **IAM Service Account**: Secure access between Cloud Run and Cloud Storage
- **Cloud Build Configuration**: Automated container building and deployment
- **API Services**: Required Google Cloud APIs (Cloud Run, Cloud Storage, Cloud Build)

## Configuration Options

### Infrastructure Manager Variables

Customize your deployment by modifying the variables section in `infrastructure-manager/main.yaml`:

- `project_id`: Your Google Cloud Project ID
- `region`: Deployment region (default: us-central1)
- `service_name`: Cloud Run service name (default: qr-code-api)
- `bucket_location`: Cloud Storage bucket location
- `container_memory`: Memory allocation for Cloud Run service
- `container_cpu`: CPU allocation for Cloud Run service

### Terraform Variables

Configure your deployment using `terraform/variables.tf` or command-line variables:

```bash
# Using variable file
terraform apply -var-file="production.tfvars"

# Using command-line variables
terraform apply \
    -var="project_id=my-project" \
    -var="region=us-west1" \
    -var="service_name=my-qr-service" \
    -var="max_instances=20"
```

### Script Configuration

The bash scripts support environment variable configuration:

```bash
# Set custom configuration before running deploy.sh
export PROJECT_ID="my-project"
export REGION="us-west1"
export SERVICE_NAME="my-qr-generator"
export BUCKET_NAME="my-qr-codes-bucket"

./scripts/deploy.sh
```

## Deployment Verification

After successful deployment, verify your infrastructure:

1. **Check Cloud Run Service**:
   ```bash
   # Get service URL
   gcloud run services list --platform managed
   
   # Test health endpoint
   curl -s "https://your-service-url/" | jq '.'
   ```

2. **Verify Cloud Storage Bucket**:
   ```bash
   # List buckets
   gsutil ls
   
   # Check bucket permissions
   gsutil iam get gs://your-bucket-name
   ```

3. **Test QR Code Generation**:
   ```bash
   # Generate a sample QR code
   curl -X POST "https://your-service-url/generate" \
        -H "Content-Type: application/json" \
        -d '{"text": "https://cloud.google.com/"}' | jq '.'
   ```

## Monitoring and Observability

The deployed infrastructure includes built-in monitoring capabilities:

- **Cloud Run Metrics**: Request latency, error rates, and instance scaling
- **Cloud Storage Metrics**: Storage usage, request counts, and access patterns
- **Cloud Logging**: Application logs and system events
- **Cloud Monitoring**: Custom dashboards and alerting policies

Access monitoring data through:
```bash
# View Cloud Run logs
gcloud logs read "resource.type=cloud_run_revision" --limit=50

# Monitor service performance
gcloud run services describe qr-code-api --region=us-central1
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete qr-generator-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Plan destruction (optional - review what will be deleted)
terraform plan -destroy

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# Script handles proper cleanup order and verification
```

## Customization

### Scaling Configuration

Modify scaling parameters for production workloads:

**Terraform example**:
```hcl
# In terraform/main.tf
resource "google_cloud_run_service" "qr_generator" {
  template {
    spec {
      container_concurrency = 1000
    }
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "100"
        "autoscaling.knative.dev/minScale" = "1"
        "run.googleapis.com/cpu-throttling" = "false"
      }
    }
  }
}
```

### Security Enhancements

Add additional security configurations:

1. **Custom Service Account**:
   ```bash
   # Create dedicated service account
   gcloud iam service-accounts create qr-generator-sa \
       --display-name="QR Generator Service Account"
   ```

2. **VPC Connector** (for private networking):
   ```yaml
   # In infrastructure-manager/main.yaml
   - name: vpc-connector
     type: compute.v1.vpcAccessConnector
     properties:
       network: projects/${project_id}/global/networks/default
       ipCidrRange: 10.8.0.0/28
   ```

### Performance Optimization

Optimize for high-traffic scenarios:

- **Increase memory allocation**: 1Gi for image processing workloads
- **Configure CPU allocation**: 2 vCPUs for better parallel processing
- **Enable CPU boost**: For reduced cold start times
- **Implement caching**: Add Cloud Memorystore integration

## Troubleshooting

### Common Issues

1. **Deployment Fails**:
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Verify API enablement
   gcloud services list --enabled
   ```

2. **Application Errors**:
   ```bash
   # Check Cloud Run logs
   gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=qr-code-api" --limit=100
   ```

3. **Storage Access Issues**:
   ```bash
   # Test bucket access
   gsutil ls -L gs://your-bucket-name
   
   # Check IAM permissions
   gsutil iam get gs://your-bucket-name
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Set debug environment variable
export GOOGLE_CLOUD_DEBUG=true

# Run deployment with verbose output
gcloud --verbosity=debug run deploy ...
```

## Cost Optimization

Monitor and optimize costs:

1. **Resource Usage Monitoring**:
   ```bash
   # Check Cloud Run pricing details
   gcloud run services describe qr-code-api --region=us-central1 \
       --format="value(status.traffic[0].latestRevision)"
   ```

2. **Storage Lifecycle Management**:
   ```bash
   # Set lifecycle policy for old QR codes
   gsutil lifecycle set lifecycle.json gs://your-bucket-name
   ```

3. **Request Optimization**:
   - Implement request deduplication
   - Add image compression
   - Use appropriate Cloud Run concurrency settings

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud Status page for service issues
3. Consult Google Cloud documentation:
   - [Cloud Run Documentation](https://cloud.google.com/run/docs)
   - [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
   - [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Next Steps

Extend this infrastructure for production use:

1. **Add Custom Domain**: Configure Cloud Run with custom domain and SSL
2. **Implement Authentication**: Add Firebase Auth or Google Cloud IAM
3. **Add Monitoring Dashboards**: Create custom Cloud Monitoring dashboards
4. **Implement Rate Limiting**: Add API rate limiting and quota management
5. **Set Up CI/CD**: Automate deployments with Cloud Build pipelines

For advanced features and production hardening, refer to the Challenge section in the original recipe documentation.