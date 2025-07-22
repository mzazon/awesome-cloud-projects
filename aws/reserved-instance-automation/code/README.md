# Infrastructure as Code for Reserved Instance Management Automation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automating Reserved Instance Managementexisting_folder_name".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution automates Reserved Instance (RI) management through:

- **Lambda Functions**: Three automated functions for RI utilization analysis, recommendations, and expiration monitoring
- **EventBridge Scheduling**: Automated execution on daily and weekly schedules
- **Data Storage**: S3 for reports and DynamoDB for tracking data
- **Notifications**: SNS topic for email alerts on utilization issues and expiring RIs
- **Cost Analysis**: Integration with AWS Cost Explorer APIs for intelligent recommendations

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Cost Explorer API access
  - Lambda function creation and execution
  - EventBridge rule creation
  - S3 bucket operations
  - DynamoDB table operations
  - SNS topic management
  - IAM role and policy creation
- Cost Explorer enabled in your AWS account
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

## Cost Considerations

- **Estimated monthly cost**: $15-25 for Lambda executions, DynamoDB, S3 storage, and SNS notifications
- **Cost Explorer API**: First 1,000 requests per month are free, then $0.01 per request
- **Lambda**: Pay-per-execution model with generous free tier
- **Storage**: Minimal costs for S3 reports and DynamoDB tracking data

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name ri-management-automation \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name ri-management-automation

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ri-management-automation \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=your-email@example.com

# Get stack outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=your-email@example.com

# Get stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="notification_email=your-email@example.com"

# Apply the configuration
terraform apply -var="notification_email=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment outputs
./scripts/deploy.sh --status
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `NOTIFICATION_EMAIL` | Email address for RI alerts | - | Yes |
| `AWS_REGION` | AWS region for deployment | us-east-1 | No |
| `PROJECT_PREFIX` | Prefix for resource names | ri-mgmt | No |
| `UTILIZATION_THRESHOLD` | RI utilization alert threshold | 80 | No |
| `EXPIRATION_WARNING_DAYS` | Days before expiration to alert | 90 | No |

### CloudFormation Parameters

- `NotificationEmail`: Email address for SNS notifications
- `ProjectPrefix`: Prefix for all resource names
- `UtilizationThreshold`: Percentage threshold for utilization alerts
- `ExpirationWarningDays`: Days before expiration to send warnings

### CDK Context Variables

```json
{
  "notification-email": "your-email@example.com",
  "project-prefix": "ri-mgmt",
  "utilization-threshold": 80,
  "expiration-warning-days": 90
}
```

### Terraform Variables

```hcl
notification_email = "your-email@example.com"
project_prefix = "ri-mgmt"
utilization_threshold = 80
expiration_warning_days = 90
```

## Deployment Validation

After deployment, verify the solution is working:

### 1. Check Lambda Functions

```bash
# List created Lambda functions
aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `ri-`)].FunctionName'

# Test utilization analysis function
aws lambda invoke \
    --function-name ri-mgmt-ri-utilization \
    --payload '{}' \
    response.json && cat response.json
```

### 2. Verify EventBridge Rules

```bash
# List EventBridge rules
aws events list-rules \
    --query 'Rules[?contains(Name, `ri-`)].{Name:Name,State:State,Schedule:ScheduleExpression}'
```

### 3. Check S3 Bucket and Reports

```bash
# List S3 buckets
aws s3 ls | grep ri-reports

# Check for generated reports (after first execution)
aws s3 ls s3://your-ri-reports-bucket/ri-utilization-reports/
aws s3 ls s3://your-ri-reports-bucket/ri-recommendations/
```

### 4. Verify DynamoDB Table

```bash
# Describe the tracking table
aws dynamodb describe-table \
    --table-name ri-tracking-table \
    --query 'Table.{Name:TableName,Status:TableStatus,ItemCount:ItemCount}'
```

### 5. Confirm SNS Subscription

```bash
# List SNS subscriptions
aws sns list-subscriptions \
    --query 'Subscriptions[?contains(TopicArn, `ri-alerts`)].{Topic:TopicArn,Protocol:Protocol,Endpoint:Endpoint}'
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda function execution:

```bash
# View recent log events for utilization function
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/ri-mgmt

# Get recent log events
aws logs filter-log-events \
    --log-group-name /aws/lambda/ri-mgmt-ri-utilization \
    --start-time $(date -d '1 hour ago' +%s)000
```

### Common Issues

1. **Cost Explorer Not Enabled**
   - Solution: Enable Cost Explorer in AWS Console under Billing and Cost Management

2. **No RI Data Available**
   - Solution: Ensure you have active Reserved Instances or create test RIs

3. **Permission Errors**
   - Solution: Verify IAM roles have Cost Explorer API permissions

4. **Email Not Received**
   - Solution: Check SNS subscription confirmation in email and spam folders

### Testing Functions Manually

```bash
# Test all three Lambda functions
for function in ri-utilization ri-recommendations ri-monitoring; do
    echo "Testing $function..."
    aws lambda invoke \
        --function-name ri-mgmt-$function \
        --payload '{}' \
        response-$function.json
    echo "Response: $(cat response-$function.json)"
done
```

## Customization

### Modifying Schedules

Edit EventBridge cron expressions in your chosen IaC tool:

- **Daily utilization**: `cron(0 8 * * ? *)` (8 AM UTC daily)
- **Weekly recommendations**: `cron(0 9 ? * MON *)` (9 AM UTC Mondays)
- **Weekly monitoring**: `cron(0 10 ? * MON *)` (10 AM UTC Mondays)

### Adding Additional Services

Extend the Lambda functions to include other AWS services with Reserved Instances:

- Amazon RDS
- Amazon ElastiCache
- Amazon Redshift
- Amazon OpenSearch Service

### Custom Alert Thresholds

Modify the utilization threshold and expiration warning periods by updating the environment variables in your chosen deployment method.

### Integration with External Systems

The SNS topic can be extended to integrate with:

- Slack webhooks
- Microsoft Teams
- ITSM tools (ServiceNow, Jira)
- Custom webhooks

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name ri-management-automation

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name ri-management-automation
```

### Using CDK

```bash
# From the CDK directory
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

### Manual Cleanup Verification

After automated cleanup, verify all resources are removed:

```bash
# Check for remaining Lambda functions
aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `ri-`)].FunctionName'

# Check for remaining S3 buckets
aws s3 ls | grep ri-reports

# Check for remaining DynamoDB tables
aws dynamodb list-tables \
    --query 'TableNames[?contains(@, `ri-tracking`)]'

# Check for remaining SNS topics
aws sns list-topics \
    --query 'Topics[?contains(TopicArn, `ri-alerts`)]'
```

## Security Considerations

- **IAM Roles**: Functions use least-privilege IAM roles
- **Encryption**: S3 buckets and DynamoDB tables use AWS-managed encryption
- **Network**: No VPC configuration required; uses AWS API endpoints
- **Secrets**: No hardcoded credentials; uses IAM roles for authentication

## Support and Troubleshooting

For issues with this infrastructure code:

1. Check AWS CloudWatch Logs for Lambda function errors
2. Verify Cost Explorer API access and billing permissions
3. Ensure all prerequisite services are enabled
4. Review the original recipe documentation for implementation details
5. Check AWS service quotas and limits

## Additional Resources

- [AWS Cost Explorer API Documentation](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_Operations_AWS_Cost_Explorer_Service.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [EventBridge Scheduled Rules](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-rule-schedule.html)
- [Reserved Instance Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ri-market-concepts-buying.html)