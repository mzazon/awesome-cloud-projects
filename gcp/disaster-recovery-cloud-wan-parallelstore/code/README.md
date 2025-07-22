# Infrastructure as Code for Disaster Recovery Orchestration with Cloud WAN and Parallelstore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Disaster Recovery Orchestration with Cloud WAN and Parallelstore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) v450.0.0 or later installed and configured
- Active Google Cloud project with billing enabled
- Access to Parallelstore service (requires allowlist approval from Google Cloud sales)
- Appropriate IAM permissions for:
  - Compute Engine API
  - Cloud Workflows API
  - Cloud Monitoring API
  - Parallelstore API
  - Pub/Sub API
  - Cloud Functions API
  - Network Connectivity API
  - Cloud Scheduler API
- Terraform v1.5+ (if using Terraform implementation)
- Estimated cost: $2,400-3,600/month for dual-region setup

> **Important**: Parallelstore is currently available by invitation only. Contact your Google Cloud sales representative to request access before proceeding.

## Architecture Overview

This solution implements an intelligent disaster recovery orchestration system featuring:

- **Multi-Region Setup**: Primary (us-central1) and secondary (us-east1) regions
- **High-Performance Storage**: 100 TiB Parallelstore instances in each region
- **Global Network**: Network Connectivity Center for Cloud WAN functionality
- **Automated Orchestration**: Cloud Workflows for disaster recovery automation
- **Intelligent Monitoring**: Cloud Monitoring with predictive alerting
- **Secure Connectivity**: HA VPN tunnels between regions
- **Event-Driven Architecture**: Pub/Sub messaging for decoupled communication

## Quick Start

### Using Infrastructure Manager

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export PRIMARY_REGION="us-central1"
export SECONDARY_REGION="us-east1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${PRIMARY_REGION}/deployments/hpc-dr-deployment \
    --service-account="your-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/infrastructure-repo" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${PRIMARY_REGION}/deployments/hpc-dr-deployment
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export PRIMARY_REGION="us-central1"
export SECONDARY_REGION="us-east1"

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates and verification commands
```

## Configuration Options

### Infrastructure Manager Configuration

The Infrastructure Manager deployment uses the following key parameters:

- `project_id`: Your Google Cloud project ID
- `primary_region`: Primary region for HPC workloads (default: us-central1)
- `secondary_region`: Secondary region for disaster recovery (default: us-east1)
- `parallelstore_capacity`: Storage capacity in TiB (default: 100)
- `vpc_cidr_primary`: CIDR block for primary VPC (default: 10.1.0.0/16)
- `vpc_cidr_secondary`: CIDR block for secondary VPC (default: 10.2.0.0/16)

### Terraform Configuration

Key variables in `terraform.tfvars`:

```hcl
# Project Configuration
project_id = "your-project-id"
primary_region = "us-central1"
secondary_region = "us-east1"

# Network Configuration
primary_vpc_cidr = "10.1.0.0/16"
secondary_vpc_cidr = "10.2.0.0/16"

# Storage Configuration
parallelstore_capacity = 100  # TiB

# Naming
resource_prefix = "hpc-dr"
random_suffix = true

# Monitoring Configuration
health_check_interval = "*/5 * * * *"  # Every 5 minutes
replication_interval = "*/15 * * * *"  # Every 15 minutes

# Security Configuration
enable_private_endpoints = true
enable_encryption = true
```

### Bash Script Configuration

Environment variables for bash deployment:

```bash
# Core Configuration
export PROJECT_ID="your-project-id"
export PRIMARY_REGION="us-central1"
export SECONDARY_REGION="us-east1"
export PRIMARY_ZONE="${PRIMARY_REGION}-a"
export SECONDARY_ZONE="${SECONDARY_REGION}-a"

# Resource Configuration
export PARALLELSTORE_CAPACITY="100"  # TiB
export HEALTH_CHECK_FREQUENCY="300"  # seconds
export REPLICATION_FREQUENCY="900"   # seconds (15 minutes)

# Optional: Custom naming
export DR_PREFIX="hpc-dr-custom"
```

## Verification

After deployment, verify your infrastructure:

### Check Parallelstore Status

```bash
# Verify primary Parallelstore instance
gcloud parallelstore instances describe ${DR_PREFIX}-primary-pfs \
    --location=${PRIMARY_ZONE} \
    --format="table(name,state,capacityGib)"

# Verify secondary Parallelstore instance
gcloud parallelstore instances describe ${DR_PREFIX}-secondary-pfs \
    --location=${SECONDARY_ZONE} \
    --format="table(name,state,capacityGib)"
```

### Test Network Connectivity

```bash
# Check Network Connectivity Center hub
gcloud network-connectivity hubs describe ${DR_PREFIX}-wan-hub \
    --format="table(name,state,routingVpcs)"

# Verify VPN tunnel status
gcloud compute vpn-tunnels list \
    --filter="name~'${DR_PREFIX}'" \
    --format="table(name,region,status,peerIp)"
```

### Validate Disaster Recovery Workflow

```bash
# Test workflow execution
gcloud workflows run ${DR_PREFIX}-dr-orchestrator \
    --location=${PRIMARY_REGION} \
    --data='{"trigger":"manual_failover","test_mode":true}'

# Monitor workflow status
gcloud workflows executions list \
    --workflow=${DR_PREFIX}-dr-orchestrator \
    --location=${PRIMARY_REGION} \
    --limit=5
```

### Test Health Monitoring

```bash
# Trigger health monitoring function
HEALTH_FUNCTION_URL=$(gcloud functions describe ${DR_PREFIX}-health-monitor \
    --region=${PRIMARY_REGION} \
    --format="value(httpsTrigger.url)")

curl -X GET "${HEALTH_FUNCTION_URL}" \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${PRIMARY_REGION}/deployments/hpc-dr-deployment

# Verify cleanup
gcloud infra-manager deployments list --location=${PRIMARY_REGION}
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

## Cost Optimization

### Storage Costs

- **Parallelstore**: ~$1,200-1,800/month per 100 TiB instance
- **Total Storage**: ~$2,400-3,600/month for both regions
- **Data Transfer**: Additional charges for cross-region replication

### Compute Costs

- **Cloud Functions**: Pay-per-execution model, minimal cost for monitoring
- **Cloud Workflows**: Pay-per-execution, typically <$10/month for DR operations
- **VPN Tunnels**: ~$36/month per tunnel

### Cost Reduction Strategies

1. **Adjust Parallelstore Capacity**: Start with smaller capacity and scale up
2. **Optimize Replication Frequency**: Reduce from 15-minute to hourly intervals
3. **Use Preemptible Instances**: For non-critical compute workloads
4. **Schedule Resource Scaling**: Scale down secondary region during low-usage periods

## Troubleshooting

### Common Issues

1. **Parallelstore Access Denied**
   ```bash
   # Verify API is enabled and you have access
   gcloud services list --enabled --filter="name:parallelstore.googleapis.com"
   # Contact Google Cloud sales for allowlist access
   ```

2. **VPN Tunnel Connection Issues**
   ```bash
   # Check tunnel status
   gcloud compute vpn-tunnels describe TUNNEL_NAME --region=REGION
   # Verify shared secrets match between tunnels
   ```

3. **Workflow Execution Failures**
   ```bash
   # Check workflow logs
   gcloud workflows executions describe EXECUTION_ID \
       --workflow=WORKFLOW_NAME \
       --location=REGION
   ```

4. **Function Deployment Issues**
   ```bash
   # Check function logs
   gcloud functions logs read FUNCTION_NAME --region=REGION
   ```

### Performance Optimization

1. **Network Bandwidth**: Configure multiple VPN tunnels for higher throughput
2. **Parallelstore Performance**: Use appropriate instance sizes for workload requirements
3. **Monitoring Frequency**: Balance between responsiveness and cost
4. **Replication Strategy**: Implement incremental replication for large datasets

## Security Considerations

### Network Security

- Private VPC networks with custom subnets
- HA VPN tunnels with strong encryption (IKEv2)
- Network Connectivity Center for optimized routing
- Firewall rules limiting inter-region traffic to required services

### Data Security

- Encryption at rest for Parallelstore instances
- Encryption in transit for all data replication
- IAM roles with least privilege principles
- Service accounts with minimal required permissions

### Access Control

- Cloud Functions with authentication required
- Workflow execution with proper IAM bindings
- Monitoring alerting with secure notification channels
- Audit logging for all disaster recovery operations

## Monitoring and Alerting

### Key Metrics

- Parallelstore instance health and performance
- Network connectivity latency and throughput
- Data replication lag and completion status
- Workflow execution success rates
- Resource utilization across regions

### Alert Configuration

- Critical: Parallelstore instance failures
- Warning: High replication lag (>15 minutes)
- Info: Successful failover completions
- Custom: Application-specific health metrics

## Support

### Google Cloud Support

- [Parallelstore Documentation](https://cloud.google.com/parallelstore/docs)
- [Network Connectivity Center](https://cloud.google.com/network-connectivity/docs/network-connectivity-center)
- [Cloud Workflows](https://cloud.google.com/workflows/docs)
- [Disaster Recovery Guide](https://cloud.google.com/architecture/disaster-recovery)

### Community Resources

- [Google Cloud Architecture Center](https://cloud.google.com/architecture)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest)
- [Infrastructure Manager Samples](https://github.com/GoogleCloudPlatform/infrastructure-manager-samples)

### Recipe-Specific Support

For issues specific to this disaster recovery implementation, refer to:
- Original recipe documentation in `../disaster-recovery-cloud-wan-parallelstore.md`
- Architecture diagrams and implementation details
- Step-by-step validation procedures
- Discussion section for design decisions and alternatives

---

**Note**: This infrastructure implements enterprise-grade disaster recovery for high-performance computing workloads. Ensure proper testing in non-production environments before deploying to production systems.