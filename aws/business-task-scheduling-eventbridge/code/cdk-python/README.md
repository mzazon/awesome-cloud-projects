# AWS CDK Python: Automated Business Task Scheduling

This AWS CDK Python application creates infrastructure for automated business task scheduling using EventBridge Scheduler, Lambda, S3, and SNS.

## Architecture

The application deploys:

- **EventBridge Scheduler**: Three schedules for different business automation patterns
  - Daily reports at 9 AM ET
  - Hourly data processing 
  - Weekly notifications on Mondays at 10 AM ET
- **Lambda Function**: Processes business tasks (Python 3.11 runtime)
- **S3 Bucket**: Stores generated reports and processed data with lifecycle policies
- **SNS Topic**: Sends notifications for task completion and failures
- **IAM Roles**: Least privilege access for EventBridge Scheduler and Lambda

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate permissions
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Virtual environment (recommended)

## Setup

1. **Create and activate virtual environment**:
   ```bash
   python -m venv .venv
   
   # On Windows
   .venv\Scripts\activate
   
   # On macOS/Linux
   source .venv/bin/activate
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Bootstrap CDK (if first time)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

You can customize the deployment by modifying the `context` section in `cdk.json`:

```json
{
  "context": {
    "unique_suffix": "dev123",
    "notification_email": "your-email@example.com"
  }
}
```

- `unique_suffix`: Unique identifier for resource naming (default: "dev123")
- `notification_email`: Email address for SNS notifications (optional)

## Deployment

1. **Synthesize CloudFormation template**:
   ```bash
   cdk synth
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Confirm email subscription** (if configured):
   Check your email and confirm the SNS subscription to receive notifications.

## Usage

After deployment, the system will automatically:

- Generate daily business reports at 9 AM ET
- Process data every hour
- Send weekly status notifications on Mondays at 10 AM ET

### Manual Testing

You can manually invoke the Lambda function to test different task types:

```bash
# Test report generation
aws lambda invoke \
    --function-name business-task-processor-dev123 \
    --payload '{"task_type":"report"}' \
    response.json

# Test data processing
aws lambda invoke \
    --function-name business-task-processor-dev123 \
    --payload '{"task_type":"data_processing"}' \
    response.json

# Test notification
aws lambda invoke \
    --function-name business-task-processor-dev123 \
    --payload '{"task_type":"notification"}' \
    response.json
```

### View Generated Reports

Check the S3 bucket for generated reports:

```bash
aws s3 ls s3://business-automation-dev123/reports/
aws s3 ls s3://business-automation-dev123/processed-data/
```

## Monitoring

The application includes:

- **CloudWatch Logs**: Lambda function logs with configurable retention
- **SNS Notifications**: Success and failure notifications
- **S3 Lifecycle**: Automatic data archiving to reduce costs
- **EventBridge Metrics**: Built-in monitoring for schedule execution

View Lambda logs:
```bash
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/business-task-processor"
```

## Cost Optimization

The application implements several cost optimization features:

- **S3 Lifecycle Policies**: Automatic transition to IA (30 days) and Glacier (90 days)
- **Lambda Memory**: Optimized at 256MB for balance of performance and cost
- **CloudWatch Logs**: 1-month retention to control log storage costs
- **Serverless Architecture**: Pay-per-execution model

Estimated monthly cost for typical usage: $5-15

## Development

### Code Quality

The project includes development dependencies for code quality:

```bash
# Format code
black app.py

# Type checking
mypy app.py

# Linting
flake8 app.py
```

### Testing

```bash
# Run tests (if test files are added)
pytest tests/
```

### Adding New Schedules

To add new schedules, modify the `_create_schedules()` method in `app.py`:

```python
scheduler.Schedule(
    self,
    "CustomSchedule",
    schedule_name="custom-schedule",
    schedule=scheduler.ScheduleExpression.cron(
        minute="0",
        hour="12",
        day="*",
        month="*",
        week_day="*"
    ),
    target=scheduler.ScheduleTargetConfig(
        arn=self.task_processor_function.function_arn,
        role_arn=self.scheduler_role.role_arn,
        input='{"task_type": "custom_task"}'
    ),
    description="Custom business task schedule"
)
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have necessary permissions
2. **Email Not Received**: Check spam folder and confirm SNS subscription
3. **Lambda Timeouts**: Increase timeout if processing larger datasets
4. **Schedule Not Triggering**: Verify timezone settings and schedule expressions

### Debug Lambda Function

```bash
# View recent logs
aws logs tail /aws/lambda/business-task-processor-dev123 --follow

# Check function configuration
aws lambda get-function --function-name business-task-processor-dev123
```

### View EventBridge Schedules

```bash
# List all schedules
aws scheduler list-schedules

# Get specific schedule details
aws scheduler get-schedule --name daily-report-schedule
```

## Cleanup

To destroy all resources:

```bash
cdk destroy
```

This will remove all AWS resources created by the stack, including S3 bucket contents.

## Security

The application follows AWS security best practices:

- **Least Privilege IAM**: Minimal permissions for each service
- **Encryption**: S3 server-side encryption enabled
- **VPC**: Can be deployed in VPC for additional network isolation
- **Resource Isolation**: Unique resource names prevent conflicts

## Support

For issues related to:
- **AWS CDK**: [CDK GitHub Repository](https://github.com/aws/aws-cdk)
- **EventBridge Scheduler**: [AWS Documentation](https://docs.aws.amazon.com/scheduler/)
- **Lambda**: [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)

## License

This sample code is provided under the MIT-0 License. See the LICENSE file for details.