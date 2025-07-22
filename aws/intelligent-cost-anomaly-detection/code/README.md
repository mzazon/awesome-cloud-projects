# Infrastructure as Code for Intelligent Cost Anomaly Detection

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Cost Anomaly Detection".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Cost Explorer and Cost Anomaly Detection
  - Lambda functions and IAM roles
  - SNS topics and subscriptions
  - CloudWatch dashboards and metrics
  - EventBridge rules and targets
- At least 24 hours of AWS usage history for anomaly detection training
- Estimated cost: $5-15/month for CloudWatch metrics, Lambda executions, and SNS notifications

> **Note**: Cost Anomaly Detection service is free, but associated services like CloudWatch custom metrics and Lambda invocations incur standard charges.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name cost-anomaly-detection \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=EmailAddress,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name cost-anomaly-detection

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name cost-anomaly-detection \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Set email parameter
export EMAIL_ADDRESS=your-email@example.com

# Deploy the stack
cdk deploy --parameters emailAddress=${EMAIL_ADDRESS}

# View outputs
cdk outputs
```

### Using CDK Python
```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Set email parameter
export EMAIL_ADDRESS=your-email@example.com

# Deploy the stack
cdk deploy --parameters emailAddress=${EMAIL_ADDRESS}

# View outputs
cdk outputs
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the plan
terraform plan -var="email_address=your-email@example.com"

# Apply the configuration
terraform apply -var="email_address=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set email address for notifications
export EMAIL_ADDRESS=your-email@example.com

# Deploy infrastructure
./scripts/deploy.sh

# View deployment summary
./scripts/deploy.sh --status
```

## Configuration Options

### CloudFormation Parameters
- `EmailAddress`: Email address for cost anomaly notifications (required)
- `AnomalyThreshold`: Dollar threshold for anomaly detection (default: 10.0)
- `MonitorName`: Custom name for the cost monitor (optional)
- `Environment`: Environment tag for resources (default: production)

### CDK Parameters
- `emailAddress`: Email address for notifications
- `anomalyThreshold`: Cost threshold in USD (default: 10.0)
- `environment`: Environment name (default: production)

### Terraform Variables
- `email_address`: Email address for notifications (required)
- `anomaly_threshold`: Cost threshold in USD (default: 10.0)
- `aws_region`: AWS region for deployment (default: us-east-1)
- `environment`: Environment tag (default: production)
- `resource_prefix`: Prefix for resource names (optional)

## Post-Deployment Setup

1. **Confirm Email Subscription**:
   After deployment, check your email for an SNS subscription confirmation and click the confirmation link.

2. **Wait for Learning Period**:
   Cost Anomaly Detection requires 24-48 hours to learn your spending patterns before generating accurate anomalies.

3. **Access CloudWatch Dashboard**:
   Navigate to CloudWatch in the AWS Console to view the custom cost monitoring dashboard.

4. **Test the System**:
   You can test the Lambda function using the test event provided in the deployment outputs.

## Architecture Components

The deployed infrastructure includes:

- **Cost Anomaly Monitor**: Tracks spending patterns for EC2 compute services
- **Cost Anomaly Detector**: Triggers alerts when anomalies exceed threshold
- **Lambda Function**: Processes anomaly events and enriches notifications
- **SNS Topic**: Delivers notifications to subscribers
- **EventBridge Rule**: Routes cost anomaly events to Lambda function
- **CloudWatch Dashboard**: Displays cost metrics and system health
- **IAM Roles and Policies**: Secure access with least privilege

## Monitoring and Alerts

### CloudWatch Metrics
- `AWS/CostAnomaly/AnomalyImpact`: Dollar impact of detected anomalies
- `AWS/CostAnomaly/AnomalyPercentage`: Percentage increase from baseline
- `AWS/Lambda/Invocations`: Lambda function execution count
- `AWS/Lambda/Duration`: Function execution time
- `AWS/Lambda/Errors`: Function error count

### Dashboard Access
```bash
# Get dashboard URL from outputs
aws cloudformation describe-stacks \
    --stack-name cost-anomaly-detection \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
    --output text
```

## Validation and Testing

### Test Lambda Function
```bash
# Get function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name cost-anomaly-detection \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Invoke test
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload file://test-event.json \
    response.json

# Check response
cat response.json
```

### Verify SNS Subscriptions
```bash
# Get SNS topic ARN
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name cost-anomaly-detection \
    --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
    --output text)

# List subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn ${SNS_TOPIC_ARN}
```

## Troubleshooting

### Common Issues

1. **Email Not Received**:
   - Check spam/junk folder
   - Verify email address in parameters
   - Confirm SNS subscription status

2. **Lambda Function Errors**:
   - Check CloudWatch Logs for the Lambda function
   - Verify IAM permissions
   - Review function environment variables

3. **No Anomalies Detected**:
   - Ensure sufficient usage history (24+ hours)
   - Verify Cost Explorer is enabled
   - Check anomaly threshold settings

### Debug Commands
```bash
# Check Lambda logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/cost-anomaly"

# View recent log events
aws logs filter-log-events \
    --log-group-name "/aws/lambda/cost-anomaly-processor" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cost-anomaly-detection

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cost-anomaly-detection
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="email_address=your-email@example.com"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

## Cost Optimization

### Resource Costs
- **Lambda**: Pay per invocation and duration (typically $0.01-0.10/month)
- **SNS**: Pay per notification (typically $0.50/million notifications)
- **CloudWatch**: Custom metrics and dashboard charges (typically $1-5/month)
- **EventBridge**: Pay per rule evaluation (typically $1/million events)

### Cost Controls
- Adjust anomaly threshold to reduce false positives
- Use CloudWatch metric filters to limit custom metrics
- Configure SNS message filtering for specific notification types
- Set up billing alerts for the monitoring infrastructure itself

## Security Considerations

### IAM Permissions
- Lambda execution role follows least privilege principle
- Cost Explorer access limited to read-only operations
- SNS publish permissions restricted to specific topic
- CloudWatch permissions limited to metric publishing

### Data Protection
- Cost data remains within your AWS account
- No sensitive billing information exposed in logs
- Encryption in transit for all service communications
- CloudWatch Logs encrypted by default

## Customization

### Extending Notifications
To add Slack integration:
```bash
# Add Slack webhook URL as parameter
# Modify Lambda function to include Slack notifications
# Update IAM policies if additional services are needed
```

### Multi-Account Setup
For organization-wide monitoring:
- Deploy in management account
- Configure cross-account IAM roles
- Use AWS Organizations Cost Anomaly Detection
- Centralize notifications and reporting

### Additional Monitors
To monitor other services:
- Duplicate monitor configuration
- Adjust monitor dimensions (SERVICE, ACCOUNT, etc.)
- Configure separate thresholds per service
- Create service-specific notification channels

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS Cost Anomaly Detection documentation
3. Consult AWS CloudFormation/CDK/Terraform documentation
4. Review CloudWatch and Lambda troubleshooting guides

## Related Resources

- [AWS Cost Anomaly Detection User Guide](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-anomaly-detection.html)
- [AWS Cost Management Best Practices](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-best-practices.html)
- [CloudWatch Custom Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html)
- [Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)