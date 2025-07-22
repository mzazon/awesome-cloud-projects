# Infrastructure as Code for High-Performance Data Science Workflows with Cloud NetApp Volumes and Vertex AI Workbench

This directory contains Infrastructure as Code (IaC) implementations for the recipe "High-Performance Data Science Workflows with Cloud NetApp Volumes and Vertex AI Workbench".

## Solution Overview

This solution combines Google Cloud NetApp Volumes with Vertex AI Workbench to create a high-performance, collaborative data science environment. Cloud NetApp Volumes provides enterprise-grade file storage with up to 4.5 GiB/sec throughput and sub-millisecond latency, while Vertex AI Workbench offers managed Jupyter notebooks with seamless integration to Google Cloud services.

## Available Implementations

- **Infrastructure Manager**: Google's Infrastructure as Code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code (HCL)
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure deploys the following Google Cloud resources:

- **VPC Network & Subnet**: Custom network for high-performance data science workflows
- **Cloud NetApp Volumes**: High-performance file storage with Premium service level
  - Storage Pool (1024 GiB capacity)
  - Volume (500 GiB capacity with NFS protocol)
- **Vertex AI Workbench**: Managed Jupyter notebook instance with GPU acceleration
  - Machine Type: n1-standard-4
  - GPU: NVIDIA Tesla T4
  - TensorFlow Enterprise 2.11 image
- **Cloud Storage**: Data lake bucket for model versioning and archival
- **Compute Engine**: GPU-enabled instances for ML workloads

## Prerequisites

- Google Cloud Platform account with billing enabled
- Appropriate permissions for:
  - Vertex AI and Notebooks API
  - Compute Engine API
  - NetApp Volumes API
  - Cloud Storage API
  - AI Platform API
- Google Cloud CLI (gcloud) installed and configured, or access to Google Cloud Shell
- Basic understanding of:
  - Jupyter notebooks and data science workflows
  - File system mounting and Linux commands
  - Infrastructure as Code concepts

### Cost Estimates

- **NetApp Volumes**: ~$0.35/GB/month (Premium tier)
- **Vertex AI Workbench**: ~$0.50/hour for standard instances
- **GPU acceleration**: Additional hourly charges for Tesla T4
- **Cloud Storage**: Standard storage rates
- **Total estimated cost**: $50-150 per day depending on usage

> **Important**: Cloud NetApp Volumes is currently available in select regions. Verify availability in your preferred region before proceeding. See the [Cloud NetApp Volumes documentation](https://cloud.google.com/netapp-volumes/docs) for current regional availability.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google's recommended IaC solution that provides native Google Cloud integration.

```bash
# Set your project ID and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="ml-netapp-deployment"

# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Customize the deployment configuration
cp config.yaml.example config.yaml
# Edit config.yaml with your specific values

# Create the deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="config.yaml"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

Terraform provides a mature, multi-cloud infrastructure as code solution with extensive Google Cloud support.

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# Verify the deployment
terraform show
```

### Using Bash Scripts

The bash scripts provide a simple, automated deployment approach using gcloud CLI commands.

```bash
# Navigate to the scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy the infrastructure
./deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create VPC network and subnet
# 3. Set up NetApp storage pool and volume
# 4. Deploy Vertex AI Workbench instance
# 5. Configure Cloud Storage integration
# 6. Mount NetApp volume to workbench instance
```

## Configuration Options

### Infrastructure Manager Configuration

Key configuration parameters in `config.yaml`:

```yaml
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"
network_name: "netapp-ml-network"
netapp_storage_pool:
  capacity_gib: 1024
  service_level: "PREMIUM"
netapp_volume:
  capacity_gib: 500
  protocols: ["NFSV3"]
workbench_instance:
  machine_type: "n1-standard-4"
  accelerator_type: "NVIDIA_TESLA_T4"
  disk_size_gb: 100
```

### Terraform Variables

Key variables in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Network configuration
network_name = "netapp-ml-network"
subnet_cidr  = "10.0.0.0/24"

# NetApp configuration
storage_pool_capacity_gib = 1024
volume_capacity_gib      = 500
service_level           = "PREMIUM"

# Workbench configuration
machine_type        = "n1-standard-4"
accelerator_type    = "NVIDIA_TESLA_T4"
accelerator_count   = 1
boot_disk_size_gb   = 100

# Storage configuration
bucket_location = "US"
bucket_storage_class = "STANDARD"
```

### Script Environment Variables

Required environment variables for bash scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export NETWORK_NAME="netapp-ml-network"

# Optional customization
export STORAGE_POOL_CAPACITY="1024"
export VOLUME_CAPACITY="500"
export MACHINE_TYPE="n1-standard-4"
export ACCELERATOR_TYPE="NVIDIA_TESLA_T4"
```

## Post-Deployment Setup

### Access Vertex AI Workbench

1. Get the Jupyter URL:
   ```bash
   export WORKBENCH_NAME=$(gcloud notebooks instances list --format="value(name)" --filter="labels.purpose=ml-netapp")
   export JUPYTER_URL=$(gcloud notebooks instances describe ${WORKBENCH_NAME} --location=${ZONE} --format="value(proxyUri)")
   echo "Access Jupyter at: ${JUPYTER_URL}"
   ```

2. Navigate to `/mnt/ml-datasets/notebooks/` in the Jupyter interface to access the pre-configured environment.

### Mount Verification

Verify that the NetApp volume is properly mounted:

```bash
gcloud compute ssh ${WORKBENCH_NAME} --zone=${ZONE} --command="df -h /mnt/ml-datasets"
```

### Test Performance

Run the included performance test notebook:

```bash
gcloud compute ssh ${WORKBENCH_NAME} --zone=${ZONE} --command="
    cd /mnt/ml-datasets/notebooks
    jupyter nbconvert --execute netapp_performance_test.ipynb --to html
"
```

## Data Pipeline Integration

The solution includes integration with Cloud Storage for data lifecycle management:

### Sync Models to Cloud Storage

```bash
# From within the Workbench instance
cd /mnt/ml-datasets
python sync_to_storage.py
```

### Access Shared Datasets

The NetApp volume provides shared access to datasets:

- `/mnt/ml-datasets/raw-data/`: Original datasets (read-only)
- `/mnt/ml-datasets/processed-data/`: Cleaned and transformed datasets
- `/mnt/ml-datasets/models/`: Trained model artifacts
- `/mnt/ml-datasets/notebooks/`: Jupyter notebooks for experiments
- `/mnt/ml-datasets/config/`: Shared configuration files

## Monitoring and Optimization

### Performance Monitoring

Monitor NetApp Volumes performance using Cloud Monitoring:

```bash
# View storage metrics
gcloud logging read "resource.type=netapp_volume" --limit=50 --format=json

# Monitor workbench instance metrics
gcloud logging read "resource.type=notebooks_instance" --limit=50 --format=json
```

### Cost Optimization

1. **Service Level Adjustment**: Consider adjusting NetApp service level based on performance requirements
2. **Instance Scheduling**: Implement automated start/stop for Workbench instances during off-hours
3. **Storage Lifecycle**: Use Cloud Storage lifecycle policies for archived data
4. **GPU Usage**: Monitor GPU utilization and adjust instance types as needed

## Security Considerations

### Network Security

- VPC network provides isolation from other workloads
- Private IP configuration for enhanced security
- OS Login enabled for secure SSH access

### Access Control

- IAM roles for service accounts with minimal required permissions
- NetApp volume Unix permissions (0755) for controlled access
- Cloud Storage bucket with appropriate IAM policies

### Data Protection

- NetApp volume snapshots for data protection
- Cloud Storage versioning for model artifacts
- Encryption at rest and in transit

## Troubleshooting

### Common Issues

1. **NetApp Volume Mount Fails**:
   ```bash
   # Check volume status
   gcloud netapp volumes describe VOLUME_NAME --location=REGION
   
   # Verify network connectivity
   gcloud compute ssh WORKBENCH_NAME --zone=ZONE --command="ping -c 3 VOLUME_IP"
   ```

2. **Workbench Instance Not Ready**:
   ```bash
   # Check instance status
   gcloud notebooks instances describe WORKBENCH_NAME --location=ZONE --format="value(state)"
   
   # View instance logs
   gcloud logging read "resource.type=notebooks_instance AND resource.labels.instance_id=INSTANCE_ID" --limit=20
   ```

3. **GPU Not Available**:
   ```bash
   # Check GPU availability in zone
   gcloud compute accelerator-types list --filter="zone:ZONE AND name:nvidia-tesla-t4"
   
   # Verify GPU attachment
   gcloud compute ssh WORKBENCH_NAME --zone=ZONE --command="nvidia-smi"
   ```

### Performance Issues

1. **Slow Data Loading**:
   - Verify NetApp volume is mounted at `/mnt/ml-datasets`
   - Check network latency between workbench and NetApp volume
   - Consider upgrading to higher NetApp service level

2. **Jupyter Kernel Issues**:
   - Restart kernel from Jupyter interface
   - Check available memory and disk space
   - Verify Python package installations

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# The script will remove resources in proper order:
# 1. Workbench instances
# 2. NetApp volumes and storage pools
# 3. Cloud Storage buckets
# 4. VPC networks and subnets
```

### Manual Cleanup Verification

Verify all resources are removed:

```bash
# Check NetApp resources
gcloud netapp storage-pools list --location=${REGION}
gcloud netapp volumes list --location=${REGION}

# Check Workbench instances
gcloud notebooks instances list

# Check networks
gcloud compute networks list --filter="name:netapp-ml-network"

# Check storage buckets
gsutil ls -p ${PROJECT_ID} | grep ml-datalake
```

## Advanced Configurations

### Multi-Region Setup

For distributed teams, consider deploying across multiple regions:

1. Create regional NetApp storage pools
2. Set up cross-region replication
3. Deploy Workbench instances in multiple zones
4. Configure regional Cloud Storage buckets

### Team Collaboration

Enhance collaboration by:

1. Creating shared service accounts for team access
2. Implementing Git integration for notebook version control
3. Setting up automated data synchronization workflows
4. Configuring team-wide monitoring and alerting

### Enterprise Integration

For enterprise deployments:

1. Integrate with existing Identity and Access Management (IAM) systems
2. Configure VPC peering with on-premises networks
3. Implement advanced data governance with Cloud Data Catalog
4. Set up compliance monitoring and audit logging

## Support and Documentation

- [Original Recipe Documentation](../high-performance-data-science-workflows-netapp-volumes-vertex-ai-workbench.md)
- [Google Cloud NetApp Volumes Documentation](https://cloud.google.com/netapp-volumes/docs)
- [Vertex AI Workbench Documentation](https://cloud.google.com/vertex-ai/docs/workbench)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud documentation for specific services.