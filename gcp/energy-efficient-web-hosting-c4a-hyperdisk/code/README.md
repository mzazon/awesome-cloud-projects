# Infrastructure as Code for Energy-Efficient Web Hosting with C4A and Hyperdisk

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Energy-Efficient Web Hosting with C4A and Hyperdisk".

## Overview

This solution deploys ARM-based C4A instances powered by Google's custom Axion processors combined with high-performance Hyperdisk storage to achieve up to 60% better energy efficiency compared to traditional x86 instances. The infrastructure includes load balancing for high availability and Cloud Monitoring for comprehensive observability.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code tool
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

- Google Cloud C4A instances with Axion ARM processors
- Hyperdisk Balanced storage volumes with optimized performance
- HTTP Load Balancer with health checks
- VPC networking with security rules
- Cloud Monitoring dashboards for energy efficiency tracking

## Prerequisites

- Google Cloud Project with billing enabled
- Google Cloud CLI (gcloud) installed and authenticated
- Project APIs enabled: Compute Engine, Cloud Monitoring, Cloud Logging
- Appropriate IAM permissions for resource creation:
  - Compute Admin
  - Network Admin
  - Monitoring Admin
  - Service Usage Admin
- Estimated cost: $45-75 per month for 3 C4A instances with Hyperdisk storage

> **Note**: C4A instances with Axion processors are available in select regions: us-central1, us-east4, us-east1, eu-west1, eu-west4, eu-west3, and asia-southeast1.

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Configure gcloud
gcloud config set project ${PROJECT_ID}

# Create deployment
gcloud infra-manager deployments create energy-web-hosting \
    --location=${REGION} \
    --service-account="your-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/energy-efficient-web-hosting-c4a-hyperdisk/code/infrastructure-manager" \
    --git-source-ref="main"

# Monitor deployment status
gcloud infra-manager deployments describe energy-web-hosting \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="zone=us-central1-a"

# Apply the configuration
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="zone=us-central1-a"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
gcloud compute instances list --filter="labels.recipe=energy-efficient-web-hosting"
```

## Configuration Variables

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Google Cloud region | `us-central1` | No |
| `zone` | Google Cloud zone | `us-central1-a` | No |
| `instance_count` | Number of C4A instances | `3` | No |
| `machine_type` | C4A machine type | `c4a-standard-4` | No |
| `disk_size_gb` | Hyperdisk size in GB | `50` | No |
| `disk_iops` | Provisioned IOPS for Hyperdisk | `3000` | No |
| `disk_throughput` | Provisioned throughput (MB/s) | `140` | No |
| `network_name` | VPC network name | `energy-web-vpc` | No |
| `subnet_name` | Subnet name | `energy-web-subnet` | No |
| `subnet_cidr` | Subnet CIDR range | `10.0.0.0/24` | No |

### Environment Variables (Bash Scripts)

```bash
export PROJECT_ID="your-project-id"           # Required: Your GCP project ID
export REGION="us-central1"                   # Optional: Default us-central1
export ZONE="us-central1-a"                   # Optional: Default us-central1-a
export INSTANCE_COUNT="3"                     # Optional: Number of instances
export MACHINE_TYPE="c4a-standard-4"          # Optional: C4A machine type
export DISK_SIZE="50"                         # Optional: Disk size in GB
```

## Validation and Testing

After deployment, verify the infrastructure:

```bash
# Check C4A instances
gcloud compute instances list --filter="machineType~c4a"

# Verify ARM architecture
gcloud compute ssh [INSTANCE-NAME] --zone=[ZONE] --command="uname -m"

# Test load balancer
LB_IP=$(gcloud compute forwarding-rules describe [LB-NAME] \
    --global --format="value(IPAddress)")
curl http://${LB_IP}

# Check Hyperdisk performance
gcloud compute disks list --filter="type=hyperdisk-balanced"

# View monitoring dashboard
echo "https://console.cloud.google.com/monitoring/dashboards"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete energy-web-hosting \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="zone=us-central1-a"

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud compute instances list --filter="labels.recipe=energy-efficient-web-hosting"
```

## Customization

### Energy Efficiency Optimizations

1. **Instance Sizing**: Adjust `machine_type` variable to match your workload requirements
2. **Auto Scaling**: Extend with managed instance groups for dynamic scaling
3. **Regional Distribution**: Deploy across multiple regions for global efficiency
4. **Storage Optimization**: Tune Hyperdisk IOPS and throughput based on I/O patterns

### Security Enhancements

1. **HTTPS Termination**: Add SSL certificates for secure connections
2. **Identity-Aware Proxy**: Implement IAP for secure access control
3. **VPC Service Controls**: Add perimeter security for data protection
4. **Secrets Management**: Use Secret Manager for sensitive configuration

### Monitoring Extensions

1. **Custom Metrics**: Add application-specific energy efficiency metrics
2. **Alerting Policies**: Configure alerts for performance thresholds
3. **Cost Monitoring**: Implement cost tracking and budget alerts
4. **Carbon Footprint**: Track and report environmental impact metrics

## Performance Optimization

### C4A Instance Tuning

- Monitor CPU utilization and adjust instance size as needed
- Use placement policies for optimal network performance
- Configure appropriate machine types based on workload characteristics

### Hyperdisk Configuration

- Tune provisioned IOPS and throughput based on application requirements
- Consider Hyperdisk Extreme for highest performance workloads
- Implement appropriate backup and snapshot strategies

### Load Balancer Optimization

- Configure connection draining for smooth maintenance
- Implement SSL offloading for reduced instance overhead
- Use appropriate backend service timeout settings

## Troubleshooting

### Common Issues

1. **C4A Availability**: Ensure your selected region supports C4A instances
2. **API Enablement**: Verify all required APIs are enabled in your project
3. **IAM Permissions**: Check that your account has necessary permissions
4. **Resource Quotas**: Ensure sufficient quota for C4A instances and Hyperdisk

### Debugging Commands

```bash
# Check API status
gcloud services list --enabled

# Verify quotas
gcloud compute project-info describe --format="yaml(quotas)"

# Check instance creation logs
gcloud logging read "resource.type=gce_instance AND operation.first=true"

# Monitor deployment progress
gcloud compute operations list --filter="operationType=insert"
```

## Cost Optimization

### Resource Sizing

- Start with smaller C4A instances and scale based on monitoring data
- Use sustained use discounts for long-running workloads
- Consider committed use discounts for predictable workloads

### Storage Optimization

- Right-size Hyperdisk volumes based on actual usage
- Use appropriate performance tiers (Balanced vs Extreme)
- Implement lifecycle policies for data management

### Monitoring and Alerting

- Set up budget alerts to monitor spending
- Use Cloud Monitoring to track resource utilization
- Implement automated scaling to optimize costs

## Support and Documentation

- [Google Cloud C4A Instance Documentation](https://cloud.google.com/compute/docs/general-purpose-machines#c4a_machine_types)
- [Hyperdisk Documentation](https://cloud.google.com/compute/docs/disks/add-hyperdisk)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Environmental Impact

This solution delivers significant environmental benefits:

- **60% better energy efficiency** compared to x86 instances
- **Reduced carbon footprint** through ARM-based computing
- **Optimized resource utilization** through intelligent load balancing
- **Sustainable storage** with Hyperdisk's efficient architecture

Monitor your environmental impact through the included Cloud Monitoring dashboards and consider this infrastructure as part of your organization's broader sustainability initiatives.

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud's official documentation.