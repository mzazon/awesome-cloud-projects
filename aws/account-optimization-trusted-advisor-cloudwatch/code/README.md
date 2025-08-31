# Infrastructure as Code for Account Optimization Monitoring with Trusted Advisor and CloudWatch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Account Optimization Monitoring with Trusted Advisor and CloudWatch".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with Business, Enterprise On-Ramp, or Enterprise Support plan for full Trusted Advisor access
- IAM permissions for CloudWatch, SNS, and Trusted Advisor operations
- Valid email address for receiving optimization alerts
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

> **Important**: All Trusted Advisor events are only available in the US East (N. Virginia) region. This infrastructure must be deployed in `us-east-1`.

## Quick Start

### Using CloudFormation

```bash
# Set required environment variables
export EMAIL_ADDRESS="your-email@example.com"
export AWS_REGION="us-east-1"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name trusted-advisor-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=${EMAIL_ADDRESS} \
    --capabilities CAPABILITY_IAM \
    --region ${AWS_REGION}

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name trusted-advisor-monitoring \
    --region ${AWS_REGION}

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name trusted-advisor-monitoring \
    --query 'Stacks[0].Outputs' \
    --region ${AWS_REGION}
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Set environment variables
export EMAIL_ADDRESS="your-email@example.com"
export CDK_DEFAULT_REGION="us-east-1"

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy TrustedAdvisorMonitoringStack \
    --parameters notificationEmail=${EMAIL_ADDRESS}

# View stack outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export EMAIL_ADDRESS="your-email@example.com"
export CDK_DEFAULT_REGION="us-east-1"

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy TrustedAdvisorMonitoringStack \
    --parameters notificationEmail=${EMAIL_ADDRESS}

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
aws_region = "us-east-1"
resource_prefix = "trusted-advisor"
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

# Set environment variables
export EMAIL_ADDRESS="your-email@example.com"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# View created resources
aws sns list-topics --region ${AWS_REGION}
aws cloudwatch describe-alarms --region ${AWS_REGION}
```

## Post-Deployment Steps

### Email Subscription Confirmation

After deployment, you'll receive an email subscription confirmation:

1. Check your email inbox for an AWS notification
2. Click "Confirm subscription" in the email
3. Verify subscription status:

```bash
# Check subscription status
aws sns list-subscriptions-by-topic \
    --topic-arn $(aws sns list-topics \
        --query 'Topics[?contains(TopicArn, `trusted-advisor`)].TopicArn' \
        --output text) \
    --region us-east-1
```

### Testing Notifications

Send a test notification to verify the setup:

```bash
# Get SNS topic ARN
TOPIC_ARN=$(aws sns list-topics \
    --query 'Topics[?contains(TopicArn, `trusted-advisor`)].TopicArn' \
    --output text \
    --region us-east-1)

# Send test message
aws sns publish \
    --topic-arn ${TOPIC_ARN} \
    --message "Test: AWS Account Optimization Monitoring is active" \
    --subject "AWS Trusted Advisor - Test Alert" \
    --region us-east-1
```

## Monitoring and Validation

### Check Alarm Status

```bash
# View all created alarms
aws cloudwatch describe-alarms \
    --query 'MetricAlarms[?contains(AlarmName, `trusted-advisor`)].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
    --output table \
    --region us-east-1

# Check specific alarm details
aws cloudwatch describe-alarms \
    --alarm-names "trusted-advisor-cost-optimization" \
    --region us-east-1
```

### View Trusted Advisor Metrics

```bash
# List available Trusted Advisor metrics
aws cloudwatch list-metrics \
    --namespace AWS/TrustedAdvisor \
    --region us-east-1

# Get metric statistics for cost optimization
aws cloudwatch get-metric-statistics \
    --namespace AWS/TrustedAdvisor \
    --metric-name YellowResources \
    --dimensions Name=CheckName,Value="Low Utilization Amazon EC2 Instances" \
    --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 86400 \
    --statistics Sum \
    --region us-east-1
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name trusted-advisor-monitoring \
    --region us-east-1

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name trusted-advisor-monitoring \
    --region us-east-1
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy TrustedAdvisorMonitoringStack
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy TrustedAdvisorMonitoringStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Customization

### CloudFormation Parameters

- `NotificationEmail`: Email address for alerts
- `ResourcePrefix`: Prefix for resource names (default: trusted-advisor)
- `CostOptimizationThreshold`: Threshold for cost optimization alerts (default: 1)
- `SecurityThreshold`: Threshold for security alerts (default: 1)
- `ServiceLimitThreshold`: Percentage threshold for service limits (default: 80)

### CDK Parameters

- `notificationEmail`: Email address for SNS notifications
- `resourcePrefix`: Prefix for all created resources
- `enableCostOptimizationAlarm`: Enable/disable cost optimization monitoring
- `enableSecurityAlarm`: Enable/disable security monitoring
- `enableServiceLimitAlarm`: Enable/disable service limit monitoring

### Terraform Variables

- `notification_email`: Email address for alerts
- `aws_region`: AWS region (must be us-east-1)
- `resource_prefix`: Prefix for resource names
- `cost_optimization_threshold`: Threshold for cost alerts
- `security_threshold`: Threshold for security alerts
- `service_limit_threshold`: Service limit percentage threshold
- `alarm_evaluation_periods`: Number of periods for alarm evaluation
- `alarm_period`: Period in seconds for metric evaluation

### Environment Variables for Bash Scripts

- `EMAIL_ADDRESS`: Email address for notifications
- `AWS_REGION`: AWS region (must be us-east-1)
- `RESOURCE_PREFIX`: Prefix for resource names (optional)
- `COST_THRESHOLD`: Cost optimization threshold (optional)
- `SECURITY_THRESHOLD`: Security threshold (optional)
- `LIMIT_THRESHOLD`: Service limit threshold percentage (optional)

## Architecture Components

The infrastructure creates the following resources:

1. **SNS Topic**: `trusted-advisor-alerts` - Central notification hub
2. **Email Subscription**: Email endpoint for receiving alerts
3. **Cost Optimization Alarm**: Monitors EC2 underutilization
4. **Security Alarm**: Monitors unrestricted security groups
5. **Service Limits Alarm**: Monitors EC2 instance quota usage

## Trusted Advisor Checks Monitored

- **Low Utilization Amazon EC2 Instances**: Identifies underutilized EC2 instances
- **Security Groups - Specific Ports Unrestricted**: Detects security groups with unrestricted access
- **Service Limits**: Monitors usage against AWS service quotas

## Cost Considerations

- **SNS**: $0.50 per 1 million email notifications
- **CloudWatch Alarms**: $0.10 per alarm per month
- **CloudWatch Metrics**: Trusted Advisor metrics are provided at no additional charge

Estimated monthly cost: $0.50 - $2.00 (depending on alert frequency)

## Troubleshooting

### Common Issues

1. **Insufficient Support Plan**: Ensure your AWS account has Business, Enterprise On-Ramp, or Enterprise Support
2. **Region Mismatch**: All resources must be deployed in us-east-1
3. **Email Not Confirmed**: Check spam folder and confirm SNS subscription
4. **Alarm in INSUFFICIENT_DATA State**: Wait for Trusted Advisor to publish fresh metrics (may take several hours)

### Validation Commands

```bash
# Check support plan level
aws support describe-trusted-advisor-checks --language en --region us-east-1

# Verify SNS topic exists
aws sns list-topics --region us-east-1 | grep trusted-advisor

# Check alarm configurations
aws cloudwatch describe-alarms --region us-east-1 --alarm-name-prefix trusted-advisor
```

## Security Best Practices

- SNS topic uses default encryption
- CloudWatch alarms follow least privilege principles
- Email subscriptions require confirmation to prevent spam
- No sensitive information is logged or exposed

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS Trusted Advisor documentation
3. Verify CloudWatch alarm configuration
4. Confirm SNS topic and subscription status
5. Review AWS Support plan requirements

## Additional Resources

- [AWS Trusted Advisor User Guide](https://docs.aws.amazon.com/awssupport/latest/user/trusted-advisor.html)
- [CloudWatch Monitoring for Trusted Advisor](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch-ta.html)
- [SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
- [AWS Cost Optimization Best Practices](https://docs.aws.amazon.com/awssupport/latest/user/cost-optimization-checks.html)