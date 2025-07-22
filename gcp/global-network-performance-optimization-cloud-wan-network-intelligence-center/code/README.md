# Infrastructure as Code for Global Network Performance Optimization with Cloud WAN and Network Intelligence Center

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Establishing Global Network Performance Optimization with Cloud WAN and Network Intelligence Center".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a global network performance optimization architecture that includes:

- Multi-region VPC network with global connectivity
- Regional compute infrastructure across US, EU, and APAC
- Global HTTP(S) load balancer with SSL termination
- Comprehensive firewall rules and security policies
- VPC Flow Logs for network telemetry
- Network Intelligence Center integration for monitoring
- Cloud Monitoring dashboards and alerting

## Prerequisites

### Required Tools
- Google Cloud CLI (`gcloud`) installed and configured
- Terraform (>= 1.0) installed (for Terraform deployment)
- Bash shell environment
- `openssl` for random string generation

### Required Permissions
- Project Creator or Project Owner role
- Compute Admin role
- Network Admin role
- Monitoring Admin role
- Service Usage Admin role

### Estimated Costs
- **Monthly Cost Range**: $500-2000 USD
- **Primary Cost Drivers**:
  - Multi-region compute instances
  - Global load balancer traffic
  - VPC Flow Logs storage
  - Cross-region network egress

> **Note**: Cloud WAN requires Enterprise Support and is available through Google Cloud sales. This implementation demonstrates the configuration principles using standard VPC networking with Network Intelligence Center.

## Quick Start

### Using Infrastructure Manager

```bash
# Create deployment
gcloud infra-manager deployments create network-optimization \
    --location=us-central1 \
    --service-account=PROJECT_ID@PROJECT_ID.iam.gserviceaccount.com \
    --gcs-source=gs://BUCKET_NAME/infrastructure-manager/ \
    --input-values=project_id=PROJECT_ID,region_us=us-central1,region_eu=europe-west1,region_apac=asia-east1

# Monitor deployment
gcloud infra-manager deployments describe network-optimization \
    --location=us-central1
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=YOUR_PROJECT_ID"

# Deploy infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set executable permissions
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will display progress indicators and success confirmations
```

## Configuration Variables

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region_us` | US region for deployment | `us-central1` | No |
| `region_eu` | EU region for deployment | `europe-west1` | No |
| `region_apac` | APAC region for deployment | `asia-east1` | No |
| `network_name` | VPC network name | `global-wan-network` | No |
| `enable_flow_logs` | Enable VPC Flow Logs | `true` | No |

### Terraform Variables

Create a `terraform.tfvars` file or set variables via command line:

```hcl
project_id = "your-project-id"
region_us = "us-central1"
region_eu = "europe-west1"
region_apac = "asia-east1"
network_name = "global-wan-network"
machine_type = "e2-medium"
enable_monitoring = true
```

### Bash Script Environment Variables

Set these environment variables before running the deployment script:

```bash
export PROJECT_ID="your-project-id"
export REGION_US="us-central1"
export REGION_EU="europe-west1"
export REGION_APAC="asia-east1"
```

## Deployment Steps

### 1. Pre-deployment Validation

```bash
# Verify Google Cloud CLI authentication
gcloud auth list

# Check project access
gcloud projects describe YOUR_PROJECT_ID

# Verify required APIs are available
gcloud services list --available --filter="name:compute.googleapis.com OR name:monitoring.googleapis.com"
```

### 2. Infrastructure Deployment

Choose one of the deployment methods above based on your preference and organizational requirements.

### 3. Post-deployment Verification

```bash
# Check VPC network
gcloud compute networks list --filter="name:global-wan-*"

# Verify load balancer
gcloud compute forwarding-rules list --global

# Test connectivity
LOAD_BALANCER_IP=$(gcloud compute forwarding-rules describe global-web-https-rule --global --format="value(IPAddress)")
curl -v http://${LOAD_BALANCER_IP}
```

## Monitoring and Observability

### Network Intelligence Center

Access the Network Intelligence Center dashboard:

```bash
echo "Network Topology: https://console.cloud.google.com/net-intelligence/topology?project=YOUR_PROJECT_ID"
echo "Performance Dashboard: https://console.cloud.google.com/net-intelligence/performance?project=YOUR_PROJECT_ID"
```

### Cloud Monitoring

View the custom monitoring dashboard:

```bash
echo "Monitoring Dashboard: https://console.cloud.google.com/monitoring/dashboards?project=YOUR_PROJECT_ID"
```

### VPC Flow Logs

Query VPC Flow Logs using Cloud Logging:

```bash
gcloud logging read "resource.type=gce_subnetwork" \
    --project=YOUR_PROJECT_ID \
    --freshness=1h \
    --limit=50
```

## Testing and Validation

### Network Performance Testing

```bash
# Test cross-region connectivity
gcloud compute ssh web-server-us-1 \
    --zone=us-central1-a \
    --command="curl -w 'Total time: %{time_total}s\n' -s -o /dev/null http://INTERNAL_IP_EU"

# Load balancer health check
gcloud compute backend-services get-health global-web-backend --global
```

### Traffic Generation

```bash
# Generate test traffic for monitoring
for i in {1..100}; do
    curl -s http://${LOAD_BALANCER_IP} > /dev/null
    sleep 1
done
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete network-optimization \
    --location=us-central1 \
    --delete-policy=DELETE
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud compute networks list --filter="name:global-wan-*"
gcloud compute forwarding-rules list --global
gcloud compute instances list
```

## Troubleshooting

### Common Issues

**API Not Enabled Error**
```bash
# Enable required APIs
gcloud services enable compute.googleapis.com monitoring.googleapis.com
```

**Insufficient Permissions**
```bash
# Check current permissions
gcloud projects get-iam-policy YOUR_PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:user:YOUR_EMAIL"
```

**Load Balancer Not Responding**
```bash
# Check backend health
gcloud compute backend-services get-health global-web-backend --global

# Verify firewall rules
gcloud compute firewall-rules list --filter="network:global-wan-*"
```

**High Costs**
```bash
# Monitor resource usage
gcloud compute instances list --format="table(name,zone,machineType,status)"

# Check VPC Flow Logs volume
gcloud logging read "resource.type=gce_subnetwork" --freshness=1d --format="value(timestamp)" | wc -l
```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# For Terraform
export TF_LOG=DEBUG

# For gcloud commands
gcloud config set core/verbosity debug
```

## Security Considerations

### Best Practices Implemented

- **Network Segmentation**: Regional subnets with controlled inter-region communication
- **Firewall Rules**: Least-privilege access with specific source ranges
- **SSL/TLS**: HTTPS termination at the load balancer
- **Private IP Access**: Google services accessed via private endpoints
- **Flow Logs**: Comprehensive network monitoring and audit trails

### Additional Security Recommendations

1. **Enable VPC Service Controls** for additional data protection
2. **Implement Identity-Aware Proxy** for zero-trust access
3. **Configure Cloud Armor** for DDoS protection
4. **Enable Cloud Asset Inventory** for resource monitoring
5. **Use Organization Policies** for governance controls

## Performance Optimization

### Network Optimization Tips

1. **Regional Placement**: Deploy resources close to users
2. **Load Balancer Configuration**: Use appropriate balancing modes
3. **Health Check Tuning**: Optimize intervals and thresholds
4. **Flow Logs Sampling**: Adjust sampling rate based on needs
5. **Monitoring Alerts**: Set up proactive performance alerts

### Cost Optimization

1. **Instance Rightsizing**: Use appropriate machine types
2. **Flow Logs Management**: Configure retention policies
3. **Load Balancer Optimization**: Use regional load balancers when appropriate
4. **Monitoring Data**: Set up log-based metrics for cost control

## Support and Documentation

### Official Documentation
- [Google Cloud VPC Documentation](https://cloud.google.com/vpc/docs)
- [Network Intelligence Center](https://cloud.google.com/network-intelligence-center/docs)
- [Cloud Load Balancing](https://cloud.google.com/load-balancing/docs)
- [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)

### Community Resources
- [Google Cloud Architecture Center](https://cloud.google.com/architecture)
- [Google Cloud Community](https://cloud.google.com/community)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation
4. Contact Google Cloud Support (for production issues)

## Contributing

To improve this infrastructure code:
1. Follow Google Cloud best practices
2. Test changes in a development environment
3. Update documentation accordingly
4. Submit changes through proper channels

---

**Generated by**: IaC Generator v1.3  
**Recipe Version**: 1.0  
**Last Updated**: 2025-07-12