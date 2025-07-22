# Infrastructure as Code for Cost Anomaly Detection with Machine Learning

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost Anomaly Detection with Machine Learning".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Cost Explorer and Cost Anomaly Detection
  - SNS topic creation and subscription management
  - Lambda function creation and execution
  - EventBridge rule management
  - CloudWatch dashboard and log group creation
  - IAM role creation (for Lambda execution)
- Cost Explorer enabled in your AWS account (required for Cost Anomaly Detection)
- At least 10 days of billing history for accurate anomaly detection
- Valid email address for SNS notifications

### Tool-specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js 18+ installed
- AWS CDK CLI installed (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8+ installed
- AWS CDK CLI installed (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.0+ installed
- AWS provider configured

## Quick Start

### Using CloudFormation
```bash
# Create stack with parameters
aws cloudformation create-stack \
    --stack-name cost-anomaly-detection-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name cost-anomaly-detection-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Set email parameter
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Set email parameter
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
aws_region = "us-east-1"
EOF

# Plan the deployment
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

# Set required environment variables
export COST_ANOMALY_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Architecture Components

The infrastructure includes:

- **Cost Anomaly Monitors**: Three monitors for comprehensive coverage
  - AWS Services Monitor (dimensional monitoring across all services)
  - Account-Based Monitor (monitoring by linked account)
  - Tag-Based Monitor (custom monitoring for Environment tags)
- **SNS Topic**: Central notification hub for cost anomaly alerts
- **Anomaly Subscriptions**: Two alert subscriptions
  - Daily Summary (consolidated daily reports)
  - Individual Alerts (immediate notifications via SNS)
- **EventBridge Rule**: Captures cost anomaly events for automated processing
- **Lambda Function**: Processes anomaly events and performs automated actions
- **CloudWatch Dashboard**: Visualization of cost anomaly trends and patterns
- **IAM Roles**: Least privilege execution roles for Lambda

## Configuration Options

### Email Notifications
- All implementations support configuring the notification email address
- SNS subscription confirmation required via email after deployment

### Anomaly Thresholds
- Daily Summary: $100 minimum impact threshold
- Individual Alerts: $50 minimum impact threshold
- Thresholds can be customized in the IaC templates

### Monitor Scope
- Service Monitor: All AWS services
- Account Monitor: All linked accounts in organization
- Tag Monitor: Resources tagged with Environment=Production or Environment=Staging

## Validation

After deployment, verify the setup:

1. **Check Cost Anomaly Monitors**:
   ```bash
   aws ce get-anomaly-monitors \
       --query 'AnomalyMonitors[*].{Name:MonitorName,Type:MonitorType}'
   ```

2. **Verify Subscriptions**:
   ```bash
   aws ce get-anomaly-subscriptions \
       --query 'AnomalySubscriptions[*].{Name:SubscriptionName,Frequency:Frequency}'
   ```

3. **Test SNS Notifications**:
   ```bash
   # Get SNS topic ARN from stack outputs
   TOPIC_ARN=$(aws cloudformation describe-stacks \
       --stack-name cost-anomaly-detection-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
       --output text)
   
   # Send test message
   aws sns publish \
       --topic-arn "$TOPIC_ARN" \
       --message "Test cost anomaly notification" \
       --subject "Cost Anomaly Detection Test"
   ```

4. **Check Lambda Function**:
   ```bash
   aws lambda get-function \
       --function-name cost-anomaly-processor \
       --query 'Configuration.{Name:FunctionName,State:State}'
   ```

5. **Verify CloudWatch Dashboard**:
   ```bash
   aws cloudwatch list-dashboards \
       --query 'DashboardEntries[?DashboardName==`Cost-Anomaly-Detection-Dashboard`]'
   ```

## Monitoring and Observability

### CloudWatch Dashboard
Access the dashboard at: https://console.aws.amazon.com/cloudwatch/home#dashboards:name=Cost-Anomaly-Detection-Dashboard

The dashboard includes:
- High impact cost anomalies (>$100)
- Anomaly count by severity level
- Recent anomaly trends and patterns

### Lambda Function Logs
Monitor Lambda execution:
```bash
aws logs tail /aws/lambda/cost-anomaly-processor --follow
```

### Cost Anomaly Detection Console
Monitor anomalies directly: https://console.aws.amazon.com/cost-management/home#/anomaly-detection

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cost-anomaly-detection-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name cost-anomaly-detection-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm destruction when prompted
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

# Confirm destruction when prompted
```

## Customization

### Modifying Anomaly Thresholds
Edit the threshold values in your chosen IaC template:
- CloudFormation: Update `DailySummaryThreshold` and `IndividualAlertThreshold` parameters
- CDK: Modify threshold values in the subscription configurations
- Terraform: Update `daily_threshold` and `individual_threshold` variables

### Adding Custom Monitors
To add additional monitors, extend the IaC templates with new monitor configurations:
```yaml
# CloudFormation example
CustomMonitor:
  Type: AWS::CE::AnomalyMonitor
  Properties:
    MonitorName: Custom-Monitor
    MonitorType: CUSTOM
    MonitorSpecification:
      Tags:
        Key: CostCenter
        Values: [Engineering, Marketing]
        MatchOptions: [EQUALS]
```

### Integrating with Additional Services
- **Slack Integration**: Add Slack webhook endpoints to SNS subscriptions
- **Service Desk Integration**: Extend Lambda function to create tickets
- **Custom Analytics**: Add additional CloudWatch Logs Insights queries

### Environment-Specific Configurations
- **Development**: Higher thresholds, less frequent notifications
- **Production**: Lower thresholds, immediate alerts, additional automation
- **Multi-Account**: Account-specific monitor configurations

## Cost Optimization

### Expected Costs
- **Cost Anomaly Detection**: Free service
- **SNS**: ~$0.50/month for 1,000 email notifications
- **Lambda**: ~$0.20/month for 1,000 executions
- **CloudWatch**: ~$0.50/month for dashboard and logs
- **Total**: ~$1.20/month estimated costs

### Cost Reduction Tips
- Adjust notification thresholds to reduce SNS costs
- Use daily summaries instead of individual alerts for non-critical environments
- Implement Lambda cost optimization with reserved concurrency
- Archive old CloudWatch logs to reduce storage costs

## Troubleshooting

### Common Issues

1. **Cost Explorer Not Enabled**:
   ```bash
   # Check if Cost Explorer is accessible
   aws ce get-cost-and-usage \
       --time-period Start=2024-01-01,End=2024-01-02 \
       --granularity MONTHLY \
       --metrics BlendedCost
   ```

2. **SNS Subscription Not Confirmed**:
   - Check email for confirmation message
   - Resend confirmation if needed:
   ```bash
   aws sns get-subscription-attributes \
       --subscription-arn <subscription-arn> \
       --query 'Attributes.ConfirmationWasAuthenticated'
   ```

3. **Lambda Execution Errors**:
   ```bash
   # Check Lambda logs
   aws logs filter-log-events \
       --log-group-name /aws/lambda/cost-anomaly-processor \
       --filter-pattern ERROR
   ```

4. **Missing Anomaly Data**:
   - Cost Anomaly Detection requires 10+ days of billing history
   - Check account billing history and Cost Explorer enablement

### Support Resources
- [AWS Cost Anomaly Detection Documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/getting-started-ad.html)
- [AWS SNS Troubleshooting Guide](https://docs.aws.amazon.com/sns/latest/dg/sns-troubleshooting.html)
- [AWS Lambda Troubleshooting](https://docs.aws.amazon.com/lambda/latest/dg/troubleshooting.html)
- [AWS EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/latest/userguide/what-is-amazon-eventbridge.html)

## Support

For issues with this infrastructure code, refer to:
1. The original recipe documentation
2. AWS service-specific documentation
3. Provider tool documentation (CDK, Terraform, etc.)
4. AWS Support (for service-specific issues)

## Security Considerations

- All IAM roles follow least privilege principle
- Lambda function has minimal required permissions
- SNS topic uses encryption in transit
- CloudWatch logs retain data for 14 days by default
- No hardcoded credentials or sensitive data in templates

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Validate with all provided IaC tools
3. Update documentation for any configuration changes
4. Follow AWS security and cost optimization best practices