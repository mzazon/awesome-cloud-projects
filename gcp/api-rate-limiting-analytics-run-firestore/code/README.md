# Infrastructure as Code for API Rate Limiting and Analytics with Cloud Run and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "API Rate Limiting and Analytics with Cloud Run and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured (version 450.0.0 or later)
- Active Google Cloud project with billing enabled
- Docker installed locally for container development
- Appropriate IAM permissions:
  - Cloud Run Admin
  - Firestore Admin
  - Cloud Build Editor
  - Project Editor (for Infrastructure Manager)
  - Service Account Admin
- For Terraform: Terraform CLI installed (version 1.5+ recommended)

## Architecture Overview

This solution deploys:
- **Cloud Run Service**: Serverless API gateway with automatic scaling
- **Firestore Database**: NoSQL database for rate limiting and analytics storage
- **Container Registry**: Storage for containerized application
- **Cloud Monitoring**: Observability and alerting for the API gateway
- **IAM Roles**: Appropriate service accounts and permissions

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's fully managed service for infrastructure automation.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments create api-gateway-deployment \
    --location=us-central1 \
    --source-blueprint=main.yaml \
    --input-values="project_id=$(gcloud config get-value project),region=us-central1"

# Monitor deployment status
gcloud infra-manager deployments describe api-gateway-deployment \
    --location=us-central1

# Get service URL after deployment
gcloud infra-manager deployments describe api-gateway-deployment \
    --location=us-central1 \
    --format="value(serviceAccount.email)"
```

### Using Terraform

Terraform provides cross-platform infrastructure management with extensive provider support.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform (downloads providers and modules)
terraform init

# Review planned changes
terraform plan -var="project_id=$(gcloud config get-value project)" \
                -var="region=us-central1"

# Apply infrastructure changes
terraform apply -var="project_id=$(gcloud config get-value project)" \
                 -var="region=us-central1"

# View important outputs
terraform output
```

### Using Bash Scripts

Automated deployment scripts that replicate the manual recipe steps.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# The script will prompt for required variables:
# - Project ID (or use current gcloud project)
# - Region (default: us-central1)
# - Service name (default: api-rate-limiter)
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
    required: true
  
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  
  service_name:
    description: "Cloud Run service name"
    type: string
    default: "api-rate-limiter"
  
  container_cpu:
    description: "CPU allocation for Cloud Run"
    type: string
    default: "1"
  
  container_memory:
    description: "Memory allocation for Cloud Run"
    type: string
    default: "1Gi"
```

### Terraform Variables

Customize deployment in `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
service_name = "api-rate-limiter"

# Optional customizations
container_cpu = "1"
container_memory = "1Gi"
max_instances = 10
min_instances = 0
concurrency = 100

# Firestore configuration
firestore_location = "us-central1"
enable_delete_protection = false

# Monitoring configuration
enable_monitoring_dashboard = true
enable_alerting = true
alert_notification_channels = []
```

### Environment Variables for Scripts

Set these environment variables before running bash scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export SERVICE_NAME="api-rate-limiter"
export CONTAINER_CPU="1"
export CONTAINER_MEMORY="1Gi"
```

## Deployment Verification

After deployment, verify the solution is working correctly:

### 1. Check Cloud Run Service

```bash
# Get service URL
SERVICE_URL=$(gcloud run services describe api-rate-limiter \
    --region=us-central1 \
    --format='value(status.url)')

# Test health endpoint
curl "${SERVICE_URL}/health"
```

### 2. Test API with Rate Limiting

```bash
# Generate test API key
TEST_API_KEY="test-key-$(openssl rand -hex 16)"

# Test authenticated endpoint
curl -H "X-API-Key: ${TEST_API_KEY}" \
     "${SERVICE_URL}/api/v1/data"

# Check rate limit headers
curl -v -H "X-API-Key: ${TEST_API_KEY}" \
     "${SERVICE_URL}/api/v1/data" 2>&1 | grep -i "x-ratelimit"
```

### 3. Verify Firestore Collections

```bash
# Check if Firestore collections exist
gcloud firestore collections list

# Expected collections: rate_limits, api_analytics
```

### 4. Access Monitoring Dashboard

Navigate to [Cloud Monitoring](https://console.cloud.google.com/monitoring) to view:
- API request rates and response codes
- Cloud Run service metrics
- Custom dashboards (if enabled)

## Testing the Solution

### Load Testing

Test rate limiting behavior with multiple requests:

```bash
# Generate 105 requests to trigger rate limiting
for i in {1..105}; do
    response=$(curl -s -w "%{http_code}" \
                   -H "X-API-Key: ${TEST_API_KEY}" \
                   "${SERVICE_URL}/api/v1/data")
    http_code="${response: -3}"
    if [[ "${http_code}" == "429" ]]; then
        echo "Rate limit enforced at request $i"
        break
    fi
    if (( i % 10 == 0 )); then
        echo "Completed $i requests successfully"
    fi
done
```

### Analytics Verification

```bash
# Wait for analytics to be written
sleep 10

# Retrieve usage analytics
curl -s -H "X-API-Key: ${TEST_API_KEY}" \
     "${SERVICE_URL}/api/v1/analytics" | jq '.'
```

## Monitoring and Observability

### Cloud Monitoring Integration

The deployment includes:

1. **Built-in Metrics**: Cloud Run request count, latency, and error rates
2. **Custom Dashboard**: API-specific metrics and usage analytics
3. **Alerting Policies**: Notifications for high error rates or unusual traffic

### Log Analysis

View application logs:

```bash
# Stream Cloud Run logs
gcloud logs tail "resource.type=cloud_run_revision AND resource.labels.service_name=api-rate-limiter" \
    --location=us-central1

# Query specific log entries
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=api-rate-limiter" \
    --limit=50 \
    --format="table(timestamp,textPayload)"
```

## Security Considerations

### Firestore Security Rules

The deployment includes security rules that:
- Allow authenticated services to read/write rate limit data
- Enable analytics collection while protecting sensitive information
- Provide foundation for production-ready access controls

### IAM and Service Accounts

The infrastructure creates:
- Dedicated service account for Cloud Run with minimal required permissions
- Firestore access limited to necessary operations
- Cloud Build service account for container builds

### Network Security

- Cloud Run service configured with appropriate concurrency limits
- Container runs as non-root user for enhanced security
- Environment variables used for configuration (no hardcoded secrets)

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Ensure required APIs are enabled
   gcloud services enable run.googleapis.com firestore.googleapis.com \
       cloudbuild.googleapis.com monitoring.googleapis.com
   
   # Verify IAM permissions
   gcloud projects get-iam-policy $(gcloud config get-value project)
   ```

2. **Container Build Failures**
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # Get detailed build information
   gcloud builds describe [BUILD_ID]
   ```

3. **Firestore Connection Issues**
   ```bash
   # Verify Firestore database exists
   gcloud firestore databases list
   
   # Check service account permissions
   gcloud projects get-iam-policy $(gcloud config get-value project) \
       --flatten="bindings[].members" \
       --filter="bindings.members:serviceAccount"
   ```

4. **Rate Limiting Not Working**
   ```bash
   # Check Firestore security rules
   gcloud firestore rules get
   
   # Verify collections exist and have data
   gcloud firestore query "SELECT * FROM rate_limits LIMIT 5"
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# For Terraform
export TF_LOG=DEBUG

# For gcloud commands
export CLOUDSDK_CORE_VERBOSITY=debug

# Check Cloud Run service logs
gcloud run services logs read api-rate-limiter --region=us-central1
```

## Cost Optimization

### Estimated Costs

Daily cost breakdown (USD, approximate):
- Cloud Run: $0.10-$0.50 (based on requests and compute time)
- Firestore: $0.01-$0.05 (document reads/writes)
- Container Registry: $0.01 (storage)
- Cloud Monitoring: Free tier
- **Total**: $0.12-$0.56 per day

### Cost Optimization Tips

1. **Use Free Tier**: Most services offer generous free tiers
2. **Optimize Container**: Minimize container size and startup time
3. **Configure Scaling**: Set appropriate min/max instances
4. **Monitor Usage**: Use Cloud Billing alerts for cost control

```bash
# Set up billing alerts
gcloud billing budgets create \
    --billing-account=[BILLING_ACCOUNT_ID] \
    --display-name="API Gateway Budget" \
    --budget-amount=10USD \
    --threshold-rules-percent=0.8
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete api-gateway-deployment \
    --location=us-central1

# Verify cleanup
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=$(gcloud config get-value project)" \
                  -var="region=us-central1"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Script will prompt for confirmation before deleting resources
```

### Manual Cleanup Verification

Verify all resources are removed:

```bash
# Check Cloud Run services
gcloud run services list --region=us-central1

# Check Firestore collections
gcloud firestore collections list

# Check container images
gcloud container images list

# Check Cloud Build history
gcloud builds list --limit=5
```

## Advanced Configuration

### Multi-Region Deployment

For global deployment, modify the configuration:

```bash
# Deploy to multiple regions
REGIONS=("us-central1" "europe-west1" "asia-southeast1")

for region in "${REGIONS[@]}"; do
    # Use region-specific deployment names
    terraform apply -var="project_id=${PROJECT_ID}" \
                   -var="region=${region}" \
                   -var="service_name=api-rate-limiter-${region}"
done
```

### Custom Rate Limiting

Modify the application code to implement:
- Per-endpoint rate limits
- User tier-based quotas
- Dynamic rate limit adjustment
- Geographic rate limiting

### Integration with Existing Systems

Connect to existing infrastructure:

```bash
# Use existing VPC
terraform apply -var="vpc_network=projects/${PROJECT_ID}/global/networks/existing-vpc"

# Connect to existing monitoring
terraform apply -var="notification_channels=[\"projects/${PROJECT_ID}/notificationChannels/12345\"]"
```

## Support and Contributing

### Getting Help

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: [Cloud Run](https://cloud.google.com/run/docs), [Firestore](https://cloud.google.com/firestore/docs)
3. **Terraform Documentation**: [Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: Google Cloud Community, Stack Overflow

### Reporting Issues

When reporting issues, include:
- Deployment method used (Infrastructure Manager, Terraform, or Scripts)
- Error messages and logs
- Google Cloud project configuration
- Steps to reproduce the issue

### Contributing Improvements

To contribute improvements:
1. Test changes thoroughly in a development environment
2. Follow Google Cloud and Terraform best practices
3. Update documentation for any configuration changes
4. Ensure backward compatibility where possible

---

**Note**: This infrastructure code implements the complete API Rate Limiting and Analytics solution as described in the recipe. For production deployments, consider additional security hardening, monitoring configuration, and high availability patterns based on your specific requirements.