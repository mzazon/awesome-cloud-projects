# Infrastructure as Code for Cost Optimization Automation with Lambda and Trusted Advisor APIs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost Optimization Automation with Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with Business or Enterprise support plan (required for Trusted Advisor API access)
- Appropriate IAM permissions for Lambda, Trusted Advisor, SNS, CloudWatch, DynamoDB, S3, EC2, and RDS services
- Python 3.9 or higher for local development and testing
- Node.js 18+ (for CDK TypeScript)
- Terraform 1.0+ (for Terraform implementation)

> **Note**: Business or Enterprise support plan is required to access Trusted Advisor APIs programmatically. Basic support plan only provides limited web console access.

## Architecture Overview

This solution creates an automated cost optimization system that:

- Analyzes AWS Trusted Advisor cost optimization recommendations
- Stores findings in DynamoDB for tracking and audit
- Implements automated remediation for approved actions
- Sends notifications via SNS for cost-saving opportunities
- Monitors system performance through CloudWatch dashboards
- Schedules regular analysis using EventBridge

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete infrastructure
aws cloudformation create-stack \
    --stack-name cost-optimization-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name cost-optimization-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name cost-optimization-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=your-email@example.com

# View outputs
cdk list
```

### Using CDK Python
```bash
# Set up Python environment
cd cdk-python/
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=your-email@example.com

# View outputs
cdk list
```

### Using Terraform
```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan \
    -var="notification_email=your-email@example.com" \
    -var="aws_region=us-east-1"

# Apply configuration
terraform apply \
    -var="notification_email=your-email@example.com" \
    -var="aws_region=us-east-1"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export AWS_REGION=us-east-1

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration Parameters

### CloudFormation Parameters
- `NotificationEmail`: Email address for cost optimization alerts
- `ScheduleExpression`: EventBridge schedule expression (default: rate(1 day))
- `AutoRemediationEnabled`: Enable automatic remediation (default: true)
- `Environment`: Environment tag (default: production)

### CDK Parameters
- `notificationEmail`: Email address for notifications
- `scheduleExpression`: Analysis schedule expression
- `autoRemediation`: Enable/disable auto-remediation
- `environment`: Environment identifier

### Terraform Variables
- `notification_email`: Email for alerts
- `aws_region`: AWS region for deployment
- `schedule_expression`: EventBridge schedule
- `auto_remediation_enabled`: Boolean for auto-remediation
- `environment`: Environment tag

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email and confirm the SNS subscription
2. **Review IAM Permissions**: Ensure the Lambda execution role has required permissions
3. **Test the System**: Trigger a manual analysis to verify functionality
4. **Configure Monitoring**: Set up CloudWatch alarms for system monitoring
5. **Customize Policies**: Adjust auto-remediation policies based on your requirements

## Testing the Deployment

### Manual Function Invocation
```bash
# Test cost analysis function
aws lambda invoke \
    --function-name cost-optimization-analysis \
    --payload '{"test": true}' \
    response.json

# Check response
cat response.json
```

### Verify Resources
```bash
# Check DynamoDB table
aws dynamodb describe-table \
    --table-name cost-optimization-tracking-* \
    --query 'Table.[TableName,TableStatus]'

# Verify SNS topic
aws sns list-subscriptions \
    --query 'Subscriptions[?contains(TopicArn, `cost-optimization`)]'

# Check EventBridge schedules
aws scheduler list-schedules \
    --group-name cost-optimization-schedules
```

## Monitoring and Maintenance

### CloudWatch Dashboard
Access the created CloudWatch dashboard to monitor:
- Lambda function execution metrics
- Error rates and duration
- Cost optimization analysis logs
- System performance trends

### Log Analysis
```bash
# View analysis function logs
aws logs tail /aws/lambda/cost-optimization-analysis --follow

# View remediation function logs
aws logs tail /aws/lambda/cost-optimization-remediation --follow
```

### Cost Tracking
```bash
# Query DynamoDB for recent opportunities
aws dynamodb scan \
    --table-name cost-optimization-tracking-* \
    --projection-expression "ResourceId, CheckName, EstimatedSavings" \
    --limit 10
```

## Customization

### Auto-Remediation Policies
Edit the Lambda function code to customize which cost optimization recommendations trigger automatic remediation:

```python
# In remediation function
def should_auto_remediate(opportunity):
    auto_remediate_checks = [
        'EC2 instances stopped',
        'EBS volumes unattached',
        'RDS idle DB instances'
    ]
    return opportunity['check_name'] in auto_remediate_checks
```

### Schedule Frequency
Modify the EventBridge schedule expression:
- `rate(1 day)` - Daily analysis
- `rate(12 hours)` - Twice daily
- `rate(1 week)` - Weekly analysis
- `cron(0 9 ? * MON-FRI *)` - Weekdays at 9 AM

### Notification Channels
Add additional SNS subscriptions for different notification channels:

```bash
# Add Slack webhook subscription
aws sns subscribe \
    --topic-arn arn:aws:sns:region:account:cost-optimization-alerts \
    --protocol https \
    --notification-endpoint https://hooks.slack.com/your-webhook-url
```

## Security Considerations

- **IAM Permissions**: The Lambda execution role follows least privilege principles
- **Encryption**: S3 bucket uses server-side encryption, DynamoDB uses encryption at rest
- **API Access**: Trusted Advisor API requires Business/Enterprise support plan
- **Resource Tagging**: All resources are tagged for cost tracking and governance
- **Backup Strategy**: EBS snapshots are created before volume deletion

## Troubleshooting

### Common Issues

1. **Support Plan Error**: Ensure you have Business or Enterprise support plan
2. **Permission Errors**: Verify IAM role has all required permissions
3. **Email Not Received**: Check spam folder and confirm SNS subscription
4. **Lambda Timeout**: Increase timeout for large accounts with many resources
5. **API Rate Limits**: Implement exponential backoff for API calls

### Debug Commands
```bash
# Check Lambda function configuration
aws lambda get-function-configuration \
    --function-name cost-optimization-analysis

# View recent CloudWatch logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/cost-optimization-analysis \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cost Estimates

### Monthly Operational Costs
- **Lambda Execution**: $5-15 (depends on frequency and account size)
- **DynamoDB**: $5-10 (depends on optimization opportunities found)
- **S3 Storage**: $1-5 (for reports and function code)
- **SNS Notifications**: $0.50-2 (depends on notification volume)
- **CloudWatch Logs**: $1-3 (depends on log retention)

**Total Estimated Monthly Cost**: $15-35

### Potential Savings
Based on AWS case studies, organizations typically save 10-30% on their AWS costs through automated optimization, often exceeding $1,000+ monthly for medium to large deployments.

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cost-optimization-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cost-optimization-stack
```

### Using CDK
```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm destruction
cdk list
```

### Using Terraform
```bash
# Destroy infrastructure
cd terraform/
terraform destroy \
    -var="notification_email=your-email@example.com" \
    -var="aws_region=us-east-1"

# Verify destruction
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
./scripts/destroy.sh --verify
```

## Advanced Features

### Multi-Account Support
For organizations with multiple AWS accounts, consider:
- AWS Organizations integration
- Cross-account IAM roles
- Centralized cost optimization dashboard
- Account-specific remediation policies

### Integration with CI/CD
- Deploy using AWS CodePipeline
- Implement infrastructure testing
- Automated rollback on failures
- Blue-green deployment strategies

### Enhanced Monitoring
- Custom CloudWatch metrics
- AWS X-Ray tracing for Lambda functions
- Integration with AWS Cost Explorer APIs
- Automated cost anomaly detection

## Support and Resources

- **Original Recipe**: Refer to the complete recipe documentation for detailed explanations
- **AWS Documentation**: [Trusted Advisor API Reference](https://docs.aws.amazon.com/awssupport/latest/user/trusted-advisor.html)
- **Cost Optimization**: [AWS Cost Optimization Best Practices](https://docs.aws.amazon.com/whitepapers/latest/cost-optimization-laying-the-foundation/welcome.html)
- **Lambda Best Practices**: [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)

## Contributing

When modifying the infrastructure code:
1. Follow AWS best practices and security guidelines
2. Test changes in a non-production environment
3. Update documentation to reflect changes
4. Consider backward compatibility with existing deployments
5. Validate cost implications of modifications

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.