# Simple Website Uptime Monitoring - CDK Python

This directory contains a AWS CDK Python application that creates an automated website uptime monitoring system using Route53 health checks, CloudWatch alarms, and SNS email notifications.

## Architecture Overview

The solution creates:
- **Route53 Health Check**: Monitors website availability from multiple global locations
- **CloudWatch Alarms**: Triggers notifications on health status changes
- **SNS Topic**: Delivers email notifications for both downtime and recovery events

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Python 3.8 or higher
- Node.js 18.x or higher (for CDK CLI)
- AWS CDK CLI installed (`npm install -g aws-cdk`)

### Required AWS Permissions

Your AWS credentials need permissions for:
- Route53 (health checks)
- CloudWatch (alarms and metrics)
- SNS (topics and subscriptions)
- CloudFormation (stack operations)

## Quick Start

### 1. Install Dependencies

```bash
# Install Python dependencies
pip install -r requirements.txt

# Verify CDK installation
cdk --version
```

### 2. Configure Monitoring Parameters

Set environment variables for your monitoring configuration:

```bash
# Required: Website to monitor and admin email
export WEBSITE_URL="https://your-website.com"
export ADMIN_EMAIL="admin@your-domain.com"

# Optional: AWS account and region (defaults to current AWS CLI configuration)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
```

Alternatively, you can pass these as CDK context parameters:

```bash
cdk deploy -c website_url=https://your-website.com -c admin_email=admin@your-domain.com
```

### 3. Bootstrap CDK (First Time Only)

If this is your first CDK deployment in this AWS account/region:

```bash
cdk bootstrap
```

### 4. Deploy the Monitoring Stack

```bash
# Preview the resources that will be created
cdk synth

# Deploy the stack
cdk deploy

# Deploy with auto-approval (skip confirmation prompts)
cdk deploy --require-approval never
```

### 5. Confirm Email Subscription

After deployment:
1. Check your email for an AWS SNS subscription confirmation
2. Click "Confirm subscription" in the email
3. You will now receive uptime monitoring alerts

## Configuration Options

### Website URL

The application supports both HTTP and HTTPS websites:

```bash
# HTTPS website (recommended)
export WEBSITE_URL="https://example.com"

# HTTP website
export WEBSITE_URL="http://example.com"
```

The CDK application automatically:
- Extracts the domain name from the URL
- Configures the correct port (80 for HTTP, 443 for HTTPS)
- Enables SNI for HTTPS health checks

### Health Check Parameters

The Route53 health check is configured with:
- **Check Interval**: 30 seconds
- **Failure Threshold**: 3 consecutive failures
- **Global Monitoring**: Multiple AWS regions
- **Path**: "/" (root path)

### CloudWatch Alarms

Two alarms are created:
1. **Downtime Alarm**: Triggers when health check fails (threshold < 1)
2. **Recovery Alarm**: Triggers when website recovers (requires 2 consecutive successes)

## Verification

After deployment, verify the monitoring system:

### 1. Check Health Check Status

```bash
# Get health check ID from CDK output
HEALTH_CHECK_ID=$(aws cloudformation describe-stacks \
    --stack-name uptime-monitoring-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`HealthCheckId`].OutputValue' \
    --output text)

# Check current health status
aws route53 get-health-check-status --health-check-id $HEALTH_CHECK_ID
```

### 2. Verify SNS Subscription

```bash
# Get SNS topic ARN from CDK output
TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name uptime-monitoring-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
    --output text)

# Check subscription status
aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN
```

### 3. View CloudWatch Alarms

```bash
# List all monitoring alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix "Website-"
```

## Monitoring and Maintenance

### Viewing Metrics

Access CloudWatch metrics for your health check:

```bash
# View health check metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Route53 \
    --metric-name HealthCheckStatus \
    --dimensions Name=HealthCheckId,Value=$HEALTH_CHECK_ID \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Minimum,Maximum
```

### Cost Optimization

Estimated monthly costs (US East 1):
- Route53 Health Check: ~$0.50/month
- CloudWatch Alarms: ~$0.20/month (2 alarms)
- SNS Notifications: ~$0.06/month (up to 1000 emails)
- **Total**: ~$0.76/month

### Updating Configuration

To modify the monitored website or email:

```bash
# Update environment variables
export WEBSITE_URL="https://new-website.com"
export ADMIN_EMAIL="new-admin@domain.com"

# Redeploy with new configuration
cdk deploy
```

## Cleanup

To remove all monitoring resources:

```bash
# Delete the CDK stack
cdk destroy

# Confirm deletion when prompted
```

This will remove:
- Route53 health check
- CloudWatch alarms
- SNS topic and subscription
- All associated resources

## Troubleshooting

### Common Issues

1. **Email subscription not confirmed**:
   - Check spam folder for AWS SNS confirmation email
   - Resend confirmation: `aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint your-email@domain.com`

2. **Health check failing for valid website**:
   - Verify website is accessible from multiple locations
   - Check if website requires specific headers or authentication
   - Review Route53 health check failure reasons in AWS Console

3. **CDK deployment fails**:
   - Ensure AWS credentials have sufficient permissions
   - Check if CDK bootstrap was completed
   - Verify unique stack name if deploying multiple instances

### Debugging

Enable CDK debug output:

```bash
# Deploy with verbose logging
cdk deploy --verbose

# View CDK app logs
cdk synth --verbose
```

### Support

For issues with this CDK application:
1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review [Route53 health check troubleshooting](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover-problems.html)
3. Consult [CloudWatch alarms guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)

## Advanced Configuration

### Multiple Websites

To monitor multiple websites, deploy separate stacks:

```bash
# Deploy stack for first website
cdk deploy -c website_url=https://site1.com -c admin_email=admin@domain.com --stack-name uptime-monitoring-site1

# Deploy stack for second website  
cdk deploy -c website_url=https://site2.com -c admin_email=admin@domain.com --stack-name uptime-monitoring-site2
```

### Custom Health Check Path

Modify the `resource_path` in the CDK code to monitor specific endpoints:

```python
# In app.py, modify the health check configuration
resource_path="/health",  # Instead of "/"
```

### Enhanced Notifications

The SNS topic can be extended to support:
- SMS notifications
- Slack/Teams webhooks
- Lambda function triggers
- SQS queue integration

Add additional subscriptions in the CDK code:

```python
# Add SMS subscription
self.alert_topic.add_subscription(
    sns_subscriptions.SmsSubscription("+1234567890")
)
```

## Security Considerations

This monitoring solution follows AWS security best practices:

- **CDK Nag Integration**: Validates security configurations
- **Least Privilege**: IAM roles have minimal required permissions
- **No Sensitive Data**: Monitoring alerts contain only operational status
- **Encrypted Transit**: All AWS API calls use HTTPS

The solution suppresses `AwsSolutions-SNS3` (SSL enforcement) as the SNS topic contains only operational monitoring data and is used for internal notifications.