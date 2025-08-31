# Simple Log Analysis with CloudWatch Insights and SNS - CDK Python

This CDK Python application creates a complete automated log monitoring solution that combines CloudWatch Logs Insights with SNS notifications. The solution provides real-time alerting for critical log patterns, enabling proactive incident response and improved system reliability.

## Architecture Overview

The solution includes:

- **CloudWatch Log Group**: Centralized storage for application logs with 7-day retention
- **Lambda Function**: Automated log analysis using CloudWatch Logs Insights queries
- **SNS Topic**: Reliable alert notification delivery via email
- **EventBridge Rule**: Scheduled execution every 5 minutes for continuous monitoring
- **IAM Roles**: Least-privilege security policies for all components

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI v2** installed and configured with appropriate credentials
2. **Python 3.8+** installed on your system
3. **AWS CDK v2** installed (`npm install -g aws-cdk`)
4. **AWS Account** with permissions to create:
   - CloudWatch Logs resources
   - Lambda functions
   - SNS topics
   - EventBridge rules
   - IAM roles and policies
5. **Email address** for receiving log analysis alerts

## Installation and Setup

### 1. Clone and Navigate to Directory

```bash
cd aws/simple-log-analysis-insights-sns/code/cdk-python/
```

### 2. Create Python Virtual Environment

```bash
# Create virtual environment
python -m venv .venv

# Activate virtual environment (Linux/macOS)
source .venv/bin/activate

# Activate virtual environment (Windows)
.venv\\Scripts\\activate
```

### 3. Install Dependencies

```bash
# Upgrade pip to latest version
pip install --upgrade pip

# Install CDK dependencies
pip install -r requirements.txt
```

### 4. Configure AWS Environment

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Set default region (if not already set)
export AWS_DEFAULT_REGION=us-east-1

# Bootstrap CDK (first time only in account/region)
cdk bootstrap
```

## Configuration

### Email Notification Setup

Update the email address for notifications in `cdk.json`:

```json
{
  "context": {
    "email_address": "your-email@example.com"
  }
}
```

### Schedule Configuration

Modify the log analysis frequency in `cdk.json`:

```json
{
  "context": {
    "log_analysis_schedule": "rate(5 minutes)"
  }
}
```

Available schedule formats:
- `rate(5 minutes)` - Every 5 minutes
- `rate(1 hour)` - Every hour
- `cron(0 9 * * ? *)` - Daily at 9 AM UTC

## Deployment

### 1. Synthesize CloudFormation Template

```bash
# Generate CloudFormation template
cdk synth
```

This command:
- Validates your CDK code
- Applies CDK Nag security checks
- Generates CloudFormation template in `cdk.out/`

### 2. Deploy the Stack

```bash
# Deploy to AWS
cdk deploy
```

The deployment process will:
- Create all AWS resources
- Apply security best practices
- Configure monitoring and alerting
- Output resource information

### 3. Confirm Email Subscription

After deployment:
1. Check your email for SNS subscription confirmation
2. Click the confirmation link to enable notifications

## Usage and Testing

### Generate Test Log Events

Create sample log events to test the monitoring system:

```bash
# Get the log group name from CDK output
LOG_GROUP_NAME=$(aws cloudformation describe-stacks \
    --stack-name SimpleLogAnalysisStack \
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

### Manual Function Testing

Test the Lambda function manually:

```bash
# Get the function name from CDK output
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name SimpleLogAnalysisStack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Invoke the function
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{}' \
    response.json

# View the response
cat response.json
```

### Monitor Function Logs

View Lambda function execution logs:

```bash
# View recent logs
aws logs tail /aws/lambda/${FUNCTION_NAME} --follow
```

## Customization

### Modify Log Analysis Query

Update the CloudWatch Logs Insights query in `app.py`:

```python
# Current query looks for ERROR and CRITICAL patterns
query = '''
fields @timestamp, @message
| filter @message like /ERROR|CRITICAL/
| sort @timestamp desc
| limit 100
'''

# Example: Look for specific error codes
query = '''
fields @timestamp, @message
| filter @message like /HTTP 5\d\d|timeout|connection refused/
| sort @timestamp desc
| limit 50
'''
```

### Add Multiple Log Groups

Extend the Lambda function to monitor multiple log groups:

```python
log_groups = [
    "/aws/lambda/app1",
    "/aws/lambda/app2",
    "/aws/apigateway/api1"
]

for log_group in log_groups:
    # Run analysis for each log group
    analyze_log_group(log_group)
```

### Custom Alert Thresholds

Implement dynamic alert thresholds:

```python
# Only alert if error count exceeds threshold
ERROR_THRESHOLD = 5

if error_count > ERROR_THRESHOLD:
    send_sns_alert(error_count, recent_errors)
```

## Monitoring and Observability

### CloudWatch Metrics

The solution automatically creates CloudWatch metrics for:
- Lambda function invocations
- Lambda function errors
- Lambda function duration
- SNS message delivery

### View Metrics Dashboard

```bash
# Create a custom dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "LogAnalysisMonitoring" \
    --dashboard-body file://dashboard.json
```

### Set Up Additional Alarms

```bash
# Create alarm for Lambda function errors
aws cloudwatch put-metric-alarm \
    --alarm-name "LogAnalysisLambdaErrors" \
    --alarm-description "Alert on Lambda function errors" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --dimensions Name=FunctionName,Value=${FUNCTION_NAME}
```

## Security Considerations

This CDK application implements security best practices:

### IAM Policies
- **Least Privilege**: Lambda role has minimal required permissions
- **Resource-Specific**: SNS publish limited to specific topic
- **Service-Scoped**: CloudWatch Logs access scoped appropriately

### Encryption
- **SNS Topic**: Uses AWS managed encryption
- **CloudWatch Logs**: Encrypted at rest by default
- **Lambda Environment**: Variables encrypted with AWS managed keys

### Network Security
- **No VPC**: Serverless components use AWS managed networking
- **HTTPS Only**: All API calls use encrypted connections

### CDK Nag Integration

The application includes CDK Nag for automated security scanning:

```bash
# View security findings during synthesis
cdk synth --verbose
```

## Cost Optimization

### Estimated Costs (monthly)

- **CloudWatch Logs**: $0.50 per GB ingested
- **CloudWatch Logs Insights**: $0.005 per GB scanned
- **Lambda**: $0.20 per 1M requests + $0.0000166667 per GB-second
- **SNS**: $0.50 per 1M notifications
- **EventBridge**: $1.00 per 1M events

**Total estimated cost for typical usage**: $5-15/month

### Cost Optimization Strategies

1. **Log Retention**: Set to 7 days (configurable)
2. **Query Optimization**: Limit query results and time range
3. **Conditional Alerting**: Only send alerts when errors exceed thresholds
4. **Scheduled Analysis**: Adjustable frequency (default: 5 minutes)

## Troubleshooting

### Common Issues

#### 1. Email Not Receiving Alerts

```bash
# Check SNS subscription status
aws sns list-subscriptions-by-topic \
    --topic-arn $(aws cloudformation describe-stacks \
        --stack-name SimpleLogAnalysisStack \
        --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
        --output text)
```

#### 2. Lambda Function Errors

```bash
# View detailed error logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/${FUNCTION_NAME} \
    --filter-pattern "ERROR"
```

#### 3. No Log Events Found

```bash
# Verify log group exists and has data
aws logs describe-log-streams \
    --log-group-name ${LOG_GROUP_NAME}
```

#### 4. CDK Deployment Issues

```bash
# Clear CDK cache
rm -rf cdk.out/

# Re-run synthesis
cdk synth --verbose

# Check for CDK Nag issues
cdk synth | grep -i "warning\|error"
```

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
# Destroy the CDK stack
cdk destroy

# Confirm deletion when prompted
# Type 'y' and press Enter
```

This will remove:
- All AWS resources created by the stack
- CloudFormation stack
- Associated IAM roles and policies

**Note**: Log data in CloudWatch Logs will be permanently deleted.

## Development

### Code Quality

```bash
# Format code with Black
black app.py

# Lint with flake8
flake8 app.py

# Type checking with mypy
mypy app.py
```

### Testing

```bash
# Install test dependencies
pip install -e .[dev]

# Run tests (if implemented)
pytest tests/ -v

# Run with coverage
pytest tests/ --cov=. --cov-report=html
```

### Pre-commit Hooks

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

## Additional Resources

- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [AWS CDK Best Practices](https://docs.aws.amazon.com/cdk/v2/guide/best-practices.html)
- [CDK Nag Documentation](https://github.com/cdklabs/cdk-nag)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## Support

For issues with this CDK application:

1. Check the troubleshooting section above
2. Review AWS CloudFormation stack events
3. Examine Lambda function logs in CloudWatch
4. Refer to AWS CDK documentation
5. Check AWS service health dashboard