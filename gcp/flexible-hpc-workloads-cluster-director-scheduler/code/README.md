# Infrastructure as Code for Flexible HPC Workloads with Cluster Toolkit and Dynamic Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Flexible HPC Workloads with Cluster Toolkit and Dynamic Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Compute Engine (compute.instances.*, compute.reservations.*)
  - Cloud Storage (storage.buckets.*, storage.objects.*)
  - Cloud Batch (batch.jobs.*, batch.locations.*)
  - Cloud Monitoring (monitoring.dashboards.*, monitoring.alertPolicies.*)
  - Service Account creation and management
- Terraform installed (version 1.0+ for Terraform implementation)
- Cluster Toolkit installed for advanced HPC configurations
- Basic understanding of HPC workloads and scientific computing

> **Cost Estimate**: $50-200 for a 45-minute session depending on GPU/TPU usage and storage requirements

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native infrastructure as code service that provides a fully managed Terraform experience.

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export CLUSTER_NAME="hpc-cluster-$(date +%s)"

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply hpc-cluster-deployment \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/hpc-cluster" \
    --git-source-directory="infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION},cluster_name=${CLUSTER_NAME}"

# Monitor deployment progress
gcloud infra-manager deployments describe hpc-cluster-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned infrastructure changes
terraform plan -var="project_id=your-project-id" \
                -var="region=us-central1" \
                -var="cluster_name=hpc-cluster-$(date +%s)"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" \
                 -var="region=us-central1" \
                 -var="cluster_name=hpc-cluster-$(date +%s)"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud compute instances list --filter="name~hpc-"
gcloud batch jobs list --location=${REGION}
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `infrastructure-manager/main.yaml` file to customize:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `cluster_name`: HPC cluster name prefix
- `machine_type_cpu`: CPU instance type (default: c2-standard-16)
- `machine_type_gpu`: GPU instance type (default: n1-standard-8)
- `gpu_type`: GPU accelerator type (default: nvidia-tesla-t4)
- `instance_count_cpu`: Number of CPU instances (default: 2)
- `instance_count_gpu`: Number of GPU instances (default: 1)
- `disk_size_gb`: Boot disk size (default: 100GB)
- `enable_spot_instances`: Use spot instances for cost optimization (default: true)

### Terraform Variables

Customize your deployment by setting variables in `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
cluster_name = "my-hpc-cluster"
machine_type_cpu = "c2-standard-16"
machine_type_gpu = "n1-standard-8"
gpu_type = "nvidia-tesla-t4"
instance_count_cpu = 2
instance_count_gpu = 1
disk_size_gb = 100
enable_spot_instances = true
storage_bucket_location = "US"
enable_gpu_reservations = true
monitoring_notification_channels = ["projects/PROJECT_ID/notificationChannels/CHANNEL_ID"]
```

### Script Configuration

Edit environment variables in `scripts/deploy.sh`:

- `MACHINE_TYPE_CPU`: CPU instance machine type
- `MACHINE_TYPE_GPU`: GPU instance machine type
- `GPU_COUNT`: Number of GPUs per instance
- `ENABLE_MONITORING`: Enable advanced monitoring and dashboards
- `STORAGE_CLASS`: Cloud Storage class for data bucket
- `RESERVATION_DURATION`: GPU reservation duration in seconds

## Architecture Components

The infrastructure deploys the following components:

### Compute Resources
- **HPC CPU Nodes**: High-performance compute instances (c2-standard-16)
- **GPU Nodes**: GPU-accelerated instances with NVIDIA Tesla T4
- **Managed Instance Groups**: Auto-scaling groups for workload management
- **Placement Policies**: Optimized placement for low-latency communication

### Storage Infrastructure
- **Cloud Storage Bucket**: High-performance data storage with lifecycle policies
- **Persistent Disks**: SSD storage for compute instances
- **Lustre File System**: High-performance parallel file system integration

### Batch Processing
- **Cloud Batch Jobs**: Managed batch processing service
- **Job Queues**: Intelligent scheduling and resource allocation
- **Spot Instance Integration**: Cost-optimized compute for fault-tolerant workloads
- **GPU Reservations**: Predictable resource access for critical workloads

### Monitoring & Management
- **Cloud Monitoring Dashboards**: GPU utilization and batch job monitoring
- **Custom Metrics**: HPC-specific performance indicators
- **Cost Alerting**: Budget monitoring and spend optimization
- **Cloud Logging**: Centralized log aggregation and analysis

## Deployment Workflow

1. **Infrastructure Provisioning**: Deploy compute, storage, and networking resources
2. **Service Configuration**: Configure Cloud Batch, monitoring, and security
3. **Workload Submission**: Submit sample HPC workloads for validation
4. **Resource Optimization**: Enable spot instances and reservation management
5. **Monitoring Setup**: Configure dashboards and alerting policies

## Validation & Testing

After deployment, validate the infrastructure:

```bash
# Check compute instance status
gcloud compute instances list --filter="name~hpc-" \
    --format="table(name,status,machineType,zone)"

# Verify Cloud Batch configuration
gcloud batch jobs list --location=${REGION}

# Test storage accessibility
gsutil ls gs://your-hpc-data-bucket

# Monitor GPU reservations
gcloud compute reservations list --filter="name~hpc-gpu"

# Check monitoring dashboard
gcloud monitoring dashboards list --filter="displayName~HPC"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete hpc-cluster-deployment \
    --location=${REGION} \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" \
                   -var="region=us-central1" \
                   -var="cluster_name=your-cluster-name"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual cleanup verification
gcloud compute instances list --filter="name~hpc-"
gcloud batch jobs list --location=${REGION}
gsutil ls gs://your-hpc-data-bucket
```

## Cost Optimization

### Spot Instances
- Enable spot instances for fault-tolerant workloads (up to 80% cost reduction)
- Configure automatic failover to on-demand instances for critical tasks
- Use preemption-resistant workloads with checkpointing capabilities

### Resource Scheduling
- Leverage Cloud Batch intelligent scheduling for optimal resource allocation
- Use GPU reservations only for time-critical computational campaigns
- Implement lifecycle policies for long-term data storage cost optimization

### Monitoring and Alerting
- Set up budget alerts to monitor HPC cluster spending
- Use custom metrics to track computational efficiency and resource utilization
- Implement automated scaling policies based on workload demand patterns

## Security Considerations

### IAM and Access Control
- Use service accounts with minimal required permissions
- Implement fine-grained IAM policies for different user roles
- Enable audit logging for all compute and storage operations

### Network Security
- Deploy instances in private subnets with controlled internet access
- Use Cloud NAT for outbound internet connectivity
- Implement firewall rules for inter-cluster communication

### Data Protection
- Enable encryption at rest for all storage resources
- Use Cloud KMS for managing encryption keys
- Implement data classification and access policies

## Troubleshooting

### Common Issues

**Instance Quota Exceeded**:
```bash
# Check current quotas
gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)"

# Request quota increase
gcloud compute quotas list --filter="metric:INSTANCES"
```

**GPU Unavailability**:
```bash
# Check GPU availability in different zones
gcloud compute accelerator-types list --filter="zone:(us-central1-a,us-central1-b,us-central1-c)"

# Use reservations for guaranteed GPU access
gcloud compute reservations create gpu-reservation \
    --zone=us-central1-a \
    --vm-count=1 \
    --machine-type=n1-standard-8 \
    --accelerator=type=nvidia-tesla-t4,count=1
```

**Batch Job Failures**:
```bash
# Check job logs
gcloud batch jobs describe JOB_NAME --location=${REGION}

# Monitor task execution
gcloud logging read "resource.type=batch_task" --limit=50
```

### Support Resources

- [Google Cloud HPC Documentation](https://cloud.google.com/hpc)
- [Cloud Batch Documentation](https://cloud.google.com/batch/docs)
- [Cluster Toolkit Repository](https://github.com/GoogleCloudPlatform/cluster-toolkit)
- [Google Cloud Architecture Center](https://cloud.google.com/architecture)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Advanced Configurations

### Multi-Region Deployments
Configure workload distribution across multiple regions for improved availability and cost optimization.

### Custom Machine Images
Create optimized machine images with pre-installed HPC software and libraries.

### Integration with AI/ML Platforms
Connect HPC workloads with Vertex AI for advanced analytics and machine learning integration.

### Performance Tuning
Optimize instance types, placement policies, and storage configurations for specific computational workloads.

## Contributing

For improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Ensure compatibility with all three deployment methods
4. Update documentation to reflect any configuration changes

## License

This infrastructure code is provided under the same license as the parent recipe repository.