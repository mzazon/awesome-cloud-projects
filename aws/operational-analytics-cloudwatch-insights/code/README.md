# Infrastructure as Code for Analyzing Operational Data with CloudWatch Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Analyzing Operational Data with CloudWatch Insights".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for CloudWatch, Lambda, SNS, and IAM services
- For CDK implementations: Node.js 16+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Valid email address for SNS alert subscriptions
- Estimated cost: $10-50/month for log storage and query execution

> **Note**: CloudWatch Logs Insights queries are charged based on the amount of data scanned. The generated infrastructure includes cost optimization features like log retention policies and volume monitoring.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name operational-analytics-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@domain.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment
aws cloudformation wait stack-create-complete \
    --stack-name operational-analytics-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name operational-analytics-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure email parameter
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy \
    --parameters NotificationEmail=your-email@domain.com

# View outputs
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy \
    --parameters NotificationEmail=your-email@domain.com

# View outputs
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="notification_email=your-email@domain.com"

# Apply the configuration
terraform apply \
    -var="notification_email=your-email@domain.com"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts to enter your email address
# The script will create all necessary resources and configure monitoring
```

## Post-Deployment Steps

After deploying the infrastructure:

1. **Confirm SNS Subscription**: Check your email and confirm the SNS subscription to receive operational alerts.

2. **Generate Sample Data**: The Lambda function is automatically deployed. Invoke it to generate sample log data:
   ```bash
   # Get function name from outputs
   FUNCTION_NAME=$(aws cloudformation describe-stacks \
       --stack-name operational-analytics-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`LogGeneratorFunction`].OutputValue' \
       --output text)
   
   # Generate sample data
   for i in {1..5}; do
       aws lambda invoke \
           --function-name "$FUNCTION_NAME" \
           --payload '{}' \
           output.txt
       sleep 2
   done
   ```

3. **Access Dashboard**: Use the dashboard URL from the stack outputs to view operational analytics.

4. **Test Queries**: Navigate to CloudWatch Logs Insights and test the pre-built queries on the created log group.

## Architecture Overview

The deployed infrastructure includes:

- **Log Generation**: Lambda function that creates realistic operational log data
- **Log Storage**: CloudWatch Log Group with optimized retention policies
- **Analytics Engine**: CloudWatch Logs Insights for querying and analysis
- **Visualization**: CloudWatch Dashboard with embedded analytics widgets
- **Alerting**: CloudWatch Alarms with SNS notifications for operational issues
- **Cost Optimization**: Automated log lifecycle management and volume monitoring
- **Anomaly Detection**: Machine learning-based pattern detection for log ingestion

## Customization

### Key Parameters

| Parameter | Description | Default | CloudFormation | CDK | Terraform |
|-----------|-------------|---------|----------------|-----|-----------|
| Notification Email | Email for operational alerts | Required | ✅ | ✅ | ✅ |
| Log Retention Days | Days to retain log data | 30 | ✅ | ✅ | ✅ |
| Environment | Deployment environment | prod | ✅ | ✅ | ✅ |
| Dashboard Name | Custom dashboard name | Auto-generated | ✅ | ✅ | ✅ |
| Error Threshold | Error rate alarm threshold | 5 | ✅ | ✅ | ✅ |

### Advanced Configuration

#### Log Volume Monitoring
```bash
# Adjust log volume threshold (logs per hour)
# CloudFormation
--parameters ParameterKey=LogVolumeThreshold,ParameterValue=15000

# Terraform
-var="log_volume_threshold=15000"
```

#### Custom Retention Policies
```bash
# Set different retention periods
# CloudFormation
--parameters ParameterKey=LogRetentionDays,ParameterValue=14

# Terraform
-var="log_retention_days=14"
```

## Monitoring and Operations

### Key Metrics to Monitor

1. **Error Rate**: Number of ERROR-level log entries per time period
2. **Log Volume**: Total log ingestion volume for cost management
3. **Query Performance**: CloudWatch Insights query execution times
4. **Anomaly Detection**: Deviations from normal log patterns

### Operational Dashboards

The deployment creates a comprehensive dashboard with:
- Real-time error analysis trends
- Performance metrics visualization
- Top active users analysis
- Cost optimization metrics

### Alert Configuration

Alerts are configured for:
- High error rates (> 5 errors in 10 minutes)
- Excessive log volume (> 10,000 entries per hour)
- Log ingestion anomalies (ML-detected patterns)

## Cost Optimization

The infrastructure includes several cost optimization features:

- **Log Retention**: Automatic cleanup after 30 days (configurable)
- **Volume Monitoring**: Alerts for unexpected log volume spikes
- **Query Optimization**: Time-based filters in dashboard queries
- **Resource Tagging**: Comprehensive tagging for cost allocation

### Estimated Costs

| Service | Usage | Monthly Cost (USD) |
|---------|-------|-------------------|
| CloudWatch Logs | 10GB ingestion, 30-day retention | $5-15 |
| CloudWatch Insights | 100 queries, 1GB scanned each | $10-20 |
| Lambda | 1,000 invocations/month | $0.20 |
| SNS | 100 notifications/month | $0.06 |
| CloudWatch Alarms | 5 alarms | $3.50 |
| **Total** | | **$18.76-38.76** |

> **Tip**: Use the log volume alarm to prevent unexpected cost spikes from verbose application logging.

## Troubleshooting

### Common Issues

1. **Dashboard Not Loading**:
   ```bash
   # Verify dashboard exists
   aws cloudwatch describe-dashboards \
       --dashboard-name-prefix "OperationalAnalytics"
   ```

2. **No Log Data**:
   ```bash
   # Check log group exists and has data
   aws logs describe-log-groups \
       --log-group-name-prefix "/aws/lambda/operational-analytics"
   
   # Generate sample data manually
   aws lambda invoke \
       --function-name <function-name> \
       --payload '{}' output.txt
   ```

3. **Alarms Not Triggering**:
   ```bash
   # Check alarm state
   aws cloudwatch describe-alarms \
       --alarm-names "HighErrorRate-*"
   
   # Verify metric filters
   aws logs describe-metric-filters \
       --log-group-name <log-group-name>
   ```

4. **SNS Subscription Issues**:
   ```bash
   # Check subscription status
   aws sns list-subscriptions-by-topic \
       --topic-arn <topic-arn>
   
   # Resend confirmation if needed
   aws sns confirm-subscription \
       --topic-arn <topic-arn> \
       --token <confirmation-token>
   ```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name operational-analytics-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name operational-analytics-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy

# Confirm deletion when prompted
```

### Using CDK Python
```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="notification_email=your-email@domain.com"

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

After automated cleanup, verify all resources are removed:

```bash
# Check for remaining log groups
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/operational-analytics"

# Check for remaining alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix "HighErrorRate"

# Check for remaining Lambda functions
aws lambda list-functions \
    --function-version ALL \
    --query 'Functions[?starts_with(FunctionName, `log-generator`)]'
```

## Security Considerations

The infrastructure implements security best practices:

- **IAM Least Privilege**: Lambda functions have minimal required permissions
- **Encryption**: CloudWatch Logs encrypted at rest and in transit
- **Access Control**: Dashboard access controlled via AWS IAM
- **Network Security**: No public internet exposure of resources
- **Audit Trail**: All actions logged in CloudTrail

## Integration with Existing Systems

### CI/CD Integration

```bash
# Example GitLab CI integration
deploy_analytics:
  script:
    - cd terraform/
    - terraform init
    - terraform plan -var="notification_email=$ALERT_EMAIL"
    - terraform apply -auto-approve -var="notification_email=$ALERT_EMAIL"
```

### Application Integration

```javascript
// Example: Sending structured logs from Node.js application
const winston = require('winston');
const CloudWatchTransport = require('winston-cloudwatch');

const logger = winston.createLogger({
  transports: [
    new CloudWatchTransport({
      logGroupName: '/aws/lambda/operational-analytics-demo',
      logStreamName: 'application-logs',
      awsOptions: {
        region: 'us-east-1'
      }
    })
  ]
});

// Structured logging for analytics
logger.info(JSON.stringify({
  level: 'INFO',
  message: 'User authentication successful',
  user_id: 'user_1234',
  response_time: 245,
  timestamp: new Date().toISOString()
}));
```

## Support

For issues with this infrastructure code:

1. Check the [troubleshooting section](#troubleshooting) above
2. Refer to the [original recipe documentation](../operational-analytics-cloudwatch-insights.md)
3. Consult AWS documentation for CloudWatch Logs Insights
4. Review CloudFormation/CDK/Terraform provider documentation

## Related Resources

- [AWS CloudWatch Logs Insights Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html)
- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [AWS Well-Architected Framework - Operational Excellence](https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/welcome.html)
- [CloudWatch Anomaly Detection Best Practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Anomaly_Detector.html)