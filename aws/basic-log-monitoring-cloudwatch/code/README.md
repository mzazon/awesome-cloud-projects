# Infrastructure as Code for Basic Log Monitoring with CloudWatch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Basic Log Monitoring with CloudWatch".

## Overview

This solution creates an automated log monitoring system that detects critical errors in application logs and sends real-time alerts to your team. The infrastructure includes:

- **CloudWatch Log Group** for centralized log collection
- **CloudWatch Metric Filter** to detect error patterns in logs
- **CloudWatch Alarm** to trigger notifications when error thresholds are exceeded
- **SNS Topic** for flexible notification delivery
- **Lambda Function** for automated log processing and analysis

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - CloudWatch Logs
  - CloudWatch Metrics and Alarms
  - SNS
  - Lambda
  - IAM (for Lambda execution role)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Valid email address for receiving notifications

## Cost Estimation

- **CloudWatch Logs**: $0.50 per GB ingested, $0.03 per GB stored per month
- **CloudWatch Metrics**: $0.30 per metric per month
- **CloudWatch Alarms**: $0.10 per alarm per month
- **SNS**: $0.50 per 1 million requests
- **Lambda**: $0.20 per 1 million requests + $0.0000166667 per GB-second
- **Estimated monthly cost**: $5-15 for moderate log volumes

## Quick Start

### Using CloudFormation

Deploy the complete monitoring infrastructure with a single command:

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name basic-log-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name basic-log-monitoring \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name basic-log-monitoring \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

Deploy using the AWS Cloud Development Kit with TypeScript:

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this region)
cdk bootstrap

# Set your notification email
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy BasicLogMonitoringStack

# View stack outputs
cdk ls
```

### Using CDK Python

Deploy using the AWS Cloud Development Kit with Python:

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this region)
cdk bootstrap

# Set your notification email
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy BasicLogMonitoringStack

# View stack outputs
cdk ls
```

### Using Terraform

Deploy using Terraform with the official AWS provider:

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="notification_email=your-email@example.com"

# Apply the configuration
terraform apply -var="notification_email=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

Deploy using automated bash scripts:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set your notification email
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy infrastructure
./scripts/deploy.sh

# The script will output key resource identifiers for testing
```

## Testing the Deployment

After deployment, test the monitoring system:

1. **Confirm SNS subscription**: Check your email and confirm the SNS subscription
2. **Send test log events**: Use the AWS CLI to send error events to the log group
3. **Verify alarm triggers**: Monitor CloudWatch alarms and SNS notifications
4. **Check Lambda processing**: Review Lambda function logs for processing details

### Example Test Commands

```bash
# Get the log group name from stack outputs
LOG_GROUP_NAME="/aws/application/monitoring-demo"

# Create a test log stream
aws logs create-log-stream \
    --log-group-name $LOG_GROUP_NAME \
    --log-stream-name test-$(date +%s)

# Send test error events
aws logs put-log-events \
    --log-group-name $LOG_GROUP_NAME \
    --log-stream-name test-$(date +%s) \
    --log-events \
        timestamp=$(date +%s000),message="ERROR: Database connection failed"

# Monitor alarm state
aws cloudwatch describe-alarms \
    --alarm-names "ApplicationErrorsAlarm" \
    --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason}'
```

## Customization

### Configuration Variables

Each implementation supports the following customizations:

- **Log Group Name**: Customize the CloudWatch log group name
- **Retention Period**: Adjust log retention (default: 7 days)
- **Error Threshold**: Modify alarm threshold (default: 2 errors)
- **Evaluation Period**: Change alarm evaluation period (default: 5 minutes)
- **Notification Email**: Set email address for alerts
- **Lambda Memory**: Adjust Lambda function memory allocation
- **Lambda Timeout**: Modify Lambda function timeout

### CloudFormation Parameters

```yaml
Parameters:
  NotificationEmail:
    Type: String
    Description: Email address for receiving notifications
  
  LogRetentionDays:
    Type: Number
    Default: 7
    Description: Log retention period in days
  
  ErrorThreshold:
    Type: Number
    Default: 2
    Description: Number of errors to trigger alarm
```

### Terraform Variables

```hcl
variable "notification_email" {
  description = "Email address for receiving notifications"
  type        = string
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 7
}

variable "error_threshold" {
  description = "Number of errors to trigger alarm"
  type        = number
  default     = 2
}
```

## Architecture Components

### CloudWatch Log Group
- Centralized log collection with configurable retention
- Structured for application log ingestion
- Cost-optimized with 7-day default retention

### Metric Filter
- Detects error patterns: ERROR, FAILED, EXCEPTION, TIMEOUT
- Creates custom ApplicationErrors metric
- JSON-based filtering for structured logs

### CloudWatch Alarm
- Monitors ApplicationErrors metric
- Threshold: 2 errors in 5-minute period
- Balances sensitivity with false positive prevention

### SNS Topic
- Multi-endpoint notification delivery
- Supports email, SMS, Lambda, and webhook integrations
- Decoupled architecture for notification flexibility

### Lambda Function
- Serverless log processing and analysis
- Enriches alert data with context
- Extensible for automated remediation

## Security Considerations

### IAM Permissions
- Lambda execution role with minimal required permissions
- CloudWatch Logs read access for metric filters
- SNS publish permissions for alarm notifications

### Encryption
- CloudWatch Logs encrypted at rest
- SNS message encryption in transit
- Lambda environment variables encryption

### Network Security
- No public endpoints exposed
- All communication within AWS network
- VPC endpoints can be added for enhanced security

## Monitoring and Observability

### CloudWatch Dashboards
Create custom dashboards to monitor:
- Error rate trends over time
- Alarm state history
- Lambda function performance
- SNS delivery success rates

### X-Ray Integration
Add distributed tracing to the Lambda function for detailed performance analysis:

```python
from aws_xray_sdk.core import xray_recorder

@xray_recorder.capture('lambda_handler')
def lambda_handler(event, context):
    # Function code with X-Ray tracing
```

## Troubleshooting

### Common Issues

1. **Alarm not triggering**:
   - Verify metric filter pattern matches your log format
   - Check log events are being ingested
   - Confirm alarm threshold and evaluation period

2. **Email notifications not received**:
   - Confirm SNS subscription in email
   - Check spam/junk folders
   - Verify SNS topic permissions

3. **Lambda function errors**:
   - Review CloudWatch Logs for Lambda execution
   - Check IAM role permissions
   - Verify SNS trigger configuration

### Debug Commands

```bash
# Check metric filter statistics
aws logs describe-metric-filters \
    --log-group-name "/aws/application/monitoring-demo"

# View alarm history
aws cloudwatch describe-alarm-history \
    --alarm-name "ApplicationErrorsAlarm"

# Check SNS subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn "arn:aws:sns:region:account:topic-name"

# View Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/log-processor-function"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack and all resources
aws cloudformation delete-stack --stack-name basic-log-monitoring

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name basic-log-monitoring \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# From the CDK directory
cdk destroy BasicLogMonitoringStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="notification_email=your-email@example.com"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Extensions and Enhancements

### Multi-Region Deployment
Deploy the monitoring system across multiple AWS regions for applications with global distribution.

### Advanced Error Classification
Extend metric filters to categorize errors by severity levels (WARNING, ERROR, CRITICAL, FATAL).

### Automated Remediation
Add Step Functions workflows to automate common remediation tasks based on error patterns.

### Integration with External Systems
Connect to PagerDuty, Slack, or other incident management tools using additional SNS subscriptions.

### Cost Optimization
Implement log sampling for high-volume applications to reduce CloudWatch Logs costs while maintaining monitoring coverage.

## Support and Documentation

- [AWS CloudWatch Logs Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
- [AWS SNS Documentation](https://docs.aws.amazon.com/sns/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or consult the AWS documentation for specific services.