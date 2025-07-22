# Infrastructure as Code for Zero-Trust Network Security with Service Extensions and Cloud Armor

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Zero-Trust Network Security with Service Extensions and Cloud Armor".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Security Admin
  - Network Admin
  - Service Account Admin
  - Compute Admin
  - Cloud Run Admin
  - Load Balancer Admin
- Docker installed (for Service Extension container builds)
- Terraform >= 1.5 installed (for Terraform implementation)
- Estimated cost: $50-$100/month for testing environment

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

```bash
# Set your project and region
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/zero-trust-security \
    --service-account=${PROJECT_ID}@appspot.gserviceaccount.com \
    --config-file=main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Set your project and region
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Initialize and deploy with Terraform
cd terraform/
terraform init
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete infrastructure
./scripts/deploy.sh

# Follow the interactive prompts to configure your deployment
```

## Architecture Overview

This implementation creates a comprehensive zero-trust network security architecture including:

- **Custom VPC Network**: Secure network foundation with private subnets
- **Cloud Armor Security Policy**: DDoS protection and WAF with OWASP rules
- **Service Extensions**: Custom security logic implemented via Cloud Run
- **Identity-Aware Proxy**: Centralized authentication and authorization
- **Global Load Balancer**: Entry point with integrated security controls
- **Security Monitoring**: Comprehensive logging and alerting

## Configuration Options

### Infrastructure Manager Variables

Configure your deployment by modifying values in the Infrastructure Manager configuration:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `network_name`: Custom VPC network name
- `app_name_prefix`: Prefix for resource naming
- `enable_iap`: Enable Identity-Aware Proxy (default: true)
- `armor_policy_rules`: Custom Cloud Armor security rules

### Terraform Variables

Key variables you can customize in `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "zero-trust-vpc"
}

variable "enable_geo_blocking" {
  description = "Enable geographic blocking in Cloud Armor"
  type        = bool
  default     = true
}

variable "rate_limit_threshold" {
  description = "Rate limiting threshold per minute"
  type        = number
  default     = 100
}
```

### Script Configuration

The bash scripts use environment variables for configuration:

```bash
# Core configuration
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export NETWORK_NAME="zero-trust-vpc"
export APP_NAME_PREFIX="zt-security"
export ENABLE_GEO_BLOCKING="true"
export RATE_LIMIT_THRESHOLD="100"
```

## Deployment Details

### Service Extension Implementation

The deployment includes a Cloud Run service that implements custom security logic:

- **Request Analysis**: Evaluates incoming requests based on path, method, and headers
- **Security Scoring**: Assigns risk scores to requests
- **Custom Policies**: Implements organization-specific security rules
- **Response Headers**: Adds security headers to allowed requests

### Cloud Armor Configuration

Comprehensive security policies including:

- **Rate Limiting**: Prevents abuse with configurable thresholds
- **Geographic Filtering**: Blocks traffic from high-risk regions
- **OWASP Protection**: Implements Core Rule Set for web application security
- **Custom Rules**: Supports additional security patterns

### Identity-Aware Proxy Setup

Centralized authentication including:

- **OAuth Integration**: Supports Google Identity and external providers
- **User Management**: Granular access control policies
- **Audit Logging**: Comprehensive authentication event logging
- **Session Management**: Secure session handling and timeout controls

## Security Considerations

### Network Security

- All backend resources deployed without public IP addresses
- Private Google Access enabled for secure service communication
- Custom firewall rules restrict traffic to necessary ports only
- VPC Flow Logs enabled for network traffic analysis

### Access Control

- Service accounts follow least privilege principle
- IAM roles scoped to minimum required permissions
- IAP enforces authentication before application access
- Service Extensions validate all requests before processing

### Monitoring and Compliance

- All security events logged to Cloud Logging
- Security Command Center integration for threat detection
- Audit logs enabled for all security-related services
- Monitoring alerts configured for suspicious activities

## Validation and Testing

After deployment, validate your zero-trust security implementation:

### Test Cloud Armor Protection

```bash
# Get load balancer IP
LB_IP=$(gcloud compute forwarding-rules describe ${APP_NAME}-forwarding-rule \
    --global --format="value(IPAddress)")

# Test rate limiting
for i in {1..20}; do
  curl -s -o /dev/null -w "%{http_code}\n" "https://${LB_IP}" \
    -H "Host: ${APP_NAME}.example.com" --insecure
done
```

### Verify Service Extension Logic

```bash
# Test allowed request
curl -X GET "https://${LB_IP}/api/data" \
  -H "Host: ${APP_NAME}.example.com" \
  -H "User-Agent: Mozilla/5.0" --insecure -v

# Test blocked request
curl -X DELETE "https://${LB_IP}/admin/users" \
  -H "Host: ${APP_NAME}.example.com" \
  -H "User-Agent: automated-scanner" --insecure -v
```

### Check Security Logs

```bash
# View security events
gcloud logging read \
  'protoPayload.serviceName="iap.googleapis.com" OR 
   protoPayload.serviceName="compute.googleapis.com"' \
  --limit=10 --format=json
```

## Troubleshooting

### Common Issues

1. **Service Extension Not Responding**
   - Check Cloud Run service logs: `gcloud logging read "resource.type=cloud_run_revision"`
   - Verify service has sufficient memory and CPU allocation
   - Confirm service is receiving traffic from load balancer

2. **IAP Authentication Errors**
   - Verify OAuth consent screen configuration
   - Check IAM bindings for IAP-secured Web App User role
   - Confirm backend service has IAP enabled

3. **Cloud Armor Policy Not Applied**
   - Verify policy is attached to backend service
   - Check rule priorities and expressions
   - Monitor Cloud Armor logs for policy evaluation

### Debug Commands

```bash
# Check all deployed resources
gcloud compute instances list
gcloud compute backend-services list
gcloud compute security-policies list
gcloud run services list

# View detailed resource configurations
gcloud compute backend-services describe ${APP_NAME}-backend-service --global
gcloud compute security-policies describe ${SECURITY_POLICY_NAME}
gcloud run services describe ${SERVICE_EXTENSION_NAME} --region=${REGION}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/zero-trust-security
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Clean up all resources
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup Verification

After automated cleanup, verify all resources are removed:

```bash
# Check for remaining resources
gcloud compute instances list --filter="name~'zero-trust|zt-security'"
gcloud compute backend-services list --filter="name~'zero-trust|zt-security'"
gcloud compute security-policies list --filter="name~'zero-trust|zt-security'"
gcloud run services list --filter="metadata.name~'zero-trust|zt-security'"
```

## Cost Optimization

### Resource Sizing

- **Compute Engine**: Use e2-medium instances for testing, scale based on traffic
- **Cloud Run**: Configure appropriate CPU and memory limits for Service Extensions
- **Load Balancer**: Global load balancer pricing based on forwarding rules and data processing

### Monitoring Costs

- **Cloud Logging**: Configure log retention policies to manage storage costs
- **Cloud Monitoring**: Use metric-based alerting to avoid unnecessary monitoring charges
- **Storage**: Monitor and optimize Cloud Storage usage for logs and artifacts

### Budget Controls

```bash
# Set up budget alerts
gcloud billing budgets create \
  --billing-account=${BILLING_ACCOUNT_ID} \
  --display-name="Zero Trust Security Budget" \
  --budget-amount=100USD \
  --threshold-rules-percent=50,90 \
  --project=${PROJECT_ID}
```

## Performance Considerations

### Load Balancer Optimization

- Use CDN caching for static content to reduce backend load
- Configure appropriate health check intervals
- Consider regional load balancing for lower latency

### Service Extension Performance

- Optimize custom security logic for minimal latency impact
- Use Cloud Run concurrency settings to handle traffic spikes
- Monitor request processing times and adjust resources accordingly

### Network Performance

- Use Premium Network Tier for optimal global performance
- Configure appropriate instance types based on network requirements
- Monitor VPC Flow Logs to optimize network patterns

## Support and Documentation

### Additional Resources

- [Google Cloud Zero Trust Architecture Guide](https://cloud.google.com/architecture/framework/security/implement-zero-trust)
- [Cloud Armor Security Policies Documentation](https://cloud.google.com/armor/docs/security-policy-overview)
- [Service Extensions Overview](https://cloud.google.com/service-extensions/docs/overview)
- [Identity-Aware Proxy Concepts](https://cloud.google.com/iap/docs/concepts-overview)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Community Support

- [Google Cloud Community Forums](https://cloud.google.com/community)
- [Stack Overflow Google Cloud Tag](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Reddit r/googlecloud](https://www.reddit.com/r/googlecloud/)

### Professional Support

For production deployments, consider:
- Google Cloud Professional Services for architecture review
- Google Cloud Support plans for technical assistance
- Partner consulting services for implementation guidance

## License

This infrastructure code is provided under the same license as the parent recipe repository. Refer to the repository LICENSE file for details.