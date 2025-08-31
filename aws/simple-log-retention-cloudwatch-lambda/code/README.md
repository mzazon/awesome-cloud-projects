# Infrastructure as Code for Simple Log Retention Management with CloudWatch and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Log Retention Management with CloudWatch and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions:
  - CloudWatch Logs: `CloudWatchLogsFullAccess`
  - Lambda: `AWSLambdaExecute`
  - IAM: Permission to create roles and policies
  - EventBridge: Permission to create rules and targets
- Python 3.12 runtime available (for Lambda function)
- Estimated cost: $0.50-2.00 for testing (Lambda executions + log storage)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name log-retention-manager \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DefaultRetentionDays,ParameterValue=30

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name log-retention-manager \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name log-retention-manager \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Review the changes that will be made
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Review the changes that will be made
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# 1. Set up environment variables
# 2. Create IAM role and policies
# 3. Deploy Lambda function
# 4. Configure EventBridge schedule
# 5. Create test log groups
# 6. Execute initial retention policy application
```

## Configuration Options

### Environment Variables

All implementations support these configuration options:

- `DEFAULT_RETENTION_DAYS`: Default retention period for unmatched log groups (default: 30)
- `SCHEDULE_EXPRESSION`: EventBridge schedule expression (default: "rate(7 days)")
- `LAMBDA_TIMEOUT`: Lambda function timeout in seconds (default: 300)
- `LAMBDA_MEMORY`: Lambda function memory allocation in MB (default: 256)

### Retention Policy Rules

The Lambda function applies retention policies based on log group naming patterns:

| Log Group Pattern | Retention Period | Use Case |
|------------------|------------------|----------|
| `/aws/lambda/` | 30 days | Lambda function logs |
| `/aws/apigateway/` | 90 days | API Gateway access logs |
| `/aws/codebuild/` | 14 days | CodeBuild project logs |
| `/aws/ecs/` | 60 days | ECS container logs |
| `/aws/stepfunctions/` | 90 days | Step Functions execution logs |
| `/application/` | 180 days | Application-specific logs |
| `/system/` | 365 days | System and infrastructure logs |
| *default* | 30 days | All other log groups |

### Customizing Retention Rules

To modify retention rules, update the Lambda function code in the respective IaC implementation:

**CloudFormation**: Modify the `LambdaFunction` resource's `Code.ZipFile` property
**CDK**: Update the function code in the construct definition
**Terraform**: Modify the `aws_lambda_function` resource's `filename` or inline code

## Validation

After deployment, verify the solution is working:

1. **Check Lambda function deployment:**
   ```bash
   aws lambda get-function --function-name log-retention-manager
   ```

2. **Verify EventBridge rule:**
   ```bash
   aws events describe-rule --name log-retention-schedule
   ```

3. **Test retention policy application:**
   ```bash
   # Invoke the function manually
   aws lambda invoke --function-name log-retention-manager response.json
   cat response.json
   ```

4. **Check log groups with retention policies:**
   ```bash
   aws logs describe-log-groups \
       --query 'logGroups[?retentionInDays!=null].{Name:logGroupName,Retention:retentionInDays}'
   ```

## Monitoring

The solution provides several monitoring capabilities:

- **Lambda Function Logs**: Check `/aws/lambda/log-retention-manager` log group
- **EventBridge Execution**: Monitor rule invocations in EventBridge console
- **Cost Impact**: Use AWS Cost Explorer to track CloudWatch Logs storage costs

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this removes all resources)
aws cloudformation delete-stack --stack-name log-retention-manager

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name log-retention-manager \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Remove EventBridge rule and targets
# 2. Delete Lambda function
# 3. Remove test log groups
# 4. Delete IAM role and policies
# 5. Clean up local files
```

## Troubleshooting

### Common Issues

1. **IAM Permission Errors:**
   - Ensure your AWS credentials have sufficient permissions
   - Check that the Lambda execution role has CloudWatch Logs permissions

2. **Lambda Function Timeout:**
   - Increase timeout if you have many log groups (>1000)
   - Consider batch processing for very large accounts

3. **EventBridge Rule Not Triggering:**
   - Verify the rule is in ENABLED state
   - Check Lambda function permissions for EventBridge invocation

4. **Cost Concerns:**
   - Monitor execution frequency and duration
   - Consider adjusting schedule for less frequent execution

### Debug Commands

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/log-retention-manager --follow

# List all EventBridge rules
aws events list-rules --name-prefix log-retention

# Check Lambda function configuration
aws lambda get-function-configuration --function-name log-retention-manager
```

## Customization

### Modifying Retention Rules

To add or modify retention patterns, update the `get_retention_days()` function in the Lambda code:

```python
retention_rules = {
    '/aws/lambda/': 30,
    '/aws/apigateway/': 90,
    '/custom/pattern/': 60,  # Add custom patterns
    # ... existing rules
}
```

### Changing Schedule

To modify the execution schedule, update the EventBridge rule's schedule expression:

- **Hourly**: `rate(1 hour)`
- **Daily**: `rate(1 day)`
- **Weekly**: `rate(7 days)`
- **Monthly**: `rate(30 days)`
- **Cron expression**: `cron(0 9 * * ? *)` (9 AM daily)

### Adding Notifications

Extend the solution by adding SNS notifications for retention policy changes:

1. Create SNS topic in your IaC template
2. Modify Lambda function to publish messages
3. Subscribe email/SMS endpoints to the topic

## Cost Optimization

This solution is designed for cost efficiency:

- **Lambda**: Pay-per-execution model with minimal compute requirements
- **EventBridge**: Low-cost scheduled executions
- **Log Retention**: Automatic cleanup reduces CloudWatch Logs storage costs
- **Estimated Monthly Cost**: $1-5 for typical enterprise accounts

## Security Considerations

The implementation follows AWS security best practices:

- **Least Privilege IAM**: Lambda role has minimal required permissions
- **Resource-based Policies**: EventBridge uses resource-based permissions
- **No Hardcoded Secrets**: All configuration through environment variables
- **Audit Trail**: All actions logged in CloudTrail and Lambda logs

## Integration

This solution can be integrated with:

- **AWS Config**: Monitor compliance with retention policies
- **AWS Cost Explorer**: Track cost savings from retention policies
- **Amazon SNS**: Send notifications about policy changes
- **AWS Systems Manager**: Store configuration in Parameter Store
- **AWS Organizations**: Deploy across multiple accounts

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult AWS documentation for specific services:
   - [CloudWatch Logs User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
   - [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
   - [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)

## Contributing

To improve this infrastructure code:

1. Follow AWS Well-Architected Framework principles
2. Test changes in a development environment
3. Update documentation for any configuration changes
4. Consider backward compatibility for existing deployments