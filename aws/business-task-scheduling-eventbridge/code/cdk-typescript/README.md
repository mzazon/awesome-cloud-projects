# Business Task Scheduling CDK TypeScript Application

This CDK TypeScript application deploys an automated business task scheduling system using AWS EventBridge Scheduler and Lambda functions. The system automates recurring business tasks like report generation, data processing, and notification delivery.

## Architecture Overview

The application creates:

- **EventBridge Scheduler**: Manages three different schedule types (daily, hourly, weekly)
- **Lambda Function**: Processes business tasks including report generation and data processing
- **S3 Bucket**: Stores generated reports and processed data with versioning and encryption
- **SNS Topic**: Sends notifications for task completion, failures, and status updates
- **IAM Roles**: Secure role-based access for Lambda execution and scheduler invocation
- **CloudWatch Logs**: Centralized logging with retention policies

## Schedule Configuration

- **Daily Reports**: Generated at 9:00 AM Eastern Time
- **Data Processing**: Runs every hour
- **Status Notifications**: Sent every Monday at 10:00 AM Eastern Time

## Prerequisites

Before deploying this application, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Node.js** (version 18 or later) installed
3. **AWS CDK** v2 installed globally: `npm install -g aws-cdk`
4. **AWS account** with permissions to create the required resources
5. **CDK bootstrapped** in your target AWS account and region

## Installation

1. Clone or download this CDK application
2. Navigate to the application directory
3. Install dependencies:

```bash
npm install
```

## Configuration

### Environment Variables

Set the following environment variables (optional):

```bash
export CDK_DEFAULT_ACCOUNT=123456789012  # Your AWS Account ID
export CDK_DEFAULT_REGION=us-east-1      # Your preferred AWS Region
```

### Email Notifications

To receive email notifications, you'll need to subscribe to the SNS topic after deployment:

```bash
# Get the SNS Topic ARN from the stack outputs
aws sns subscribe \
    --topic-arn <SNS_TOPIC_ARN> \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Deployment

### Bootstrap CDK (one-time setup)

If you haven't bootstrapped CDK in your account/region:

```bash
cdk bootstrap
```

### Deploy the Stack

```bash
# Build the TypeScript code
npm run build

# Review the changes that will be made
cdk diff

# Deploy the stack
cdk deploy
```

The deployment will create all necessary resources and provide outputs including:
- S3 bucket name
- SNS topic ARN
- Lambda function name
- Manual test command

### Verify Deployment

After deployment, you can test the Lambda function manually:

```bash
# Use the command provided in the stack outputs
aws lambda invoke \
    --function-name <LAMBDA_FUNCTION_NAME> \
    --payload '{"task_type":"report"}' \
    --cli-binary-format raw-in-base64-out \
    response.json

# Check the response
cat response.json
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Lambda function logs are available in CloudWatch:

```bash
# View recent logs
aws logs tail /aws/lambda/<LAMBDA_FUNCTION_NAME> --follow
```

### EventBridge Scheduler Monitoring

Monitor schedule executions:

```bash
# List schedules in the group
aws scheduler list-schedules --group-name business-automation-group

# Get schedule details
aws scheduler get-schedule --name daily-report-schedule
```

### S3 Bucket Contents

Check generated reports and processed data:

```bash
# List bucket contents
aws s3 ls s3://<BUCKET_NAME> --recursive

# Download reports
aws s3 cp s3://<BUCKET_NAME>/reports/ ./reports/ --recursive
```

## Customization

### Modifying Schedules

To change schedule timings, edit the `scheduleExpression` values in `lib/business-task-scheduling-stack.ts`:

```typescript
// Daily report at different time
scheduleExpression: 'cron(0 8 * * ? *)', // 8 AM instead of 9 AM

// Different frequency for data processing
scheduleExpression: 'rate(30 minutes)', // Every 30 minutes instead of hourly
```

### Adding New Task Types

Extend the Lambda function code to handle additional task types:

1. Add new task type logic to the Lambda function
2. Create additional schedules with different `input` parameters
3. Update IAM permissions if accessing new AWS services

### Security Enhancements

For production deployments, consider:

1. **VPC Configuration**: Deploy Lambda in a VPC for network isolation
2. **KMS Encryption**: Use customer-managed KMS keys for S3 encryption
3. **SNS Encryption**: Enable SNS message encryption
4. **Dead Letter Queues**: Add DLQ for failed Lambda executions

## Cost Optimization

The application is designed for cost efficiency:

- **Serverless Architecture**: Pay only for execution time
- **S3 Lifecycle Policies**: Automatically transition old data to cheaper storage classes
- **CloudWatch Log Retention**: Logs are retained for 1 week to control costs

Estimated monthly costs (assuming typical business workload):
- Lambda: $1-5 (based on execution frequency)
- S3: $1-3 (storage and requests)
- EventBridge Scheduler: $1-2 (schedule executions)
- SNS: <$1 (notification delivery)

## Cleanup

To avoid ongoing charges, delete the stack when no longer needed:

```bash
cdk destroy
```

This will remove all resources created by the stack. Note that S3 bucket contents will be automatically deleted due to the demo configuration.

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Schedule Not Triggering**: Check schedule expressions and timezone settings
3. **Lambda Timeout**: Increase timeout if processing large datasets
4. **S3 Access Denied**: Verify IAM roles have correct S3 permissions

### Support Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [EventBridge Scheduler User Guide](https://docs.aws.amazon.com/scheduler/latest/UserGuide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)

## Contributing

To contribute improvements to this CDK application:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This CDK application is provided under the MIT License. See LICENSE file for details.