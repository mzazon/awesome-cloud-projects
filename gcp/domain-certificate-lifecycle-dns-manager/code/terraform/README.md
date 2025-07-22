# Terraform Infrastructure for Domain and Certificate Lifecycle Management

This Terraform configuration deploys a complete automated certificate and domain management system using Google Cloud DNS and Certificate Manager, following the recipe "Domain and Certificate Lifecycle Management with Cloud DNS and Certificate Manager".

## Architecture Overview

The infrastructure creates:

- **Cloud DNS Zone**: Authoritative DNS management for your domain
- **Certificate Manager**: Automated SSL/TLS certificate provisioning and renewal
- **Cloud Functions**: Serverless automation for certificate monitoring and DNS management
- **Cloud Scheduler**: Automated certificate health checks and monitoring
- **Application Load Balancer**: Production-ready HTTPS endpoint with automated certificates
- **Service Account**: Secure authentication with least-privilege permissions
- **Cloud Monitoring**: Custom metrics and observability for certificate health

## Prerequisites

Before deploying this infrastructure:

1. **Google Cloud Project**: Active GCP project with billing enabled
2. **Domain Name**: Registered domain that you can configure nameservers for
3. **Required APIs**: The following APIs will be automatically enabled:
   - Cloud DNS API
   - Certificate Manager API
   - Cloud Functions API
   - Cloud Scheduler API
   - Secret Manager API
   - Cloud Monitoring API
   - Compute Engine API
   - Cloud Build API

4. **Permissions**: Your account needs the following IAM roles:
   - Project Editor or equivalent permissions
   - DNS Administrator
   - Certificate Manager Editor
   - Cloud Functions Developer
   - Service Account Admin

5. **Tools**:
   - [Terraform](https://www.terraform.io/downloads.html) >= 1.0
   - [Google Cloud CLI](https://cloud.google.com/sdk/docs/install)

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the terraform directory
cd gcp/domain-certificate-lifecycle-dns-manager/code/terraform/
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your specific values
nano terraform.tfvars
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Configure DNS Delegation

After deployment, configure your domain registrar with the nameservers provided in the output:

```bash
# Get nameservers from Terraform output
terraform output dns_zone_nameservers
```

Configure these nameservers with your domain registrar to delegate DNS authority to Google Cloud.

### 5. Verify Certificate Provisioning

Certificate validation will begin automatically once DNS delegation is complete. Monitor the status:

```bash
# Check certificate status
gcloud certificate-manager certificates describe $(terraform output -raw certificate_name) --global

# Test certificate monitoring function
curl -X GET "$(terraform output -raw cert_monitoring_function_url)"
```

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | GCP project ID | `my-cert-project-123` |
| `domain_name` | Your domain name | `example.com` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | `us-central1` | GCP region for resources |
| `dns_zone_name` | Auto-generated | Custom name for DNS zone |
| `certificate_name` | Auto-generated | Custom name for certificate |
| `enable_monitoring` | `true` | Enable automated monitoring |
| `monitoring_schedule` | `0 */6 * * *` | Cron schedule for monitoring |
| `create_load_balancer` | `true` | Create demo load balancer |
| `enable_www_subdomain` | `true` | Create www CNAME record |
| `function_timeout` | `60` | Function timeout in seconds |
| `function_memory` | `256` | Function memory in MB |

See `variables.tf` for complete variable documentation.

## Post-Deployment Setup

### 1. DNS Delegation

Configure your domain registrar with the nameservers from the output:

```bash
terraform output dns_zone_nameservers
```

### 2. Certificate Validation

Certificate validation happens automatically after DNS delegation. Monitor progress:

```bash
# Check certificate status
gcloud certificate-manager certificates list --global

# View certificate details
gcloud certificate-manager certificates describe CERTIFICATE_NAME --global
```

### 3. Test Automation Functions

```bash
# Test certificate monitoring
curl -X GET "$(terraform output -raw cert_monitoring_function_url)"

# Test DNS record management
curl -X POST "$(terraform output -raw dns_update_function_url)" \
  -H "Content-Type: application/json" \
  -d '{
    "zone_name": "ZONE_NAME",
    "record_name": "test.example.com.",
    "record_type": "A",
    "record_data": "1.2.3.4"
  }'
```

### 4. Monitor Scheduled Jobs

```bash
# List scheduler jobs
gcloud scheduler jobs list --location=REGION

# View job execution history
gcloud scheduler jobs describe JOB_NAME --location=REGION
```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

### Cloud Monitoring Metrics

- `custom.googleapis.com/certificate_automation/certificate_status`: Individual certificate health
- `custom.googleapis.com/certificate_automation/certificates_healthy_total`: Count of healthy certificates
- `custom.googleapis.com/certificate_automation/certificates_unhealthy_total`: Count of unhealthy certificates

### Cloud Logging

View function logs:

```bash
# Certificate monitoring function logs
gcloud functions logs read FUNCTION_NAME --limit=50

# Filter for errors
gcloud functions logs read FUNCTION_NAME --limit=50 --filter="severity=ERROR"
```

### Scheduled Monitoring

- **Regular Checks**: Every 6 hours (configurable)
- **Daily Audits**: Daily at 2:00 AM UTC (configurable)
- **Automatic Alerting**: Through Cloud Monitoring metrics

## Security Features

The deployment implements security best practices:

- **Least Privilege**: Service account with minimal required permissions
- **HTTPS Everywhere**: All communication over HTTPS
- **Managed Certificates**: Google-managed certificates with automatic renewal
- **Secure Functions**: Cloud Functions with authenticated triggers
- **Encrypted Storage**: All data encrypted at rest and in transit

## Cost Optimization

Estimated monthly costs (USD):

- **DNS Zone**: $0.50 per zone + $0.40 per million queries
- **Certificate Manager**: Free for Google-managed certificates
- **Cloud Functions**: $0.40 per million requests + compute time
- **Cloud Scheduler**: $0.10 per job per month
- **Load Balancer**: $18 per month + data processing fees (if enabled)

**Typical Monthly Cost**: $5-15 for standard usage

## Customization Examples

### Multiple Domains

```hcl
# In terraform.tfvars
certificate_domains = ["www.example.com", "api.example.com", "app.example.com"]
```

### Custom Monitoring Schedule

```hcl
# Check certificates every 2 hours
monitoring_schedule = "0 */2 * * *"

# Daily audit at 3:00 AM
daily_audit_schedule = "0 3 * * *"
```

### Production Configuration

```hcl
# Recommended production settings
function_memory = 512
function_timeout = 120
enable_cloud_armor = true
dns_ttl = 60  # Lower TTL for faster changes
```

## Troubleshooting

### Certificate Not Validating

1. **Check DNS Delegation**:
   ```bash
   nslookup -type=NS example.com
   ```

2. **Verify Certificate Status**:
   ```bash
   gcloud certificate-manager certificates describe CERT_NAME --global
   ```

3. **Check DNS Records**:
   ```bash
   gcloud dns record-sets list --zone=ZONE_NAME
   ```

### Function Errors

1. **Check Function Logs**:
   ```bash
   gcloud functions logs read FUNCTION_NAME --limit=20
   ```

2. **Test Function Manually**:
   ```bash
   curl -X GET "FUNCTION_URL"
   ```

3. **Verify Service Account Permissions**:
   ```bash
   gcloud projects get-iam-policy PROJECT_ID
   ```

### DNS Issues

1. **Verify Zone Configuration**:
   ```bash
   gcloud dns managed-zones describe ZONE_NAME
   ```

2. **Check Record Propagation**:
   ```bash
   dig @8.8.8.8 example.com
   ```

## Cleanup

To remove all deployed resources:

```bash
# Destroy all infrastructure
terraform destroy

# Confirm deletion
# Type 'yes' when prompted
```

**Important**: Remember to revert nameserver changes with your domain registrar after destroying the infrastructure.

## Advanced Features

### Integration with CI/CD

The DNS update function can be integrated with CI/CD pipelines for automated domain management:

```bash
# Example: Update staging environment DNS
curl -X POST "DNS_FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "zone_name": "staging-zone",
    "record_name": "app.staging.example.com.",
    "record_type": "A",
    "record_data": "NEW_IP_ADDRESS"
  }'
```

### Custom Certificate Validation

Extend the monitoring function to implement custom validation logic for specific business requirements.

### Multi-Environment Support

Deploy separate instances for different environments (dev, staging, production) with environment-specific configurations.

## Support and Documentation

- [Google Cloud DNS Documentation](https://cloud.google.com/dns/docs)
- [Certificate Manager Documentation](https://cloud.google.com/certificate-manager/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update variable descriptions for any new variables
3. Add appropriate outputs for new resources
4. Update this README with any configuration changes
5. Validate with `terraform plan` before applying

## License

This infrastructure code is provided as part of the Google Cloud recipe collection and follows the same licensing terms as the parent repository.