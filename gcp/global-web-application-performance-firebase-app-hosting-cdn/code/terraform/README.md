# Terraform Infrastructure for Global Web Application Performance

This directory contains Terraform Infrastructure as Code (IaC) for deploying a high-performance web application stack using Firebase App Hosting, Cloud CDN, and Google Cloud's global infrastructure.

## Architecture Overview

The infrastructure deploys a complete solution for global web application performance:

- **Firebase App Hosting**: Serverless web hosting with integrated CI/CD
- **Cloud CDN**: Global content distribution and caching
- **Global Load Balancer**: Traffic management and SSL termination
- **Cloud Storage**: Static asset hosting with optimized delivery
- **Cloud Functions**: Automated performance optimization
- **Cloud Monitoring**: Real-time performance tracking and alerting

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud Account**: With billing enabled and appropriate permissions
2. **Terraform**: Version >= 1.5.0 installed
3. **Google Cloud CLI**: Latest version installed and authenticated
4. **Project Permissions**: The following roles are required:
   - `roles/compute.admin` - For load balancer and CDN management
   - `roles/storage.admin` - For Cloud Storage bucket management
   - `roles/cloudfunctions.admin` - For Cloud Functions deployment
   - `roles/monitoring.admin` - For monitoring and alerting setup
   - `roles/firebase.admin` - For Firebase App Hosting configuration
   - `roles/serviceusage.serviceUsageAdmin` - For enabling APIs

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd gcp/global-web-application-performance-firebase-app-hosting-cdn/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment    = "prod"
resource_prefix = "webapp"
domain_name    = "example.com"
notification_email = "alerts@example.com"

# CDN optimization
cdn_cache_mode    = "CACHE_ALL_STATIC"
cdn_default_ttl   = 3600
cdn_max_ttl       = 86400

# Monitoring configuration
enable_monitoring = true
alert_threshold_latency_ms = 1000
alert_threshold_error_rate = 0.05
```

### 4. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Access Your Application

After deployment, Terraform will output the global IP address and URLs for accessing your web application.

## Configuration

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | Google Cloud project ID | `"my-web-app-project"` |
| `region` | Primary deployment region | `"us-central1"` |

### Important Optional Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `domain_name` | Custom domain for SSL certificate | `""` | `"example.com"` |
| `notification_email` | Email for monitoring alerts | `""` | `"admin@example.com"` |
| `environment` | Environment tag | `"dev"` | `"prod"` |
| `cdn_cache_mode` | CDN caching strategy | `"CACHE_ALL_STATIC"` | `"USE_ORIGIN_HEADERS"` |
| `enable_monitoring` | Enable Cloud Monitoring | `true` | `false` |

For a complete list of variables, see `variables.tf`.

## Deployment Process

### Step 1: API Enablement

Terraform automatically enables the required Google Cloud APIs:
- Compute Engine API
- Firebase API
- Cloud Build API
- Cloud Run API
- Cloud Monitoring API
- Cloud Functions API
- Cloud Storage API

### Step 2: Storage Infrastructure

Creates optimized Cloud Storage bucket with:
- Versioning enabled for asset management
- CORS configuration for web serving
- Lifecycle policies for cost optimization
- Public read access for web assets

### Step 3: Load Balancer and CDN

Deploys global load balancer with:
- Static global IP address
- Managed SSL certificate (if domain provided)
- CDN-enabled backend services
- Optimized caching policies
- Health checks for reliability

### Step 4: Performance Optimization

Configures automated optimization with:
- Cloud Functions for performance analysis
- Pub/Sub for event-driven optimization
- Cloud Scheduler for regular analysis
- Intelligent caching recommendations

### Step 5: Monitoring and Alerting

Sets up comprehensive monitoring:
- Performance metric collection
- Latency and error rate alerts
- Uptime monitoring
- Email notifications

## Post-Deployment Steps

### 1. Configure DNS (if using custom domain)

Update your DNS records to point to the global IP address:

```bash
# Get the global IP from Terraform output
terraform output global_ip_address

# Add DNS A record
# example.com -> <global_ip_address>
```

### 2. Upload Static Assets

Upload your web application assets to the configured bucket:

```bash
# Get bucket name from Terraform output
BUCKET_NAME=$(terraform output -raw storage_bucket_name)

# Upload static files
gsutil -m cp -r ./dist/* gs://$BUCKET_NAME/
```

### 3. Configure Firebase App Hosting

Set up your Firebase App Hosting backend to serve dynamic content:

```bash
# Initialize Firebase in your application directory
firebase init hosting

# Configure Firebase App Hosting backend
firebase apphosting:backends:create \
    --project=$(terraform output -raw project_id) \
    --location=$(terraform output -raw region) \
    --service-id=web-app-backend
```

### 4. Verify Deployment

Test your deployment:

```bash
# Test global IP access
curl -I $(terraform output -raw load_balancer_url_https)

# Check CDN cache headers
curl -I $(terraform output -raw load_balancer_url_https) | grep -i cache

# Verify SSL certificate (if using custom domain)
openssl s_client -connect $(terraform output -raw domain_name):443 -servername $(terraform output -raw domain_name)
```

## Monitoring and Optimization

### Performance Monitoring

The infrastructure includes comprehensive monitoring:

- **Latency Tracking**: Response time monitoring with 95th percentile alerts
- **Error Rate Monitoring**: HTTP error tracking with configurable thresholds
- **Cache Hit Rate**: CDN performance optimization metrics
- **Uptime Monitoring**: Global availability checks

### Automated Optimization

The deployed Cloud Function provides automated optimization:

- **Cache Policy Tuning**: Adjusts TTL based on hit rates
- **Performance Analysis**: Identifies bottlenecks and optimization opportunities
- **Alert Generation**: Notifies administrators of performance issues
- **Trend Analysis**: Tracks performance trends over time

### Viewing Metrics

Access monitoring dashboards:

```bash
# Open Cloud Monitoring console
gcloud monitoring dashboards list

# View function logs
gcloud functions logs read $(terraform output -raw performance_optimizer_function_name) \
    --region=$(terraform output -raw region)
```

## Customization

### CDN Cache Configuration

Adjust caching behavior by modifying variables:

```hcl
# Aggressive caching for static content
cdn_cache_mode    = "CACHE_ALL_STATIC"
cdn_default_ttl   = 7200    # 2 hours
cdn_max_ttl       = 31536000 # 1 year

# Origin-controlled caching
cdn_cache_mode    = "USE_ORIGIN_HEADERS"
cdn_default_ttl   = 0
```

### Function Optimization

Customize the performance optimization function:

1. Modify `function_code/main.py` for custom optimization logic
2. Update thresholds in the function configuration
3. Redeploy with `terraform apply`

### Monitoring Thresholds

Adjust alert thresholds:

```hcl
alert_threshold_latency_ms = 500    # 500ms latency threshold
alert_threshold_error_rate = 0.01   # 1% error rate threshold
```

## Cost Optimization

### Resource Optimization

The infrastructure includes several cost optimization features:

- **Storage Lifecycle**: Automatic transition to cheaper storage classes
- **Function Scaling**: Pay-per-use Cloud Functions with automatic scaling
- **CDN Efficiency**: Reduced bandwidth costs through intelligent caching
- **Regional Optimization**: Deploy in cost-effective regions

### Cost Monitoring

Monitor costs:

```bash
# View current month costs
gcloud billing budgets list

# Check resource usage
gcloud monitoring metrics list --filter="resource.type=gce_backend_service"
```

## Troubleshooting

### Common Issues

1. **SSL Certificate Provisioning**: Managed certificates can take up to 24 hours to provision
2. **DNS Propagation**: DNS changes may take time to propagate globally
3. **Function Deployment**: Check function logs if optimization isn't working
4. **CDN Cache**: Use cache-busting parameters for immediate content updates

### Debugging Commands

```bash
# Check SSL certificate status
gcloud compute ssl-certificates describe $(terraform output -raw ssl_certificate_name) --global

# Verify backend service health
gcloud compute backend-services get-health $(terraform output -raw backend_service_name) --global

# Test CDN caching
curl -H "Cache-Control: no-cache" $(terraform output -raw load_balancer_url_https)

# View detailed function logs
gcloud logging read "resource.type=cloud_function" --limit=50
```

### Support Resources

- [Firebase App Hosting Documentation](https://firebase.google.com/docs/app-hosting)
- [Cloud CDN Best Practices](https://cloud.google.com/cdn/docs/best-practices)
- [Cloud Load Balancing Guide](https://cloud.google.com/load-balancing/docs)
- [Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)

## Cleanup

To remove all infrastructure:

```bash
# Destroy all resources
terraform destroy

# Confirm deletion
# Type 'yes' when prompted
```

**Note**: This will permanently delete all resources including stored data. Ensure you have backups if needed.

## Security Considerations

### Default Security Features

- **Uniform Bucket Access**: Prevents object-level ACL bypass
- **HTTPS Enforcement**: All traffic encrypted in transit
- **Service Account Isolation**: Least-privilege access principles
- **VPC Integration**: Secure internal communication

### Additional Security Recommendations

1. **Enable Cloud Armor**: Add DDoS protection and WAF rules
2. **Implement IAM Policies**: Restrict access to production resources
3. **Regular Security Audits**: Monitor access logs and permissions
4. **Secret Management**: Use Secret Manager for sensitive configuration

## Contributing

When modifying this infrastructure:

1. Follow Terraform best practices
2. Update variable descriptions and validation
3. Test changes in development environment first
4. Update this README with any new features or requirements
5. Ensure security configurations meet your organization's standards

## Version History

- **v1.0**: Initial implementation with Firebase App Hosting and CDN
- **v1.1**: Added automated performance optimization
- **v1.2**: Enhanced monitoring and alerting capabilities

For questions or issues, please refer to the project documentation or contact your cloud infrastructure team.