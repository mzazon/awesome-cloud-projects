# Infrastructure as Code for Architecting Enterprise-Grade Database Performance with NetApp Volumes and AlloyDB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Architecting Enterprise-Grade Database Performance with NetApp Volumes and AlloyDB".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - AlloyDB cluster and instance creation
  - NetApp Volumes storage pool and volume creation
  - VPC and networking configuration
  - Cloud Monitoring and alerting setup
  - Cloud Build and deployment pipeline creation
- Sufficient project quotas for:
  - AlloyDB instances (16+ vCPUs for primary instance)
  - NetApp Volumes storage (20 TiB storage pool capacity)
  - VPC networking resources
- Estimated cost: $1,200-2,500/month depending on configuration

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply infrastructure-deployment \
    --location=${REGION} \
    --service-account="your-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/infrastructure" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe infrastructure-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

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

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud alloydb clusters list --region=${REGION}
gcloud netapp storage-pools list --location=${REGION}
```

## Configuration Options

### Infrastructure Manager Variables

Configure the deployment by modifying the input values:

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `vpc_name`: VPC network name (default: enterprise-db-vpc)
- `alloydb_cluster_name`: AlloyDB cluster identifier
- `netapp_pool_name`: NetApp storage pool name
- `database_password`: AlloyDB cluster password (use Secret Manager in production)
- `enable_monitoring`: Enable Cloud Monitoring dashboard (default: true)
- `enable_backup`: Enable automated backups (default: true)

### Terraform Variables

Customize the deployment using terraform.tfvars:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Network configuration
vpc_name    = "enterprise-db-vpc"
subnet_name = "enterprise-db-subnet"
subnet_cidr = "10.0.0.0/24"

# AlloyDB configuration
alloydb_cluster_id = "enterprise-alloydb"
database_version   = "POSTGRES_15"
primary_cpu_count  = 16
primary_memory_gb  = 64
replica_cpu_count  = 8
replica_memory_gb  = 32
replica_node_count = 3

# NetApp Volumes configuration
storage_pool_name     = "enterprise-storage-pool"
storage_pool_capacity = "20TiB"
storage_pool_service_level = "FLEX"
volume_name          = "enterprise-db-volume"
volume_capacity      = "10TiB"
volume_protocols     = ["NFSV4"]

# Monitoring configuration
enable_monitoring = true
enable_alerting   = true

# Security configuration
enable_encryption = true
backup_retention_days = 30
```

### Bash Script Configuration

The bash scripts use environment variables for configuration:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export VPC_NAME="enterprise-db-vpc"
export SUBNET_NAME="enterprise-db-subnet"
export ALLOYDB_CLUSTER_ID="enterprise-alloydb"
export NETAPP_STORAGE_POOL="enterprise-storage-pool"
export NETAPP_VOLUME="enterprise-db-volume"
```

## Deployment Architecture

The infrastructure creates the following components:

### Networking
- VPC network with custom subnet
- Private service connection for AlloyDB
- Internal load balancer for database access
- Firewall rules for secure communication

### Database Layer
- AlloyDB cluster with PostgreSQL 15
- Primary instance (16 vCPU, 64 GB RAM)
- Read replica pool (3 nodes, 8 vCPU, 32 GB RAM each)
- Automated backup and point-in-time recovery
- Customer-managed encryption keys

### Storage Layer
- NetApp Volumes storage pool (20 TiB, Flex service level)
- High-performance NFS volume (10 TiB)
- Advanced data protection and snapshot capabilities

### Monitoring & Automation
- Cloud Monitoring dashboard for performance metrics
- Alert policies for proactive monitoring
- Cloud Build pipeline for automated deployment
- Comprehensive logging and audit trails

## Post-Deployment Steps

1. **Configure Database Access**:
   ```bash
   # Get database connection information
   gcloud alloydb clusters describe ${ALLOYDB_CLUSTER_ID} \
       --region=${REGION} \
       --format="value(primaryCluster.ipAddress)"
   ```

2. **Set Up Application Connections**:
   ```bash
   # Connect through the load balancer endpoint
   psql "host=10.0.0.100 port=5432 dbname=postgres user=postgres"
   ```

3. **Configure NetApp Volume Mounting**:
   ```bash
   # Get volume mount path
   gcloud netapp volumes describe ${NETAPP_VOLUME} \
       --location=${REGION} \
       --format="value(mountOptions.mountPath)"
   ```

4. **Verify Monitoring Setup**:
   ```bash
   # Access monitoring dashboard
   echo "Visit Cloud Monitoring dashboard: https://console.cloud.google.com/monitoring"
   ```

## Security Considerations

- All database instances use private IP addresses only
- Customer-managed encryption keys protect data at rest
- VPC Service Controls can be enabled for additional security
- Audit logging captures all database access and modifications
- IAM roles follow least privilege principle

## Performance Optimization

- NetApp Volumes provides up to 4.5 GiB/s throughput
- AlloyDB columnar storage optimizes analytical queries
- Read replicas distribute analytical workloads
- Connection pooling and load balancing optimize resource utilization
- Performance monitoring enables proactive optimization

## Backup and Disaster Recovery

- Automated daily backups with 30-day retention
- Point-in-time recovery capability
- NetApp snapshot technology for storage-level protection
- Cross-region replication available for disaster recovery

## Troubleshooting

### Common Issues

1. **Quota Exceeded**:
   ```bash
   # Check AlloyDB quotas
   gcloud compute project-info describe --format="value(quotas)"
   ```

2. **Network Connectivity**:
   ```bash
   # Verify VPC peering
   gcloud services vpc-peerings list --network=${VPC_NAME}
   ```

3. **Storage Pool Creation Timeout**:
   ```bash
   # Check storage pool status
   gcloud netapp storage-pools describe ${NETAPP_STORAGE_POOL} \
       --location=${REGION}
   ```

### Logs and Monitoring

```bash
# View deployment logs
gcloud logging read "resource.type=cloud_build" --limit=50

# Check AlloyDB logs
gcloud logging read "resource.type=alloydb_database" --limit=50

# Monitor NetApp Volumes metrics
gcloud monitoring metrics list --filter="metric.type:netapp"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete infrastructure-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify AlloyDB resources are deleted
gcloud alloydb clusters list --region=${REGION}

# Verify NetApp resources are deleted
gcloud netapp storage-pools list --location=${REGION}
gcloud netapp volumes list --location=${REGION}

# Verify networking resources are deleted
gcloud compute networks list --filter="name=${VPC_NAME}"
```

## Cost Management

### Cost Optimization Tips

1. **Right-size instances** based on actual workload requirements
2. **Use scheduled scaling** for development environments
3. **Monitor storage utilization** and adjust NetApp volume sizes
4. **Implement data lifecycle policies** for automated archiving
5. **Review performance metrics** to optimize resource allocation

### Cost Monitoring

```bash
# View current month's costs
gcloud billing budgets list

# Set up budget alerts
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="AlloyDB Budget" \
    --budget-amount=2000USD
```

## Support and Documentation

- [Google Cloud AlloyDB Documentation](https://cloud.google.com/alloydb/docs)
- [Google Cloud NetApp Volumes Documentation](https://cloud.google.com/netapp/volumes/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support channels.

## Contributing

When modifying the infrastructure code:

1. Test changes in a development environment first
2. Update variable descriptions and documentation
3. Validate syntax using appropriate tools (terraform validate, etc.)
4. Update this README if new configuration options are added
5. Follow Google Cloud best practices and security guidelines