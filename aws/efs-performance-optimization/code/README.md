# Infrastructure as Code for EFS Performance Optimization and Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EFS Performance Optimization and Monitoring".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS IAM permissions for:
  - Amazon EFS (create file systems, mount targets)
  - Amazon EC2 (create instances, security groups)
  - Amazon CloudWatch (create dashboards, alarms)
  - AWS IAM (create roles, policies, instance profiles)
- Valid EC2 key pair for instance access (for testing components)
- Existing VPC with at least two subnets in different Availability Zones

## Architecture Overview

This implementation creates:
- Amazon EFS file system with performance optimization (General Purpose mode, Provisioned throughput)
- Mount targets across multiple Availability Zones
- Security groups for NFS access
- CloudWatch monitoring dashboard and alarms
- Optional EC2 test instance with proper IAM roles

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name efs-performance-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=KeyPairName,ParameterValue=your-key-pair \
                 ParameterKey=ProvisionedThroughputMibps,ParameterValue=100 \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name efs-performance-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name efs-performance-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Install dependencies
cd cdk-typescript/
npm install

# Deploy the stack
cdk deploy --parameters keyPairName=your-key-pair \
           --parameters provisionedThroughputMibps=100

# View outputs
cdk list
```

### Using CDK Python
```bash
# Set up Python environment
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy --parameters keyPairName=your-key-pair \
           --parameters provisionedThroughputMibps=100

# View outputs
cdk list
```

### Using Terraform
```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the plan
terraform plan -var="key_pair_name=your-key-pair" \
               -var="provisioned_throughput_mibps=100"

# Apply the configuration
terraform apply -var="key_pair_name=your-key-pair" \
                -var="provisioned_throughput_mibps=100"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export KEY_PAIR_NAME="your-key-pair"
export PROVISIONED_THROUGHPUT_MIBPS="100"

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output important resource IDs and endpoints
```

## Configuration Options

### Key Parameters

- **Key Pair Name**: EC2 key pair for test instance access
- **Provisioned Throughput**: EFS provisioned throughput in MiB/s (default: 100)
- **Performance Mode**: EFS performance mode (generalPurpose or maxIO)
- **Instance Type**: EC2 instance type for testing (default: t3.medium)

### CloudFormation Parameters
```yaml
Parameters:
  KeyPairName: your-ec2-key-pair
  ProvisionedThroughputMibps: 100
  PerformanceMode: generalPurpose
  InstanceType: t3.medium
```

### Terraform Variables
```hcl
# terraform.tfvars
key_pair_name = "your-ec2-key-pair"
provisioned_throughput_mibps = 100
performance_mode = "generalPurpose"
instance_type = "t3.medium"
```

## Monitoring and Validation

After deployment, access the monitoring resources:

1. **CloudWatch Dashboard**: Navigate to CloudWatch Console → Dashboards → "EFS-Performance-{stack-name}"
2. **CloudWatch Alarms**: View alarms for throughput utilization, client connections, and IO latency
3. **EFS Console**: Verify file system configuration and mount targets

### Key Metrics to Monitor

- **TotalIOBytes**: Overall throughput utilization
- **PercentIOLimit**: Percentage of provisioned throughput being used
- **ClientConnections**: Number of concurrent client connections
- **TotalIOTime**: Average IO latency (should be < 50ms for optimal performance)

## Testing the Deployment

### Mount EFS on EC2 Instance
```bash
# Connect to the test instance
aws ec2 describe-instances --filters "Name=tag:Name,Values=EFS-Test-Instance" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text

# SSH to the instance
ssh -i your-key-pair.pem ec2-user@<instance-ip>

# Mount the EFS file system
sudo mkdir -p /mnt/efs
sudo mount -t efs <efs-file-system-id>:/ /mnt/efs

# Test write performance
sudo dd if=/dev/zero of=/mnt/efs/testfile bs=1M count=100 oflag=direct
```

### Performance Testing
```bash
# Install fio for advanced performance testing
sudo yum install -y fio

# Test sequential write performance
sudo fio --name=seq-write --directory=/mnt/efs --size=1G \
    --bs=1M --rw=write --direct=1 --numjobs=4 --group_reporting

# Test random read performance
sudo fio --name=rand-read --directory=/mnt/efs --size=1G \
    --bs=4k --rw=randread --direct=1 --numjobs=8 --group_reporting
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name efs-performance-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name efs-performance-stack
```

### Using CDK
```bash
# From the cdk-typescript/ or cdk-python/ directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
# From the terraform/ directory
terraform destroy -var="key_pair_name=your-key-pair" \
                  -var="provisioned_throughput_mibps=100"

# Confirm deletion when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Cost Optimization

### Understanding EFS Costs

- **Storage**: Charged per GB stored
- **Provisioned Throughput**: Charged per MiB/s provisioned (separate from storage)
- **Request Charges**: Charged per request for Infrequent Access storage class

### Cost Optimization Tips

1. **Right-size Provisioned Throughput**: Monitor `PercentIOLimit` metric and adjust provisioned throughput based on actual usage
2. **Use EFS Intelligent Tiering**: Automatically move files to lower-cost storage classes
3. **Consider Elastic Throughput**: For unpredictable workloads, use Elastic mode instead of Provisioned
4. **Monitor Usage Patterns**: Use CloudWatch metrics to identify optimization opportunities

## Security Considerations

### Network Security
- Security groups restrict NFS access to authorized sources only
- Mount targets are deployed in private subnets when possible
- Consider using VPC endpoints for enhanced security

### Encryption
- EFS file system encryption at rest is enabled by default
- Consider enabling encryption in transit for sensitive workloads
- Use IAM policies to control access to EFS resources

### IAM Best Practices
- EC2 instances use IAM roles instead of embedded credentials
- Least privilege principle applied to all IAM policies
- Regular review of IAM permissions and access patterns

## Troubleshooting

### Common Issues

1. **Mount Target Creation Fails**
   - Verify security group allows NFS traffic (port 2049)
   - Ensure subnets are in different Availability Zones
   - Check VPC and subnet configurations

2. **High Latency**
   - Verify instances are in the same AZ as mount targets
   - Check network connectivity and security group rules
   - Monitor `TotalIOTime` metric for latency patterns

3. **Throughput Limitations**
   - Monitor `PercentIOLimit` to check provisioned throughput utilization
   - Consider increasing provisioned throughput or switching to Elastic mode
   - Verify client-side configurations (concurrent connections, I/O size)

### Support Resources

- [Amazon EFS User Guide](https://docs.aws.amazon.com/efs/latest/ug/)
- [EFS Performance Documentation](https://docs.aws.amazon.com/efs/latest/ug/performance.html)
- [CloudWatch Metrics for EFS](https://docs.aws.amazon.com/efs/latest/ug/monitoring-cloudwatch.html)
- [EFS Troubleshooting Guide](https://docs.aws.amazon.com/efs/latest/ug/troubleshooting.html)

## Customization

### Advanced Configurations

1. **Multi-Region Replication**: Extend the implementation to include EFS replication to another region
2. **Backup Integration**: Add AWS Backup service configuration for automated backups
3. **Custom Metrics**: Implement additional CloudWatch custom metrics for application-specific monitoring
4. **Auto Scaling**: Integrate with EC2 Auto Scaling for dynamic client scaling

### Environment-Specific Modifications

- Modify security group rules for specific network requirements
- Adjust provisioned throughput based on workload characteristics
- Configure different performance modes based on latency vs. throughput requirements
- Customize CloudWatch alarm thresholds based on SLA requirements

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS service-specific documentation
3. Review CloudWatch logs and metrics for troubleshooting
4. Consult AWS Support for service-specific issues