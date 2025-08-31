# AWS CDK Python - Trusted Advisor Monitoring

This CDK Python application creates AWS infrastructure to monitor AWS Trusted Advisor optimization recommendations and send email alerts when opportunities are identified.

## Architecture

The application deploys:

- **SNS Topic**: For sending optimization alerts via email
- **CloudWatch Alarms**: Monitor Trusted Advisor metrics for different check types
  - Cost Optimization: Monitors EC2 instance utilization
  - Security: Monitors security group configurations
  - Service Limits: Monitors AWS service quota usage
- **Email Subscription**: Automatically subscribes email addresses to receive alerts

## Prerequisites

### AWS Requirements

- AWS account with **Business, Enterprise On-Ramp, or Enterprise Support plan** (required for full Trusted Advisor access)
- AWS CLI v2 installed and configured
- CDK CLI installed (`npm install -g aws-cdk`)
- Python 3.8 or higher

### Permissions Required

Your AWS credentials need permissions for:
- CloudWatch (alarms, metrics)
- SNS (topic creation, subscriptions)
- CloudFormation (stack operations)
- IAM (for CDK service roles)

### Important Region Note

**This application MUST be deployed to `us-east-1`** because AWS Trusted Advisor publishes all metrics exclusively to the US East (N. Virginia) region, regardless of where your resources are located.

## Installation and Setup

### 1. Create Python Virtual Environment

```bash
# Navigate to the CDK directory
cd ./aws/account-optimization-trusted-advisor-cloudwatch/code/cdk-python/

# Create virtual environment
python3 -m venv .venv

# Activate virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\Scripts\activate.bat
```

### 2. Install Dependencies

```bash
# Install Python dependencies
pip install -r requirements.txt

# Install CDK CLI if not already installed
npm install -g aws-cdk
```

### 3. Bootstrap CDK (if first time using CDK in this account/region)

```bash
# Bootstrap CDK in us-east-1 (required for Trusted Advisor)
cdk bootstrap aws://ACCOUNT-NUMBER/us-east-1
```

## Deployment

### Option 1: Deploy with Email Parameter

```bash
# Deploy with email address parameter
cdk deploy --parameters EmailAddress=your-email@company.com
```

### Option 2: Deploy with Context Variables

```bash
# Set email in CDK context
cdk deploy --context email_address=your-email@company.com \
           --context environment=production \
           --context cost_center=IT
```

### Option 3: Interactive Deployment

```bash
# Deploy and enter email when prompted
cdk deploy
```

During deployment, you'll be prompted to enter your email address if not provided via parameters or context.

## Post-Deployment Steps

### 1. Confirm Email Subscription

After deployment:

1. Check your email inbox for an SNS subscription confirmation
2. Click the "Confirm subscription" link in the email
3. You should see a confirmation page in your browser

### 2. Verify Deployment

Check the created resources:

```bash
# List CloudWatch alarms
aws cloudwatch describe-alarms \
    --region us-east-1 \
    --alarm-name-prefix trusted-advisor

# Check SNS topic
aws sns list-topics --region us-east-1 | grep trusted-advisor

# View stack outputs
aws cloudformation describe-stacks \
    --region us-east-1 \
    --stack-name TrustedAdvisorMonitoringStack \
    --query 'Stacks[0].Outputs'
```

### 3. Test Notifications

Send a test message to verify email delivery:

```bash
# Get SNS topic ARN from stack outputs
TOPIC_ARN=$(aws cloudformation describe-stacks \
    --region us-east-1 \
    --stack-name TrustedAdvisorMonitoringStack \
    --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
    --output text)

# Send test notification
aws sns publish \
    --region us-east-1 \
    --topic-arn $TOPIC_ARN \
    --message "Test notification: AWS Account Optimization Monitoring is active" \
    --subject "AWS Trusted Advisor - Test Alert"
```

## Monitoring and Validation

### View CloudWatch Alarms

Access the CloudWatch console to monitor alarm states:

```bash
# Get dashboard URL from stack outputs
aws cloudformation describe-stacks \
    --region us-east-1 \
    --stack-name TrustedAdvisorMonitoringStack \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudWatchDashboardURL`].OutputValue' \
    --output text
```

### Check Trusted Advisor Metrics

Verify that Trusted Advisor is publishing metrics:

```bash
# List available Trusted Advisor metrics
aws cloudwatch list-metrics \
    --region us-east-1 \
    --namespace AWS/TrustedAdvisor \
    --output table

# Get metric data for cost optimization
aws cloudwatch get-metric-statistics \
    --region us-east-1 \
    --namespace AWS/TrustedAdvisor \
    --metric-name YellowResources \
    --dimensions Name=CheckName,Value="Low Utilization Amazon EC2 Instances" \
    --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average
```

## Customization

### Adding More Trusted Advisor Checks

To monitor additional Trusted Advisor checks, modify `app.py`:

```python
# Example: Add IAM access key rotation monitoring
iam_alarm = cloudwatch.Alarm(
    self,
    "IAMAccessKeyRotationAlarm",
    alarm_name=f"{resource_prefix_param.value_as_string}-iam-keys",
    alarm_description="Alert when IAM access keys need rotation",
    metric=cloudwatch.Metric(
        namespace="AWS/TrustedAdvisor",
        metric_name="YellowResources",
        statistic="Average",
        period=Duration.minutes(5),
        dimensions_map={
            "CheckName": "IAM Access Key Rotation"
        }
    ),
    threshold=1,
    comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    evaluation_periods=1
)

# Add SNS action
iam_alarm.add_alarm_action(cloudwatch.SnsAction(self.alert_topic))
```

### Multiple Email Recipients

To add multiple email addresses:

```python
# In the stack constructor, add multiple subscriptions
email_list = ["ops@company.com", "security@company.com", "finance@company.com"]

for email in email_list:
    self.alert_topic.add_subscription(
        sns_subscriptions.EmailSubscription(email_address=email)
    )
```

### Environment-Specific Configuration

Use CDK context for environment-specific settings:

```bash
# Development environment
cdk deploy --context environment=development \
           --context email_address=dev-ops@company.com \
           --context cost_center=DevOps

# Production environment
cdk deploy --context environment=production \
           --context email_address=prod-ops@company.com \
           --context cost_center=Operations
```

## Cost Optimization

### Expected Costs

- **SNS Email Delivery**: $0.50 - $2.00/month (depending on alert frequency)
- **CloudWatch Alarms**: $0.10/alarm/month × 3 alarms = $0.30/month
- **Total Estimated Monthly Cost**: $0.80 - $2.30

### Cost Management

1. **Monitor Alert Frequency**: Review SNS usage in billing console
2. **Optimize Alarm Periods**: Increase evaluation periods if alerts are too frequent
3. **Use SNS Message Filtering**: Filter messages by severity if needed

## Troubleshooting

### Common Issues

1. **Email Not Received**
   - Check spam/junk folder
   - Verify email address spelling
   - Confirm SNS subscription status

2. **Alarms in INSUFFICIENT_DATA State**
   - Normal for new deployments
   - Trusted Advisor metrics update several times daily
   - Wait 2-4 hours for first metrics

3. **Deployment Fails**
   - Ensure you're deploying to `us-east-1`
   - Verify AWS credentials have required permissions
   - Check CDK bootstrap status

### Debugging Commands

```bash
# Check CDK app synthesis
cdk synth

# View CloudFormation template
cdk synth > template.json

# Compare with deployed stack
cdk diff

# View CDK logs
cdk deploy --verbose
```

## Security Best Practices

### IAM Permissions

The CDK will create minimal IAM roles with least-privilege permissions:

- CloudWatch alarms can only publish to the specific SNS topic
- SNS topic can only be accessed by CloudWatch alarms
- No cross-account access is granted

### Email Security

- SNS subscriptions require email confirmation
- Unsubscribe links are included in all emails
- Email addresses are not exposed in CloudFormation outputs

### Monitoring Security

- All resources are tagged for tracking
- CloudFormation stack events are logged
- SNS delivery failures are tracked in CloudWatch

## Cleanup

To remove all resources:

```bash
# Delete the CDK stack
cdk destroy

# Confirm deletion when prompted
# This will remove:
# - All CloudWatch alarms
# - SNS topic and subscriptions
# - Associated IAM roles and policies
```

## Support and Documentation

### AWS Documentation

- [AWS Trusted Advisor User Guide](https://docs.aws.amazon.com/awssupport/latest/user/trusted-advisor.html)
- [CloudWatch Trusted Advisor Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch-ta.html)
- [SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
- [CDK Python Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)

### Additional Resources

- [AWS Cost Optimization Best Practices](https://docs.aws.amazon.com/awssupport/latest/user/cost-optimization-checks.html)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)

## Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Make changes following Python and CDK best practices
4. Test deployment in a development environment
5. Submit a pull request with detailed description

## License

This project is licensed under the MIT License. See LICENSE file for details.