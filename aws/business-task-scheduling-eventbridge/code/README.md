# Infrastructure as Code for Business Task Scheduling with EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Business Task Scheduling with EventBridge".

## Overview

This recipe demonstrates how to build an automated business workflow system using EventBridge Scheduler to trigger Lambda functions on flexible schedules. The serverless architecture eliminates manual intervention by automatically executing tasks like report generation, data processing, and notification delivery based on configurable cron expressions and rate schedules.

## Architecture Components

- **EventBridge Scheduler**: Manages flexible scheduling with cron and rate expressions
- **Lambda Functions**: Processes business tasks (reports, data processing, notifications)
- **S3 Bucket**: Stores generated reports and processed data with encryption
- **SNS Topic**: Delivers notifications via email and SMS
- **IAM Roles**: Provides secure, least-privilege access between services

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- AWS account with EventBridge Scheduler, Lambda, SNS, and S3 permissions
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)
- Basic understanding of serverless architectures and event-driven patterns
- Estimated cost: $5-15 per month for typical business automation workloads

### Required AWS Permissions

Your AWS credentials must have permissions for:
- EventBridge Scheduler (create schedules, schedule groups)
- Lambda (create functions, manage execution)
- S3 (create buckets, manage objects)
- SNS (create topics, manage subscriptions)
- IAM (create roles and policies)
- CloudWatch Logs (log management)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name business-automation-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=admin@example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment status
aws cloudformation wait stack-create-complete \
    --stack-name business-automation-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name business-automation-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy \
    --parameters notificationEmail=admin@example.com

# View deployed resources
npx cdk ls
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy \
    --parameters notificationEmail=admin@example.com

# View deployed resources
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "admin@example.com"
aws_region        = "us-east-1"
environment       = "production"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="admin@example.com"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
aws scheduler list-schedules
aws lambda list-functions --query 'Functions[?contains(FunctionName, `business-task-processor`)].FunctionName'
```

## Configuration Parameters

### CloudFormation Parameters

- `NotificationEmail`: Email address for business task notifications
- `ScheduleTimezone`: Timezone for cron schedules (default: America/New_York)
- `Environment`: Environment tag (default: production)

### CDK Parameters

- `notificationEmail`: Email address for SNS notifications
- `scheduleTimezone`: Timezone for EventBridge schedules
- `environment`: Deployment environment

### Terraform Variables

- `notification_email`: Email address for notifications (required)
- `aws_region`: AWS region for deployment (default: us-east-1)
- `environment`: Environment name (default: production)
- `schedule_timezone`: Timezone for schedules (default: America/New_York)

## Deployment Validation

After deployment, verify the infrastructure is working correctly:

### 1. Check Lambda Function

```bash
# List Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `business-task-processor`)].FunctionName'

# Test Lambda function
aws lambda invoke \
    --function-name business-task-processor-<suffix> \
    --payload '{"task_type":"report"}' \
    --cli-binary-format raw-in-base64-out \
    response.json

cat response.json
```

### 2. Verify EventBridge Schedules

```bash
# List all schedules
aws scheduler list-schedules

# Get specific schedule details
aws scheduler get-schedule --name daily-report-schedule
```

### 3. Check S3 Bucket

```bash
# List S3 buckets
aws s3 ls | grep business-automation

# Check bucket contents after Lambda execution
aws s3 ls s3://business-automation-<suffix>/reports/
```

### 4. Verify SNS Topic

```bash
# List SNS topics
aws sns list-topics | grep business-notifications

# Check subscriptions (you should confirm email subscription)
aws sns list-subscriptions-by-topic --topic-arn <topic-arn>
```

## Schedule Configuration

The deployed solution includes three pre-configured schedules:

1. **Daily Report Schedule**: Runs at 9:00 AM every day
   - Cron expression: `cron(0 9 * * ? *)`
   - Generates business reports in CSV format

2. **Hourly Data Processing**: Runs every hour
   - Rate expression: `rate(1 hour)`
   - Processes business data and saves to S3

3. **Weekly Notification**: Runs every Monday at 10:00 AM
   - Cron expression: `cron(0 10 ? * MON *)`
   - Sends status notifications via SNS

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda execution:

```bash
# View Lambda log groups
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/business-task-processor

# View recent log events
aws logs filter-log-events \
    --log-group-name /aws/lambda/business-task-processor-<suffix> \
    --start-time $(date -d '1 hour ago' +%s)000
```

### EventBridge Scheduler Metrics

Monitor schedule execution:

```bash
# View schedule execution history (requires additional configuration)
aws scheduler list-schedule-groups
aws cloudwatch get-metric-statistics \
    --namespace AWS/Scheduler \
    --metric-name Invocations \
    --start-time $(date -d '1 day ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum
```

### Common Issues

1. **Email notifications not received**: Confirm SNS subscription via email
2. **Lambda timeout errors**: Increase timeout in function configuration
3. **Permission errors**: Verify IAM roles have necessary permissions
4. **Schedule not triggering**: Check timezone settings and cron expression syntax

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name business-automation-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name business-automation-stack
```

### Using CDK (AWS)

```bash
# TypeScript
cd cdk-typescript/
npx cdk destroy

# Python
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resources are deleted
aws scheduler list-schedules
aws lambda list-functions --query 'Functions[?contains(FunctionName, `business-task-processor`)].FunctionName'
aws s3 ls | grep business-automation
```

## Security Considerations

- **IAM Roles**: All services use least-privilege IAM roles
- **S3 Encryption**: Bucket configured with AES-256 server-side encryption
- **SNS Security**: Topic access restricted to authorized services
- **Lambda Security**: Functions run with minimal required permissions
- **Network Security**: Consider VPC deployment for enhanced isolation

## Cost Optimization

- **Lambda**: Pay per execution with 1M free requests monthly
- **EventBridge Scheduler**: $1 per million schedule evaluations
- **S3**: Standard storage pricing with lifecycle policies
- **SNS**: $0.50 per million email notifications

Monitor costs using AWS Cost Explorer and set up billing alerts.

## Customization

### Adding New Task Types

Modify the Lambda function to support additional business tasks:

1. Update the Lambda function code with new task handlers
2. Create additional EventBridge schedules for new tasks
3. Update IAM permissions if accessing new AWS services

### Modifying Schedules

Update schedule expressions through the AWS Console or CLI:

```bash
# Update schedule frequency
aws scheduler update-schedule \
    --name daily-report-schedule \
    --schedule-expression "cron(0 8 * * ? *)" \
    --flexible-time-window Mode=OFF
```

### Environment-Specific Deployments

Deploy to multiple environments by:

1. Using different stack names or Terraform workspaces
2. Updating parameter values for each environment
3. Implementing environment-specific schedule frequencies

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../automated-business-task-scheduling-eventbridge-scheduler-lambda.md)
- [AWS EventBridge Scheduler documentation](https://docs.aws.amazon.com/scheduler/latest/UserGuide/what-is-scheduler.html)
- [AWS Lambda documentation](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [AWS CDK documentation](https://docs.aws.amazon.com/cdk/v2/guide/home.html)
- [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Follow AWS Well-Architected Framework principles
3. Update documentation for any new parameters or outputs
4. Validate security configurations
5. Test cleanup procedures