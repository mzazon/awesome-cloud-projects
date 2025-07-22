# Infrastructure as Code for Secure API Gateway Architecture with Cloud Endpoints and Cloud Armor

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure API Gateway Architecture with Cloud Endpoints and Cloud Armor".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code platform (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Project Editor role OR custom roles for:
    - Compute Engine Admin
    - Cloud Endpoints Admin
    - Cloud Armor Admin
    - Load Balancer Admin
    - Service Management Admin
    - Logging Admin
    - Monitoring Admin
- For Terraform: Terraform >= 1.5.0 installed
- Docker installed (for containerized backend services)
- Basic understanding of REST APIs, HTTP load balancing, and security concepts

## Estimated Costs

- **Development/Testing**: $10-25/month
- **Production Workloads**: $50-100/month
- **High-Traffic Production**: $100-500/month

Costs vary based on:
- Traffic volume and bandwidth usage
- Number of Cloud Armor rules and requests processed
- Compute Engine instance types and usage
- Load balancer data processing charges

> **Note**: Cloud Armor charges are based on the number of rules and requests processed. Review [Cloud Armor pricing](https://cloud.google.com/armor/pricing) for detailed cost calculations.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's managed infrastructure as code service that supports Terraform configurations with additional Google Cloud integrations.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="secure-api-gateway"

# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable servicemanagement.googleapis.com
gcloud services enable endpoints.googleapis.com

# Create deployment
gcloud infra-manager deployments create ${DEPLOYMENT_NAME} \
    --location=${REGION} \
    --source-blueprint=infrastructure-manager/main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe ${DEPLOYMENT_NAME} \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Set required environment variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs (API endpoint, security policy details, etc.)
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables (edit these values)
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# The script will output:
# - API Gateway endpoint URL
# - API key for authentication
# - Security policy configuration
# - Load balancer IP address
```

## Configuration Options

### Infrastructure Manager Variables

Located in `infrastructure-manager/main.yaml`:

- `project_id`: Google Cloud project ID
- `region`: Primary deployment region (default: us-central1)
- `zone`: Specific zone for VM instances (default: us-central1-a)
- `api_name_prefix`: Prefix for API service names (default: secure-api)
- `machine_type`: VM instance type (default: e2-medium)
- `disk_size_gb`: Boot disk size in GB (default: 20)

### Terraform Variables

Located in `terraform/variables.tf`:

```hcl
# Core configuration
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Primary deployment region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Specific zone for VM instances"
  type        = string
  default     = "us-central1-a"
}

# Resource configuration
variable "api_name_prefix" {
  description = "Prefix for API service names"
  type        = string
  default     = "secure-api"
}

variable "machine_type" {
  description = "VM instance machine type"
  type        = string
  default     = "e2-medium"
}

variable "enable_geo_restrictions" {
  description = "Enable geographic restrictions in Cloud Armor"
  type        = bool
  default     = true
}
```

Create a `terraform.tfvars` file to customize:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
api_name_prefix = "my-secure-api"
machine_type = "e2-standard-2"
enable_geo_restrictions = false
```

## Architecture Components

The infrastructure code deploys:

### Core Services
- **Cloud Endpoints**: API management and authentication
- **Cloud Armor**: Web Application Firewall and DDoS protection
- **Cloud Load Balancing**: Global load distribution and high availability

### Compute Resources
- **Backend Service VM**: Hosts the API application (Flask-based demo)
- **ESP Proxy VM**: Endpoints Service Proxy for request handling
- **Instance Groups**: Managed collections for load balancing

### Security Components
- **Security Policies**: Cloud Armor rules for threat protection
- **Firewall Rules**: Network-level access controls
- **API Keys**: Authentication tokens for client access

### Networking
- **HTTP(S) Load Balancer**: Global frontend with static IP
- **URL Maps**: Request routing configuration
- **Health Checks**: Service availability monitoring

## Security Features

### Cloud Armor Protection
- **Rate Limiting**: 100 requests per minute per IP address
- **XSS Protection**: Blocks cross-site scripting attempts
- **SQL Injection Protection**: Prevents database injection attacks
- **Geographic Restrictions**: Configurable country-based blocking
- **DDoS Mitigation**: Automatic volumetric attack protection

### API Security
- **Authentication**: API key validation for all endpoints
- **Authorization**: Role-based access control
- **Request Validation**: OpenAPI specification enforcement
- **TLS Encryption**: HTTPS termination at load balancer

### Network Security
- **VPC Integration**: Private network communication
- **Firewall Rules**: Restrictive ingress/egress policies
- **Internal Load Balancing**: Backend service isolation

## Testing and Validation

After deployment, test the security features:

```bash
# Get the deployed API endpoint and key (from outputs)
export API_ENDPOINT="http://YOUR_LOAD_BALANCER_IP"
export API_KEY="YOUR_GENERATED_API_KEY"

# Test authenticated API access
curl -w "%{http_code}\n" -s \
    "${API_ENDPOINT}/api/v1/users?key=${API_KEY}"

# Test rate limiting (should trigger after 100 requests)
for i in {1..110}; do
    curl -s -o /dev/null -w "%{http_code} " \
        "${API_ENDPOINT}/health?key=${API_KEY}"
done

# Test security rules (should return 403)
curl -w "%{http_code}\n" -o /dev/null -s \
    "${API_ENDPOINT}/api/v1/users?key=${API_KEY}&test=<script>alert('xss')</script>"
```

## Monitoring and Observability

### Cloud Monitoring
Access pre-configured dashboards for:
- API request volume and latency
- Error rates and response codes
- Cloud Armor security events
- Backend service health

### Cloud Logging
View structured logs for:
- API access logs with authentication details
- Security policy violations and blocks
- Load balancer performance metrics
- ESP proxy request processing

### Alerting
Recommended alerts to configure:
- High error rates (>5% 4xx/5xx responses)
- Security policy violations (>10 blocks/minute)
- Backend service health check failures
- API quota exhaustion

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete ${DEPLOYMENT_NAME} \
    --location=${REGION} \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Optional: Delete the entire project (removes all resources)
# gcloud projects delete ${PROJECT_ID}
```

> **Warning**: The destroy operations will permanently delete all infrastructure. Ensure you have backups of any important data before proceeding.

## Customization

### Adding Custom API Endpoints

1. **Update OpenAPI Specification**: Modify the `openapi-spec.yaml` file to include new endpoints
2. **Backend Service Logic**: Update the Flask application in the startup script
3. **Security Policies**: Adjust Cloud Armor rules for new endpoint patterns
4. **Redeploy**: Apply the updated configuration

### Scaling for Production

1. **Multi-Zone Deployment**: Deploy ESP proxies across multiple zones
2. **Auto Scaling**: Configure managed instance groups with autoscaling
3. **SSL/TLS Termination**: Add Google-managed SSL certificates
4. **Custom Domains**: Configure custom domain names for the API

### Enhanced Security

1. **IAM Integration**: Replace API keys with Cloud IAM authentication
2. **VPC Service Controls**: Add additional network security boundaries
3. **Binary Authorization**: Implement container image security scanning
4. **Secret Manager**: Store sensitive configuration in Secret Manager

## Troubleshooting

### Common Issues

**API Returns 403 Errors**
- Verify API key is correctly generated and passed in requests
- Check Cloud Armor security policy isn't blocking legitimate traffic
- Ensure OpenAPI specification matches request patterns

**High Latency Responses**
- Check backend service health and resource utilization
- Verify ESP proxy instances aren't overloaded
- Review Cloud Armor processing overhead

**Deployment Failures**
- Verify all required APIs are enabled in the project
- Check IAM permissions for the deployment service account
- Ensure resource quotas aren't exceeded

### Debug Commands

```bash
# Check Cloud Endpoints service status
gcloud endpoints services list

# View Cloud Armor security policy details
gcloud compute security-policies describe POLICY_NAME

# Check load balancer backend health
gcloud compute backend-services get-health BACKEND_SERVICE_NAME --global

# View recent logs
gcloud logging read "resource.type=http_load_balancer" --limit=50
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: 
   - [Cloud Endpoints](https://cloud.google.com/endpoints/docs)
   - [Cloud Armor](https://cloud.google.com/armor/docs)
   - [Load Balancing](https://cloud.google.com/load-balancing/docs)
3. **Community Support**: Google Cloud Community forums and Stack Overflow
4. **Professional Support**: Google Cloud Support (for paid support plans)

## Additional Resources

- [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)
- [API Security Best Practices](https://cloud.google.com/endpoints/docs/openapi/best-practices)
- [Cloud Armor Best Practices](https://cloud.google.com/armor/docs/best-practices)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)