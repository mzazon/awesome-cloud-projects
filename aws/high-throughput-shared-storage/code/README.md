# Infrastructure as Code for High-Throughput Shared Storage System

This directory contains Infrastructure as Code (IaC) implementations for the recipe "High-Throughput Shared Storage System".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon FSx (all file system types)
  - Amazon EC2 (instances, security groups, VPC)
  - Amazon S3 (bucket creation and management)
  - Amazon CloudWatch (alarms and monitoring)
  - AWS IAM (roles and policies)
- Basic knowledge of Linux file systems and HPC workloads
- Existing VPC with subnets (or permissions to create)
- Valid EC2 key pair for test instances
- Estimated cost: $0.50-$2.00 per hour for FSx + $0.10-$0.50 per hour for EC2 instances

> **Note**: FSx for Lustre is available in specific regions. Check service availability in your region before proceeding.

## Architecture Overview

This infrastructure creates:

- **FSx for Lustre**: High-performance file system for HPC workloads (1.2 TB, SCRATCH_2 deployment)
- **FSx for Windows File Server**: SMB-based shared storage (32 GB, Single-AZ)
- **FSx for NetApp ONTAP**: Multi-protocol file system (1 TB, Multi-AZ)
- **Storage Virtual Machine (SVM)**: Isolated namespace for ONTAP
- **ONTAP Volumes**: Separate NFS and SMB volumes with storage efficiency
- **Security Groups**: Properly configured for FSx protocols
- **S3 Bucket**: Data repository for Lustre integration
- **CloudWatch Alarms**: Performance monitoring across all file systems
- **EC2 Test Instance**: Linux client for testing file system access
- **IAM Role**: Service permissions for S3 integration

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name fsx-demo-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=KeyPairName,ParameterValue=your-key-pair \
    --capabilities CAPABILITY_IAM \
    --tags Key=Project,Value=FSx-Demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name fsx-demo-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name fsx-demo-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure AWS CDK (first time only)
npx cdk bootstrap

# Review what will be deployed
npx cdk diff

# Deploy the infrastructure
npx cdk deploy --parameters keyPairName=your-key-pair

# List all resources created
npx cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure AWS CDK (first time only)
cdk bootstrap

# Review what will be deployed
cdk diff

# Deploy the infrastructure
cdk deploy --parameters keyPairName=your-key-pair

# List all resources created
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan \
    -var="key_pair_name=your-key-pair" \
    -var="aws_region=us-west-2"

# Apply the configuration
terraform apply \
    -var="key_pair_name=your-key-pair" \
    -var="aws_region=us-west-2"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export KEY_PAIR_NAME=your-key-pair
export AWS_REGION=us-west-2

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Post-Deployment Validation

### 1. Verify File System Status

```bash
# List all FSx file systems
aws fsx describe-file-systems \
    --query 'FileSystems[*].{ID:FileSystemId,Type:FileSystemType,State:Lifecycle,DNSName:DNSName}'

# Check specific file system details
aws fsx describe-file-systems \
    --file-system-ids <your-lustre-fs-id> \
    --query 'FileSystems[0].{State:Lifecycle,Performance:LustreConfiguration.PerUnitStorageThroughput}'
```

### 2. Test File System Mounting

```bash
# Connect to the Linux test instance
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=*fsx-demo*linux*" \
    --query 'Reservations[0].Instances[0].PublicIpAddress'

# SSH to instance and mount Lustre (run on EC2 instance)
sudo mount -t lustre <lustre-dns>@tcp:/<mount-name> /mnt/fsx

# Test performance (run on EC2 instance)
dd if=/dev/zero of=/mnt/fsx/testfile bs=1M count=1000
dd if=/mnt/fsx/testfile of=/dev/null bs=1M
```

### 3. Verify Monitoring

```bash
# Check CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names "*fsx-demo*" \
    --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue,Reason:StateReason}'

# View recent metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/FSx \
    --metric-name ThroughputUtilization \
    --dimensions Name=FileSystemId,Value=<your-fs-id> \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T01:00:00Z \
    --period 300 \
    --statistics Average
```

## Customization

### Key Parameters

#### CloudFormation Parameters
- `KeyPairName`: EC2 key pair for SSH access
- `VpcId`: Target VPC (uses default if not specified)
- `LustreStorageCapacity`: Lustre file system size in GB (default: 1200)
- `WindowsStorageCapacity`: Windows file system size in GB (default: 32)
- `OntapStorageCapacity`: ONTAP file system size in GB (default: 1024)

#### Terraform Variables
- `key_pair_name`: EC2 key pair name
- `aws_region`: Deployment region
- `lustre_storage_capacity`: Lustre storage size
- `windows_throughput_capacity`: Windows throughput (8-2048 MB/s)
- `ontap_throughput_capacity`: ONTAP throughput (128-2048 MB/s)
- `enable_backup`: Enable automated backups (default: true)

#### CDK Context Values
- `keyPairName`: EC2 key pair for instances
- `enableMonitoring`: Enable CloudWatch alarms (default: true)
- `enableBackups`: Enable automated backup policies (default: true)
- `lustreDeploymentType`: SCRATCH_1, SCRATCH_2, or PERSISTENT_1

### Performance Tuning

#### Lustre Configuration
```bash
# Modify deployment type for persistent storage
LustreDeploymentType: PERSISTENT_1
PerUnitStorageThroughput: 500  # Up to 1000 MB/s/TiB

# Enable data compression
DataCompressionType: LZ4

# Configure auto-import from S3
AutoImportPolicy: NEW_CHANGED_DELETED
```

#### Windows File Server Optimization
```bash
# Increase throughput capacity
ThroughputCapacity: 32  # 8-2048 MB/s range

# Enable Multi-AZ for high availability
DeploymentType: MULTI_AZ_1
```

#### ONTAP Advanced Features
```bash
# Enable storage efficiency
StorageEfficiencyEnabled: true

# Configure automatic snapshots
SnapshotPolicy: default

# Set up SnapMirror replication
ReplicationConfiguration:
  ReplicationTarget: arn:aws:fsx:us-east-1:account:volume/fsvol-123
```

## Monitoring and Alerting

### CloudWatch Metrics

The infrastructure creates monitoring for:
- **Lustre**: ThroughputUtilization, DataReadBytes, DataWriteBytes
- **Windows**: CPUUtilization, NetworkThroughput, StorageUtilization  
- **ONTAP**: StorageUtilization, TotalThroughput, ClientConnections

### Custom Alarms

Add additional monitoring:

```bash
# High latency alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "FSx-HighLatency" \
    --metric-name AverageIOTime \
    --threshold 10 \
    --comparison-operator GreaterThanThreshold

# Storage capacity alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "FSx-LowSpace" \
    --metric-name StorageUtilization \
    --threshold 85 \
    --comparison-operator GreaterThanThreshold
```

## Security Considerations

### Network Security
- Security groups restrict access to FSx protocols only
- VPC endpoints available for private connectivity
- Encryption in transit supported for all file system types

### Data Protection
- Encryption at rest enabled by default
- AWS KMS key management integration
- Automated backup policies with configurable retention
- Cross-region backup capability for business continuity

### Access Control
- IAM roles for service-to-service communication
- POSIX permissions for NFS volumes
- NTFS ACLs for SMB volumes
- Integration with AWS Directory Service

## Troubleshooting

### Common Issues

#### File System Creation Fails
```bash
# Check service limits
aws service-quotas get-service-quota \
    --service-code fsx \
    --quota-code L-8FBA7C9D  # FSx for Lustre file systems

# Verify subnet availability zones
aws fsx describe-file-systems \
    --file-system-ids <fs-id> \
    --query 'FileSystems[0].FailureDetails'
```

#### Mount Issues
```bash
# Check security group rules
aws ec2 describe-security-groups \
    --group-ids <sg-id> \
    --query 'SecurityGroups[0].IpPermissions'

# Verify Lustre client installation
sudo yum list installed | grep lustre
```

#### Performance Problems
```bash
# Check file system throughput utilization
aws cloudwatch get-metric-statistics \
    --namespace AWS/FSx \
    --metric-name ThroughputUtilization \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Maximum
```

### Support Resources
- [AWS FSx Documentation](https://docs.aws.amazon.com/fsx/)
- [FSx Performance Guide](https://docs.aws.amazon.com/fsx/latest/LustreGuide/performance.html)
- [FSx Troubleshooting](https://docs.aws.amazon.com/fsx/latest/WindowsGuide/troubleshooting.html)

## Cleanup

> **Warning**: Cleanup will permanently delete all file systems and data. Ensure you have backups if needed.

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name fsx-demo-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name fsx-demo-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy all resources
cdk destroy

# Confirm when prompted
# This will delete all file systems and associated data
```

### Using Terraform

```bash
cd terraform/

# Plan the destruction
terraform plan -destroy

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Script will prompt for confirmation before deleting resources
# Follow prompts to complete cleanup
```

### Manual Cleanup Verification

```bash
# Verify all FSx file systems are deleted
aws fsx describe-file-systems \
    --query 'length(FileSystems[?contains(Tags[?Key==`Name`].Value, `fsx-demo`)])'

# Check for remaining S3 buckets
aws s3 ls | grep fsx-demo

# Verify security groups are removed
aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=*fsx-demo*"
```

## Cost Optimization

### Billing Considerations

- **FSx for Lustre**: Charged per GB-month of provisioned storage
- **FSx for Windows**: Charged for storage and throughput capacity
- **FSx for ONTAP**: Charged for provisioned SSD storage and throughput
- **Data Transfer**: Charges apply for data transfer between AZs
- **Backups**: Additional charges for backup storage beyond free tier

### Cost Reduction Strategies

1. **Right-size Storage**: Monitor utilization and adjust capacity
2. **Scheduled Scaling**: Scale down throughput during off-hours
3. **Backup Optimization**: Tune retention periods and frequency
4. **Regional Selection**: Consider data transfer costs between regions

```bash
# Monitor storage utilization
aws cloudwatch get-metric-statistics \
    --namespace AWS/FSx \
    --metric-name StorageUtilization \
    --dimensions Name=FileSystemId,Value=<fs-id> \
    --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 86400 \
    --statistics Average
```

## Advanced Configuration

### Multi-Region Deployment

For disaster recovery scenarios, deploy FSx across multiple regions:

```bash
# Primary region deployment
terraform apply -var="aws_region=us-west-2"

# Secondary region for DR
terraform apply -var="aws_region=us-east-1" \
    -var="enable_cross_region_backup=true"
```

### Integration with Other Services

- **Amazon EMR**: Mount FSx for Lustre on EMR clusters
- **AWS Batch**: Use FSx for high-performance computing jobs  
- **Amazon EKS**: Deploy FSx CSI driver for container workloads
- **AWS DataSync**: Synchronize data with on-premises storage

## Support

For issues with this infrastructure code:

1. Check the [troubleshooting section](#troubleshooting) above
2. Refer to the [original recipe documentation](../high-performance-file-systems-amazon-fsx.md)
3. Consult [AWS FSx documentation](https://docs.aws.amazon.com/fsx/)
4. Contact AWS Support for service-specific issues

## Contributing

To improve this infrastructure code:

1. Test changes in a non-production environment
2. Follow AWS best practices for security and performance
3. Update documentation for any parameter changes
4. Validate against the original recipe requirements