# Flexible HPC Workloads with Cluster Toolkit and Dynamic Scheduler - Terraform

This directory contains Terraform infrastructure as code for deploying the "Flexible HPC Workloads with Cluster Toolkit and Dynamic Scheduler" recipe on Google Cloud Platform.

## Overview

This Terraform configuration deploys a comprehensive HPC environment that combines:

- **High-Performance Computing Infrastructure**: CPU-optimized and GPU-accelerated compute instances
- **Intelligent Scheduling**: Cloud Batch with spot instance optimization and predictable reservations
- **Scalable Storage**: Cloud Storage with lifecycle management and cost optimization
- **Advanced Monitoring**: Custom dashboards, alerting, and cost management
- **Security Best Practices**: IAM roles, private networking, and encrypted storage

## Architecture Components

### Networking
- VPC network with jumbo frame support (MTU 8896) for high-performance communication
- Private subnet with Google Private Access enabled
- Cloud NAT for outbound internet access from private instances
- Firewall rules optimized for HPC cluster communication

### Compute Resources
- **HPC Compute Instances**: CPU-optimized instances (c2-standard-16) with placement policies
- **GPU Compute Instances**: GPU-accelerated instances (n1-standard-8) with NVIDIA Tesla T4
- Managed Instance Groups with auto-healing and rolling updates
- Custom startup scripts for HPC software installation and optimization

### Storage
- Cloud Storage bucket with intelligent lifecycle management
- Automatic tiering: Standard → Nearline (30 days) → Coldline (90 days) → Archive (365 days)
- Version control and access logging
- Optimized for scientific computing data patterns

### Batch Processing
- Cloud Batch jobs with spot instance optimization
- Intelligent workload distribution and scaling
- Automated resource provisioning based on demand
- Integration with storage and monitoring systems

### Monitoring & Alerting
- Custom monitoring dashboard for HPC metrics
- GPU utilization and performance tracking
- Cost management with budget alerts and thresholds
- Comprehensive logging and observability

## Prerequisites

1. **Google Cloud Project** with billing enabled
2. **Required APIs** (automatically enabled by Terraform):
   - Compute Engine API
   - Cloud Storage API
   - Cloud Batch API
   - Cloud Monitoring API
   - Cloud Logging API
   - Cloud Billing API

3. **Authentication** - one of the following:
   - Service account key file
   - Application Default Credentials (ADC)
   - Google Cloud SDK authentication

4. **Terraform** version >= 1.5
5. **Required permissions**:
   - Compute Admin
   - Storage Admin
   - Service Account Admin
   - Monitoring Admin
   - Project IAM Admin

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd gcp/flexible-hpc-workloads-cluster-director-scheduler/code/terraform/
```

### 2. Configure Variables
Create a `terraform.tfvars` file:

```hcl
# Required Variables
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional Customizations
hpc_instance_count    = 2
gpu_instance_count    = 1
hpc_machine_type      = "c2-standard-16"
gpu_machine_type      = "n1-standard-8"
gpu_type              = "nvidia-tesla-t4"

# Storage Configuration
hpc_bucket_name = "my-hpc-data"
storage_class   = "STANDARD"

# Batch Configuration
enable_batch_jobs     = true
batch_task_count      = 4
batch_parallelism     = 2

# Monitoring Configuration
enable_monitoring     = true
budget_amount         = 100

# GPU Reservations (optional)
enable_gpu_reservation = false

# Labels
labels = {
  environment = "production"
  project     = "scientific-computing"
  team        = "research"
  managed-by  = "terraform"
}
```

### 3. Initialize and Deploy
```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment
```bash
# Check compute instances
gcloud compute instances list --filter="name~(hpc-worker|gpu-worker)"

# Verify storage bucket
gsutil ls gs://$(terraform output -raw hpc_storage_bucket_name)

# List batch jobs
gcloud batch jobs list --location=$(terraform output -raw region)

# View monitoring dashboard
echo "Dashboard: $(terraform output -raw monitoring_dashboard_id)"
```

## Configuration Variables

### Core Configuration
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | ✅ |
| `region` | Google Cloud region | `us-central1` | ❌ |
| `zone` | Google Cloud zone | `us-central1-a` | ❌ |

### Compute Configuration
| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `hpc_instance_count` | Number of HPC compute instances | `2` | 1-100 |
| `gpu_instance_count` | Number of GPU compute instances | `1` | 0-10 |
| `hpc_machine_type` | Machine type for HPC instances | `c2-standard-16` | c2-* series |
| `gpu_machine_type` | Machine type for GPU instances | `n1-standard-8` | GPU-compatible |
| `gpu_type` | GPU accelerator type | `nvidia-tesla-t4` | NVIDIA GPUs |
| `gpu_count` | GPUs per instance | `1` | 1-8 |

### Storage Configuration
| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `hpc_bucket_name` | Storage bucket name prefix | `hpc-data` | - |
| `storage_class` | Default storage class | `STANDARD` | STANDARD, NEARLINE, COLDLINE, ARCHIVE |

### Batch Processing
| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `enable_batch_jobs` | Create sample batch jobs | `true` | boolean |
| `batch_task_count` | Tasks per batch job | `4` | 1-1000 |
| `batch_parallelism` | Parallel task execution | `2` | 1-100 |

### Monitoring & Cost Management
| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `enable_monitoring` | Enable monitoring dashboards | `true` | boolean |
| `budget_amount` | Budget alert threshold (USD) | `100` | 1-10000 |

## Resource Outputs

After successful deployment, Terraform provides comprehensive outputs:

### Key Outputs
- **Storage Bucket**: `hpc_storage_bucket_name`
- **VPC Network**: `vpc_network_name`
- **Instance Groups**: `hpc_instance_group_manager_name`, `gpu_instance_group_manager_name`
- **Service Account**: `hpc_service_account_email`
- **Monitoring Dashboard**: `monitoring_dashboard_id`

### Access Information
- **SSH Command**: Use Cloud IAP tunnel for secure access
- **Storage Access**: Use `gsutil` with the provided bucket name
- **Batch Jobs**: Monitor via Cloud Console or `gcloud batch` commands

## Operational Guidance

### Scaling Operations
```bash
# Scale HPC instances
terraform apply -var="hpc_instance_count=5"

# Scale GPU instances
terraform apply -var="gpu_instance_count=3"

# Enable GPU reservations for predictable access
terraform apply -var="enable_gpu_reservation=true"
```

### Monitoring and Optimization
1. **Access Monitoring Dashboard**:
   ```bash
   # Get dashboard URL
   echo "https://console.cloud.google.com/monitoring/dashboards/custom/$(terraform output -raw monitoring_dashboard_id)"
   ```

2. **Monitor Costs**:
   ```bash
   # View current spending
   gcloud billing projects describe $(terraform output -raw project_id)
   ```

3. **GPU Utilization**:
   ```bash
   # SSH to GPU instance and check utilization
   gcloud compute ssh --zone=$(terraform output -raw zone) --tunnel-through-iap gpu-worker-<suffix>
   nvidia-smi
   ```

### Performance Optimization
1. **HPC Workload Optimization**:
   - Use placement policies for low-latency communication
   - Configure NUMA topology for optimal memory access
   - Leverage high-performance storage mounts

2. **GPU Workload Optimization**:
   - Monitor GPU memory usage and adjust batch sizes
   - Use mixed precision training for improved performance
   - Implement gradient accumulation for large models

3. **Cost Optimization**:
   - Use spot instances for fault-tolerant workloads
   - Schedule GPU reservations only when needed
   - Implement automatic scaling based on workload demand

## Security Considerations

### Network Security
- Instances use private IPs with no external access
- Cloud NAT provides secure outbound internet access
- Firewall rules restrict access to authorized sources only

### Access Control
- Service accounts follow principle of least privilege
- OS Login enabled for centralized SSH key management
- IAM roles scoped to specific resource access patterns

### Data Protection
- Storage buckets use uniform bucket-level access
- Data encrypted at rest with Google-managed keys
- Access logging enabled for audit trails

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs manually
   gcloud services enable compute.googleapis.com
   gcloud services enable batch.googleapis.com
   ```

2. **Quota Limitations**:
   ```bash
   # Check compute quotas
   gcloud compute project-info describe --project=$(terraform output -raw project_id)
   ```

3. **GPU Driver Issues**:
   ```bash
   # Check GPU driver installation on instances
   gcloud compute ssh --zone=$(terraform output -raw zone) --tunnel-through-iap gpu-worker-<suffix>
   nvidia-smi
   ```

4. **Storage Access Issues**:
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://$(terraform output -raw hpc_storage_bucket_name)
   ```

### Debugging Commands
```bash
# Check Terraform state
terraform show

# Validate configuration
terraform validate

# View instance logs
gcloud logging read "resource.type=gce_instance"

# Monitor batch job status
gcloud batch jobs describe <job-name> --location=$(terraform output -raw region)
```

## Cleanup

### Complete Infrastructure Removal
```bash
# Destroy all resources
terraform destroy

# Confirm removal of storage buckets (if needed)
gsutil rm -r gs://$(terraform output -raw hpc_storage_bucket_name)
```

### Selective Resource Cleanup
```bash
# Remove only GPU instances
terraform apply -var="gpu_instance_count=0"

# Disable batch jobs
terraform apply -var="enable_batch_jobs=false"

# Disable monitoring
terraform apply -var="enable_monitoring=false"
```

## Advanced Configurations

### Custom Images
Modify the image variables in `terraform.tfvars`:
```hcl
hpc_image_family  = "ubuntu-2204-lts"
hpc_image_project = "ubuntu-os-cloud"
gpu_image_family  = "deep-learning-vm"
gpu_image_project = "deeplearning-platform-release"
```

### Network Customization
```hcl
vpc_name     = "custom-hpc-vpc"
subnet_name  = "custom-hpc-subnet"
subnet_cidr  = "10.10.0.0/24"
```

### Storage Optimization
```hcl
storage_class = "NEARLINE"  # For cost-sensitive workloads
```

## Support and Documentation

- **Terraform Provider**: [Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Cloud Batch**: [Cloud Batch Documentation](https://cloud.google.com/batch/docs)
- **HPC on Google Cloud**: [HPC Toolkit Documentation](https://cloud.google.com/hpc-toolkit/docs)
- **Monitoring**: [Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with appropriate tests
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the same license as the parent repository.