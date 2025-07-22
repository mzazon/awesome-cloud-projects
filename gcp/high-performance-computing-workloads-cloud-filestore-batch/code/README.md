# Infrastructure as Code for Building High-Performance Computing Workloads with Cloud Filestore and Cloud Batch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building High-Performance Computing Workloads with Cloud Filestore and Cloud Batch".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for:
  - Compute Engine (Compute Admin)
  - Cloud Filestore (Filestore Admin)
  - Cloud Batch (Batch Job Editor)
  - Cloud Monitoring (Monitoring Editor)
  - VPC Networks (Network Admin)
- Estimated cost: $50-150 for testing (varies by compute duration and storage capacity)

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create hpc-deployment \
    --location=us-central1 \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="gcp/high-performance-computing-workloads-cloud-filestore-batch/code/infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=us-central1"

# Monitor deployment
gcloud infra-manager deployments describe hpc-deployment \
    --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id"

# Apply configuration
terraform apply -var="project_id=your-project-id"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud filestore instances list --filter="zone:${ZONE}"
gcloud batch jobs list --filter="region:${REGION}"
```

## Architecture Overview

This IaC deploys a complete HPC environment consisting of:

- **VPC Network**: Dedicated network infrastructure with private subnet
- **Cloud Filestore**: Enterprise-grade NFS storage (2.56TB Enterprise tier)
- **Cloud Batch**: Managed job scheduling and compute provisioning
- **Cloud Monitoring**: Performance tracking and alerting
- **Auto-scaling**: Dynamic compute resource management (0-10 instances)

## Configuration Options

### Infrastructure Manager Variables

```yaml
# infrastructure-manager/main.yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  zone:
    description: "Deployment zone"
    type: string
    default: "us-central1-a"
  filestore_capacity_gb:
    description: "Filestore capacity in GB"
    type: number
    default: 2560
```

### Terraform Variables

```hcl
# terraform/variables.tf
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Deployment region"
  type        = string
  default     = "us-central1"
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB"
  type        = number
  default     = 2560
}
```

### Environment Variables for Scripts

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export FILESTORE_CAPACITY="2560"
export MAX_INSTANCES="10"
export MACHINE_TYPE="e2-standard-4"
```

## Validation & Testing

After deployment, validate the HPC environment:

```bash
# Check Filestore instance
gcloud filestore instances describe hpc-storage-$(openssl rand -hex 3) \
    --location=${ZONE} \
    --format="table(name,state,tier,networks.ipAddresses[0])"

# Verify network configuration
gcloud compute networks subnets describe hpc-subnet-$(openssl rand -hex 3) \
    --region=${REGION}

# Test batch job submission
gcloud batch jobs submit test-hpc-job \
    --location=${REGION} \
    --config=test-job-config.json

# Monitor job execution
gcloud batch jobs describe test-hpc-job \
    --location=${REGION} \
    --format="value(status.state)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete hpc-deployment \
    --location=us-central1 \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Security Considerations

This infrastructure implements several security best practices:

- **Private Subnet**: Compute instances deployed in private subnet with no external IPs
- **Firewall Rules**: Restrictive firewall rules allowing only necessary internal communication
- **IAM**: Service accounts with minimal required permissions
- **Encryption**: Data encrypted at rest and in transit
- **VPC**: Isolated network environment for HPC workloads

## Performance Optimization

For optimal HPC performance:

1. **Storage Performance**: Enterprise Filestore tier provides consistent IOPS and throughput
2. **Network**: Regional persistent disks and VPC peering minimize latency
3. **Compute**: Auto-scaling based on CPU utilization (70% threshold)
4. **Monitoring**: Real-time performance metrics and alerting

## Cost Management

Monitor and optimize costs with:

- **Preemptible Instances**: Consider using preemptible VMs for fault-tolerant workloads
- **Auto-scaling**: Automatic scale-down during low utilization periods
- **Storage Tiers**: Right-size Filestore capacity based on actual usage
- **Budget Alerts**: Set up billing alerts for cost control

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure service account has required IAM roles
2. **Quota Limits**: Check project quotas for compute and storage resources
3. **Network Connectivity**: Verify VPC and subnet configurations
4. **Job Failures**: Check Cloud Logging for batch job execution details

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:compute.googleapis.com OR name:file.googleapis.com OR name:batch.googleapis.com"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check resource quotas
gcloud compute project-info describe --format="table(quotas.limit,quotas.metric,quotas.usage)"

# View logs
gcloud logging read "resource.type=\"batch_job\"" --limit=20
```

## Advanced Configuration

### Multi-Zone Deployment

For high availability, consider deploying across multiple zones:

```bash
# terraform/variables.tf
variable "zones" {
  description = "List of zones for deployment"
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b", "us-central1-c"]
}
```

### GPU Acceleration

For ML/AI workloads, add GPU support:

```bash
# Update machine type for GPU instances
export GPU_MACHINE_TYPE="a2-highgpu-1g"
export GPU_TYPE="nvidia-tesla-a100"
```

### Hybrid Connectivity

Connect to on-premises infrastructure:

```bash
# Create VPN tunnel
gcloud compute vpn-tunnels create hpc-tunnel \
    --peer-address=YOUR_ON_PREM_IP \
    --shared-secret=YOUR_SHARED_SECRET \
    --target-vpn-gateway=hpc-vpn-gateway
```

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../high-performance-computing-workloads-cloud-filestore-batch.md)
2. Consult [Google Cloud HPC documentation](https://cloud.google.com/solutions/hpc)
3. Check [Cloud Filestore best practices](https://cloud.google.com/filestore/docs/best-practices)
4. Refer to [Cloud Batch optimization guide](https://cloud.google.com/batch/docs/best-practices)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update documentation for any new variables or resources
3. Ensure cleanup scripts handle new resources
4. Validate security configurations
5. Update cost estimates for new resources

## License

This infrastructure code is provided under the same license as the parent repository.