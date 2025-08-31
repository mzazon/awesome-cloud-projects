# Infrastructure as Code for Simple Resource Monitoring with CloudWatch and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Resource Monitoring with CloudWatch and SNS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Valid email address for receiving notifications
- Appropriate AWS permissions for:
  - EC2 (launch instances, create security groups)
  - CloudWatch (create alarms, metrics access)
  - SNS (create topics, manage subscriptions)
  - IAM (create service roles if needed)
- Estimated cost: $0.15-$0.75 for testing (includes EC2 instance hours, CloudWatch alarms, and SNS messages)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name simple-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name simple-monitoring-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name simple-monitoring-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Set notification email (required)
export NOTIFICATION_EMAIL=your-email@example.com

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set notification email (required)
export NOTIFICATION_EMAIL=your-email@example.com

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your email
echo 'notification_email = "your-email@example.com"' > terraform.tfvars

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set your email address for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the infrastructure
./scripts/deploy.sh

# Optionally, test the monitoring system
./scripts/test-monitoring.sh  # If available
```

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email inbox for an SNS subscription confirmation message and click the confirmation link.

2. **Verify Resources**: 
   ```bash
   # Check EC2 instance status
   aws ec2 describe-instances \
       --filters "Name=tag:Name,Values=monitoring-demo-*" \
       --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]'
   
   # Check CloudWatch alarm status
   aws cloudwatch describe-alarms \
       --alarm-names "high-cpu-*" \
       --query 'MetricAlarms[*].[AlarmName,StateValue,Threshold]'
   ```

3. **Test the Monitoring**: The deployment includes mechanisms to generate CPU load for testing. Monitor your email for alarm notifications.

## Monitoring and Validation

### Check Alarm Status
```bash
# Monitor alarm state changes
aws cloudwatch describe-alarm-history \
    --alarm-name $(aws cloudwatch describe-alarms --query 'MetricAlarms[0].AlarmName' --output text) \
    --history-item-type StateUpdate \
    --max-records 5
```

### View Metrics
```bash
# Get recent CPU utilization
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=monitoring-demo-*" --query 'Reservations[0].Instances[0].InstanceId' --output text) \
    --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

## Cleanup

### Using CloudFormation (AWS)
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name simple-monitoring-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name simple-monitoring-stack
```

### Using CDK (AWS)
```bash
# Destroy the stack (from appropriate CDK directory)
cdk destroy

# Clean up local files
rm -rf cdk.out/
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Configuration Options

### Environment Variables
- `NOTIFICATION_EMAIL`: Email address for receiving alerts (required)
- `AWS_REGION`: AWS region for deployment (defaults to configured region)
- `INSTANCE_TYPE`: EC2 instance type (defaults to t2.micro)
- `CPU_THRESHOLD`: CPU alarm threshold percentage (defaults to 70)

### Customizable Parameters

#### CloudFormation Parameters
- `NotificationEmail`: Email address for notifications
- `InstanceType`: EC2 instance type (default: t2.micro)
- `CpuThreshold`: CPU utilization threshold (default: 70)
- `AlarmEvaluationPeriods`: Number of periods for alarm evaluation (default: 2)

#### Terraform Variables
- `notification_email`: Email address for notifications (required)
- `instance_type`: EC2 instance type (default: "t2.micro")
- `cpu_threshold`: CPU utilization threshold (default: 70)
- `alarm_evaluation_periods`: Number of periods for alarm evaluation (default: 2)
- `aws_region`: AWS region (defaults to provider region)

#### CDK Configuration
Both CDK implementations support the following environment variables:
- `NOTIFICATION_EMAIL`: Required email address
- `INSTANCE_TYPE`: EC2 instance type (default: t2.micro)
- `CPU_THRESHOLD`: Alarm threshold (default: 70)

## Architecture Components

The IaC implementations deploy the following resources:

1. **EC2 Instance**: t2.micro instance running Amazon Linux 2023
2. **CloudWatch Alarm**: Monitors CPU utilization with 70% threshold
3. **SNS Topic**: Handles notification delivery
4. **Email Subscription**: Connects your email to the SNS topic
5. **IAM Roles**: Required service permissions (where applicable)
6. **Security Groups**: Basic security configuration for EC2

## Troubleshooting

### Common Issues

1. **Email Not Confirmed**: Check spam folder for SNS confirmation email
2. **Insufficient Permissions**: Ensure AWS credentials have required permissions
3. **Instance Launch Failure**: Check for service limits or subnet availability
4. **Alarm Not Triggering**: Verify CloudWatch agent installation and metric collection

### Debug Commands
```bash
# Check CloudWatch agent status (if installed)
aws ssm get-command-invocation --command-id <command-id> --instance-id <instance-id>

# View recent alarm history
aws cloudwatch describe-alarm-history --alarm-name <alarm-name> --max-records 10

# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn <topic-arn>
```

## Cost Optimization

- Use t2.micro or t3.micro instances (free tier eligible)
- CloudWatch alarms cost $0.10/month each
- SNS email notifications are free for first 1,000 emails/month
- Consider using CloudWatch composite alarms for complex monitoring scenarios

## Security Considerations

- EC2 instances use default security groups (customize as needed)
- SNS topics use AWS account-level access policies
- Email subscriptions require confirmation to prevent spam
- Consider using AWS Systems Manager Session Manager instead of SSH for instance access

## Support

For issues with this infrastructure code, refer to:
- Original recipe documentation
- AWS CloudFormation documentation
- AWS CDK documentation  
- Terraform AWS provider documentation
- AWS support forums and documentation

## Next Steps

After successful deployment, consider these enhancements:
1. Add memory and disk monitoring with CloudWatch agent
2. Create CloudWatch dashboards for visualization
3. Implement Auto Scaling based on alarm triggers
4. Add cross-region monitoring for high availability
5. Integrate with AWS Systems Manager for automated remediation