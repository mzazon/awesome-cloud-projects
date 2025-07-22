# AWS ParallelCluster HPC Infrastructure - Terraform Implementation

This Terraform configuration deploys the complete infrastructure needed for the "Scalable HPC Cluster with Auto-Scaling" recipe.

## Architecture Overview

This implementation creates:
- **VPC with public and private subnets** for network isolation
- **NAT Gateway** for secure internet access from compute nodes
- **Security Groups** with optimized rules for HPC workloads
- **S3 Bucket** for data storage with FSx Lustre integration
- **IAM roles and policies** for ParallelCluster operations
- **CloudWatch monitoring** with dashboards and alarms
- **SSH key pair** for secure cluster access
- **ParallelCluster configuration** ready for deployment

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - VPC, EC2, S3, IAM resource creation
  - ParallelCluster service access
  - CloudWatch monitoring setup
- Python 3.8+ for ParallelCluster CLI (post-deployment)

## Quick Start

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Review Configuration

```bash
terraform plan
```

### 3. Deploy Infrastructure

```bash
terraform apply
```

### 4. Install ParallelCluster CLI

```bash
pip3 install aws-parallelcluster
```

### 5. Download SSH Key

```bash
# Get the S3 bucket name from Terraform output
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
KEYPAIR_NAME=$(terraform output -raw keypair_name)

# Download the private key
aws s3 cp s3://${BUCKET_NAME}/keys/${KEYPAIR_NAME}.pem ~/.ssh/
chmod 600 ~/.ssh/${KEYPAIR_NAME}.pem
```

### 6. Create ParallelCluster

```bash
# Get the cluster creation command from Terraform output
terraform output -raw cluster_creation_command

# Or execute directly
CLUSTER_NAME=$(terraform output -raw cluster_name)
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

pcluster create-cluster \
  --cluster-name ${CLUSTER_NAME} \
  --cluster-configuration s3://${BUCKET_NAME}/config/cluster-config.yaml
```

### 7. Monitor Cluster Creation

```bash
pcluster describe-cluster --cluster-name ${CLUSTER_NAME}
```

## Configuration Variables

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | `us-east-1` |
| `environment` | Environment name for tagging | `dev` |

### Cluster Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `cluster_name` | ParallelCluster name | Auto-generated |
| `head_node_instance_type` | Head node EC2 instance type | `m5.large` |
| `compute_instance_type` | Compute node EC2 instance type | `c5n.large` |
| `min_compute_nodes` | Minimum compute nodes | `0` |
| `max_compute_nodes` | Maximum compute nodes | `10` |
| `enable_efa` | Enable Elastic Fabric Adapter | `true` |
| `disable_hyperthreading` | Disable simultaneous multithreading | `true` |

### Network Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `public_subnet_cidr` | Public subnet CIDR | `10.0.1.0/24` |
| `private_subnet_cidr` | Private subnet CIDR | `10.0.2.0/24` |
| `availability_zone` | AZ for subnet placement | `us-east-1a` |

### Storage Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `shared_storage_size` | Shared EBS storage size (GB) | `100` |
| `fsx_storage_capacity` | FSx Lustre capacity (GB) | `1200` |
| `fsx_deployment_type` | FSx deployment type | `SCRATCH_2` |
| `root_volume_size` | Root volume size (GB) | `50` |
| `root_volume_type` | Root volume type | `gp3` |

### Security Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `allowed_ssh_cidr` | CIDR blocks for SSH access | `["0.0.0.0/0"]` |
| `enable_ebs_encryption` | Enable EBS encryption | `true` |
| `kms_key_id` | KMS key for encryption | `""` |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_cloudwatch_monitoring` | Enable CloudWatch monitoring | `true` |
| `enable_cloudwatch_logs` | Enable CloudWatch logs | `true` |
| `enable_detailed_monitoring` | Enable detailed EC2 monitoring | `false` |

## Example Terraform Variable Files

### Development Environment (`dev.tfvars`)

```hcl
environment = "dev"
aws_region  = "us-east-1"
availability_zone = "us-east-1a"

# Small cluster for development
head_node_instance_type = "m5.large"
compute_instance_type   = "c5n.large"
max_compute_nodes       = 5

# Basic storage
shared_storage_size   = 100
fsx_storage_capacity  = 1200

# Open SSH access (restrict in production)
allowed_ssh_cidr = ["0.0.0.0/0"]

additional_tags = {
  Team        = "Research"
  CostCenter  = "R&D"
}
```

### Production Environment (`prod.tfvars`)

```hcl
environment = "prod"
aws_region  = "us-west-2"
availability_zone = "us-west-2a"

# Larger cluster for production workloads
head_node_instance_type = "m5.xlarge"
compute_instance_type   = "c5n.4xlarge"
max_compute_nodes       = 50

# High-performance storage
shared_storage_size   = 500
fsx_storage_capacity  = 7200
fsx_deployment_type   = "PERSISTENT_1"

# Restricted SSH access
allowed_ssh_cidr = ["10.0.0.0/8"]

# Enhanced monitoring
enable_detailed_monitoring = true

additional_tags = {
  Environment = "production"
  Team        = "HPC"
  CostCenter  = "Research"
  Backup      = "required"
}
```

## Usage Examples

### Deploy with Custom Variables

```bash
terraform apply -var-file="prod.tfvars"
```

### Deploy with Inline Variables

```bash
terraform apply \
  -var="environment=test" \
  -var="max_compute_nodes=20" \
  -var="compute_instance_type=c5n.2xlarge"
```

### Target Specific Resources

```bash
# Deploy only networking
terraform apply -target=aws_vpc.hpc_vpc -target=aws_subnet.public_subnet

# Deploy only storage
terraform apply -target=aws_s3_bucket.hpc_data_bucket
```

## Outputs

After deployment, Terraform provides these useful outputs:

```bash
# Get cluster connection information
terraform output ssh_connection_command
terraform output cluster_creation_command

# Get resource identifiers
terraform output vpc_id
terraform output s3_bucket_name
terraform output keypair_name

# Get configuration summary
terraform output cluster_configuration_summary
```

## Post-Deployment Tasks

### 1. Verify Infrastructure

```bash
# Check VPC and subnets
aws ec2 describe-vpcs --vpc-ids $(terraform output -raw vpc_id)

# Verify S3 bucket
aws s3 ls s3://$(terraform output -raw s3_bucket_name)

# Check security groups
aws ec2 describe-security-groups --group-ids $(terraform output -raw head_node_security_group_id)
```

### 2. Create ParallelCluster

```bash
# Create cluster using the generated configuration
terraform output -raw cluster_creation_command | bash
```

### 3. Connect to Head Node

```bash
# After cluster creation completes
HEAD_NODE_IP=$(pcluster describe-cluster --cluster-name $(terraform output -raw cluster_name) --query 'headNode.publicIpAddress' --output text)
KEYPAIR_NAME=$(terraform output -raw keypair_name)

ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP}
```

### 4. Submit Test Jobs

```bash
# On the head node
sinfo  # Check available compute resources
sbatch /shared/jobs/sample_job.sh  # Submit sample job
squeue  # Check job queue
```

## Monitoring and Troubleshooting

### CloudWatch Dashboard

Access the HPC cluster dashboard:
```bash
CLUSTER_NAME=$(terraform output -raw cluster_name)
echo "https://console.aws.amazon.com/cloudwatch/home?region=$(terraform output -raw cluster_region)#dashboards:name=${CLUSTER_NAME}-performance"
```

### CloudWatch Logs

View cluster logs:
```bash
LOG_GROUP=$(terraform output -raw cloudwatch_log_group_name)
aws logs describe-log-streams --log-group-name ${LOG_GROUP}
```

### Common Issues

1. **Cluster creation fails**: Check IAM permissions and subnet configurations
2. **No compute nodes launching**: Verify instance limits and subnet capacity
3. **SSH access denied**: Ensure security group rules and key permissions
4. **Storage mount issues**: Check FSx Lustre configuration and S3 permissions

## Cost Optimization

### Auto-Scaling Configuration

The cluster automatically scales based on job demand:
- **Minimum nodes**: 0 (cost-effective when idle)
- **Maximum nodes**: Configurable (default 10)
- **Scale-down time**: 5 minutes of idle time

### Instance Types

Choose appropriate instance types for your workload:
- **Compute-optimized**: c5n.large, c5n.xlarge for CPU-intensive tasks
- **Memory-optimized**: r5n.large, r5n.xlarge for memory-intensive workloads
- **GPU-accelerated**: p3.2xlarge, p4d.24xlarge for ML/AI workloads

### Storage Optimization

- **FSx Lustre SCRATCH_2**: Lower cost, higher performance
- **FSx Lustre PERSISTENT_1**: Higher cost, data persistence
- **EBS gp3**: Cost-effective for shared storage

## Security Best Practices

### Network Security

- Use private subnets for compute nodes
- Restrict SSH access to specific IP ranges
- Enable VPC Flow Logs for network monitoring

### Data Security

- Enable S3 encryption at rest
- Use KMS keys for additional encryption control
- Implement S3 bucket policies for access control

### Access Control

- Use IAM roles instead of access keys
- Implement least privilege principle
- Regular security audits and updates

## Backup and Disaster Recovery

### Data Backup

```bash
# Schedule S3 cross-region replication
aws s3api put-bucket-replication \
  --bucket $(terraform output -raw s3_bucket_name) \
  --replication-configuration file://replication.json
```

### Configuration Backup

```bash
# Backup Terraform state
terraform state pull > terraform.tfstate.backup

# Export cluster configuration
aws s3 cp s3://$(terraform output -raw s3_bucket_name)/config/cluster-config.yaml ./cluster-config.backup.yaml
```

## Cleanup

### Delete ParallelCluster

```bash
# Delete cluster first
pcluster delete-cluster --cluster-name $(terraform output -raw cluster_name)

# Wait for deletion to complete
pcluster describe-cluster --cluster-name $(terraform output -raw cluster_name)
```

### Destroy Infrastructure

```bash
# Remove all Terraform-managed resources
terraform destroy
```

### Manual Cleanup (if needed)

```bash
# Clean up any remaining resources
aws ec2 describe-instances --filters "Name=tag:Project,Values=HPC-ParallelCluster"
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive
```

## Advanced Configuration

### Custom AMI

```hcl
custom_ami_id = "ami-12345678"  # Your custom HPC AMI
```

### Multi-AZ Deployment

```hcl
# Create additional subnets in different AZs
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
```

### GPU Instances

```hcl
compute_instance_type = "p3.2xlarge"
enable_efa           = true
```

## Support

For issues with this Terraform implementation:

1. Check the [AWS ParallelCluster documentation](https://docs.aws.amazon.com/parallelcluster/)
2. Review [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
3. Consult the original recipe documentation
4. Check AWS CloudWatch logs for detailed error messages

## Contributing

To improve this Terraform configuration:

1. Follow Terraform best practices
2. Test changes in a development environment
3. Update documentation for any new variables or outputs
4. Ensure backward compatibility where possible

## License

This code is provided as-is for educational and demonstration purposes. Please review and modify security settings before production use.