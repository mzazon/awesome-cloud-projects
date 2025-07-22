# Infrastructure as Code for EFS Mounting Strategies and Optimization

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EFS Mounting Strategies and Optimization".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate IAM permissions for creating EFS, EC2, VPC, and IAM resources
- Basic understanding of NFS, file systems, and Linux mounting concepts
- Existing VPC with at least two subnets in different availability zones
- Estimated cost: $0.30/GB per month for standard storage + $0.10/GB per month for mount target usage

## Quick Start

### Using CloudFormation

```bash
# Deploy the EFS infrastructure
aws cloudformation create-stack \
    --stack-name efs-mounting-strategies \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxx \
        ParameterKey=SubnetIds,ParameterValue=subnet-xxxxxxxx,subnet-yyyyyyyy \
        ParameterKey=InstanceType,ParameterValue=t3.micro

# Check stack status
aws cloudformation describe-stacks \
    --stack-name efs-mounting-strategies \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# Check deployment status
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# Check deployment status
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# Check resource status
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws efs describe-file-systems --query 'FileSystems[?Name==`efs-demo-*`]'
```

## Architecture Overview

This implementation creates:

- **EFS File System**: Fully managed NFS file system with encryption at rest
- **Mount Targets**: Network endpoints in multiple availability zones
- **Security Groups**: Network access control for NFS traffic (port 2049)
- **Access Points**: Secure entry points with enforced POSIX permissions
- **IAM Roles**: Secure access credentials for EC2 instances
- **EC2 Instance**: Test instance with EFS utilities pre-installed

## Configuration Options

### CloudFormation Parameters

- `VpcId`: VPC where resources will be created
- `SubnetIds`: Comma-separated list of subnet IDs in different AZs
- `InstanceType`: EC2 instance type (default: t3.micro)
- `EFSPerformanceMode`: EFS performance mode (generalPurpose or maxIO)
- `EFSThroughputMode`: EFS throughput mode (bursting or provisioned)
- `ProvisionedThroughputInMibps`: Provisioned throughput (if using provisioned mode)

### CDK Configuration

Modify the configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript example
const config = {
  efsPerformanceMode: 'generalPurpose',
  efsThroughputMode: 'provisioned',
  provisionedThroughputInMibps: 100,
  instanceType: 't3.micro'
};
```

### Terraform Variables

Configure in `terraform.tfvars`:

```hcl
# Terraform variables
vpc_id = "vpc-xxxxxxxx"
subnet_ids = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]
instance_type = "t3.micro"
efs_performance_mode = "generalPurpose"
efs_throughput_mode = "provisioned"
provisioned_throughput_in_mibps = 100
```

## Post-Deployment Steps

### Accessing the EC2 Instance

1. Get the instance IP address:
```bash
# Using AWS CLI
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=efs-instance-*" \
    --query 'Reservations[0].Instances[0].PublicIpAddress'
```

2. SSH into the instance:
```bash
# Connect to the instance
ssh -i your-key.pem ec2-user@INSTANCE_IP
```

### Testing EFS Mounting Strategies

Once connected to the EC2 instance:

1. **Standard NFS Mount**:
```bash
# Mount using standard NFS
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 \
    EFS_ID.efs.REGION.amazonaws.com:/ /mnt/efs

# Verify mount
df -h /mnt/efs
```

2. **EFS Utils Mount with Encryption**:
```bash
# Mount with TLS encryption
sudo mount -t efs -o tls EFS_ID:/ /mnt/efs

# Mount using access points
sudo mount -t efs -o tls,accesspoint=ACCESS_POINT_ID EFS_ID:/ /mnt/efs-app
```

3. **Persistent Mounting**:
```bash
# Add to fstab for automatic mounting
echo "EFS_ID.efs.REGION.amazonaws.com:/ /mnt/efs efs defaults,_netdev,tls" | sudo tee -a /etc/fstab
sudo mount -a
```

## Performance Testing

Test EFS performance on the deployed instance:

```bash
# Test write performance
time dd if=/dev/zero of=/mnt/efs/test-file bs=1M count=100

# Test read performance
time dd if=/mnt/efs/test-file of=/dev/null bs=1M

# View NFS statistics
sudo nfsstat -m
```

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor EFS performance using these key metrics:
- `TotalIOBytes`: Total bytes transferred
- `ClientConnections`: Number of client connections
- `DataReadIOBytes`: Bytes read from the file system
- `DataWriteIOBytes`: Bytes written to the file system
- `TotalIOTime`: Total time for I/O operations

### Common Issues

1. **Mount Timeout**: Ensure security groups allow NFS traffic (port 2049)
2. **Permission Denied**: Verify IAM roles have appropriate EFS permissions
3. **Performance Issues**: Check throughput mode and provisioned throughput settings
4. **Network Connectivity**: Verify mount targets are in the correct subnets

## Security Considerations

- EFS file system is encrypted at rest using AWS managed keys
- Security groups restrict NFS access to VPC CIDR blocks
- IAM roles use least privilege principle
- TLS encryption in transit when using EFS utils
- Access points provide directory-level isolation

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name efs-mounting-strategies

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name efs-mounting-strategies \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm resources are deleted
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
aws efs describe-file-systems --query 'FileSystems[?Name==`efs-demo-*`]'
```

## Cost Optimization

- Use EFS Intelligent Tiering to automatically move infrequently accessed files to lower-cost storage classes
- Monitor throughput utilization to optimize between bursting and provisioned modes
- Consider EFS One Zone storage class for workloads that don't require multi-AZ resilience
- Implement lifecycle policies to transition files to Archive storage classes

## Customization

### Adding More Access Points

Modify the IaC templates to add additional access points for different use cases:

```yaml
# CloudFormation example
LogsAccessPoint:
  Type: AWS::EFS::AccessPoint
  Properties:
    FileSystemId: !Ref EFSFileSystem
    PosixUser:
      Uid: 3000
      Gid: 3000
    RootDirectory:
      Path: /logs
      CreationInfo:
        OwnerUid: 3000
        OwnerGid: 3000
        Permissions: '0755'
```

### Scaling to Multiple Regions

For disaster recovery, consider:
- Setting up EFS replication to another region
- Using AWS Backup for cross-region EFS backups
- Implementing multi-region access patterns

## Support

For issues with this infrastructure code:
1. Check the AWS EFS documentation: https://docs.aws.amazon.com/efs/
2. Review the original recipe documentation
3. Consult AWS Support for service-specific issues
4. Use AWS CloudFormation/CDK/Terraform community forums for IaC-specific questions

## Additional Resources

- [Amazon EFS User Guide](https://docs.aws.amazon.com/efs/latest/ug/)
- [EFS Performance Documentation](https://docs.aws.amazon.com/efs/latest/ug/performance.html)
- [EFS Security Best Practices](https://docs.aws.amazon.com/efs/latest/ug/security-considerations.html)
- [EFS Troubleshooting Guide](https://docs.aws.amazon.com/efs/latest/ug/troubleshooting.html)