# Infrastructure as Code for Global Content Delivery Infrastructure with Cloud WAN and Anywhere Cache

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Establishing Global Content Delivery Infrastructure with Cloud WAN and Anywhere Cache".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Terraform 1.0+ installed (for Terraform implementation)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud WAN and Network Connectivity resources
  - Cloud Storage and Anywhere Cache management
  - Compute Engine and Load Balancer creation
  - Cloud CDN and monitoring services
  - Cross-region resource deployment

### Required APIs
The following APIs must be enabled in your project:
- Compute Engine API (`compute.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Network Management API (`networkmanagement.googleapis.com`)
- Cloud CDN API (`cdn.googleapis.com`)

## Architecture Overview

This infrastructure deploys a global content delivery solution featuring:

- **Multi-region Cloud Storage bucket** with global replication
- **Anywhere Cache instances** in three strategic regions (US, Europe, Asia)
- **Cloud CDN** with global load balancer and edge caching
- **Cloud WAN hub** with regional spokes for enterprise connectivity
- **Compute Engine instances** for content processing in each region
- **Cloud Monitoring** dashboards and alerting policies

### Estimated Costs
- **Testing Environment**: $50-100 per day across multiple regions
- **Production Environment**: Varies based on traffic and storage usage
- **Key Cost Factors**: Multi-region storage, compute instances, data transfer

> **Warning**: This deployment creates resources in multiple regions which may incur significant cross-region data transfer charges. Review [Google Cloud pricing](https://cloud.google.com/pricing) and set up billing alerts.

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export DEPLOYMENT_NAME="global-content-delivery"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/global/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/validate.sh
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

- `project_id`: Your Google Cloud project ID
- `primary_region`: Primary deployment region (default: us-central1)
- `secondary_region`: Secondary deployment region (default: europe-west1)
- `tertiary_region`: Tertiary deployment region (default: asia-east1)
- `bucket_name_suffix`: Unique suffix for storage bucket name
- `machine_type`: Compute instance type (default: e2-standard-4)

### Terraform Variables

Create a `terraform.tfvars` file with your customizations:

```hcl
project_id = "your-project-id"
primary_region = "us-central1"
secondary_region = "europe-west1"
tertiary_region = "asia-east1"
machine_type = "e2-standard-4"
bucket_name_suffix = "unique-suffix"
enable_monitoring = true
cache_ttl_seconds = 3600
```

### Environment Variables for Scripts

```bash
export PROJECT_ID="your-project-id"
export PRIMARY_REGION="us-central1"
export SECONDARY_REGION="europe-west1"
export TERTIARY_REGION="asia-east1"
export MACHINE_TYPE="e2-standard-4"
```

## Deployment Validation

After deployment, validate the infrastructure:

### Verify Anywhere Cache Status

```bash
# List all Anywhere Cache instances
gcloud storage anywhere-caches list \
    --bucket="your-bucket-name" \
    --format="table(zone,state,ttl,creation_time)"
```

### Test Content Delivery Performance

```bash
# Download test content and measure performance
time gsutil cp gs://your-bucket-name/sample-content/medium-file.dat /tmp/test-download.dat

# Verify Cloud CDN cache headers
curl -I "http://your-global-ip/sample-content/medium-file.dat"
```

### Check Cloud WAN Connectivity

```bash
# Verify WAN hub and spoke status
gcloud network-connectivity hubs describe your-wan-hub-name
gcloud network-connectivity spokes list --hub=your-wan-hub-name
```

### Monitor Performance Metrics

```bash
# View monitoring dashboard
gcloud monitoring dashboards list --filter="displayName:Global Content Delivery Performance"

# Check alerting policies
gcloud alpha monitoring policies list --filter="displayName:High Content Delivery Latency"
```

## Performance Optimization

### Cache Configuration

- **TTL Settings**: Adjust cache TTL based on content update frequency
- **Cache Size**: Monitor cache hit ratios and adjust instance types if needed
- **Regional Distribution**: Consider adding caches in additional regions for better coverage

### Network Optimization

- **Cloud WAN Configuration**: Optimize spoke attachments based on traffic patterns
- **Load Balancer Settings**: Fine-tune backend service configurations for optimal routing
- **CDN Settings**: Configure cache policies based on content types

### Monitoring and Alerting

- **Custom Metrics**: Create additional monitoring for business-specific KPIs
- **Alerting Thresholds**: Adjust alert thresholds based on baseline performance
- **Dashboard Customization**: Add widgets for specific content delivery metrics

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/global/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource cleanup
./scripts/validate-cleanup.sh
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
gcloud storage anywhere-caches delete --bucket=bucket-name --zone=zone-name
gcloud network-connectivity spokes delete spoke-name --location=region
gcloud network-connectivity hubs delete hub-name
gsutil -m rm -r gs://bucket-name
```

## Troubleshooting

### Common Issues

**API Not Enabled**
```bash
# Enable required APIs
gcloud services enable compute.googleapis.com storage.googleapis.com \
    monitoring.googleapis.com networkmanagement.googleapis.com
```

**Insufficient Permissions**
```bash
# Check current permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Add required roles (adjust as needed)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:your-email@domain.com" \
    --role="roles/editor"
```

**Resource Quotas Exceeded**
```bash
# Check current quotas
gcloud compute project-info describe --project=${PROJECT_ID}

# Request quota increases through Cloud Console
echo "Visit: https://console.cloud.google.com/iam-admin/quotas"
```

**Cache Deployment Failures**
```bash
# Check Anywhere Cache status and logs
gcloud storage anywhere-caches describe --bucket=bucket-name --zone=zone-name
gcloud logging read "resource.type=gcs_bucket" --limit=50
```

### Performance Issues

**High Latency**
- Check Cloud WAN spoke connectivity
- Verify Anywhere Cache hit ratios
- Review CDN cache configuration
- Monitor cross-region network metrics

**Low Cache Hit Rates**
- Adjust cache TTL settings
- Verify content access patterns
- Check cache instance sizing
- Review load balancer routing

**Connectivity Problems**
- Verify firewall rules
- Check IAM permissions
- Validate network configuration
- Test regional connectivity

## Security Considerations

### IAM and Access Control

- Use least privilege principle for service accounts
- Implement proper bucket IAM policies
- Configure Cloud WAN security policies
- Enable audit logging for all resources

### Network Security

- Configure appropriate firewall rules
- Use VPC security controls
- Implement Cloud Armor for DDoS protection
- Enable SSL/TLS for all communications

### Data Protection

- Enable bucket versioning for content protection
- Configure appropriate retention policies
- Implement encryption at rest and in transit
- Use Cloud KMS for key management

## Support and Documentation

### Google Cloud Documentation

- [Cloud WAN Documentation](https://cloud.google.com/network-connectivity/docs/cloud-wan)
- [Anywhere Cache Guide](https://cloud.google.com/storage/docs/anywhere-cache)
- [Cloud CDN Best Practices](https://cloud.google.com/cdn/docs/best-practices)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Terraform Resources

- [Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Terraform Google Cloud Modules](https://registry.terraform.io/namespaces/terraform-google-modules)

### Additional Resources

- [Google Cloud Architecture Center](https://cloud.google.com/architecture)
- [Cloud Network Performance Guide](https://cloud.google.com/architecture/framework/performance-efficiency)
- [Global Infrastructure Overview](https://cloud.google.com/about/locations)

## Contributing

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult the relevant Google Cloud documentation
4. Submit issues through appropriate channels

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **Generator Version**: 1.3
- **Compatible Terraform Version**: >= 1.0
- **Compatible Google Cloud Provider**: >= 4.0