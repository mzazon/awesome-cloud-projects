# Infrastructure as Code for Basic Monitoring with CloudWatch Alarms

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Basic Monitoring with CloudWatch Alarms".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for CloudWatch, SNS, and IAM operations
- Valid email address for alarm notifications
- Tool-specific prerequisites (see individual sections below)

### CloudFormation Prerequisites
- AWS CLI with CloudFormation permissions
- `CAPABILITY_IAM` permissions for stack creation

### CDK Prerequisites
- Node.js 18+ (for TypeScript)
- Python 3.8+ (for Python)
- AWS CDK CLI installed: `npm install -g aws-cdk`

### Terraform Prerequisites
- Terraform 1.0+ installed
- AWS provider configured

## Quick Start

### Using CloudFormation (AWS)
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name basic-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name basic-monitoring-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name basic-monitoring-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy

# Get outputs
cdk list --long
```

### Using CDK Python (AWS)
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy

# Get outputs
cdk list --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
aws_region = "us-east-1"
EOF

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

# Set notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy infrastructure
./scripts/deploy.sh

# View created resources
aws cloudwatch describe-alarms --query 'MetricAlarms[].AlarmName'
aws sns list-topics --query 'Topics[].TopicArn'
```

## Post-Deployment Steps

After deploying with any method:

1. **Confirm Email Subscription**: Check your email for an SNS subscription confirmation message and click the confirmation link.

2. **Test Alarms**: Use the following command to test alarm notifications:
   ```bash
   # Replace ALARM_NAME with actual alarm name from outputs
   aws cloudwatch set-alarm-state \
       --alarm-name "HighCPUUtilization-XXXXX" \
       --state-value ALARM \
       --state-reason "Testing alarm notification"
   ```

3. **Verify Notifications**: You should receive an email notification when the alarm state changes.

## Monitoring Resources Created

This infrastructure creates the following resources:

- **SNS Topic**: For sending alarm notifications
- **SNS Subscription**: Email subscription for notifications
- **CloudWatch Alarms**:
  - High CPU Utilization alarm (>80% for 2 periods)
  - High Response Time alarm (>1 second for 3 periods)
  - High Database Connections alarm (>80 connections for 2 periods)

## Customization

### CloudFormation Parameters
- `NotificationEmail`: Email address for alarm notifications
- `CPUThreshold`: CPU utilization threshold (default: 80)
- `ResponseTimeThreshold`: Response time threshold in seconds (default: 1.0)
- `DatabaseConnectionThreshold`: Database connection threshold (default: 80)

### CDK Context Variables
Set these environment variables or modify the code:
- `NOTIFICATION_EMAIL`: Email address for notifications
- `AWS_REGION`: AWS region for deployment

### Terraform Variables
Modify `terraform.tfvars` or use command-line variables:
- `notification_email`: Email address for notifications
- `cpu_threshold`: CPU utilization threshold
- `response_time_threshold`: Response time threshold
- `db_connection_threshold`: Database connection threshold
- `aws_region`: AWS region for deployment

### Bash Script Environment Variables
Set these before running scripts:
- `NOTIFICATION_EMAIL`: Email address for notifications
- `AWS_REGION`: AWS region (optional, uses CLI default)

## Cleanup

### Using CloudFormation (AWS)
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name basic-monitoring-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name basic-monitoring-stack
```

### Using CDK (AWS)
```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Cost Considerations

This monitoring setup has minimal costs:
- CloudWatch Alarms: $0.10 per alarm per month (3 alarms = $0.30/month)
- SNS Email notifications: Free for first 1,000 emails/month
- CloudWatch metrics: Free for basic AWS service metrics

Total estimated cost: ~$0.30-$2.00 per month depending on alarm frequency

## Troubleshooting

### Common Issues

1. **Email notifications not received**:
   - Check spam folder
   - Verify email subscription is confirmed
   - Check SNS topic permissions

2. **Alarms not triggering**:
   - Ensure resources exist to generate metrics
   - Check alarm configuration and thresholds
   - Verify alarm state using AWS CLI

3. **Permission errors**:
   - Ensure IAM user/role has CloudWatch and SNS permissions
   - Check resource-based policies

### Validation Commands

```bash
# Check alarm status
aws cloudwatch describe-alarms \
    --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}'

# Check SNS subscriptions
aws sns list-subscriptions \
    --query 'Subscriptions[?Protocol==`email`]'

# Test alarm manually
aws cloudwatch set-alarm-state \
    --alarm-name "ALARM_NAME" \
    --state-value ALARM \
    --state-reason "Manual test"
```

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS CloudWatch and SNS documentation
3. Validate your AWS permissions and configuration
4. Ensure all prerequisites are met

## Additional Resources

- [AWS CloudWatch Alarms Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [Amazon SNS Email Notifications](https://docs.aws.amazon.com/sns/latest/dg/sns-email-notifications.html)
- [CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/)
- [SNS Pricing](https://aws.amazon.com/sns/pricing/)