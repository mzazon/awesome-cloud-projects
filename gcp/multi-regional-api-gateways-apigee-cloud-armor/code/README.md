# Infrastructure as Code for Securing Multi-Regional API Gateways with Apigee and Cloud Armor

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Securing Multi-Regional API Gateways with Apigee and Cloud Armor". This solution demonstrates how to deploy a comprehensive multi-regional API security architecture using Apigee X for API management combined with Cloud Armor for web application firewall protection and Cloud Load Balancing for global traffic distribution.

## Solution Overview

The infrastructure deploys:
- **Global VPC Network** with regional subnets in US and EU
- **Apigee X Organization** with multi-regional instances
- **Cloud Armor Security Policies** with DDoS protection, geo-fencing, and WAF rules
- **Global Load Balancer** with SSL termination and intelligent routing
- **Comprehensive Security Layer** including rate limiting and threat detection
- **Monitoring and Logging** infrastructure for security analytics

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native Infrastructure as Code tool (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for manual execution

## Prerequisites

### Required Tools and Access
- Google Cloud CLI (gcloud) v400.0.0 or later installed and configured
- Google Cloud project with Owner or Editor permissions
- Enabled APIs: Apigee, Compute Engine, Service Networking, DNS, Logging, Monitoring
- Domain name with DNS management capabilities for SSL certificate provisioning
- Basic understanding of API gateway concepts and web application security

### Cost Considerations
- **Estimated cost**: $500-1000/month for Apigee X and associated resources
- Cost varies significantly based on API traffic volume and regional deployment
- Apigee X requires a minimum commitment - review [pricing](https://cloud.google.com/apigee/pricing) before deployment
- Cloud Armor and Load Balancing costs scale with traffic and security policies applied

### Important Notes
- Apigee X has specific regional availability requirements
- Organization provisioning can take 30-45 minutes to complete
- Some resources have minimum billing commitments
- Review [Apigee X regional availability](https://cloud.google.com/apigee/docs/api-platform/get-started/overview) before proceeding

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager provides Google Cloud's native IaC experience with deep integration into GCP services and YAML-based configuration.

```bash
# Set your project and authentication
export PROJECT_ID=$(gcloud config get-value project)
gcloud config set project ${PROJECT_ID}

# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Review and customize the configuration
vi main.yaml

# Deploy the infrastructure using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/global/deployments/multi-regional-api-security \
    --service-account=$(gcloud config get-value account) \
    --local-source="."

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/global/deployments/multi-regional-api-security

# View deployment outputs
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/global/deployments/multi-regional-api-security \
    --format="value(serviceAccount,latestRevision)"
```

### Using Terraform

Terraform provides a mature, multi-cloud IaC solution with extensive Google Cloud provider support and module ecosystem.

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review the planned infrastructure changes
terraform plan

# Deploy the infrastructure
terraform apply

# View important output values
terraform output

# Check Apigee organization status
terraform output apigee_organization_name
terraform output global_load_balancer_ip
```

### Using Bash Scripts

The bash scripts provide a straightforward deployment approach that mirrors the original recipe steps with enhanced error handling and automation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run the deployment script
./scripts/deploy.sh

# Follow the prompts and monitor progress
# The script will:
# 1. Validate prerequisites and environment
# 2. Enable required APIs
# 3. Create networking infrastructure
# 4. Deploy Apigee X organization and instances
# 5. Configure Cloud Armor security policies
# 6. Set up global load balancer with SSL

# View deployment summary
./scripts/deploy.sh --status
```

## Configuration Customization

### Infrastructure Manager Configuration

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
# Example customizations
properties:
  region_us: "us-central1"           # Primary US region
  region_eu: "europe-west1"         # Primary EU region
  domain_name: "api.example.com"    # Your domain for SSL certificate
  apigee_organization_name: "my-org" # Apigee organization identifier
  
  # Security policy customizations
  blocked_countries: ["CN", "RU"]   # Countries to block via Cloud Armor
  rate_limit_threshold: 100         # Requests per minute threshold
  enable_adaptive_protection: true  # ML-based DDoS protection
```

### Terraform Variables

Customize `terraform/terraform.tfvars`:

```hcl
# Core configuration
project_id = "your-project-id"
region_us  = "us-central1"
region_eu  = "europe-west1"

# Domain and SSL configuration
domain_name = "api.yourdomain.com"
create_ssl_certificate = true

# Apigee configuration
apigee_organization_display_name = "Multi-Regional API Gateway"
apigee_billing_type = "PAYG"  # Pay-as-you-go or "SUBSCRIPTION"

# Security configuration
blocked_countries = ["CN", "RU", "KP"]
rate_limit_threshold = 100
enable_bot_management = true

# Network configuration
vpc_name = "apigee-global-network"
subnet_us_cidr = "10.1.0.0/16"
subnet_eu_cidr = "10.2.0.0/16"

# Monitoring and logging
enable_advanced_logging = true
log_retention_days = 30
```

### Script Configuration

Modify environment variables in `scripts/deploy.sh`:

```bash
# Edit these variables at the top of the script
export REGION_US="us-central1"
export REGION_EU="europe-west1"
export DOMAIN_NAME="api.yourdomain.com"

# Security policy settings
export BLOCKED_COUNTRIES="CN,RU,KP"
export RATE_LIMIT_THRESHOLD=100
export ENABLE_ADAPTIVE_PROTECTION="true"

# Resource naming
export NETWORK_NAME="apigee-network"
export ARMOR_POLICY_NAME="api-security-policy"
```

## Deployment Validation

### Verify Infrastructure Manager Deployment

```bash
# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/global/deployments/multi-regional-api-security

# Verify Apigee organization
gcloud apigee organizations describe ${PROJECT_ID}

# Test security policies
gcloud compute security-policies describe api-security-policy

# Check load balancer health
gcloud compute backend-services get-health apigee-backend-us --global
```

### Verify Terraform Deployment

```bash
# Check Terraform state
terraform show

# Verify specific resources
terraform state list | grep apigee
terraform state list | grep security-policy

# Test connectivity
curl -v https://$(terraform output -raw global_ip_address)/health
```

### Verify Script Deployment

```bash
# Run validation checks included in deploy script
./scripts/deploy.sh --validate

# Manual verification commands
gcloud apigee organizations list
gcloud compute security-policies list
gcloud compute addresses list --global
```

## Testing and Validation

### Security Policy Testing

```bash
# Test rate limiting (should be blocked after threshold)
for i in {1..150}; do curl -s https://your-domain.com/api/test; done

# Test geographic blocking (use VPN to test from blocked countries)
curl -H "CF-IPCountry: CN" https://your-domain.com/api/test

# Test SQL injection protection
curl "https://your-domain.com/api/test?id=1' OR '1'='1"
```

### Performance Testing

```bash
# Load testing with Apache Bench
ab -n 1000 -c 10 https://your-domain.com/api/v1/status

# Regional latency testing
curl -w "@curl-format.txt" -o /dev/null https://your-domain.com/api/test
curl -w "@curl-format.txt" -o /dev/null https://eu-your-domain.com/api/test
```

### Monitoring Validation

```bash
# Check Cloud Armor logs
gcloud logging read 'resource.type="http_load_balancer"' --limit=10

# Monitor Apigee analytics
gcloud apigee analytics export --organization=${PROJECT_ID} --environment=production-us

# View security events
gcloud logging read 'protoPayload.serviceName="compute.googleapis.com" AND protoPayload.methodName="compute.securityPolicies.patch"'
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/global/deployments/multi-regional-api-security

# Verify cleanup
gcloud infra-manager deployments list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# The script handles dependencies and deletion order automatically

# Verify cleanup
./scripts/destroy.sh --verify
```

### Manual Cleanup Verification

```bash
# Verify Apigee organization removal (may require manual deletion)
gcloud apigee organizations list

# Check for remaining compute resources
gcloud compute instances list
gcloud compute addresses list --global

# Verify network cleanup
gcloud compute networks list | grep apigee
```

## Troubleshooting

### Common Issues

1. **Apigee Organization Provisioning Timeout**
   ```bash
   # Check provisioning status
   gcloud apigee organizations describe ${PROJECT_ID} --format="value(state)"
   
   # If stuck, contact Google Cloud Support
   ```

2. **SSL Certificate Provisioning Issues**
   ```bash
   # Verify domain ownership and DNS configuration
   gcloud compute ssl-certificates describe api-ssl-cert --global
   
   # Check DNS propagation
   nslookup your-domain.com
   ```

3. **Cloud Armor Policy Not Applied**
   ```bash
   # Verify policy attachment to backend services
   gcloud compute backend-services describe apigee-backend-us --global --format="value(securityPolicy)"
   ```

4. **Load Balancer Health Check Failures**
   ```bash
   # Check backend health
   gcloud compute backend-services get-health apigee-backend-us --global
   
   # Verify Apigee instance status
   gcloud apigee instances describe us-instance --organization=${PROJECT_ID}
   ```

### Resource Quotas

This deployment may require quota increases for:
- Apigee organizations (limited per project)
- Global load balancers
- SSL certificates
- Compute Engine resources in multiple regions

Request quota increases through the [Google Cloud Console](https://console.cloud.google.com/iam-admin/quotas).

### Support Resources

- [Apigee X Documentation](https://cloud.google.com/apigee/docs)
- [Cloud Armor Documentation](https://cloud.google.com/armor/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Google Cloud Support](https://cloud.google.com/support)

## Architecture Notes

This infrastructure implements a defense-in-depth security model:

1. **Network Layer**: VPC with regional subnets and proper firewalls
2. **Edge Security**: Cloud Armor with DDoS protection and geographic filtering
3. **Application Layer**: Apigee X with OAuth2, rate limiting, and API policies
4. **Transport Security**: SSL/TLS termination with managed certificates
5. **Monitoring**: Comprehensive logging and analytics across all layers

The multi-regional deployment ensures high availability and low latency for global users while maintaining consistent security policies and centralized management through Apigee X's global organization model.

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update documentation to reflect configuration changes
3. Verify that security policies remain effective
4. Test in multiple regions to ensure global consistency
5. Update cost estimates if resource requirements change

## License

This infrastructure code is provided as-is for educational and development purposes. Review and modify security configurations according to your organization's requirements before production deployment.