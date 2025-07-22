# Infrastructure as Code for Domain and Certificate Lifecycle Management with Cloud DNS and Certificate Manager

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Domain and Certificate Lifecycle Management with Cloud DNS and Certificate Manager".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for automated provisioning

## Architecture Overview

This solution implements automated certificate and domain management using:
- **Cloud DNS** for authoritative DNS management
- **Certificate Manager** for automated SSL/TLS certificate provisioning and renewal
- **Cloud Functions** for certificate lifecycle automation
- **Cloud Scheduler** for regular health checks and monitoring
- **Application Load Balancer** with integrated certificate management

## Prerequisites

- Google Cloud account with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Appropriate IAM permissions:
  - DNS Administrator
  - Certificate Manager Editor
  - Cloud Functions Developer
  - Compute Admin
  - Service Account Admin
  - IAM Admin
- A registered domain name with ability to configure nameservers
- Terraform (if using Terraform implementation)

> **Cost Estimate**: $5-15/month for DNS zones, certificate management, and minimal Cloud Functions usage

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export DOMAIN_NAME="your-domain.com"
export REGION="us-central1"

# Enable required APIs
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/cert-dns-automation \
    --service-account projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --input-values="project_id=${PROJECT_ID},domain_name=${DOMAIN_NAME},region=${REGION}"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "your-project-id"
domain_name = "your-domain.com"
region = "us-central1"
zone = "us-central1-a"
EOF

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export DOMAIN_NAME="your-domain.com"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to:

1. **Configure Domain Nameservers**: Update your domain registrar settings with the nameservers provided by Cloud DNS
2. **Verify Certificate Provisioning**: Monitor Certificate Manager for certificate validation and issuance
3. **Test Automation Functions**: Verify that scheduled monitoring jobs are running correctly

### Getting Nameservers

```bash
# Get nameservers for your DNS zone
gcloud dns managed-zones describe automation-zone-${RANDOM_SUFFIX} \
    --format="value(nameServers)"
```

### Monitoring Certificate Status

```bash
# Check certificate status
gcloud certificate-manager certificates list --global

# View certificate details
gcloud certificate-manager certificates describe ssl-cert-${RANDOM_SUFFIX} \
    --global --format="table(name,managed.state,managed.domains)"
```

## Customization

### Terraform Variables

The Terraform implementation supports these customizable variables:

- `project_id`: GCP project ID
- `domain_name`: Primary domain for certificate management
- `region`: GCP region for regional resources
- `zone`: GCP zone for zonal resources
- `monitoring_schedule`: Cron schedule for certificate monitoring (default: "0 */6 * * *")
- `function_memory`: Memory allocation for Cloud Functions (default: "256MB")
- `certificate_domains`: List of domains for certificate (defaults to primary domain)

### Infrastructure Manager Variables

Configure the deployment using input values:

```bash
--input-values="project_id=my-project,domain_name=example.com,region=us-central1,enable_monitoring=true"
```

### Environment-Specific Deployments

For multiple environments, use workspace separation:

```bash
# Terraform workspaces
terraform workspace new production
terraform workspace new staging

# Infrastructure Manager deployments
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/cert-dns-automation-prod
```

## Validation and Testing

### Verify DNS Configuration

```bash
# Test DNS resolution
nslookup ${DOMAIN_NAME}
dig ${DOMAIN_NAME} @8.8.8.8

# Check DNS zone records
gcloud dns record-sets list --zone=automation-zone-${RANDOM_SUFFIX}
```

### Test Certificate Management

```bash
# Trigger certificate monitoring function
FUNCTION_URL=$(gcloud functions describe cert-automation-${RANDOM_SUFFIX} \
    --format="value(httpsTrigger.url)")
curl -X GET "${FUNCTION_URL}"

# Check scheduler job status
gcloud scheduler jobs list --filter="name:cert-check-*"
```

### Verify Load Balancer Integration

```bash
# Get load balancer IP
gcloud compute forwarding-rules list --global

# Test HTTPS connectivity (after certificate validation)
curl -I https://${DOMAIN_NAME}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/cert-dns-automation

# Confirm resource cleanup
gcloud infra-manager deployments list
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:

```bash
# Check remaining certificates
gcloud certificate-manager certificates list

# Verify DNS zones are deleted
gcloud dns managed-zones list

# Confirm functions are removed
gcloud functions list

# Check scheduler jobs
gcloud scheduler jobs list
```

## Troubleshooting

### Common Issues

1. **Certificate Validation Fails**:
   - Verify nameservers are configured correctly with domain registrar
   - Check DNS propagation: `dig ${DOMAIN_NAME} @8.8.8.8`
   - Allow 15-30 minutes for DNS propagation

2. **Function Deployment Errors**:
   - Verify required APIs are enabled
   - Check service account permissions
   - Review function logs: `gcloud functions logs read FUNCTION_NAME`

3. **Load Balancer Certificate Attachment**:
   - Ensure certificate is in ACTIVE state
   - Verify certificate map configuration
   - Check HTTPS proxy certificate binding

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Review Cloud Function logs
gcloud functions logs read cert-automation-${RANDOM_SUFFIX} --limit=50

# Monitor certificate manager operations
gcloud certificate-manager operations list
```

## Security Considerations

### Service Account Permissions

The solution uses a dedicated service account with minimal required permissions:
- `roles/dns.admin`: DNS zone and record management
- `roles/certificatemanager.editor`: Certificate lifecycle operations
- `roles/monitoring.metricWriter`: Custom metrics for monitoring

### Network Security

- All communication uses HTTPS/TLS encryption
- Load balancer enforces HTTPS redirect
- Certificate validation uses secure DNS-01 challenges
- Cloud Functions require authentication for management operations

### Access Control

```bash
# Review service account key usage
gcloud iam service-accounts keys list \
    --iam-account=cert-automation@${PROJECT_ID}.iam.gserviceaccount.com

# Audit function invoker permissions
gcloud functions get-iam-policy FUNCTION_NAME
```

## Monitoring and Observability

### Cloud Monitoring Integration

The solution includes custom metrics for:
- Certificate health status
- Domain validation success/failure
- Function execution metrics
- DNS operation tracking

### Alerting Setup

```bash
# Create alerting policy for certificate expiration
gcloud alpha monitoring policies create --policy-from-file=alerting-policy.yaml
```

### Log Analysis

```bash
# View certificate monitoring logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=cert-automation-*"

# Monitor DNS API calls
gcloud logging read "protoPayload.serviceName=dns.googleapis.com"
```

## Performance Optimization

### Function Configuration

- Memory: 256MB (sufficient for certificate operations)
- Timeout: 60s (adequate for DNS API calls)
- Concurrency: 1 (prevents race conditions)

### Scheduling Optimization

- Certificate checks: Every 6 hours (balances monitoring with cost)
- Comprehensive audits: Daily at 2 AM UTC (low-traffic period)
- Custom schedules supported via Terraform variables

## Compliance and Governance

### Certificate Lifecycle Tracking

The solution provides audit trails for:
- Certificate creation and renewal events
- DNS record modifications
- Function execution logs
- Scheduler job history

### Backup and Recovery

```bash
# Export DNS zone configuration
gcloud dns record-sets export zone-backup.yaml --zone=ZONE_NAME

# Backup certificate configurations
gcloud certificate-manager certificates list --format=json > cert-backup.json
```

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Example GitHub Actions integration
- name: Deploy Certificate Automation
  run: |
    cd terraform/
    terraform init
    terraform apply -auto-approve
```

### External Monitoring Integration

The Cloud Functions can be extended to integrate with external systems:
- Slack notifications for certificate events
- PagerDuty alerts for validation failures
- ServiceNow ticket creation for manual interventions

## Support and Resources

### Documentation Links

- [Google Cloud DNS Documentation](https://cloud.google.com/dns/docs)
- [Certificate Manager Documentation](https://cloud.google.com/certificate-manager/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Community Resources

- [Google Cloud Community](https://www.googlecloudcommunity.com/)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest)
- [GCP Terraform Modules](https://github.com/terraform-google-modules)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.