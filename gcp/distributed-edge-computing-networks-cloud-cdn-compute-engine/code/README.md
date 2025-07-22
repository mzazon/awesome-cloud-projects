# Infrastructure as Code for Architecting Distributed Edge Computing Networks with Cloud CDN and Compute Engine

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Architecting Distributed Edge Computing Networks with Cloud CDN and Compute Engine".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 450.0.0 or later)
- Terraform installed (version 1.0 or later) for Terraform implementation
- Appropriate Google Cloud permissions for:
  - Compute Engine (compute.admin)
  - Cloud CDN (compute.admin)
  - Cloud Load Balancing (compute.admin)
  - Cloud DNS (dns.admin)
  - Cloud Storage (storage.admin)
  - IAM (iam.serviceAccountAdmin for service accounts)
- Project with billing enabled
- APIs enabled: Compute Engine, Cloud DNS, Cloud Storage, Logging, Monitoring

## Architecture Overview

This implementation creates a globally distributed edge computing network with:

- Global VPC network with regional subnets
- Multi-region Compute Engine clusters with auto-scaling
- Global HTTP(S) Load Balancer with Cloud CDN enabled
- Cloud Storage origin buckets for static content
- Cloud DNS for latency-based routing
- Comprehensive security and monitoring configuration

## Quick Start

### Using Infrastructure Manager

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGIONS="us-central1,europe-west1,asia-southeast1"
export DOMAIN_NAME="your-domain.com"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments create edge-network-deployment \
    --location=us-central1 \
    --file=infrastructure-manager/main.yaml \
    --input-values="project_id=${PROJECT_ID},regions=${REGIONS},domain_name=${DOMAIN_NAME}"

# Monitor deployment progress
gcloud infra-manager deployments describe edge-network-deployment \
    --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "your-project-id"
regions = ["us-central1", "europe-west1", "asia-southeast1"]
zones = ["us-central1-a", "europe-west1-b", "asia-southeast1-a"]
domain_name = "your-domain.com"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export DOMAIN_NAME="your-domain.com"

# Deploy infrastructure
./scripts/deploy.sh

# The script will guide you through the deployment process
# and provide status updates for each component
```

## Configuration Variables

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `regions` | Comma-separated list of regions | `us-central1,europe-west1,asia-southeast1` | No |
| `domain_name` | Domain name for DNS configuration | - | Yes |
| `machine_type` | Compute Engine machine type | `e2-standard-2` | No |
| `min_replicas` | Minimum instances per region | `2` | No |
| `max_replicas` | Maximum instances per region | `5` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | `string` | - | Yes |
| `regions` | List of deployment regions | `list(string)` | `["us-central1", "europe-west1", "asia-southeast1"]` | No |
| `zones` | List of deployment zones | `list(string)` | `["us-central1-a", "europe-west1-b", "asia-southeast1-a"]` | No |
| `domain_name` | Domain name for DNS | `string` | - | Yes |
| `machine_type` | Compute Engine machine type | `string` | `e2-standard-2` | No |
| `network_name` | VPC network name | `string` | `edge-network` | No |
| `min_node_count` | Minimum instances per region | `number` | `2` | No |
| `max_node_count` | Maximum instances per region | `number` | `5` | No |
| `disk_size` | Boot disk size in GB | `number` | `20` | No |
| `enable_monitoring` | Enable detailed monitoring | `bool` | `true` | No |

### Bash Script Environment Variables

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `PROJECT_ID` | Google Cloud Project ID | Yes | `my-edge-project` |
| `DOMAIN_NAME` | Domain name for DNS | Yes | `example.com` |
| `REGIONS` | Space-separated regions | No | `us-central1 europe-west1` |
| `MACHINE_TYPE` | Compute Engine machine type | No | `e2-standard-2` |
| `MIN_INSTANCES` | Minimum instances per region | No | `2` |
| `MAX_INSTANCES` | Maximum instances per region | No | `5` |

## Deployment Steps

### Pre-Deployment Checklist

1. **Project Setup**:
   ```bash
   # Create and configure project
   gcloud projects create ${PROJECT_ID}
   gcloud config set project ${PROJECT_ID}
   gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT}
   ```

2. **Enable APIs**:
   ```bash
   gcloud services enable compute.googleapis.com \
       dns.googleapis.com \
       storage.googleapis.com \
       logging.googleapis.com \
       monitoring.googleapis.com
   ```

3. **Set IAM Permissions**:
   ```bash
   # Grant necessary permissions to deployment service account
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/compute.admin"
   ```

### Post-Deployment Configuration

1. **DNS Configuration**:
   ```bash
   # Get nameservers for domain configuration
   gcloud dns managed-zones describe edge-zone \
       --format="value(nameServers[].join(' '))"
   ```

2. **SSL Certificate Setup** (Optional):
   ```bash
   # Create managed SSL certificate
   gcloud compute ssl-certificates create edge-ssl-cert \
       --domains=${DOMAIN_NAME},www.${DOMAIN_NAME} \
       --global
   ```

3. **Monitor Deployment**:
   ```bash
   # Check load balancer status
   gcloud compute backend-services get-health edge-backend-service \
       --global
   
   # Verify CDN cache configuration
   gcloud compute backend-services describe edge-backend-service \
       --global --format="value(cdnPolicy)"
   ```

## Validation and Testing

### Infrastructure Validation

```bash
# Test global load balancer
GLOBAL_IP=$(gcloud compute addresses describe edge-global-ip \
    --global --format="value(address)")
curl -H "Host: ${DOMAIN_NAME}" http://${GLOBAL_IP}/

# Test CDN caching behavior
for i in {1..5}; do
    echo "Request ${i}:"
    curl -s -w "Time: %{time_total}s\n" \
        -H "Host: ${DOMAIN_NAME}" \
        http://${GLOBAL_IP}/ -o /dev/null
done

# Verify regional backends
gcloud compute backend-services get-health edge-backend-service --global
```

### Performance Testing

```bash
# Test from multiple regions using Cloud Shell
gcloud compute instances create test-client \
    --zone=us-east1-b \
    --machine-type=e2-micro \
    --image-family=ubuntu-2004-lts \
    --image-project=ubuntu-os-cloud

# Run latency tests
gcloud compute ssh test-client --zone=us-east1-b --command="
    for i in {1..10}; do
        curl -w 'Total time: %{time_total}s\n' \
            -s -o /dev/null http://${GLOBAL_IP}/
    done
"
```

### Security Validation

```bash
# Check firewall rules
gcloud compute firewall-rules list --filter="network:edge-network"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Test security headers
curl -I http://${GLOBAL_IP}/
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete edge-network-deployment \
    --location=us-central1 \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
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

# The script will prompt for confirmation before deleting resources
# and provide progress updates during cleanup
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud compute instances list
gcloud compute load-balancers list
gcloud compute networks list --filter="name:edge-network*"
gcloud dns managed-zones list
gcloud compute addresses list
```

## Monitoring and Observability

### Cloud Monitoring Dashboards

```bash
# Create custom dashboard for edge network monitoring
gcloud monitoring dashboards create --config-from-file=monitoring/dashboard.json
```

### Alerting Policies

```bash
# Create alerting policy for high latency
gcloud alpha monitoring policies create --policy-from-file=monitoring/latency-alert.yaml
```

### Log Analysis

```bash
# View load balancer logs
gcloud logging read "resource.type=http_load_balancer" \
    --limit=50 \
    --format="table(timestamp,httpRequest.requestMethod,httpRequest.requestUrl,httpRequest.status)"

# Monitor CDN cache performance
gcloud logging read "resource.type=http_load_balancer AND jsonPayload.cacheResult" \
    --limit=100
```

## Troubleshooting

### Common Issues

1. **Backend Health Check Failures**:
   ```bash
   # Check instance group health
   gcloud compute backend-services get-health edge-backend-service --global
   
   # Verify firewall rules allow health checks
   gcloud compute firewall-rules describe edge-network-allow-health-check
   ```

2. **CDN Cache Issues**:
   ```bash
   # Clear CDN cache if needed
   gcloud compute url-maps invalidate-cdn-cache edge-url-map \
       --path="/*"
   ```

3. **DNS Resolution Problems**:
   ```bash
   # Test DNS resolution
   nslookup ${DOMAIN_NAME}
   dig ${DOMAIN_NAME} @8.8.8.8
   ```

4. **Auto-scaling Not Working**:
   ```bash
   # Check autoscaler status
   gcloud compute instance-groups managed describe edge-group-us-central1 \
       --zone=us-central1-a
   ```

### Debug Commands

```bash
# Enable debug logging for gcloud
export CLOUDSDK_CORE_LOG_LEVEL=debug

# Get detailed resource information
gcloud compute backend-services describe edge-backend-service \
    --global --format="export"

# Check quota usage
gcloud compute project-info describe \
    --format="table(quotas.metric,quotas.usage,quotas.limit)"
```

## Cost Optimization

### Resource Sizing

- Use `e2-small` instances for development environments
- Implement aggressive auto-scaling policies for cost control
- Use preemptible instances for non-critical workloads

### Monitoring Costs

```bash
# Set up billing alerts
gcloud alpha billing budgets create \
    --billing-account=${BILLING_ACCOUNT} \
    --display-name="Edge Network Budget" \
    --budget-amount=100USD
```

## Security Considerations

### Network Security

- VPC networks use private IP ranges
- Firewall rules follow least privilege principle
- Health check sources are restricted to Google Cloud ranges

### Identity and Access Management

- Service accounts use minimal required permissions
- Instance groups use default service accounts with limited scopes
- Cloud Storage buckets use uniform bucket-level access

### Data Protection

- Enable encryption at rest for all storage resources
- Use HTTPS for all external communication
- Implement Cloud Armor for DDoS protection (optional enhancement)

## Support and Documentation

### Google Cloud Documentation

- [Cloud CDN Documentation](https://cloud.google.com/cdn/docs)
- [Compute Engine Documentation](https://cloud.google.com/compute/docs)
- [Cloud Load Balancing Documentation](https://cloud.google.com/load-balancing/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Terraform Documentation

- [Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Terraform Google Cloud Modules](https://registry.terraform.io/namespaces/terraform-google-modules)

### Additional Resources

- [Google Cloud Architecture Center](https://cloud.google.com/architecture)
- [Edge Computing Best Practices](https://cloud.google.com/architecture/edge-computing)
- [CDN Performance Optimization](https://cloud.google.com/cdn/docs/best-practices)

For issues with this infrastructure code, refer to the original recipe documentation or consult the Google Cloud documentation for specific services.