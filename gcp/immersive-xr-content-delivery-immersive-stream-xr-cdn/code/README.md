# Infrastructure as Code for Immersive XR Content Delivery with Immersive Stream for XR and Cloud CDN

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Immersive XR Content Delivery with Immersive Stream for XR and Cloud CDN".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Immersive Stream for XR
  - Cloud CDN
  - Cloud Storage
  - Compute Engine
  - IAM
  - Cloud Logging
- Estimated cost: $50-150 for initial setup and testing

> **Note**: Immersive Stream for XR requires approval and is currently available in select regions. Review the [service documentation](https://cloud.google.com/immersive-stream/xr/docs) for current availability and requirements.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply \
    --location=${REGION} \
    --file=main.yaml \
    --project=${PROJECT_ID} \
    --deployment-id=xr-content-delivery

# Monitor deployment progress
gcloud infra-manager deployments describe \
    --location=${REGION} \
    --deployment-id=xr-content-delivery
```

### Using Terraform

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform configuration
cd terraform/

# Initialize Terraform
terraform init

# Review planned infrastructure changes
terraform plan \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Apply configuration
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
gcloud beta immersive-stream xr service-instances list --location=${REGION}
```

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager configuration supports the following customizable parameters:

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `bucket_name`: Cloud Storage bucket name for XR assets
- `cdn_name`: Cloud CDN configuration name
- `stream_name`: Immersive Stream for XR service instance name
- `gpu_class`: GPU type for XR rendering (default: T4)
- `gpu_count`: Number of GPUs per instance (default: 1)
- `max_concurrent_sessions`: Maximum concurrent XR sessions (default: 10)
- `session_timeout`: Session timeout in seconds (default: 1800)

### Terraform Variables

Key variables can be customized in `terraform.tfvars` or via command line:

```bash
# Example terraform.tfvars
project_id = "my-xr-project"
region = "us-central1"
bucket_name = "my-xr-assets"
cdn_name = "my-xr-cdn"
stream_name = "my-xr-stream"
gpu_class = "T4"
gpu_count = 1
max_concurrent_sessions = 20
enable_autoscaling = true
min_capacity = 1
max_capacity = 5
target_utilization = 70
```

### Script Configuration

The bash scripts use environment variables for configuration:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export BUCKET_NAME="custom-xr-assets"
export CDN_NAME="custom-xr-cdn"
export STREAM_NAME="custom-xr-stream"
```

## Architecture Overview

The deployed infrastructure includes:

1. **Cloud Storage**: Bucket for storing XR assets, 3D models, and textures
2. **Cloud CDN**: Global content delivery network for static asset caching
3. **Immersive Stream for XR**: Cloud-based XR rendering service with GPU instances
4. **Load Balancer**: HTTP(S) load balancer with path-based routing
5. **IAM Configuration**: Service accounts and permissions for secure access
6. **Monitoring**: Custom metrics, alerting policies, and logging configuration

## Validation

After deployment, verify the infrastructure:

### Infrastructure Manager

```bash
# Check deployment status
gcloud infra-manager deployments describe \
    --location=${REGION} \
    --deployment-id=xr-content-delivery \
    --format="table(state,stateDetail)"

# List created resources
gcloud infra-manager deployments describe \
    --location=${REGION} \
    --deployment-id=xr-content-delivery \
    --format="value(serviceAccount,latestRevision)"
```

### Terraform

```bash
cd terraform/

# Verify resource creation
terraform show

# Test outputs
terraform output cdn_ip_address
terraform output xr_service_endpoint
terraform output storage_bucket_url
```

### All Implementations

```bash
# Verify XR service status
gcloud beta immersive-stream xr service-instances describe ${STREAM_NAME} \
    --location=${REGION} \
    --format="table(name,state,endpoint)"

# Test CDN accessibility
CDN_IP=$(gcloud compute forwarding-rules describe xr-cdn-rule --global --format='value(IPAddress)')
curl -I "http://${CDN_IP}/configs/app-config.json"

# Check storage bucket
gsutil ls gs://${BUCKET_NAME}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    --location=${REGION} \
    --deployment-id=xr-content-delivery \
    --delete-policy=DELETE

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}"

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
gcloud beta immersive-stream xr service-instances list --location=${REGION}
gcloud compute forwarding-rules list --global
gsutil ls
```

## Troubleshooting

### Common Issues

1. **XR Service Approval Required**: Immersive Stream for XR requires approval. Check service availability in your region and request access if needed.

2. **GPU Quota Limitations**: Ensure sufficient GPU quota in your project. Check and request quota increases if needed:
   ```bash
   gcloud compute project-info describe --format="table(quotas.limit,quotas.metric,quotas.usage)"
   ```

3. **IAM Permissions**: Verify you have the required IAM roles:
   - Immersive Stream Admin
   - Storage Admin
   - Compute Admin
   - Project Editor or equivalent

4. **Region Availability**: Immersive Stream for XR is available in limited regions. Verify service availability:
   ```bash
   gcloud beta immersive-stream xr locations list
   ```

### Debugging

Enable debug logging for detailed troubleshooting:

```bash
# For gcloud commands
export CLOUDSDK_CORE_VERBOSITY=debug

# For Terraform
export TF_LOG=DEBUG

# For Infrastructure Manager
gcloud infra-manager deployments describe \
    --location=${REGION} \
    --deployment-id=xr-content-delivery \
    --format="yaml"
```

## Performance Optimization

### XR Service Optimization

- **GPU Selection**: Choose appropriate GPU class based on rendering requirements
- **Autoscaling**: Configure autoscaling parameters based on usage patterns
- **Session Management**: Optimize session timeout values for user experience

### CDN Optimization

- **Cache Policies**: Configure appropriate cache TTL for different asset types
- **Compression**: Enable compression for text-based assets
- **Regional Caching**: Optimize cache regions based on user distribution

### Cost Optimization

- **Resource Scheduling**: Implement scheduled scaling for predictable usage patterns
- **Asset Optimization**: Compress and optimize 3D assets before upload
- **Monitoring**: Set up billing alerts and resource usage monitoring

## Security Considerations

- **IAM Best Practices**: Use least privilege principle for service accounts
- **Network Security**: Configure appropriate firewall rules and network policies
- **Asset Protection**: Implement proper access controls for XR assets
- **Session Security**: Configure session timeouts and authentication mechanisms

## Support

For issues with this infrastructure code:

1. Review the original [recipe documentation](../immersive-xr-content-delivery-immersive-stream-xr-cdn.md)
2. Check [Google Cloud Immersive Stream for XR documentation](https://cloud.google.com/immersive-stream/xr/docs)
3. Consult [Cloud CDN best practices](https://cloud.google.com/cdn/docs/best-practices)
4. Review [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
5. Check [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Version Information

- **Recipe Version**: 1.0
- **Infrastructure Manager**: Uses latest Google Cloud resource types
- **Terraform**: Compatible with Google Cloud Provider v4.0+
- **Google Cloud CLI**: Requires gcloud v400.0.0 or later for Immersive Stream for XR commands

## License

This infrastructure code is provided under the same license as the parent recipe repository.