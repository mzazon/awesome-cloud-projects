# Infrastructure as Code for Personalized Recommendation APIs with Vertex AI and Cloud Run

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Personalized Recommendation APIs with Vertex AI and Cloud Run".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code using YAML
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Vertex AI (AI Platform Admin)
  - Cloud Run (Cloud Run Admin)
  - Cloud Storage (Storage Admin)
  - BigQuery (BigQuery Admin)
  - Cloud Build (Cloud Build Editor)
  - Service Account (Service Account Admin)
- Python 3.9+ for local development and testing
- Docker (for containerization)
- Estimated cost: $50-100 for training and serving resources

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for infrastructure as code, providing native integration with Google Cloud services.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/recommendation-system \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/personalized-recommendation-apis-vertex-ai-run/code/infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

Terraform provides a declarative approach to infrastructure management with excellent Google Cloud provider support.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

Bash scripts provide a straightforward deployment approach using Google Cloud CLI commands.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys a complete recommendation system including:

- **Cloud Storage**: Data storage for training datasets and model artifacts
- **BigQuery**: Data warehouse for user interaction analytics
- **Vertex AI**: Machine learning training and model serving
- **Cloud Run**: Serverless API hosting with auto-scaling
- **IAM**: Service accounts and permissions for secure access
- **Cloud Build**: Containerization and deployment pipeline

## Configuration Options

### Environment Variables

All implementations support these environment variables:

```bash
# Required
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"  # or your preferred region

# Optional customization
export BUCKET_NAME="rec-system-data-${PROJECT_ID}"
export SERVICE_NAME="recommendation-api"
export MODEL_NAME="product-recommendations"
export MACHINE_TYPE="n1-standard-4"
export MIN_REPLICAS="1"
export MAX_REPLICAS="10"
```

### Terraform Variables

Key variables for Terraform deployment:

```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "machine_type" {
  description = "Machine type for training jobs"
  type        = string
  default     = "n1-standard-4"
}

variable "enable_gpu" {
  description = "Enable GPU acceleration for training"
  type        = bool
  default     = true
}
```

## Deployment Steps

### 1. Infrastructure Provisioning

The deployment creates the following resources in order:

1. **Project APIs**: Enables required Google Cloud APIs
2. **Service Accounts**: Creates service accounts with appropriate permissions
3. **Storage Resources**: Sets up Cloud Storage bucket and BigQuery dataset
4. **Vertex AI Resources**: Creates training pipeline and model registry
5. **Cloud Run Service**: Deploys the recommendation API

### 2. Model Training

After infrastructure deployment, the system automatically:

1. Generates synthetic training data
2. Uploads data to Cloud Storage
3. Submits training job to Vertex AI
4. Registers trained model in Model Registry
5. Deploys model to Vertex AI endpoint

### 3. API Deployment

The Cloud Run service provides these endpoints:

- `GET /` - Health check endpoint
- `POST /recommend` - Generate personalized recommendations
- `POST /feedback` - Record user feedback for model improvement

## Testing and Validation

### Health Check

```bash
# Get service URL
SERVICE_URL=$(gcloud run services describe recommendation-api --region=${REGION} --format="value(status.url)")

# Test health endpoint
curl -X GET "${SERVICE_URL}/"
```

### Recommendation Test

```bash
# Test recommendation generation
curl -X POST "${SERVICE_URL}/recommend" \
    -H "Content-Type: application/json" \
    -d '{
      "user_id": "user_123",
      "num_recommendations": 5
    }'
```

### Performance Testing

```bash
# Load test with Apache Bench (if available)
ab -n 100 -c 10 -T application/json -p test_payload.json "${SERVICE_URL}/recommend"
```

## Monitoring and Logging

### View Logs

```bash
# Cloud Run logs
gcloud logs read --project=${PROJECT_ID} --format="table(timestamp,severity,textPayload)" --filter="resource.type=cloud_run_revision"

# Vertex AI training logs
gcloud ai custom-jobs list --region=${REGION}
```

### Monitor Performance

```bash
# Check Cloud Run metrics
gcloud run services describe recommendation-api --region=${REGION} --format="export"

# Monitor Vertex AI endpoint
gcloud ai endpoints list --region=${REGION}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/recommendation-system
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

## Customization

### Modify Training Pipeline

To customize the machine learning model:

1. Update `recommendation_trainer.py` with your model architecture
2. Modify training parameters in the deployment configuration
3. Adjust the API service to handle your model's input/output format

### Scale Configuration

To adjust scaling parameters:

```bash
# Update Cloud Run scaling
gcloud run services update recommendation-api \
    --region=${REGION} \
    --min-instances=2 \
    --max-instances=50 \
    --cpu=4 \
    --memory=4Gi
```

### Add Custom Features

Extend the system by:

1. **Real-time Features**: Integrate with Pub/Sub for streaming data
2. **A/B Testing**: Use Cloud Run traffic splitting
3. **Monitoring**: Add custom metrics with Cloud Monitoring
4. **Security**: Implement authentication with Cloud IAM

## Security Considerations

### IAM Best Practices

- Service accounts follow principle of least privilege
- Cross-service authentication uses service account keys
- API endpoints can be secured with Cloud IAM

### Data Protection

- All data is encrypted at rest and in transit
- BigQuery datasets use customer-managed encryption keys (optional)
- Cloud Storage buckets have versioning enabled

### Network Security

- Cloud Run services use HTTPS by default
- Vertex AI endpoints are accessible only within the project
- VPC-native networking can be enabled for additional isolation

## Cost Optimization

### Resource Management

- Cloud Run scales to zero when not in use
- Vertex AI training jobs use preemptible instances when possible
- BigQuery uses partitioned tables for cost-effective queries
- Cloud Storage uses standard storage class with lifecycle policies

### Monitoring Costs

```bash
# View current costs
gcloud billing budgets list --billing-account=${BILLING_ACCOUNT_ID}

# Set up budget alerts
gcloud billing budgets create --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Recommendation System Budget" \
    --budget-amount=100USD
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
2. **Permission Denied**: Check service account permissions
3. **Training Job Failures**: Verify data format and training script
4. **Deployment Timeouts**: Increase timeout values in Cloud Run

### Debug Commands

```bash
# Check service account permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Verify API enablement
gcloud services list --enabled --project=${PROJECT_ID}

# Check resource quotas
gcloud compute project-info describe --project=${PROJECT_ID}
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../personalized-recommendation-apis-vertex-ai-run.md)
2. Review [Google Cloud documentation](https://cloud.google.com/docs)
3. Consult [Vertex AI documentation](https://cloud.google.com/vertex-ai/docs)
4. Check [Cloud Run documentation](https://cloud.google.com/run/docs)

## Contributing

When making changes to this infrastructure:

1. Test in a development project first
2. Update documentation for any new parameters
3. Follow Google Cloud security best practices
4. Validate all generated code before submission

## License

This infrastructure code is provided under the same license as the parent recipe repository.