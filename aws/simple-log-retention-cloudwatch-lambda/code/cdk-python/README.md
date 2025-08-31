# CDK Python Implementation - Simple Log Retention Management

This directory contains the AWS CDK Python implementation for automated CloudWatch Logs retention management using Lambda and EventBridge.

## Architecture

The CDK application creates the following AWS resources:

- **Lambda Function**: Python 3.12 runtime function that scans CloudWatch log groups and applies retention policies
- **IAM Role**: Execution role with least-privilege permissions for CloudWatch Logs operations
- **EventBridge Rule**: Scheduled trigger for weekly execution of the Lambda function
- **CloudWatch Logs**: Automatic log group creation for Lambda function execution logs

## Features

- **Automated Retention Management**: Applies retention policies based on log group naming patterns
- **Cost Optimization**: Reduces storage costs by automatically purging old log data
- **Compliance Support**: Ensures data retention requirements are met consistently
- **Configurable Rules**: Support for different retention periods based on log group types
- **Error Handling**: Comprehensive error handling and logging for monitoring and troubleshooting

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS Account**: With appropriate permissions for CDK deployments
2. **AWS CLI**: Installed and configured with credentials
3. **Python**: Version 3.8 or later
4. **AWS CDK**: Version 2.170.0 or later
5. **Node.js**: Version 16.x or later (required for CDK CLI)

### Required AWS Permissions

Your AWS credentials must have permissions for:
- CloudFormation stack operations
- Lambda function management
- IAM role and policy management
- EventBridge rule management
- CloudWatch Logs operations

## Installation

1. **Clone or navigate to the CDK Python directory**:
   ```bash
   cd cdk-python/
   ```

2. **Create a Python virtual environment** (recommended):
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Install AWS CDK CLI** (if not already installed):
   ```bash
   npm install -g aws-cdk
   ```

5. **Bootstrap CDK** (first time only):
   ```bash
   cdk bootstrap
   ```

## Configuration

The application supports several configuration options through CDK context:

### Environment Variables

Set these environment variables or use CDK context:

```bash
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
```

### CDK Context Configuration

Modify `cdk.json` or use command-line context to customize:

- `default_retention_days`: Default retention period for unmatched log groups (default: 30)
- `schedule_rate`: EventBridge schedule expression (default: "rate(7 days)")
- `environment`: Environment tag for resources (default: "production")

Example with custom context:
```bash
cdk deploy -c default_retention_days=60 -c schedule_rate="rate(3 days)"
```

## Deployment

### Deploy the Stack

```bash
# Synthesize CloudFormation template (optional)
cdk synth

# Deploy the stack
cdk deploy

# Deploy with confirmation prompts disabled
cdk deploy --require-approval never
```

### Verify Deployment

After deployment, verify the resources:

```bash
# List CDK stacks
cdk list

# Check stack resources
aws cloudformation describe-stack-resources \
    --stack-name LogRetentionManagerStack
```

## Usage

### Manual Execution

Test the Lambda function manually:

```bash
# Get the function name from CDK outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name LogRetentionManagerStack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Invoke the function
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    --cli-binary-format raw-in-base64-out \
    response.json

# View results
cat response.json | python -m json.tool
```

### Monitoring

Monitor the solution using CloudWatch:

```bash
# View Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/LogRetentionManagerStack"

# View recent log events
aws logs filter-log-events \
    --log-group-name "/aws/lambda/LogRetentionManagerStack-LogRetentionManagerFunction" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Retention Policy Rules

The Lambda function applies retention policies based on these naming patterns:

| Log Group Pattern | Retention Period | Use Case |
|------------------|------------------|----------|
| `/aws/lambda/` | 30 days | Lambda function logs |
| `/aws/apigateway/` | 90 days | API Gateway access logs |
| `/aws/codebuild/` | 14 days | CodeBuild build logs |
| `/aws/ecs/` | 60 days | ECS container logs |
| `/aws/stepfunctions/` | 90 days | Step Functions execution logs |
| `/application/` | 180 days | Application-specific logs |
| `/system/` | 365 days | System and infrastructure logs |
| **Default** | 30 days | Unmatched log groups |

### Customizing Retention Rules

To modify retention rules, edit the `get_retention_days` function in `app.py`:

```python
retention_rules = {
    '/custom/pattern/': 60,  # Custom pattern: 60 days
    '/aws/lambda/': 30,      # Lambda logs: 30 days
    # Add more patterns as needed
}
```

## Testing

### Unit Tests

Run unit tests (if available):

```bash
# Install test dependencies
pip install -r requirements.txt[test]

# Run tests
python -m pytest tests/

# Run tests with coverage
python -m pytest --cov=. tests/
```

### Integration Testing

Test with actual AWS resources:

1. **Create test log groups**:
   ```bash
   aws logs create-log-group --log-group-name "/aws/lambda/test-function"
   aws logs create-log-group --log-group-name "/application/test-app"
   ```

2. **Execute the function**:
   ```bash
   aws lambda invoke \
       --function-name $FUNCTION_NAME \
       --payload '{}' \
       response.json
   ```

3. **Verify retention policies**:
   ```bash
   aws logs describe-log-groups \
       --log-group-name-prefix "/aws/lambda/test-function" \
       --query 'logGroups[*].{Name:logGroupName,Retention:retentionInDays}'
   ```

4. **Clean up test resources**:
   ```bash
   aws logs delete-log-group --log-group-name "/aws/lambda/test-function"
   aws logs delete-log-group --log-group-name "/application/test-app"
   ```

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   - Verify AWS credentials have necessary permissions
   - Check IAM role policies in the deployed stack

2. **CDK Bootstrap Issues**:
   ```bash
   cdk bootstrap --force
   ```

3. **Lambda Function Errors**:
   - Check CloudWatch Logs for the Lambda function
   - Verify environment variables are set correctly

4. **EventBridge Not Triggering**:
   - Verify the EventBridge rule is enabled
   - Check Lambda function permissions for EventBridge

### Debug Mode

Enable debug logging in the Lambda function by setting log level:

```python
logger.setLevel(logging.DEBUG)
```

## Cost Optimization

### Estimated Costs

- **Lambda**: ~$0.0001 per execution (weekly = ~$0.005/month)
- **EventBridge**: ~$0.00 (included in free tier)
- **CloudWatch Logs**: Variable based on log retention savings

### Cost Monitoring

Monitor costs using AWS Cost Explorer:

```bash
# View Lambda costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-12-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Security

### Security Features

- **Least Privilege IAM**: Role has minimal required permissions
- **No Hardcoded Credentials**: Uses IAM roles for AWS service access
- **VPC Support**: Can be deployed in VPC for additional network isolation
- **Encryption**: All data encrypted in transit and at rest

### Security Best Practices

1. **Regular Updates**: Keep CDK and dependencies updated
2. **Access Logging**: Monitor CloudTrail for API calls
3. **Resource Tagging**: Use consistent tagging for resource governance
4. **Backup Strategy**: Regular snapshots of critical configurations

## Cleanup

### Remove All Resources

```bash
# Delete the CDK stack
cdk destroy

# Confirm deletion when prompted
# This will remove all created AWS resources
```

### Manual Cleanup (if needed)

If CDK destroy fails, manually remove resources:

```bash
# Delete Lambda function
aws lambda delete-function --function-name LogRetentionManagerFunction

# Delete EventBridge rule
aws events delete-rule --name LogRetentionScheduleRule

# Delete IAM role (after detaching policies)
aws iam delete-role --role-name LogRetentionManagerRole
```

## Advanced Configuration

### Custom Scheduling

Modify the EventBridge schedule in `cdk.json`:

```json
{
  "context": {
    "schedule_rate": "cron(0 2 * * SUN *)"  // Every Sunday at 2 AM UTC
  }
}
```

### Multi-Environment Deployment

Deploy to different environments:

```bash
# Development environment
cdk deploy -c environment=development -c default_retention_days=7

# Production environment  
cdk deploy -c environment=production -c default_retention_days=30
```

### VPC Deployment

To deploy Lambda in a VPC, modify the Lambda function configuration in `app.py`:

```python
from aws_cdk import aws_ec2 as ec2

# Reference existing VPC
vpc = ec2.Vpc.from_lookup(self, "VPC", vpc_id="vpc-12345678")

# Add VPC config to Lambda function
function = _lambda.Function(
    # ... other properties
    vpc=vpc,
    vpc_subnets=ec2.SubnetSelection(
        subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
    ),
)
```

## Support and Contributing

### Getting Help

- **AWS CDK Documentation**: https://docs.aws.amazon.com/cdk/
- **AWS Lambda Documentation**: https://docs.aws.amazon.com/lambda/
- **CloudWatch Logs Documentation**: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Submit a pull request

### License

This code is provided under the MIT License. See LICENSE file for details.