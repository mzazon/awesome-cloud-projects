# Infrastructure as Code for Simple Log Analysis with CloudWatch Insights and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Log Analysis with CloudWatch Insights and SNS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an automated log monitoring system that:
- Creates CloudWatch Log Groups for application logs
- Deploys a Lambda function that queries logs using CloudWatch Logs Insights
- Sets up SNS notifications for error alerts
- Configures EventBridge rules for scheduled execution
- Implements proper IAM roles and permissions

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - CloudWatch Logs (create log groups, query logs)
  - Lambda (create functions, manage execution roles)
  - SNS (create topics, manage subscriptions)
  - EventBridge (create rules, manage targets)
  - IAM (create roles and policies)
- Email address for receiving notifications
- Estimated cost: $0.10-$1.00 for testing (mainly CloudWatch Logs Insights queries at $0.005 per GB scanned)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name simple-log-analysis-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name simple-log-analysis-stack

# Check stack status
aws cloudformation describe-stacks \
    --stack-name simple-log-analysis-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Set your notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk bootstrap  # First time only
cdk deploy

# View stack outputs
cdk ls --long
```

### Using CDK Python
```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set your notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk bootstrap  # First time only
cdk deploy

# View stack outputs
cdk ls --long
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
project_name = "simple-log-analysis"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export AWS_REGION=us-east-1

# Deploy the solution
./scripts/deploy.sh

# The script will prompt for confirmation and display progress
```

## Configuration Options

### CloudFormation Parameters
- `NotificationEmail`: Email address for SNS notifications (required)
- `ProjectName`: Prefix for resource names (default: simple-log-analysis)
- `LogRetentionDays`: CloudWatch log retention period (default: 7)
- `ScheduleExpression`: EventBridge schedule (default: rate(5 minutes))

### CDK Configuration
Set environment variables before deployment:
- `NOTIFICATION_EMAIL`: Email address for notifications
- `PROJECT_NAME`: Prefix for resource names (optional)
- `LOG_RETENTION_DAYS`: Log retention period (optional)

### Terraform Variables
Configure in terraform.tfvars:
- `notification_email`: Email address for SNS notifications (required)
- `aws_region`: AWS region for deployment (default: us-east-1)
- `project_name`: Prefix for resource names (default: simple-log-analysis)
- `log_retention_days`: CloudWatch log retention (default: 7)
- `schedule_expression`: EventBridge schedule (default: rate(5 minutes))

## Post-Deployment Steps

1. **Confirm SNS Subscription**: Check your email and confirm the SNS subscription
2. **Generate Test Logs**: Use the AWS CLI to create sample log entries for testing:

```bash
# Get the log group name from stack outputs
LOG_GROUP_NAME=$(aws cloudformation describe-stacks \
    --stack-name simple-log-analysis-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' \
    --output text)

# Create test error logs
CURRENT_TIME=$(date +%s000)
aws logs put-log-events \
    --log-group-name ${LOG_GROUP_NAME} \
    --log-stream-name "test-stream" \
    --log-events \
    timestamp=${CURRENT_TIME},message="ERROR: Database connection failed" \
    timestamp=$((CURRENT_TIME + 1000)),message="CRITICAL: Application crash detected"
```

3. **Manual Test**: Trigger the Lambda function manually to test the complete workflow:

```bash
# Get function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name simple-log-analysis-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Invoke the function
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{}' \
    response.json

# Check the response
cat response.json
```

## Monitoring and Validation

### CloudWatch Dashboards
Monitor your log analysis solution using CloudWatch:
- Lambda function execution metrics
- SNS delivery metrics
- CloudWatch Logs Insights query performance

### Testing Error Detection
Create various log patterns to test the system:

```bash
# Different error levels
aws logs put-log-events \
    --log-group-name ${LOG_GROUP_NAME} \
    --log-stream-name "error-testing" \
    --log-events \
    timestamp=$(date +%s000),message="ERROR: Service timeout occurred" \
    timestamp=$(date +%s000),message="CRITICAL: Memory allocation failed" \
    timestamp=$(date +%s000),message="ERROR: Authentication failed for user"
```

## Troubleshooting

### Common Issues

1. **Email Not Received**: Check spam folder and ensure SNS subscription is confirmed
2. **Lambda Timeout**: Increase Lambda timeout in the configuration (current: 60 seconds)
3. **Permission Errors**: Verify IAM roles have necessary permissions
4. **No Error Detection**: Check CloudWatch Logs Insights query syntax and log format

### Debug Commands

```bash
# Check Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# View recent Lambda executions
aws logs filter-log-events \
    --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
    --start-time $(date -d '1 hour ago' +%s)000

# Test SNS topic
aws sns publish \
    --topic-arn ${SNS_TOPIC_ARN} \
    --message "Test notification" \
    --subject "Test Alert"
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name simple-log-analysis-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name simple-log-analysis-stack
```

### Using CDK
```bash
# From the CDK directory (TypeScript or Python)
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
# From the Terraform directory
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Cost Optimization

### Cost Factors
- **CloudWatch Logs Storage**: $0.50 per GB ingested, $0.03 per GB stored
- **CloudWatch Logs Insights**: $0.005 per GB scanned
- **Lambda Invocations**: First 1M requests free, then $0.20 per 1M requests
- **SNS Messages**: First 1,000 free, then $0.50 per 1M messages
- **EventBridge Rules**: First 14M events free, then $1.00 per 1M events

### Optimization Tips
- Set appropriate log retention periods (default: 7 days)
- Optimize CloudWatch Logs Insights queries to scan minimal data
- Use log sampling for high-volume applications
- Consider using CloudWatch Logs subscription filters for real-time processing

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Lambda execution role has minimal required permissions
- **Resource-Level Permissions**: SNS publish permissions limited to specific topic
- **Encryption**: CloudWatch Logs encrypted at rest by default
- **VPC Security**: Lambda function can be deployed in VPC if required (modify configuration)

## Customization Examples

### Custom Log Patterns
Modify the Lambda function to detect specific patterns:

```python
# Example: Detect specific application errors
query = '''
fields @timestamp, @message
| filter @message like /DatabaseException|TimeoutError|OutOfMemoryError/
| sort @timestamp desc
| limit 100
'''
```

### Multiple Log Groups
Extend the solution to monitor multiple log groups:

```python
log_groups = [
    '/aws/lambda/app1',
    '/aws/lambda/app2',
    '/aws/ecs/service1'
]
```

### Advanced Alerting
Implement threshold-based alerting:

```python
# Alert only if error count exceeds threshold
error_threshold = 5
if error_count > error_threshold:
    # Send alert
```

## Integration Examples

### Slack Integration
Add Slack webhook support alongside email notifications:

```python
import requests

slack_webhook_url = os.environ['SLACK_WEBHOOK_URL']
slack_payload = {
    "text": f"🚨 Log Analysis Alert: {error_count} errors detected"
}
requests.post(slack_webhook_url, json=slack_payload)
```

### PagerDuty Integration
Integrate with PagerDuty for incident management:

```python
import pdpyras

session = pdpyras.APISession(os.environ['PAGERDUTY_API_KEY'])
session.trigger_incident(
    service_id=os.environ['PAGERDUTY_SERVICE_ID'],
    incident={
        'type': 'incident',
        'title': f'Log Analysis Alert: {error_count} errors',
        'body': {'type': 'incident_body', 'details': alert_message}
    }
)
```

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS CloudWatch Logs documentation
3. Refer to the original recipe documentation
4. Check AWS service health dashboard

## Related AWS Documentation

- [CloudWatch Logs User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)