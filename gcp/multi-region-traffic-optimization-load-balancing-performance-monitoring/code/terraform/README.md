# Multi-Region Traffic Optimization with Cloud Load Balancing and Performance Monitoring

This Terraform configuration deploys a comprehensive multi-region traffic optimization solution on Google Cloud Platform, featuring global load balancing, Cloud CDN, Network Intelligence Center monitoring, and advanced performance optimization.

## Architecture Overview

The infrastructure includes:

- **Global VPC Network**: Spans multiple regions with custom subnets
- **Multi-Region Compute Deployment**: Managed instance groups in US, Europe, and Asia-Pacific
- **Global HTTP(S) Load Balancer**: Single anycast IP with intelligent traffic routing
- **Cloud CDN**: Edge caching with advanced optimization policies
- **Network Intelligence Center**: Connectivity testing and network insights
- **Cloud Monitoring**: Uptime checks, alerting, and performance metrics
- **Advanced Load Balancing**: Circuit breakers, outlier detection, and compression

## Prerequisites

1. **Google Cloud Project**: Active project with billing enabled
2. **APIs Enabled**: The Terraform configuration will enable required APIs automatically
3. **Authentication**: One of the following:
   - `gcloud auth application-default login` (for local development)
   - Service account key file
   - GCE/Cloud Shell environment
4. **Terraform**: Version 1.0 or later
5. **Permissions**: Project Editor or custom role with compute, networking, and monitoring permissions

## Required IAM Permissions

Your account or service account needs these permissions:
- `compute.admin`
- `monitoring.admin` 
- `networkmanagement.admin`
- `serviceusage.serviceUsageAdmin`
- `iam.serviceAccountAdmin`

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the terraform directory
cd gcp/multi-region-traffic-optimization-load-balancing-performance-monitoring/code/terraform/
```

### 2. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"

# Optional customizations
resource_prefix = "traffic-opt"
primary_region  = "us-central1"
secondary_region = "europe-west1"
tertiary_region = "asia-southeast1"

# Instance configuration
instance_machine_type = "e2-medium"
instance_group_size   = 2

# Enable features
enable_monitoring           = true
enable_network_intelligence = true

# Labels for resource management
labels = {
  environment = "production"
  project     = "traffic-optimization"
  managed-by  = "terraform"
  team        = "platform"
}
```

### 4. Plan and Apply

```bash
# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
```

### 5. Verify Deployment

After successful deployment, test the global load balancer:

```bash
# Get the load balancer IP
LOAD_BALANCER_IP=$(terraform output -raw global_load_balancer_ip)

# Test connectivity
curl http://$LOAD_BALANCER_IP

# Test CDN headers
curl -I http://$LOAD_BALANCER_IP

# Test multiple requests to see regional distribution
for i in {1..10}; do
  curl http://$LOAD_BALANCER_IP | grep "Serving from"
  sleep 1
done
```

## Configuration Options

### Regional Configuration

```hcl
# Customize regions and zones
primary_region   = "us-central1"
secondary_region = "europe-west1" 
tertiary_region  = "asia-southeast1"

primary_zone   = "us-central1-a"
secondary_zone = "europe-west1-b"
tertiary_zone  = "asia-southeast1-a"

# Custom VPC CIDR ranges
vpc_cidr_ranges = {
  us_subnet   = "10.1.0.0/24"
  eu_subnet   = "10.2.0.0/24"
  apac_subnet = "10.3.0.0/24"
}
```

### Performance Optimization

```hcl
# Backend service optimization
backend_service_settings = {
  capacity_scaler    = 1.0
  max_utilization    = 0.8
  balancing_mode     = "UTILIZATION"
  locality_lb_policy = "ROUND_ROBIN"
}

# CDN optimization
cdn_settings = {
  cache_mode       = "CACHE_ALL_STATIC"
  default_ttl      = 3600
  max_ttl          = 86400
  client_ttl       = 3600
  compression      = true
  negative_caching = true
}

# Circuit breaker settings
circuit_breaker_settings = {
  max_requests         = 1000
  max_pending_requests = 100
  max_retries          = 3
  max_connections      = 1000
}
```

### Security Configuration

```hcl
# Restrict access by IP range
allowed_source_ranges = [
  "0.0.0.0/0"  # Allow all (default)
  # "10.0.0.0/8",     # Private networks only
  # "203.0.113.0/24"  # Specific IP range
]

# SSL certificates for HTTPS (optional)
ssl_certificates = [
  # "projects/PROJECT_ID/global/sslCertificates/my-cert"
]
```

### Monitoring Configuration

```hcl
# Monitoring settings
monitoring_settings = {
  uptime_check_timeout     = "10s"
  uptime_check_period      = "60s"
  alert_latency_threshold  = 1.0  # seconds
  alert_duration           = "120s"
}

# Health check settings
health_check_settings = {
  port                = 8080
  request_path        = "/"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}
```

## Outputs

The Terraform configuration provides comprehensive outputs:

```bash
# View all outputs
terraform output

# Specific outputs
terraform output global_load_balancer_ip
terraform output backend_service_name
terraform output deployment_summary
terraform output console_urls
```

Key outputs include:
- `global_load_balancer_ip`: Primary load balancer IP address
- `global_load_balancer_url`: HTTP URL for testing
- `instance_groups`: Information about regional instance groups
- `console_urls`: Direct links to Google Cloud Console
- `validation_commands`: Commands for testing the deployment

## Monitoring and Observability

### Cloud Console Access

Access monitoring dashboards using the output URLs:

```bash
# Get console URLs
terraform output console_urls
```

This provides direct links to:
- Load Balancer management
- Cloud Monitoring dashboards
- Network Intelligence Center
- Cloud CDN configuration
- Compute Engine instances

### Custom Monitoring

The deployment includes:
- **Uptime Checks**: Global availability monitoring
- **Latency Alerts**: Automated alerting for performance issues
- **Network Tests**: Inter-region connectivity validation
- **CDN Metrics**: Cache hit ratios and performance

### Performance Optimization

Monitor these key metrics:
- **Latency**: 95th percentile response times
- **Cache Hit Ratio**: CDN effectiveness
- **Backend Health**: Instance availability
- **Traffic Distribution**: Regional load patterns

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs manually
   gcloud services enable compute.googleapis.com
   gcloud services enable monitoring.googleapis.com
   gcloud services enable networkmanagement.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current permissions
   gcloud auth list
   gcloud projects get-iam-policy PROJECT_ID
   ```

3. **Instance Startup Issues**
   ```bash
   # Check instance startup logs
   gcloud compute instances get-serial-port-output INSTANCE_NAME --zone=ZONE
   ```

4. **Load Balancer Not Responding**
   ```bash
   # Check backend health
   gcloud compute backend-services get-health BACKEND_SERVICE_NAME --global
   ```

### Debugging Commands

```bash
# Check resource status
terraform state list
terraform state show google_compute_global_forwarding_rule.global_http_rule

# Validate configuration
terraform validate
terraform plan -detailed-exitcode

# Check Google Cloud resources
gcloud compute instances list
gcloud compute forwarding-rules list --global
gcloud compute backend-services list --global
```

## Cleanup

To remove all resources:

```bash
# Destroy all infrastructure
terraform destroy

# Confirm destruction
# Type "yes" when prompted
```

**Warning**: This will permanently delete all resources created by this configuration.

### Selective Cleanup

To remove specific resources:

```bash
# Remove monitoring only
terraform destroy -target=google_monitoring_uptime_check_config.global_app_uptime

# Remove instance groups only
terraform destroy -target=google_compute_instance_group_manager.regional_groups
```

## Cost Optimization

### Estimated Costs

Monthly cost estimates (US pricing):
- **Load Balancer**: $18-25/month (base + data processing)
- **Compute Instances**: $50-100/month (6 x e2-medium instances)
- **CDN**: Variable based on traffic (first 10TB free monthly)
- **Monitoring**: $0.20-1.00/month (based on metrics volume)
- **Data Transfer**: Variable based on usage

### Cost Reduction Strategies

1. **Use Preemptible Instances**:
   ```hcl
   # In instance template configuration
   scheduling {
     preemptible = true
   }
   ```

2. **Optimize Instance Sizes**:
   ```hcl
   instance_machine_type = "e2-small"  # Reduce from e2-medium
   instance_group_size   = 1           # Reduce from 2
   ```

3. **Configure CDN TTL**:
   ```hcl
   cdn_settings = {
     default_ttl = 7200  # Increase cache duration
     max_ttl     = 172800
   }
   ```

## Advanced Configuration

### Custom Domain Setup

1. **Create SSL Certificate**:
   ```bash
   gcloud compute ssl-certificates create my-ssl-cert \
     --domains=example.com,www.example.com \
     --global
   ```

2. **Update Terraform Configuration**:
   ```hcl
   ssl_certificates = [
     "projects/${var.project_id}/global/sslCertificates/my-ssl-cert"
   ]
   ```

3. **Configure DNS**:
   ```bash
   # Point your domain to the load balancer IP
   # A record: example.com -> LOAD_BALANCER_IP
   ```

### Multi-Environment Deployment

Use Terraform workspaces for multiple environments:

```bash
# Create development environment
terraform workspace new development
terraform apply -var-file="development.tfvars"

# Switch to production
terraform workspace select production
terraform apply -var-file="production.tfvars"
```

## Support and Documentation

- [Google Cloud Load Balancing Documentation](https://cloud.google.com/load-balancing/docs)
- [Cloud CDN Best Practices](https://cloud.google.com/cdn/docs/best-practices)
- [Network Intelligence Center](https://cloud.google.com/network-intelligence-center/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

To contribute improvements:

1. Test changes in a development environment
2. Validate with `terraform plan` and `terraform validate`
3. Update documentation as needed
4. Follow Google Cloud and Terraform best practices

## License

This configuration is provided as-is for educational and demonstration purposes. Modify according to your production requirements and security policies.