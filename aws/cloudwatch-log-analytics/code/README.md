# Infrastructure as Code for CloudWatch Log Analytics with Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "CloudWatch Log Analytics with Insights".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete log analytics infrastructure including:

- CloudWatch Log Groups for centralized log collection
- Lambda function for automated log analysis
- SNS topic for alert notifications
- CloudWatch Events rule for scheduled analysis
- IAM roles and policies for secure access
- Sample log data generation for testing

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - CloudWatch Logs (create log groups, put log events)
  - Lambda (create functions, manage execution)
  - SNS (create topics, publish messages)
  - IAM (create roles, attach policies)
  - CloudWatch Events (create rules, targets)
- Email address for receiving notifications
- Basic understanding of log analysis and monitoring concepts

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name log-analytics-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name log-analytics-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name log-analytics-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set notification email
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy --parameters NotificationEmail=$NOTIFICATION_EMAIL

# View outputs
cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Set notification email
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy --parameters NotificationEmail=$NOTIFICATION_EMAIL

# View outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="notification_email=your-email@example.com"

# Deploy infrastructure
terraform apply -var="notification_email=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy infrastructure
./scripts/deploy.sh

# View deployed resources
aws cloudformation describe-stacks --stack-name log-analytics-stack
```

## Configuration Options

### CloudFormation Parameters

- `NotificationEmail`: Email address for SNS notifications (required)
- `LogRetentionDays`: CloudWatch log retention period (default: 30)
- `AnalysisSchedule`: Schedule expression for automated analysis (default: rate(5 minutes))
- `Environment`: Environment tag for resources (default: dev)

### CDK Context Variables

- `NotificationEmail`: Email address for SNS notifications
- `LogRetentionDays`: CloudWatch log retention period
- `AnalysisSchedule`: Schedule expression for automated analysis
- `Environment`: Environment tag for resources

### Terraform Variables

- `notification_email`: Email address for SNS notifications (required)
- `log_retention_days`: CloudWatch log retention period (default: 30)
- `analysis_schedule`: Schedule expression for automated analysis (default: "rate(5 minutes)")
- `environment`: Environment tag for resources (default: "dev")
- `aws_region`: AWS region for deployment (default: current region)

## Post-Deployment Setup

1. **Confirm SNS Subscription**: Check your email and confirm the SNS subscription to receive alerts.

2. **Generate Sample Log Data**: Use the deployed Lambda function to generate sample log entries:
   ```bash
   aws lambda invoke \
       --function-name log-analytics-sample-data-generator \
       --payload '{"action": "generate_sample_logs"}' \
       response.json
   ```

3. **Test Manual Queries**: Use CloudWatch Logs Insights to run manual queries:
   ```bash
   # Start a query to find errors
   aws logs start-query \
       --log-group-name "/aws/lambda/log-analytics-processor" \
       --start-time $(date -d '1 hour ago' +%s) \
       --end-time $(date +%s) \
       --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | stats count()'
   ```

4. **Monitor Automated Analysis**: Check CloudWatch Logs for the processor function to see automated analysis results.

## Testing the Solution

### Verify Log Collection

```bash
# Check if log groups were created
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/log-analytics"

# Generate test log entries
aws logs put-log-events \
    --log-group-name "/aws/lambda/log-analytics-processor" \
    --log-stream-name "test-stream" \
    --log-events timestamp=$(date +%s000),message='[ERROR] Test error message'
```

### Test Analytics Queries

```bash
# Run a sample analytics query
QUERY_ID=$(aws logs start-query \
    --log-group-name "/aws/lambda/log-analytics-processor" \
    --start-time $(date -d '1 hour ago' +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | stats count() as error_count' \
    --query 'queryId' --output text)

# Get query results
sleep 5
aws logs get-query-results --query-id $QUERY_ID
```

### Validate Alerting

```bash
# Trigger the analysis Lambda manually
aws lambda invoke \
    --function-name log-analytics-processor \
    --payload '{}' \
    response.json

# Check response
cat response.json

# Verify SNS topic
aws sns list-subscriptions-by-topic \
    --topic-arn $(aws sns list-topics --query 'Topics[?contains(TopicArn, `log-analytics-alerts`)].TopicArn' --output text)
```

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor key metrics for your log analytics solution:

- Lambda function invocations and errors
- CloudWatch Logs ingestion and query volume
- SNS message delivery status
- Query execution times and costs

### Common Issues

1. **SNS Subscription Not Confirmed**: Check email and confirm subscription
2. **Lambda Function Timeout**: Increase timeout in configuration if processing large log volumes
3. **Insufficient Permissions**: Verify IAM roles have required permissions
4. **Log Group Not Found**: Ensure log groups exist and names match configuration

### Debugging Commands

```bash
# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/log-analytics-processor" \
    --start-time $(date -d '1 hour ago' +%s)

# Verify CloudWatch Events rule
aws events describe-rule --name log-analytics-schedule

# Check SNS topic configuration
aws sns get-topic-attributes \
    --topic-arn $(aws sns list-topics --query 'Topics[?contains(TopicArn, `log-analytics-alerts`)].TopicArn' --output text)
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name log-analytics-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name log-analytics-stack
```

### Using CDK

```bash
# From the appropriate CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="notification_email=your-email@example.com"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Cost Optimization

### Expected Costs

- **CloudWatch Logs**: $0.50 per GB ingested, $0.03 per GB stored per month
- **Lambda**: $0.20 per 1M requests, $0.0000166667 per GB-second
- **SNS**: $0.50 per 1M notifications
- **CloudWatch Events**: $1.00 per 1M events

### Cost Reduction Tips

1. **Optimize Log Retention**: Adjust retention periods based on compliance requirements
2. **Filter Log Data**: Use log filtering to reduce ingestion volume
3. **Optimize Query Frequency**: Balance monitoring needs with query costs
4. **Use Reserved Capacity**: Consider CloudWatch Logs reserved capacity for predictable workloads

## Security Considerations

### IAM Permissions

The solution follows the principle of least privilege:

- Lambda execution role has minimal CloudWatch Logs and SNS permissions
- Log groups are encrypted at rest
- SNS topics use server-side encryption
- No hardcoded credentials in code

### Best Practices

1. **Enable CloudTrail**: Monitor API calls to log analytics resources
2. **Use VPC Endpoints**: Reduce network exposure for Lambda functions
3. **Implement Log Sanitization**: Remove sensitive data before logging
4. **Regular Security Reviews**: Audit IAM permissions and access patterns

## Customization

### Adding Custom Queries

Modify the Lambda function to include additional analysis queries:

```python
# Add to lambda_function.py
custom_query = '''
fields @timestamp, @message
| filter @message like /CUSTOM_PATTERN/
| stats count() as custom_count
'''
```

### Extending Alert Conditions

Add more sophisticated alerting logic:

```python
# Enhanced alerting in Lambda function
if error_count > error_threshold:
    severity = "HIGH" if error_count > 10 else "MEDIUM"
    send_alert(f"[{severity}] {error_count} errors detected")
```

### Integration with Other Services

- **CloudWatch Dashboards**: Visualize log analytics metrics
- **AWS X-Ray**: Correlate log data with distributed traces
- **Amazon Elasticsearch**: Advanced search and analytics capabilities
- **AWS QuickSight**: Business intelligence dashboards

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for CloudWatch Logs Insights
3. Verify IAM permissions and resource configurations
4. Monitor CloudWatch Logs for error messages
5. Use AWS Support for service-specific issues

## Contributing

To improve this infrastructure code:

1. Follow AWS best practices for infrastructure as code
2. Test all changes thoroughly in development environments
3. Update documentation for any configuration changes
4. Consider backward compatibility when making modifications