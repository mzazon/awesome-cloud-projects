# Infrastructure as Code for Multi-Region Traffic Optimization with Cloud Load Balancing and Performance Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Region Traffic Optimization with Cloud Load Balancing and Performance Monitoring".

## Overview

This recipe demonstrates how to build an intelligent traffic optimization system using Google Cloud's global load balancing infrastructure combined with Cloud CDN and Network Intelligence Center. The solution dynamically routes user requests to optimal backend regions based on real-time performance metrics, automatically adjusts CDN configurations for content acceleration, and provides comprehensive monitoring to ensure consistent global application performance.

## Architecture

The solution deploys:
- Global VPC network with multi-region subnets
- Managed instance groups across US, Europe, and Asia-Pacific regions
- Global HTTP(S) load balancer with Cloud CDN integration
- Health checks and backend services with intelligent routing
- Network Intelligence Center connectivity monitoring
- Cloud Monitoring with performance alerts and uptime checks

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Google Cloud Setup
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Compute Engine (Editor or Admin)
  - Load Balancing (Admin)
  - CDN (Admin)
  - Monitoring (Editor)
  - Network Management (Admin)
- Google Cloud CLI installed and configured (or use Cloud Shell)
- APIs enabled:
  - Compute Engine API
  - Cloud Build API
  - Cloud Monitoring API
  - Cloud Logging API
  - Network Management API

### Tool-Specific Prerequisites

#### Infrastructure Manager
- `gcloud` CLI version 400.0.0 or later
- Infrastructure Manager API enabled
- Cloud Build API enabled (for Infrastructure Manager operations)

#### Terraform
- Terraform 1.5+ installed
- Google Cloud provider for Terraform
- Service account with appropriate permissions (optional but recommended)

#### Bash Scripts
- `bash` shell environment
- `curl` utility for testing
- `openssl` for generating random values

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/traffic-optimization \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/your-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/path-to-config" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/us-central1/deployments/traffic-optimization
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy example variables file and customize
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID and preferences

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Navigate to the scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export BILLING_ACCOUNT_ID="your-billing-account-id"  # Optional, for new projects

# Run deployment script
./deploy.sh

# The script will:
# 1. Create and configure GCP project
# 2. Enable required APIs
# 3. Deploy global VPC and networking
# 4. Create compute instances across regions
# 5. Configure global load balancer and CDN
# 6. Set up monitoring and alerting
```

## Configuration Options

### Infrastructure Manager Variables

Variables are defined in the `main.yaml` file and can be customized:

- `project_id`: Google Cloud project ID
- `regions`: List of deployment regions (default: us-central1, europe-west1, asia-southeast1)
- `instance_count_per_region`: Number of instances per region (default: 2)
- `machine_type`: Compute Engine machine type (default: e2-medium)
- `enable_cdn`: Enable Cloud CDN (default: true)
- `enable_monitoring`: Enable advanced monitoring (default: true)

### Terraform Variables

Customize your deployment by editing `terraform.tfvars`:

```hcl
project_id = "your-project-id"
regions = {
  us     = "us-central1"
  eu     = "europe-west1"
  apac   = "asia-southeast1"
}
zones = {
  us     = "us-central1-a"
  eu     = "europe-west1-b"
  apac   = "asia-southeast1-a"
}
instance_count_per_region = 2
machine_type = "e2-medium"
enable_cdn = true
enable_monitoring = true
network_name = "global-app-vpc"
load_balancer_name = "global-lb"
```

### Bash Script Configuration

The bash scripts use environment variables for configuration:

```bash
export PROJECT_ID="your-project-id"
export REGION_US="us-central1"
export REGION_EU="europe-west1"
export REGION_APAC="asia-southeast1"
export ZONE_US="us-central1-a"
export ZONE_EU="europe-west1-b"
export ZONE_APAC="asia-southeast1-a"
```

## Validation and Testing

After deployment, validate the solution:

### Test Global Load Balancer

```bash
# Get the global IP address
GLOBAL_IP=$(gcloud compute forwarding-rules describe global-http-rule-* \
    --global --format="value(IPAddress)")

# Test accessibility
curl -I http://${GLOBAL_IP}

# Test regional distribution
for i in {1..10}; do
    echo "Request $i:"
    curl http://${GLOBAL_IP} | grep "Serving from zone"
    sleep 1
done
```

### Verify CDN Performance

```bash
# Test CDN headers
curl -I http://${GLOBAL_IP} | grep -E "(cache|age|via)"

# Test compression
curl -H "Accept-Encoding: gzip" -I http://${GLOBAL_IP}
```

### Check Monitoring

```bash
# List uptime checks
gcloud alpha monitoring uptime list

# View connectivity tests
gcloud network-management connectivity-tests list
```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

### Cloud Monitoring Dashboards
- Global load balancer performance metrics
- CDN cache hit ratios and performance
- Regional backend health and latency
- Traffic distribution across regions

### Alerting Policies
- High latency alerts (>1000ms)
- Backend health degradation
- CDN cache miss rate increases
- Uptime check failures

### Network Intelligence Center
- Inter-region connectivity tests
- Network topology visualization
- Performance insights and recommendations

Access monitoring dashboards:
```bash
echo "Cloud Monitoring: https://console.cloud.google.com/monitoring"
echo "Network Intelligence: https://console.cloud.google.com/net-intelligence"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/traffic-optimization

# Verify deletion
gcloud infra-manager deployments list
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
cd scripts/
./destroy.sh
```

**Note**: The destroy script includes confirmation prompts for safety and removes resources in the correct order to avoid dependency issues.

## Cost Optimization

### Expected Costs

Estimated monthly costs for this deployment (varies by region and traffic):
- **Compute Instances**: $50-100 (6 x e2-medium instances)
- **Load Balancing**: $20-40 (global forwarding rules and backend services)
- **CDN**: $10-50 (varies significantly by traffic volume)
- **Network**: $20-100 (inter-region data transfer)
- **Monitoring**: $5-15 (uptime checks and custom metrics)

**Total Estimated Range**: $105-305/month

### Cost Optimization Tips

1. **Instance Sizing**: Use preemptible instances for non-critical workloads
2. **CDN Configuration**: Optimize cache policies to reduce origin requests
3. **Monitoring**: Use sampling rates for high-volume metrics
4. **Regional Strategy**: Evaluate traffic patterns to optimize region selection

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   gcloud services enable compute.googleapis.com monitoring.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Resource Quota Limits**:
   ```bash
   # Check compute quotas
   gcloud compute project-info describe --project=${PROJECT_ID}
   ```

4. **Health Check Failures**:
   ```bash
   # Debug health check status
   gcloud compute backend-services get-health BACKEND_SERVICE_NAME --global
   ```

### Logs and Debugging

```bash
# View load balancer logs
gcloud logging read "resource.type=http_load_balancer" --limit=50

# Check instance startup logs
gcloud compute instances get-serial-port-output INSTANCE_NAME --zone=ZONE

# Network connectivity troubleshooting
gcloud network-management connectivity-tests run TEST_NAME
```

## Security Considerations

### Network Security
- VPC with custom subnets for network isolation
- Firewall rules limiting access to necessary ports only
- Health check source ranges properly configured

### Load Balancer Security
- Cloud Armor integration available for DDoS protection
- SSL/TLS termination at load balancer
- Custom headers for backend identification

### Monitoring Security
- Service accounts with minimal required permissions
- Encrypted monitoring data in transit and at rest
- Access logging for audit trails

## Performance Optimization

### Load Balancer Optimization
- Outlier detection for automatic unhealthy backend removal
- Circuit breaker patterns for resilience
- Session affinity configuration available

### CDN Optimization
- Dynamic compression enabled
- Negative caching for error responses
- Custom cache key policies
- Serve-while-stale capabilities

### Regional Optimization
- Instance groups with auto-scaling policies
- Regional persistent disks for improved performance
- Network-optimized machine types available

## Support and Resources

### Documentation Links
- [Google Cloud Load Balancing](https://cloud.google.com/load-balancing/docs)
- [Cloud CDN Documentation](https://cloud.google.com/cdn/docs)
- [Network Intelligence Center](https://cloud.google.com/network-intelligence-center/docs)
- [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

### Getting Help
- For infrastructure issues: Check Google Cloud Console logs and monitoring
- For recipe questions: Refer to the original recipe documentation
- For Google Cloud support: Use Google Cloud Support (if you have a support plan)

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and modify according to your organization's requirements and policies.