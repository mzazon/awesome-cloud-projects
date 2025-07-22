# Infrastructure as Code for EC2 Hibernate Cost Optimization

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EC2 Hibernate for Cost Optimization".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for EC2, CloudWatch, and SNS operations
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform v1.0+ installed
- Understanding of EC2 hibernation requirements and limitations

> **Note**: EC2 hibernation requires specific instance types and AMIs. Ensure your chosen configuration supports hibernation before deployment.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name ec2-hibernate-demo \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name ec2-hibernate-demo \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters notificationEmail=your-email@example.com

# View outputs
npx cdk ls
```

### Using CDK Python (AWS)

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
cdk deploy --parameters notificationEmail=your-email@example.com

# View outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="notification_email=your-email@example.com"

# Apply the configuration
terraform apply -var="notification_email=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the infrastructure
./scripts/deploy.sh

# Test hibernation functionality
./scripts/test-hibernation.sh
```

## Architecture Overview

This implementation creates:

- **EC2 Instance**: Hibernation-enabled instance with encrypted EBS root volume
- **CloudWatch Monitoring**: CPU utilization metrics and low usage alarms
- **SNS Notifications**: Email alerts for hibernation recommendations
- **Security**: Key pair for secure instance access
- **Cost Optimization**: Automated monitoring for hibernation opportunities

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `InstanceType` | EC2 instance type supporting hibernation | `m5.large` | No |
| `VolumeSize` | EBS root volume size in GB | `30` | No |
| `NotificationEmail` | Email for CloudWatch notifications | - | Yes |
| `CPUThreshold` | CPU utilization threshold for alarms | `10` | No |

### CDK Configuration

Both TypeScript and Python CDK implementations support:

- Custom instance types via context variables
- Configurable monitoring thresholds
- Multiple notification endpoints
- Environment-specific deployments

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `instance_type` | EC2 instance type | `string` | `"m5.large"` |
| `volume_size` | EBS root volume size | `number` | `30` |
| `notification_email` | Email for notifications | `string` | Required |
| `cpu_threshold` | CPU threshold for alarms | `number` | `10` |
| `environment` | Environment name | `string` | `"demo"` |

## Testing Hibernation

After deployment, test the hibernation functionality:

```bash
# Get instance ID from outputs
INSTANCE_ID=$(terraform output -raw instance_id)

# Connect to instance (replace with actual key path)
ssh -i ec2-hibernate-demo-key.pem ec2-user@$(terraform output -raw instance_public_ip)

# Create test file to verify state persistence
echo "hibernation-test-$(date)" > /tmp/hibernation-test.txt

# Exit SSH session
exit

# Hibernate the instance
aws ec2 stop-instances --instance-ids $INSTANCE_ID --hibernate

# Wait for hibernation to complete
aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID

# Resume the instance
aws ec2 start-instances --instance-ids $INSTANCE_ID

# Wait for instance to be running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Verify state persistence by checking the test file
ssh -i ec2-hibernate-demo-key.pem ec2-user@$(terraform output -raw instance_public_ip) \
    "cat /tmp/hibernation-test.txt"
```

## Monitoring and Alerts

The implementation includes:

- **CPU Utilization Monitoring**: Tracks average CPU usage over 30-minute periods
- **Low Usage Alerts**: Triggers when CPU usage is below 10% for 30 minutes
- **Hibernation Recommendations**: Automated notifications for cost optimization opportunities
- **State Change Monitoring**: Tracks instance state transitions for cost analysis

## Cost Optimization Benefits

This hibernation solution provides:

- **Compute Cost Savings**: 67% reduction for 8-hour daily usage patterns
- **Storage Optimization**: Only pay for EBS storage during hibernation
- **Rapid Recovery**: Faster startup than traditional stop/start operations
- **State Preservation**: Maintains application context and open connections

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name ec2-hibernate-demo

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name ec2-hibernate-demo \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# TypeScript
cd cdk-typescript/
npx cdk destroy

# Python
cd cdk-python/
source .venv/bin/activate
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="notification_email=your-email@example.com"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are removed
aws ec2 describe-instances --filters "Name=tag:Purpose,Values=HibernationDemo" \
    --query 'Reservations[].Instances[].State.Name'
```

## Customization

### Advanced Configuration

1. **Multi-Instance Hibernation**: Modify templates to support multiple instances with different hibernation schedules
2. **Scheduled Hibernation**: Integrate with CloudWatch Events for automated hibernation/resume cycles
3. **Application-Aware Hibernation**: Add health checks before hibernation to ensure application safety
4. **Cost Analysis Dashboard**: Create CloudWatch dashboards for hibernation cost tracking

### Security Enhancements

1. **VPC Configuration**: Deploy instances in private subnets with NAT Gateway access
2. **IAM Roles**: Use instance profiles instead of key-based authentication
3. **Security Groups**: Implement least-privilege network access rules
4. **Encryption**: Enable EBS encryption with customer-managed KMS keys

### Integration Options

1. **CI/CD Pipelines**: Integrate hibernation into development environment workflows
2. **Monitoring Integration**: Connect with third-party monitoring solutions
3. **Cost Management**: Integrate with AWS Cost Explorer and Budgets
4. **Automation**: Use AWS Systems Manager for hibernation scheduling

## Troubleshooting

### Common Issues

1. **Hibernation Not Supported**: Ensure instance type and AMI support hibernation
2. **Insufficient Permissions**: Verify IAM permissions for EC2 hibernation operations
3. **Volume Encryption**: Hibernation requires encrypted root volumes
4. **Instance State**: Instances must be in 'running' state to hibernate

### Debug Commands

```bash
# Check hibernation support
aws ec2 describe-instances --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].HibernationOptions.Configured'

# View instance state reason
aws ec2 describe-instances --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].StateReason'

# Check CloudWatch alarms
aws cloudwatch describe-alarms --alarm-names "LowCPU-*"
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for context
2. Check AWS documentation for [EC2 Hibernation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Hibernate.html)
3. Validate hibernation prerequisites and limitations
4. Ensure proper IAM permissions for all operations

## Additional Resources

- [AWS EC2 Hibernation Prerequisites](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/hibernating-prerequisites.html)
- [CloudWatch Metrics for EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/viewing_metrics_with_cloudwatch.html)
- [AWS Cost Optimization Best Practices](https://docs.aws.amazon.com/whitepapers/latest/cost-optimization-pillar/welcome.html)
- [EC2 Instance Types Supporting Hibernation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/hibernating-prerequisites.html#hibernation-prerequisites-supported-instance-families)