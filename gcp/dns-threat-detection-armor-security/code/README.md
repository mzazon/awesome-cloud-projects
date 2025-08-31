# Infrastructure as Code for DNS Threat Detection with Armor and Security Center

This directory contains Infrastructure as Code (IaC) implementations for the recipe "DNS Threat Detection with Armor and Security Center".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Google Cloud project with billing enabled
- Organization-level access for Security Command Center configuration
- Appropriate IAM permissions for resource creation:
  - Security Center Admin
  - Compute Security Admin
  - DNS Administrator
  - Cloud Functions Admin
  - Pub/Sub Admin
  - Logging Admin
  - Service Usage Admin

## Quick Start

### Using Infrastructure Manager (Recommended)

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments create dns-threat-detection \
    --location=${REGION} \
    --source-blueprint=infrastructure-manager/main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

- `project_id`: Your Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `org_id`: Organization ID for Security Command Center (auto-detected)
- `random_suffix`: Unique suffix for resource names (auto-generated)

### Terraform Variables

- `project_id`: Your Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `dns_zone_name`: Name for the DNS managed zone (default: security-demo.example.com)
- `enable_geo_blocking`: Enable geographic blocking in Cloud Armor (default: true)
- `rate_limit_threshold`: Rate limiting threshold for DNS queries (default: 100)

### Script Configuration

Set these environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export ORG_ID="your-org-id"  # Optional, auto-detected if not set
```

## Architecture Overview

This infrastructure deploys:

1. **Security Command Center Premium** - Advanced threat detection and Event Threat Detection
2. **Cloud DNS** - Managed DNS service with comprehensive logging enabled
3. **Cloud Armor** - DDoS protection and security policies with rate limiting and geo-blocking
4. **Pub/Sub** - Message queue for security alert processing
5. **Cloud Functions** - Automated response system for threat mitigation
6. **Cloud Monitoring** - Custom metrics and alerting for DNS security events
7. **IAM Roles and Policies** - Least privilege access control

## Security Features

- **Real-time Threat Detection**: Automatic identification of malicious DNS queries and domains
- **Automated Response**: Immediate blocking of suspicious IPs and domains
- **Rate Limiting**: Protection against DNS amplification attacks
- **Geographic Blocking**: Restriction of access from high-risk regions
- **Comprehensive Logging**: Full audit trail of DNS queries and security events
- **Custom Monitoring**: Proactive alerting on suspicious DNS patterns

## Cost Considerations

- **Security Command Center Premium**: ~$50-100/month for premium tier
- **Cloud Functions**: Pay-per-invocation model (~$0.40 per million invocations)
- **Cloud DNS**: $0.20 per million DNS queries
- **Cloud Armor**: $5-15/month depending on rules and traffic
- **Pub/Sub**: $40 per TB of published messages
- **Cloud Monitoring**: Minimal cost for custom metrics

## Validation and Testing

After deployment, verify the solution:

1. **Check Security Command Center status**:
   ```bash
   gcloud scc settings services describe \
       --organization=${ORG_ID} \
       --service=security-center-premium
   ```

2. **Verify Cloud Armor protection**:
   ```bash
   gcloud compute security-policies list
   ```

3. **Test DNS functionality**:
   ```bash
   nslookup google.com
   ```

4. **Monitor Cloud Function logs**:
   ```bash
   gcloud functions logs read dns-security-processor --limit=10
   ```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete dns-threat-detection \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Organization Access Required**: Ensure you have organization-level permissions for Security Command Center
2. **API Enablement**: All required APIs must be enabled in your project
3. **IAM Permissions**: Verify you have sufficient permissions for all services
4. **Resource Quotas**: Check that you haven't exceeded regional quotas

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# Verify IAM permissions
gcloud iam testable-permissions list \
    --resource="//cloudresourcemanager.googleapis.com/projects/${PROJECT_ID}"

# Check resource quotas
gcloud compute project-info describe --format="table(quotas[].metric,quotas[].limit,quotas[].usage)"
```

## Customization

### Adding Custom Security Rules

Modify the Cloud Armor security policy in your chosen IaC implementation to add custom rules:

```yaml
# Infrastructure Manager example
- action: deny-403
  priority: 3000
  match:
    expr:
      expression: 'origin.ip in ["192.168.1.0/24"]'
  description: "Block specific IP range"
```

### Custom Notification Channels

Add email or Slack notifications by modifying the Cloud Function code and deployment configuration.

### Extended Monitoring

Add custom log-based metrics for specific DNS query patterns or security events.

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation for context
2. Check Google Cloud documentation for service-specific issues
3. Review Cloud Console for deployment status and errors
4. Use `gcloud logging read` to examine detailed logs

## Related Documentation

- [Security Command Center Documentation](https://cloud.google.com/security-command-center/docs)
- [Cloud Armor Security Policies](https://cloud.google.com/armor/docs/security-policy-overview)
- [DNS Security Best Practices](https://cloud.google.com/dns/docs/best-practices-dns-security)
- [Cloud Functions Security Guidelines](https://cloud.google.com/functions/docs/securing)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Version Information

- Infrastructure Manager: Latest stable version
- Terraform: >= 1.0, < 2.0
- Google Cloud Provider: >= 4.0
- Python Runtime: 3.12 (Cloud Functions)
- Generated on: 2025-07-12