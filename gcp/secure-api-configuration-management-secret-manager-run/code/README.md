# Infrastructure as Code for Secure API Configuration Management with Secret Manager and Cloud Run

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure API Configuration Management with Secret Manager and Cloud Run".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Common Requirements
- Google Cloud account with billing enabled
- gcloud CLI installed and configured (or use Cloud Shell)
- Appropriate IAM permissions for resource creation:
  - Secret Manager Admin
  - Cloud Run Admin
  - API Gateway Admin
  - Service Account Admin
  - Project IAM Admin
  - Cloud Build Editor
  - Container Registry Service Agent

### Tool-Specific Requirements

#### Infrastructure Manager
- Infrastructure Manager API enabled
- Understanding of Google Cloud Deployment Manager concepts

#### Terraform
- Terraform CLI installed (version >= 1.0)
- Google Cloud provider configured
- Understanding of Terraform state management

#### Bash Scripts
- Basic shell scripting knowledge
- Docker installed (for local container builds)

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable apigateway.googleapis.com

# Create deployment
gcloud infra-manager deployments create secure-api-deployment \
    --location=${REGION} \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe secure-api-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./deploy.sh

# Follow prompts and monitor deployment progress
```

## Architecture Components

This infrastructure creates the following resources:

### Security Layer
- **Secret Manager Secrets**: Secure storage for database credentials, API keys, and application configuration
- **IAM Service Account**: Dedicated service account with least privilege access to secrets
- **IAM Policies**: Fine-grained access control for secret access

### Application Layer
- **Cloud Run Service**: Containerized API service with secure secret integration
- **Container Registry**: Secure storage for container images
- **Application Code**: Sample Flask API with Secret Manager integration

### API Management Layer
- **API Gateway**: Managed API gateway with authentication and rate limiting
- **OpenAPI Specification**: API documentation and security definitions
- **API Keys**: Authentication tokens for API access

### Monitoring and Logging
- **Cloud Audit Logs**: Comprehensive logging for secret access and API calls
- **Cloud Monitoring**: Performance and security monitoring with alerting

## Configuration Options

### Infrastructure Manager Variables

```yaml
# main.yaml variables section
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  service_name:
    description: "Cloud Run service name"
    type: string
    default: "secure-api"
  enable_monitoring:
    description: "Enable advanced monitoring"
    type: bool
    default: true
```

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `project_id` | Google Cloud Project ID | string | required |
| `region` | Deployment region | string | us-central1 |
| `zone` | Deployment zone | string | us-central1-a |
| `service_name` | Cloud Run service name | string | secure-api |
| `secret_prefix` | Prefix for secret names | string | api-config |
| `container_cpu` | CPU allocation for Cloud Run | string | 1 |
| `container_memory` | Memory allocation for Cloud Run | string | 512Mi |
| `max_instances` | Maximum Cloud Run instances | number | 10 |
| `enable_monitoring` | Enable advanced monitoring | bool | true |

### Environment Variables for Scripts

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export SERVICE_NAME="secure-api"
export SECRET_PREFIX="api-config"
export CONTAINER_CPU="1"
export CONTAINER_MEMORY="512Mi"
export MAX_INSTANCES="10"
```

## Security Considerations

### Secret Management
- All sensitive data stored in Secret Manager with encryption at rest
- Secrets accessed at runtime, never stored in container images
- Automatic secret versioning and rotation capabilities
- Comprehensive audit logging for all secret access

### Access Control
- Dedicated service account with least privilege IAM policies
- Secret-level access controls for fine-grained permissions
- API Gateway authentication and authorization
- Network security through VPC and firewall rules

### Container Security
- Non-root container execution
- Minimal base images with security updates
- Container image scanning through Container Analysis
- Runtime security monitoring

## Monitoring and Observability

### Metrics and Logging
- Cloud Run service metrics (latency, error rates, CPU/memory usage)
- Secret Manager access logs and audit trails
- API Gateway request/response logging
- Custom application metrics through Cloud Monitoring

### Alerting Policies
- High secret access rate alerts
- API Gateway authentication failures
- Cloud Run service health monitoring
- Resource quota and billing alerts

### Dashboards
- API performance and usage dashboards
- Security monitoring dashboards
- Infrastructure health dashboards
- Cost optimization dashboards

## Testing and Validation

### Health Checks
```bash
# Test service health
curl -s "${SERVICE_URL}/health"

# Test configuration endpoint
curl -s "${GATEWAY_URL}/config?key=${API_KEY}"

# Test secure data endpoint
curl -s -H "Authorization: Bearer ${API_TOKEN}" \
    "${GATEWAY_URL}/api/data?key=${API_KEY}"
```

### Security Validation
```bash
# Verify secret access logs
gcloud logging read 'protoPayload.serviceName="secretmanager.googleapis.com"' \
    --limit=10

# Test unauthorized access (should fail)
curl -s "${GATEWAY_URL}/config"

# Verify IAM policies
gcloud secrets get-iam-policy ${SECRET_NAME}
```

### Performance Testing
```bash
# Load testing with Apache Bench
ab -n 1000 -c 10 "${SERVICE_URL}/health"

# API Gateway performance testing
for i in {1..100}; do
  curl -s "${GATEWAY_URL}/config?key=${API_KEY}" > /dev/null
done
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete secure-api-deployment \
    --location=${REGION} \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

```bash
# Delete remaining resources manually
gcloud projects delete ${PROJECT_ID} --quiet

# Or clean up individual resources
gcloud run services delete ${SERVICE_NAME} --region=${REGION} --quiet
gcloud secrets delete ${SECRET_NAME}-db --quiet
gcloud secrets delete ${SECRET_NAME}-keys --quiet
gcloud secrets delete ${SECRET_NAME}-config --quiet
```

## Troubleshooting

### Common Issues

#### Permission Errors
```bash
# Grant required permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:your-email@domain.com" \
    --role="roles/secretmanager.admin"
```

#### API Not Enabled
```bash
# Enable required APIs
gcloud services enable secretmanager.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable apigateway.googleapis.com
```

#### Container Build Failures
```bash
# Check Cloud Build logs
gcloud builds list --limit=5

# Debug build issues
gcloud builds log ${BUILD_ID}
```

#### Secret Access Issues
```bash
# Verify service account permissions
gcloud secrets get-iam-policy ${SECRET_NAME}

# Test secret access
gcloud secrets versions access latest --secret=${SECRET_NAME}
```

### Debugging Commands

```bash
# Check service logs
gcloud logs read "resource.type=cloud_run_revision" --limit=50

# Monitor API Gateway metrics
gcloud monitoring metrics list --filter="api_gateway"

# Verify resource status
gcloud run services describe ${SERVICE_NAME} --region=${REGION}
gcloud secrets list
gcloud api-gateway gateways list --location=${REGION}
```

## Cost Optimization

### Resource Sizing
- Cloud Run: Start with minimal CPU/memory and scale based on usage
- Secret Manager: Pay per secret operation, optimize access patterns
- API Gateway: Monitor request volume for cost optimization

### Free Tier Usage
- Cloud Run: 2 million requests per month free
- Secret Manager: 6 secret versions per month free
- Cloud Build: 120 build-minutes per day free

### Monitoring Costs
```bash
# Check current costs
gcloud billing budgets list

# Set up budget alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT} \
    --display-name="Secure API Budget" \
    --budget-amount=50USD
```

## Advanced Configuration

### Custom Domain Setup
```bash
# Add custom domain to API Gateway
gcloud api-gateway gateways update ${GATEWAY_NAME} \
    --location=${REGION} \
    --api-config=${GATEWAY_NAME}-config-custom
```

### Multi-Environment Setup
```bash
# Deploy to different environments
export ENVIRONMENT="staging"
terraform workspace new ${ENVIRONMENT}
terraform apply -var="environment=${ENVIRONMENT}"
```

### CI/CD Integration
```yaml
# Example Cloud Build configuration
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/$PROJECT_ID/secure-api', '.']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/$PROJECT_ID/secure-api']
  - name: 'gcr.io/cloud-builders/gcloud'
    args: ['run', 'deploy', 'secure-api', '--image', 'gcr.io/$PROJECT_ID/secure-api']
```

## Support and Documentation

### Official Documentation
- [Google Cloud Secret Manager](https://cloud.google.com/secret-manager/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [API Gateway Documentation](https://cloud.google.com/api-gateway/docs)
- [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)

### Best Practices
- [Secret Manager Best Practices](https://cloud.google.com/secret-manager/docs/best-practices)
- [Cloud Run Security](https://cloud.google.com/run/docs/securing)
- [API Gateway Authentication](https://cloud.google.com/api-gateway/docs/authentication-method)

### Community Resources
- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - Google Cloud Platform](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Reddit - Google Cloud](https://www.reddit.com/r/googlecloud)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.