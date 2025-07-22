# EC2 Hibernation Cost Optimization - CDK TypeScript

This CDK TypeScript application implements an EC2 hibernation cost optimization solution based on the AWS recipe "EC2 Hibernate for Cost Optimization".

## Overview

This solution creates an EC2 instance with hibernation enabled, allowing you to preserve instance memory state while stopping compute charges. The stack includes:

- **EC2 Instance**: Hibernation-enabled instance with encrypted EBS root volume
- **VPC**: Isolated network environment with public subnets
- **Security Group**: Configured for SSH access and basic connectivity
- **CloudWatch Monitoring**: CPU utilization alarms and custom metrics
- **SNS Notifications**: Email alerts for hibernation events
- **IAM Roles**: Least privilege permissions for instance operations
- **CloudWatch Dashboard**: Real-time monitoring and visualization

## Architecture

The solution implements the following architecture:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Developer/Ops   │    │ CloudWatch      │    │ SNS Topic       │
│ Team            │    │ Alarms          │    │ Notifications   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ EC2 Instance    │◄──►│ CloudWatch      │◄──►│ Email           │
│ (Hibernation    │    │ Metrics         │    │ Subscriber      │
│ Enabled)        │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐
│ EBS Volume      │
│ (Encrypted)     │
│ Hibernation     │
│ State Storage   │
└─────────────────┘
```

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18.x or later
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- TypeScript installed (`npm install -g typescript`)
- Appropriate AWS permissions for EC2, CloudWatch, SNS, and IAM

## Installation

1. **Clone the repository** (if not already done):
   ```bash
   git clone <repository-url>
   cd aws/ec2-hibernate-cost-optimization/code/cdk-typescript
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Bootstrap CDK** (if not already done in your account/region):
   ```bash
   cdk bootstrap
   ```

## Configuration

The stack accepts several configuration parameters through CDK context:

### Required Parameters
- None - the stack will create all necessary resources with sensible defaults

### Optional Parameters
- `stackName`: Name for the stack (default: 'EC2HibernationDemo')
- `notificationEmail`: Email address for SNS notifications
- `keyPairName`: Existing EC2 key pair name (if not provided, a new one will be created)
- `cpuThreshold`: CPU utilization threshold for hibernation alerts (default: 10)
- `enableDetailedMonitoring`: Enable detailed CloudWatch monitoring (default: false)

## Deployment

### Basic Deployment
```bash
# Deploy with default configuration
cdk deploy

# Deploy with custom stack name
cdk deploy --context stackName=MyHibernationStack

# Deploy with email notifications
cdk deploy --context notificationEmail=your-email@example.com

# Deploy with existing key pair
cdk deploy --context keyPairName=my-existing-key
```

### Advanced Deployment
```bash
# Deploy with multiple parameters
cdk deploy \
  --context stackName=DevHibernationStack \
  --context notificationEmail=devops@company.com \
  --context cpuThreshold=5 \
  --context enableDetailedMonitoring=true
```

### Development Deployment
```bash
# Build and deploy
npm run build
cdk deploy --profile dev --region us-east-1
```

## Usage

### 1. Access the Instance

After deployment, use the SSH command from the stack outputs:

```bash
# Get the SSH command from stack outputs
aws cloudformation describe-stacks \
  --stack-name EC2HibernationDemo \
  --query 'Stacks[0].Outputs[?OutputKey==`SSHCommand`].OutputValue' \
  --output text

# Example output:
# ssh -i hibernate-demo-key-ec2hibernationdemo.pem ec2-user@54.123.45.67
```

### 2. Test Hibernation State Preservation

```bash
# SSH to the instance
ssh -i <key-pair-name>.pem ec2-user@<instance-public-ip>

# Run the hibernation test script
./hibernation-test.sh

# Create additional test files
echo "Current processes: $(ps aux | wc -l)" > /tmp/pre-hibernation-state.txt
echo "Memory usage: $(free -h)" >> /tmp/pre-hibernation-state.txt
```

### 3. Hibernate the Instance

```bash
# Get hibernation command from stack outputs
aws cloudformation describe-stacks \
  --stack-name EC2HibernationDemo \
  --query 'Stacks[0].Outputs[?OutputKey==`HibernateCommand`].OutputValue' \
  --output text

# Example hibernation command:
# aws ec2 stop-instances --instance-ids i-1234567890abcdef0 --hibernate --region us-east-1
```

### 4. Monitor Hibernation Process

```bash
# Check instance state
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].State.Name'

# Verify hibernation state reason
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].StateReason.Code'
```

### 5. Resume from Hibernation

```bash
# Get resume command from stack outputs
aws cloudformation describe-stacks \
  --stack-name EC2HibernationDemo \
  --query 'Stacks[0].Outputs[?OutputKey==`ResumeCommand`].OutputValue' \
  --output text

# Example resume command:
# aws ec2 start-instances --instance-ids i-1234567890abcdef0 --region us-east-1
```

### 6. Verify State Preservation

```bash
# SSH to the resumed instance
ssh -i <key-pair-name>.pem ec2-user@<new-public-ip>

# Check hibernation test results
cat /home/ec2-user/hibernation-state.txt
cat /tmp/pre-hibernation-state.txt

# Verify processes and memory state
ps aux | grep -v grep | grep -v ssh
free -h
```

## Monitoring and Alerting

### CloudWatch Dashboard

Access the CloudWatch dashboard using the URL from stack outputs:

```bash
# Get dashboard URL
aws cloudformation describe-stacks \
  --stack-name EC2HibernationDemo \
  --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
  --output text
```

The dashboard includes:
- CPU utilization trends
- Network I/O metrics
- Instance status checks
- Custom hibernation metrics

### CloudWatch Alarms

The stack creates two main alarms:

1. **Low CPU Alarm**: Triggers when CPU utilization is below threshold for 30 minutes
2. **Instance State Alarm**: Monitors instance state changes and status checks

### SNS Notifications

If you provided an email address, you'll receive notifications for:
- Low CPU utilization events
- Instance state changes
- Hibernation recommendations

## Cost Optimization

### Hibernation Savings

When hibernated, you only pay for:
- EBS storage costs (~$0.10/GB/month for gp3)
- Data transfer costs (minimal)

You don't pay for:
- EC2 compute charges
- Instance hours
- Associated costs while hibernated

### Example Savings

For a `m5.large` instance ($0.096/hour):
- **Without hibernation**: 24 hours × $0.096 = $2.30/day
- **With hibernation** (8 hours active): 8 hours × $0.096 + EBS costs = $0.77/day + storage
- **Daily savings**: ~$1.53/day (~67% reduction)

## Testing

### Unit Tests

```bash
# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run tests with coverage
npm test -- --coverage
```

### Integration Tests

```bash
# Deploy test stack
cdk deploy --context stackName=TestHibernationStack

# Run hibernation tests
./test-hibernation.sh

# Cleanup test resources
cdk destroy --context stackName=TestHibernationStack
```

## Development

### Code Quality

```bash
# Lint TypeScript code
npm run lint

# Fix linting issues
npm run lint:fix

# Format code
npm run format

# Check formatting
npm run format:check
```

### Build Process

```bash
# Clean build artifacts
npm run clean

# Build TypeScript
npm run build

# Watch for changes
npm run watch

# Generate CloudFormation template
npm run synth
```

## Troubleshooting

### Common Issues

1. **Hibernation not available**:
   - Verify instance type supports hibernation
   - Check EBS root volume is encrypted
   - Ensure instance was launched with hibernation enabled

2. **SSH connection issues**:
   - Verify security group allows SSH (port 22)
   - Check key pair permissions (`chmod 400`)
   - Confirm public IP after hibernation resume

3. **CloudWatch alarms not triggering**:
   - Verify CloudWatch agent is running
   - Check alarm thresholds and evaluation periods
   - Ensure SNS topic subscription is confirmed

### Debug Commands

```bash
# Check hibernation support
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].HibernationOptions.Configured'

# View instance logs
aws ec2 get-console-output --instance-id <instance-id>

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=<instance-id> \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 300 \
  --statistics Average
```

## Cleanup

### Destroy Stack

```bash
# Destroy all resources
cdk destroy

# Destroy specific stack
cdk destroy --context stackName=MyHibernationStack

# Force destruction (bypass confirmation)
cdk destroy --force
```

### Manual Cleanup

If automatic cleanup fails:

```bash
# Terminate instance
aws ec2 terminate-instances --instance-ids <instance-id>

# Delete key pair (if created by stack)
aws ec2 delete-key-pair --key-name <key-pair-name>

# Delete SNS topic
aws sns delete-topic --topic-arn <topic-arn>

# Delete CloudWatch alarms
aws cloudwatch delete-alarms --alarm-names <alarm-name>
```

## Security Considerations

### IAM Permissions

The stack follows least privilege principles:
- Instance role has minimal EC2 permissions
- CloudWatch permissions limited to metrics
- SNS permissions scoped to specific topics

### Network Security

- VPC with public subnets only (no NAT gateways for cost)
- Security group allows SSH from anywhere (demo only)
- All EBS volumes encrypted at rest

### Production Hardening

For production use, consider:
- Restricting SSH access to specific IP ranges
- Using Systems Manager Session Manager instead of SSH
- Implementing VPC Flow Logs analysis
- Adding AWS Config rules for compliance

## Best Practices

### Hibernation Guidelines

1. **Test thoroughly**: Verify application behavior after hibernation
2. **Monitor patterns**: Use CloudWatch to identify hibernation opportunities
3. **Automate scheduling**: Implement Lambda-based hibernation scheduling
4. **Document processes**: Maintain hibernation procedures and runbooks

### Cost Optimization

1. **Right-size instances**: Use appropriate instance types for workloads
2. **Monitor utilization**: Set up comprehensive CloudWatch monitoring
3. **Implement tagging**: Use consistent tags for cost allocation
4. **Regular reviews**: Conduct periodic cost optimization reviews

## Support

For issues with this CDK application:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [EC2 hibernation requirements](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/hibernating-prerequisites.html)
3. Consult the original recipe documentation
4. Open an issue in the repository

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and linting
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.