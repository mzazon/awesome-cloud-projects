# CDK Python - Simple Resource Monitoring with CloudWatch and SNS

This directory contains a complete CDK Python implementation for the "Simple Resource Monitoring with CloudWatch and SNS" recipe. The application creates a foundational monitoring solution that sends email notifications when EC2 CPU utilization exceeds defined thresholds.

## Architecture

The CDK application deploys the following AWS resources:

- **EC2 Instance**: t3.micro instance with detailed monitoring enabled
- **IAM Role**: EC2 service role with Systems Manager permissions
- **Security Group**: Basic security group allowing HTTPS outbound
- **SNS Topic**: Notification topic for alarm messages
- **Email Subscription**: Email endpoint for receiving alerts
- **CloudWatch Alarm**: CPU utilization alarm with 70% threshold

## Prerequisites

1. **AWS CLI**: Installed and configured with appropriate permissions
2. **Python 3.8+**: CDK requires Python 3.8 or later
3. **AWS CDK**: Install globally with `npm install -g aws-cdk`
4. **AWS Account**: Access to create EC2, CloudWatch, SNS, and IAM resources
5. **Email Address**: Valid email for receiving alarm notifications

## Installation

1. **Clone or navigate to this directory**:
   ```bash
   cd aws/simple-resource-monitoring-cloudwatch-sns/code/cdk-python/
   ```

2. **Create Python virtual environment** (recommended):
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK** (first time only in account/region):
   ```bash
   cdk bootstrap
   ```

## Deployment

### Basic Deployment

Deploy with email address as environment variable:

```bash
export EMAIL_ADDRESS="your-email@example.com"
cdk deploy
```

### Advanced Deployment with Custom Parameters

Deploy with custom instance type and CPU threshold:

```bash
export EMAIL_ADDRESS="your-email@example.com"
cdk deploy -c instance_type=t3.small -c cpu_threshold=80.0
```

### Available Context Parameters

- `email_address`: Email address for notifications (required)
- `instance_type`: EC2 instance type (default: t3.micro)
- `cpu_threshold`: CPU percentage threshold for alarm (default: 70.0)

## Post-Deployment Steps

1. **Confirm Email Subscription**:
   - Check your email inbox for SNS subscription confirmation
   - Click the confirmation link to activate notifications

2. **Test the Alarm**:
   Use the provided test command from stack outputs:
   ```bash
   # Get the test command from stack outputs
   aws cloudformation describe-stacks \
       --stack-name SimpleResourceMonitoringStack \
       --query 'Stacks[0].Outputs[?OutputKey==`TestCommand`].OutputValue' \
       --output text
   ```

3. **Monitor Resources**:
   ```bash
   # Check alarm status
   aws cloudwatch describe-alarms \
       --alarm-names $(aws cloudformation describe-stacks \
           --stack-name SimpleResourceMonitoringStack \
           --query 'Stacks[0].Outputs[?OutputKey==`AlarmName`].OutputValue' \
           --output text)
   ```

## Stack Outputs

The deployed stack provides these outputs:

- **InstanceId**: EC2 instance identifier for monitoring
- **SNSTopicArn**: ARN of the notification topic
- **AlarmName**: Name of the CloudWatch alarm
- **EmailAddress**: Configured email address for notifications
- **TestCommand**: AWS CLI command to generate CPU load for testing

## Testing the Solution

### Generate CPU Load

After deployment, test the alarm by generating CPU load:

```bash
# Get instance ID from stack outputs
INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name SimpleResourceMonitoringStack \
    --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
    --output text)

# Generate CPU load for 10 minutes
aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --instance-ids $INSTANCE_ID \
    --parameters 'commands=["stress-ng --cpu 4 --timeout 600s"]'
```

### Monitor Alarm State

Watch the alarm state change from OK to ALARM:

```bash
# Get alarm name from stack outputs
ALARM_NAME=$(aws cloudformation describe-stacks \
    --stack-name SimpleResourceMonitoringStack \
    --query 'Stacks[0].Outputs[?OutputKey==`AlarmName`].OutputValue' \
    --output text)

# Monitor alarm state
aws cloudwatch describe-alarms --alarm-names $ALARM_NAME \
    --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason]' \
    --output table
```

## Customization

### Modify CPU Threshold

Change the CPU threshold by updating the context parameter:

```bash
cdk deploy -c cpu_threshold=85.0
```

### Use Different Instance Type

Deploy with a larger instance for different testing scenarios:

```bash
cdk deploy -c instance_type=t3.medium
```

### Add Additional Alarms

Extend the `SimpleResourceMonitoringStack` class to include additional metrics:

```python
# Example: Add memory alarm (requires CloudWatch agent)
memory_alarm = cloudwatch.Alarm(
    self,
    "HighMemoryAlarm",
    alarm_name=f"high-memory-{unique_suffix}",
    metric=cloudwatch.Metric(
        namespace="CWAgent",
        metric_name="mem_used_percent",
        dimensions_map={"InstanceId": instance.instance_id}
    ),
    threshold=80.0,
    evaluation_periods=2
)
```

## Cleanup

Remove all resources created by the stack:

```bash
cdk destroy
```

Confirm the deletion when prompted. This will remove:
- CloudWatch alarm
- SNS topic and subscription
- EC2 instance
- Security group
- IAM role

## Troubleshooting

### Common Issues

1. **Email Not Confirmed**:
   - Check spam folder for confirmation email
   - Ensure email address is correctly specified
   - Re-deploy if needed with correct email

2. **Instance Not Generating Metrics**:
   - Wait 5-10 minutes after deployment
   - Verify instance is running
   - Check CloudWatch console for metrics

3. **SSM Command Fails**:
   - Verify instance has internet connectivity
   - Check IAM role has SSM permissions
   - Manually install stress-ng if needed

4. **Permission Errors**:
   - Ensure AWS credentials have necessary permissions
   - Check CDK bootstrap was completed
   - Verify account limits for resources

### Debug Commands

```bash
# Check stack events
aws cloudformation describe-stack-events \
    --stack-name SimpleResourceMonitoringStack

# View detailed alarm information
aws cloudwatch describe-alarms \
    --alarm-names $ALARM_NAME

# Check EC2 instance status
aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]'
```

## Cost Considerations

**Estimated monthly costs** (US East):
- EC2 t3.micro: ~$8.50 (if running continuously)
- CloudWatch alarm: $0.10
- SNS email notifications: Free (first 1,000/month)
- **Total**: ~$8.60/month

**Cost optimization tips**:
- Stop EC2 instance when not testing
- Use t3.nano for minimal testing
- Delete stack after testing to avoid charges

## Security Best Practices

This implementation follows AWS security best practices:

- **Least Privilege IAM**: EC2 role has minimal required permissions
- **Security Groups**: Restrictive inbound rules, necessary outbound only
- **Email Validation**: SNS subscription requires email confirmation
- **Detailed Monitoring**: Enhanced visibility without exposing sensitive data

## Next Steps

Enhance this basic monitoring solution by:

1. **Add Custom Metrics**: Install CloudWatch agent for memory/disk monitoring
2. **Multi-Instance Monitoring**: Extend to monitor multiple EC2 instances
3. **Advanced Notifications**: Add Slack, SMS, or webhook endpoints
4. **Automated Responses**: Integrate with Lambda for auto-remediation
5. **Dashboard Creation**: Build CloudWatch dashboards for visualization

## Support

For issues with this CDK implementation:

1. Check the [original recipe documentation](../simple-resource-monitoring-cloudwatch-sns.md)
2. Review [AWS CDK Python documentation](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)
3. Consult [AWS CloudWatch documentation](https://docs.aws.amazon.com/cloudwatch/)
4. Visit [AWS SNS documentation](https://docs.aws.amazon.com/sns/)

## License

This code is provided as part of the AWS recipes collection under the MIT license.