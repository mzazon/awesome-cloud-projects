# Terraform Infrastructure for Immersive XR Content Delivery Platform

This Terraform configuration deploys a complete Immersive XR Content Delivery platform on Google Cloud Platform using Immersive Stream for XR, Cloud CDN, and Cloud Storage.

## Architecture Overview

The infrastructure creates:

- **Cloud Storage bucket** for XR assets with optimized caching policies
- **Cloud CDN** for global content delivery with edge caching
- **Load Balancer** with path-based routing for unified content delivery
- **Service Account** with appropriate IAM permissions for XR streaming
- **Monitoring and Alerting** for XR service performance tracking
- **Security Policy** with Cloud Armor for DDoS protection and rate limiting
- **Sample Web Application** demonstrating XR streaming integration

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK** installed and configured
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Authenticate and set project
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** installed (version >= 1.5)
   ```bash
   # Install Terraform
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **Required Permissions**:
   - Compute Admin
   - Storage Admin
   - Service Account Admin
   - Project IAM Admin
   - Monitoring Admin
   - Logging Admin

4. **Billing Account** linked to your Google Cloud project

5. **API Access**: Immersive Stream for XR (currently in preview - may require approval)

## Quick Start

### 1. Clone and Prepare

```bash
# Navigate to the terraform directory
cd gcp/immersive-xr-content-delivery-immersive-stream-xr-cdn/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your specific configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
resource_prefix = "my-xr-platform"
environment     = "dev"

# XR streaming configuration
xr_gpu_class                = "T4"
xr_gpu_count               = 1
xr_session_timeout         = 1800
xr_max_concurrent_sessions = 10

# Autoscaling settings
enable_autoscaling         = true
autoscaling_min_capacity   = 1
autoscaling_max_capacity   = 5
autoscaling_target_utilization = 70

# CDN configuration
cdn_cache_mode    = "CACHE_ALL_STATIC"
cdn_default_ttl   = 3600
cdn_max_ttl       = 86400

# Storage settings
storage_class        = "STANDARD"
enable_versioning    = true
bucket_public_access = true

# Security and SSL (optional)
enable_ssl = false
ssl_certificate_domains = []

# Monitoring
enable_monitoring    = true
enable_access_logs   = true
log_retention_days   = 30

# Labels
labels = {
  project     = "xr-content-delivery"
  team        = "platform"
  environment = "dev"
  managed-by  = "terraform"
}
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Confirm deployment when prompted
# Type 'yes' to proceed
```

### 4. Access Your XR Platform

After deployment, Terraform will output important information:

```bash
# Get the CDN endpoint
terraform output cdn_endpoint_http

# Get the web application URL
terraform output web_app_url

# Get service account details
terraform output xr_service_account_email
```

Access your XR platform at the web application URL provided in the outputs.

## Configuration Options

### XR Streaming Configuration

```hcl
# GPU Configuration
xr_gpu_class = "T4"        # Options: T4, V100, A100, K80
xr_gpu_count = 1           # Number of GPUs per instance (1-8)

# Session Management
xr_session_timeout         = 1800  # Session timeout in seconds (300-7200)
xr_max_concurrent_sessions = 10    # Max concurrent sessions (1-100)
```

### Autoscaling Configuration

```hcl
enable_autoscaling             = true
autoscaling_min_capacity       = 1    # Minimum instances (0-10)
autoscaling_max_capacity       = 5    # Maximum instances (1-50)
autoscaling_target_utilization = 70   # Target CPU utilization % (10-90)
```

### CDN and Storage Configuration

```hcl
# CDN Settings
cdn_cache_mode  = "CACHE_ALL_STATIC"  # Cache behavior
cdn_default_ttl = 3600                # Default cache TTL (0-86400)
cdn_max_ttl     = 86400               # Maximum cache TTL (0-31536000)

# Storage Settings
storage_class        = "STANDARD"     # STANDARD, NEARLINE, COLDLINE, ARCHIVE
enable_versioning    = true           # Enable object versioning
bucket_public_access = true           # Allow public read access
```

### SSL/TLS Configuration

```hcl
enable_ssl = true
ssl_certificate_domains = [
  "xr.example.com",
  "www.xr.example.com"
]
```

### Monitoring and Security

```hcl
# Monitoring
enable_monitoring  = true
enable_access_logs = true
log_retention_days = 30    # Log retention (1-365 days)

# Security
# Cloud Armor security policy is automatically configured
# Rate limiting and DDoS protection included
```

## Outputs

The Terraform configuration provides comprehensive outputs:

| Output | Description |
|--------|-------------|
| `cdn_endpoint_http` | HTTP endpoint for CDN access |
| `cdn_endpoint_https` | HTTPS endpoint (if SSL enabled) |
| `web_app_url` | URL for the sample XR web application |
| `storage_bucket_name` | Name of the Cloud Storage bucket |
| `xr_service_account_email` | Service account for XR operations |
| `health_check_name` | Name of the health check resource |
| `security_policy_name` | Name of the Cloud Armor security policy |

## Advanced Usage

### Custom Domain Setup

1. Update your DNS to point to the CDN IP address:
   ```bash
   # Get the CDN IP address
   terraform output cdn_ip_address
   ```

2. Configure SSL with your custom domains:
   ```hcl
   enable_ssl = true
   ssl_certificate_domains = ["your-domain.com"]
   ```

3. Apply the changes:
   ```bash
   terraform apply
   ```

### Monitoring and Alerting

The infrastructure includes built-in monitoring:

- **Custom Metrics**: XR session starts, session duration
- **Alert Policies**: GPU utilization alerts
- **Health Checks**: Automatic health monitoring
- **Access Logs**: Load balancer access logging

View metrics in Google Cloud Console:
1. Navigate to **Monitoring > Metrics Explorer**
2. Search for custom metrics: `xr_session_starts`, `xr_session_duration`

### Scaling Configuration

Adjust scaling parameters based on your needs:

```hcl
# For development/testing
autoscaling_min_capacity = 0
autoscaling_max_capacity = 2

# For production workloads
autoscaling_min_capacity = 2
autoscaling_max_capacity = 20
autoscaling_target_utilization = 60
```

### Cost Optimization

1. **Use appropriate GPU classes**:
   - `T4`: Cost-effective for most workloads
   - `V100`: High performance for demanding applications
   - `A100`: Maximum performance for AI/ML workloads

2. **Configure storage classes**:
   ```hcl
   storage_class = "NEARLINE"  # For infrequently accessed assets
   ```

3. **Adjust session timeouts**:
   ```hcl
   xr_session_timeout = 900  # Shorter sessions for cost savings
   ```

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**:
   ```bash
   # Enable required APIs manually
   gcloud services enable compute.googleapis.com
   gcloud services enable storage.googleapis.com
   gcloud services enable stream.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   
   # Add required roles
   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="user:your-email@example.com" \
     --role="roles/compute.admin"
   ```

3. **Immersive Stream for XR Unavailable**:
   - Service is currently in preview
   - May require approval from Google Cloud
   - Check regional availability

### Debugging

1. **Enable Terraform debugging**:
   ```bash
   export TF_LOG=DEBUG
   terraform apply
   ```

2. **Check resource status**:
   ```bash
   # Verify bucket creation
   gsutil ls -b gs://$(terraform output -raw storage_bucket_name)
   
   # Check CDN status
   gcloud compute backend-buckets describe $(terraform output -raw cdn_backend_bucket_name)
   ```

3. **View logs**:
   ```bash
   # Check deployment logs
   gcloud logging read "resource.type=gce_backend_service" --limit=50
   ```

## Cleanup

To avoid ongoing charges, destroy the infrastructure when no longer needed:

```bash
# Destroy all resources
terraform destroy

# Confirm destruction when prompted
# Type 'yes' to proceed
```

**Warning**: This will permanently delete all resources including stored XR assets.

## Security Considerations

### Data Protection
- All data is encrypted at rest in Cloud Storage
- CDN provides DDoS protection via Cloud Armor
- Rate limiting prevents abuse

### Access Control
- Service accounts follow principle of least privilege
- IAM policies restrict resource access
- Public access limited to static assets only

### Network Security
- Security policies include rate limiting rules
- Health checks ensure service availability
- SSL/TLS encryption for data in transit (when enabled)

## Support and Documentation

### Google Cloud Resources
- [Immersive Stream for XR Documentation](https://cloud.google.com/immersive-stream/xr/docs)
- [Cloud CDN Best Practices](https://cloud.google.com/cdn/docs/best-practices)
- [Cloud Storage Performance Guide](https://cloud.google.com/storage/docs/best-practices)

### Terraform Resources
- [Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

### Getting Help
- For Terraform issues: [Terraform Community Forum](https://discuss.hashicorp.com/c/terraform-core)
- For Google Cloud issues: [Google Cloud Support](https://cloud.google.com/support)
- For recipe-specific issues: Check the original recipe documentation

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's requirements before production use.