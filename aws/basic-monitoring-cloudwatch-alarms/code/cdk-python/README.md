# Basic CloudWatch Monitoring CDK Python Application

This directory contains a complete AWS CDK (Cloud Development Kit) Python application for implementing basic CloudWatch monitoring with alarms and SNS notifications, based on the "Basic Monitoring with CloudWatch Alarms" recipe.

## Overview

This CDK application creates a comprehensive monitoring solution that includes:

- **SNS Topic**: For centralized alarm notifications
- **Email Subscription**: To receive alerts via email
- **CloudWatch Alarms**: For monitoring various AWS services
  - EC2 CPU utilization alarm
  - ALB response time alarm
  - RDS database connections alarm

## Architecture

The solution follows AWS best practices for monitoring and alerting:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CloudWatch    │    │   CloudWatch    │    │   SNS Topic     │
│   Metrics       │───▶│   Alarms        │───▶│   Notifications │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
                                              ┌─────────────────┐
                                              │ Email Recipients│
                                              │                 │
                                              └─────────────────┘
```

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured
- Python 3.8 or higher
- Node.js (for CDK CLI)
- AWS CDK CLI installed (`npm install -g aws-cdk`)

## Installation

1. **Clone and navigate to the directory**:
   ```bash
   cd aws/basic-monitoring-cloudwatch-alarms/code/cdk-python/
   ```

2. **Create a virtual environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

## Configuration

### Method 1: Environment Variables

```bash
export NOTIFICATION_EMAIL="your-email@example.com"
export CDK_DEFAULT_REGION="us-east-1"
export CDK_DEFAULT_ACCOUNT="123456789012"
```

### Method 2: CDK Context

```bash
cdk deploy --context notification_email=your-email@example.com
```

### Method 3: Parameter (Interactive)

If no email is specified, the stack will prompt for the notification email during deployment.

## Deployment

### Quick Start

```bash
# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy
```

### With Specific Email

```bash
cdk deploy --parameters NotificationEmail=your-email@example.com
```

### Preview Changes

```bash
cdk diff
```

### Synthesize CloudFormation Template

```bash
cdk synth
```

## Usage

### Confirming Email Subscription

After deployment, you'll receive a subscription confirmation email. Click the confirmation link to start receiving alarm notifications.

### Testing Alarms

You can manually test the alarms using the AWS CLI:

```bash
# Trigger CPU alarm
aws cloudwatch set-alarm-state \
    --alarm-name "HighCPUUtilization" \
    --state-value ALARM \
    --state-reason "Testing alarm notification"

# Reset alarm
aws cloudwatch set-alarm-state \
    --alarm-name "HighCPUUtilization" \
    --state-value OK \
    --state-reason "Test completed"
```

### Monitoring Alarms

Check alarm status:

```bash
aws cloudwatch describe-alarms \
    --alarm-names "HighCPUUtilization" "HighResponseTime" "HighDBConnections"
```

## Customization

### Adding New Alarms

Extend the `BasicMonitoringStack` class in `app.py`:

```python
def _create_custom_alarm(self) -> None:
    """Create a custom CloudWatch alarm."""
    custom_alarm = cloudwatch.Alarm(
        self,
        "CustomAlarm",
        alarm_name="CustomMetricAlarm",
        alarm_description="Custom alarm description",
        metric=cloudwatch.Metric(
            namespace="AWS/Lambda",
            metric_name="Errors",
            statistic="Sum",
            period=cdk.Duration.minutes(5),
        ),
        threshold=10.0,
        comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        evaluation_periods=2,
    )
    
    custom_alarm.add_alarm_action(
        cloudwatch.SnsAction(self.alarm_topic)
    )
```

### Modifying Thresholds

Update the alarm thresholds in the respective methods:

```python
# In _create_ec2_cpu_alarm()
threshold=80.0,  # Change to desired CPU percentage

# In _create_alb_response_time_alarm()
threshold=1.0,   # Change to desired response time in seconds

# In _create_rds_connection_alarm()
threshold=80.0,  # Change to desired connection count
```

### Adding Multiple Notification Channels

```python
# Add SMS notifications
self.alarm_topic.add_subscription(
    subscriptions.SmsSubscription("+1234567890")
)

# Add SQS queue subscription
self.alarm_topic.add_subscription(
    subscriptions.SqsSubscription(queue)
)
```

## Development

### Code Quality

Run linting and formatting:

```bash
# Format code
black .

# Lint code
flake8 .

# Type checking
mypy .

# Security scanning
bandit -r .
```

### Testing

```bash
# Run unit tests
pytest tests/unit/ -v

# Run integration tests
pytest tests/integration/ -v

# Run all tests with coverage
pytest --cov=app --cov-report=html
```

### Security Scanning

```bash
# Run CDK security scanning
cdk-nag --app "python app.py"
```

## Troubleshooting

### Common Issues

1. **Email not received**: Check spam folder and ensure email confirmation was clicked
2. **Alarm not triggering**: Verify resources exist and metrics are being published
3. **Permission errors**: Ensure AWS credentials have necessary CloudWatch and SNS permissions

### Debug Mode

Enable verbose logging:

```bash
export CDK_DEBUG=true
cdk deploy --verbose
```

### Checking Alarm States

```bash
aws cloudwatch describe-alarms \
    --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}'
```

## Cost Optimization

- **CloudWatch Alarms**: $0.10 per alarm per month
- **SNS Email**: First 1,000 emails free, then $2.00 per 100,000 emails
- **Total Monthly Cost**: ~$0.30 for basic setup

## Cleanup

Remove all resources:

```bash
cdk destroy
```

## Stack Outputs

After deployment, the stack provides these outputs:

- **SNSTopicArn**: ARN of the notification topic
- **SNSTopicName**: Name of the notification topic
- **CPUAlarmName**: Name of the CPU alarm
- **ResponseTimeAlarmName**: Name of the response time alarm
- **DBConnectionAlarmName**: Name of the database connection alarm

## Best Practices

1. **Alarm Naming**: Use descriptive names with consistent patterns
2. **Thresholds**: Set based on historical data and business requirements
3. **Evaluation Periods**: Use multiple periods to reduce false positives
4. **Notifications**: Separate topics for different severity levels
5. **Tagging**: Tag all resources for cost tracking and organization

## Additional Resources

- [AWS CDK Python Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)
- [CloudWatch Alarms Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [SNS Documentation](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
- [AWS CDK API Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and linting
5. Submit a pull request

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.

## Support

For issues and questions:
- Create an issue in the repository
- Consult the AWS CDK documentation
- Check the AWS CloudWatch troubleshooting guide