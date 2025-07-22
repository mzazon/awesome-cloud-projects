# Terraform Infrastructure for Secure API Gateway Architecture

This directory contains Terraform Infrastructure as Code (IaC) for deploying a secure API gateway architecture using Google Cloud Endpoints and Cloud Armor on Google Cloud Platform.

## Architecture Overview

This Terraform configuration deploys:

- **Cloud Endpoints**: API management and authentication
- **Cloud Armor**: Web Application Firewall (WAF) and DDoS protection
- **Cloud Load Balancing**: Global load balancing with high availability
- **Compute Engine**: Backend API service and Endpoints Service Proxy (ESP)
- **Security Policies**: Rate limiting, OWASP protection, and geographic restrictions

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud CLI** installed and configured
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** installed (version >= 1.5)
   ```bash
   terraform version
   ```

3. **Required GCP APIs** enabled in your project:
   - Compute Engine API
   - Cloud Endpoints API
   - Service Management API
   - Service Control API
   - Cloud Logging API
   - Cloud Monitoring API

4. **IAM Permissions** for your user account:
   - Project Editor (or custom roles with appropriate permissions)
   - Service Account Admin
   - Security Admin

## Quick Start

### 1. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your project-specific values:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"
api_name   = "secure-api"
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review the Deployment Plan

```bash
terraform plan
```

### 4. Deploy the Infrastructure

```bash
terraform apply
```

When prompted, type `yes` to confirm the deployment.

### 5. Test the API Gateway

After deployment, use the output values to test your API:

```bash
# Get the gateway IP and API key from outputs
terraform output gateway_ip_address
terraform output -raw api_key

# Test unauthenticated request (should return 403)
curl -w '%{http_code}\n' -o /dev/null -s http://GATEWAY_IP/api/v1/users

# Test authenticated request (should return 200)
curl -w '%{http_code}\n' -s "http://GATEWAY_IP/api/v1/users?key=YOUR_API_KEY"

# Test health check (no authentication required)
curl -s http://GATEWAY_IP/health
```

## Configuration Options

### Security Settings

Configure Cloud Armor security policies:

```hcl
# Rate limiting
rate_limit_threshold = 100  # requests per minute per IP
ban_duration_sec     = 300  # ban duration in seconds

# Geographic restrictions
blocked_countries = ["CN", "RU"]  # ISO country codes

# Feature toggles
enable_owasp_protection = true
enable_geo_restriction  = true
```

### SSL/HTTPS Configuration

For production deployments with custom domains:

```hcl
enable_ssl    = true
custom_domain = "api.yourdomain.com"
```

> **Note**: SSL certificate provisioning may take 15-60 minutes. Ensure your domain's DNS points to the load balancer IP before enabling SSL.

### Compute Resources

Adjust instance types based on your performance requirements:

```hcl
backend_machine_type = "e2-medium"  # or e2-standard-2, n2-standard-2
esp_machine_type     = "e2-medium"  # or e2-standard-2, n2-standard-2
```

## Important Outputs

After deployment, Terraform provides several important outputs:

- `gateway_ip_address`: Static IP for your API gateway
- `api_key`: Authentication key for API requests (sensitive)
- `endpoints_service_name`: Cloud Endpoints service identifier
- `security_policy_name`: Cloud Armor security policy name
- `test_endpoints`: Ready-to-use endpoint URLs for testing

## Monitoring and Observability

The deployment includes comprehensive monitoring:

- **Cloud Monitoring**: Performance metrics and dashboards
- **Cloud Logging**: Request logs and security events
- **Health Checks**: Automated health monitoring for backend services
- **Load Balancer Logs**: Traffic analysis and performance insights

Access monitoring in the Google Cloud Console:
1. Navigate to Cloud Monitoring
2. Look for custom dashboards tagged with your project labels
3. Set up alerting policies based on your SLA requirements

## Security Features

### Cloud Armor Protection

The deployment includes multiple security layers:

1. **Rate Limiting**: Configurable requests per minute per IP
2. **OWASP Top 10 Protection**: XSS and SQL injection prevention
3. **Geographic Restrictions**: Block traffic from specified countries
4. **DDoS Protection**: Automatic volumetric attack mitigation

### Authentication and Authorization

- **API Key Authentication**: Required for all protected endpoints
- **Cloud Endpoints**: Managed API authentication and quota enforcement
- **Service Accounts**: Least-privilege access for compute resources

## Cost Optimization

To minimize costs during development and testing:

1. **Use preemptible instances** (modify the Terraform configuration)
2. **Scale down machine types** to e2-micro for light testing
3. **Disable monitoring** if not needed (`enable_monitoring = false`)
4. **Clean up resources** when not in use (`terraform destroy`)

Estimated monthly costs for the default configuration:
- Compute Engine instances: $30-50
- Load Balancing: $20-30
- Cloud Armor: $5-15 (based on traffic)
- Cloud Endpoints: $3 per 1M requests

## Customization and Extension

### Adding Custom API Endpoints

1. Modify the OpenAPI specification template (`templates/openapi-spec.yaml.tpl`)
2. Update the backend service code (`templates/backend-startup.sh.tpl`)
3. Redeploy with `terraform apply`

### Multi-Region Deployment

For global high availability:

1. Create additional Terraform configurations for other regions
2. Implement Cross-Region Load Balancing
3. Configure Cloud DNS for traffic routing

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy API Gateway
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - name: Terraform Apply
        run: |
          terraform init
          terraform apply -auto-approve
        env:
          GOOGLE_CREDENTIALS: ${{ secrets.GCP_SA_KEY }}
```

## Troubleshooting

### Common Issues

1. **API deployment fails**: Ensure backend service is healthy before deploying endpoints
2. **SSL certificate pending**: DNS must resolve to load balancer IP
3. **Rate limiting too aggressive**: Adjust `rate_limit_threshold` value
4. **Health checks failing**: Verify backend service is running on correct port

### Debug Commands

```bash
# Check backend service status
gcloud compute instances describe BACKEND_INSTANCE_NAME --zone=ZONE

# Verify API configuration
gcloud endpoints services list

# Check Cloud Armor policy
gcloud compute security-policies describe POLICY_NAME

# View load balancer status
gcloud compute backend-services describe BACKEND_SERVICE_NAME --global
```

### Logs and Monitoring

View logs for troubleshooting:

```bash
# Backend service logs
gcloud logging read "resource.type=\"gce_instance\" AND resource.labels.instance_name=\"BACKEND_INSTANCE\""

# Load balancer logs
gcloud logging read "resource.type=\"http_load_balancer\""

# Cloud Armor logs
gcloud logging read "resource.type=\"http_load_balancer\" AND httpRequest.status>=400"
```

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
terraform destroy
```

Confirm by typing `yes` when prompted.

> **Warning**: This will permanently delete all resources created by this Terraform configuration. Ensure you have backups of any important data.

## Support and Documentation

- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Cloud Endpoints Documentation](https://cloud.google.com/endpoints/docs)
- [Cloud Armor Documentation](https://cloud.google.com/armor/docs)
- [Cloud Load Balancing Documentation](https://cloud.google.com/load-balancing/docs)

For issues with this Terraform configuration:
1. Check the troubleshooting section above
2. Review Terraform and provider documentation
3. Consult Google Cloud support for platform-specific issues