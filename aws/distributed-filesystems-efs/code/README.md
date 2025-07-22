# Infrastructure as Code for Building Distributed File Systems with Amazon EFS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Distributed File Systems with Amazon EFS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys a complete distributed file system solution using Amazon EFS with the following components:

- **EFS File System**: Scalable, distributed file system with encryption
- **Mount Targets**: High-availability access points across multiple AZs
- **Access Points**: Fine-grained access control for different applications
- **EC2 Instances**: Compute resources distributed across availability zones
- **Security Groups**: Network security controls for EFS and EC2 access
- **CloudWatch Monitoring**: Performance metrics and dashboards
- **AWS Backup**: Automated backup configuration with lifecycle policies

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with Administrator permissions for EFS, EC2, VPC, and CloudWatch services
- Existing VPC with subnets across multiple Availability Zones
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Basic understanding of Linux file systems and NFS protocols

## Cost Considerations

This infrastructure creates billable resources:
- EFS storage charges based on data stored and throughput
- EC2 instances (t3.micro) for demonstration
- CloudWatch logs and metrics
- AWS Backup storage costs

Estimated cost: $0.10-0.50 per hour depending on usage patterns.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name distributed-efs-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=VpcId,ParameterValue=vpc-xxxxxxxxx \
                 ParameterKey=SubnetIds,ParameterValue=subnet-xxx,subnet-yyy,subnet-zzz \
                 ParameterKey=KeyPairName,ParameterValue=my-key-pair

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name distributed-efs-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name distributed-efs-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters vpcId=vpc-xxxxxxxxx \
           --parameters subnetIds=subnet-xxx,subnet-yyy,subnet-zzz \
           --parameters keyPairName=my-key-pair

# View stack outputs
cdk ls
```

### Using CDK Python

```bash
# Set up Python virtual environment
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters vpcId=vpc-xxxxxxxxx \
           --parameters subnetIds=subnet-xxx,subnet-yyy,subnet-zzz \
           --parameters keyPairName=my-key-pair

# View stack outputs
cdk ls
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
vpc_id = "vpc-xxxxxxxxx"
subnet_ids = ["subnet-xxx", "subnet-yyy", "subnet-zzz"]
key_pair_name = "my-key-pair"
aws_region = "us-east-1"
EOF

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export VPC_ID="vpc-xxxxxxxxx"
export SUBNET_IDS="subnet-xxx,subnet-yyy,subnet-zzz"
export KEY_PAIR_NAME="my-key-pair"
export AWS_REGION="us-east-1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/deploy.sh --status
```

## Post-Deployment Verification

After deployment, verify the infrastructure:

1. **Check EFS File System**:
   ```bash
   aws efs describe-file-systems \
       --query 'FileSystems[?Name==`distributed-efs-*`]'
   ```

2. **Verify Mount Targets**:
   ```bash
   aws efs describe-mount-targets \
       --file-system-id fs-xxxxxxxxx
   ```

3. **Test File Sharing**:
   ```bash
   # SSH to instances and test file operations
   ssh -i ~/.ssh/your-key.pem ec2-user@instance-ip
   # Create test file: echo "test" > /mnt/efs/test.txt
   # Verify on other instance: cat /mnt/efs/test.txt
   ```

4. **Monitor Performance**:
   ```bash
   # View CloudWatch dashboard
   aws cloudwatch get-dashboard \
       --dashboard-name EFS-distributed-efs-*
   ```

## Configuration Options

### CloudFormation Parameters

- `VpcId`: VPC ID where resources will be created
- `SubnetIds`: Comma-separated list of subnet IDs across AZs
- `KeyPairName`: EC2 Key Pair for instance access
- `InstanceType`: EC2 instance type (default: t3.micro)
- `PerformanceMode`: EFS performance mode (generalPurpose|maxIO)
- `ThroughputMode`: EFS throughput mode (bursting|elastic|provisioned)

### CDK Context Variables

- `vpcId`: VPC ID for resource deployment
- `subnetIds`: Subnet IDs for multi-AZ deployment
- `keyPairName`: EC2 Key Pair name
- `instanceType`: EC2 instance type
- `performanceMode`: EFS performance configuration
- `enableBackup`: Enable AWS Backup (true|false)

### Terraform Variables

- `vpc_id`: VPC ID (required)
- `subnet_ids`: List of subnet IDs (required)
- `key_pair_name`: EC2 Key Pair name (required)
- `aws_region`: AWS region (required)
- `instance_type`: EC2 instance type (default: "t3.micro")
- `performance_mode`: EFS performance mode (default: "generalPurpose")
- `throughput_mode`: EFS throughput mode (default: "elastic")
- `enable_backup`: Enable automated backups (default: true)
- `backup_retention_days`: Backup retention period (default: 30)

## Security Features

- **Encryption**: EFS encryption at rest and in transit enabled
- **Access Control**: Security groups restrict NFS access to authorized instances
- **IAM Integration**: EFS access controlled via IAM policies
- **Access Points**: Fine-grained access control for different applications
- **VPC Isolation**: All resources deployed within VPC boundaries

## Monitoring and Observability

- **CloudWatch Metrics**: EFS performance metrics (throughput, IOPS, connections)
- **CloudWatch Dashboards**: Visual monitoring of file system performance
- **CloudWatch Logs**: EC2 instance logs for troubleshooting
- **AWS Backup**: Automated backup status and recovery points

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name distributed-efs-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name distributed-efs-stack
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Clean up all resources
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **Mount Target Creation Fails**:
   - Verify subnets are in different AZs
   - Check security group rules allow NFS traffic
   - Ensure IAM permissions for EFS operations

2. **EFS Mount Fails on EC2**:
   - Verify amazon-efs-utils is installed
   - Check security group connectivity
   - Verify EFS mount helper configuration

3. **Performance Issues**:
   - Check EFS throughput mode configuration
   - Monitor CloudWatch metrics for bottlenecks
   - Consider switching to Max I/O performance mode

4. **Access Point Permissions**:
   - Verify POSIX user/group settings
   - Check root directory permissions
   - Ensure access point is in available state

### Debugging Commands

```bash
# Check EFS file system details
aws efs describe-file-systems --file-system-id fs-xxxxxxxxx

# View mount target status
aws efs describe-mount-targets --file-system-id fs-xxxxxxxxx

# Check access point configuration
aws efs describe-access-points --file-system-id fs-xxxxxxxxx

# Monitor EFS performance metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/EFS \
    --metric-name TotalIOBytes \
    --dimensions Name=FileSystemId,Value=fs-xxxxxxxxx \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T01:00:00Z \
    --period 300 \
    --statistics Sum
```

## Best Practices

1. **Security**:
   - Use IAM roles instead of access keys
   - Enable encryption in transit and at rest
   - Implement least privilege access policies
   - Regular security group audits

2. **Performance**:
   - Choose appropriate performance mode for workload
   - Monitor throughput utilization
   - Use access points for application isolation
   - Consider EFS Intelligent Tiering for cost optimization

3. **Backup and Recovery**:
   - Enable automated backups
   - Test backup restoration procedures
   - Implement cross-region replication for DR
   - Monitor backup job status

4. **Cost Optimization**:
   - Enable EFS Intelligent Tiering
   - Monitor storage class transitions
   - Review access patterns regularly
   - Clean up unused access points

## Extension Ideas

1. **Container Integration**: Deploy EFS CSI driver on EKS for persistent volumes
2. **Hybrid Connectivity**: Use AWS DataSync for on-premises integration
3. **Multi-Region Setup**: Implement cross-region replication
4. **Advanced Monitoring**: Custom CloudWatch alarms and automated remediation
5. **Compliance**: Implement AWS Config rules for EFS compliance monitoring

## Support

For issues with this infrastructure code:
- Review the original recipe documentation
- Check AWS EFS documentation: https://docs.aws.amazon.com/efs/
- Submit issues to the recipe repository
- Consult AWS Support for service-specific issues

## License

This infrastructure code is provided under the same license as the parent recipe repository.