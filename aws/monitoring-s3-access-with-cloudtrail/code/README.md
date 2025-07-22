# Infrastructure as Code for S3 Access Logging and Security Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Monitoring S3 Access with CloudTrail and EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - CloudTrail creation and management
  - CloudWatch Logs and Events
  - EventBridge rules and targets
  - SNS topics and subscriptions
  - Lambda function deployment
  - IAM role and policy management
- Valid email address for security alerts
- Estimated cost: $10-30/month for moderate usage

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name s3-security-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AlertEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name s3-security-monitoring \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
# Install dependencies
cd cdk-typescript/
npm install

# Set environment variables
export ALERT_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python
```bash
# Install dependencies
cd cdk-python/
pip install -r requirements.txt

# Set environment variables
export ALERT_EMAIL="your-email@example.com"

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform
```bash
# Initialize Terraform
cd terraform/
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
alert_email = "your-email@example.com"
aws_region = "us-east-1"
environment = "production"
EOF

# Plan deployment
terraform plan

# Apply changes
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export ALERT_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/validate.sh
```

## Architecture Overview

This infrastructure deploys a comprehensive S3 security monitoring solution including:

- **Source S3 Bucket**: Monitored bucket for security events
- **Access Logs Bucket**: Stores S3 server access logs with date-based partitioning
- **CloudTrail**: Captures API calls and data events for S3 operations
- **CloudWatch Integration**: Real-time log streaming and analysis
- **EventBridge Rules**: Automated detection of security events
- **SNS Alerts**: Immediate notifications for security incidents
- **Lambda Function**: Advanced security analysis and custom alerting
- **CloudWatch Dashboard**: Centralized monitoring and visualization

## Configuration Options

### CloudFormation Parameters

- `AlertEmail`: Email address for security notifications (required)
- `EnvironmentName`: Environment identifier for resource tagging
- `LogRetentionDays`: CloudWatch Logs retention period (default: 30 days)
- `EnableDataEvents`: Enable CloudTrail data events monitoring (default: true)

### CDK Context Variables

- `alertEmail`: Email address for security notifications
- `environment`: Environment name for resource tagging
- `logRetentionDays`: CloudWatch Logs retention period

### Terraform Variables

- `alert_email`: Email address for security notifications (required)
- `aws_region`: AWS region for deployment (default: us-east-1)
- `environment`: Environment name for tagging (default: production)
- `log_retention_days`: CloudWatch Logs retention period (default: 30)
- `enable_data_events`: Enable CloudTrail data events (default: true)

### Bash Script Environment Variables

- `ALERT_EMAIL`: Email address for security notifications (required)
- `AWS_REGION`: AWS region for deployment (required)
- `ENVIRONMENT`: Environment name for tagging (optional)

## Security Features

### Access Logging
- S3 Server Access Logging with date-based partitioning
- Comprehensive request logging including IP addresses and user agents
- Immutable audit trail for compliance requirements

### Real-time Monitoring
- CloudTrail integration for API call monitoring
- EventBridge rules for automated threat detection
- Lambda-based advanced security analysis

### Alerting System
- SNS notifications for immediate security alerts
- CloudWatch dashboards for operational visibility
- Custom security queries for threat hunting

### Compliance Support
- SOX, HIPAA, and PCI-DSS audit trail requirements
- Retention policies for regulatory compliance
- Encrypted log storage and transmission

## Validation & Testing

After deployment, validate the solution:

```bash
# Test S3 access logging
aws s3 cp test-file.txt s3://$(aws cloudformation describe-stacks --stack-name s3-security-monitoring --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' --output text)/

# Wait for logs to generate (5-10 minutes)
sleep 600

# Check access logs
aws s3 ls s3://$(aws cloudformation describe-stacks --stack-name s3-security-monitoring --query 'Stacks[0].Outputs[?OutputKey==`LogsBucketName`].OutputValue' --output text)/access-logs/ --recursive

# Test CloudTrail events
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=ResourceName,AttributeValue=$(aws cloudformation describe-stacks --stack-name s3-security-monitoring --query 'Stacks[0].Outputs[?OutputKey==`SourceBucketName`].OutputValue' --output text) \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)

# Test security alerts
aws sns publish \
    --topic-arn $(aws cloudformation describe-stacks --stack-name s3-security-monitoring --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' --output text) \
    --message "Test security alert"
```

## Monitoring & Operations

### CloudWatch Dashboard
Access the monitoring dashboard at:
```bash
aws cloudwatch get-dashboard --dashboard-name S3SecurityMonitoring
```

### Security Queries
Use these CloudWatch Insights queries for security analysis:

```sql
-- Failed access attempts
fields @timestamp, eventName, sourceIPAddress, errorCode
| filter errorCode = "AccessDenied"
| stats count() by sourceIPAddress
| sort count desc

-- Unusual access patterns
fields @timestamp, eventName, sourceIPAddress, userIdentity.type
| filter eventName like /GetObject|PutObject|DeleteObject/
| stats count() by sourceIPAddress
| sort count desc

-- Administrative actions
fields @timestamp, eventName, sourceIPAddress, userIdentity.arn
| filter eventName like /PutBucket|DeleteBucket|PutBucketPolicy/
| sort @timestamp desc
```

### Log Analysis
Access logs are stored in date-partitioned format:
```
s3://logs-bucket/access-logs/year=2024/month=01/day=15/
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name s3-security-monitoring

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name s3-security-monitoring \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cd cdk-typescript/ # or cdk-python/
cdk destroy --force

# Confirm deletion
cdk list
```

### Using Terraform
```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm deletion
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are deleted
./scripts/validate-cleanup.sh
```

## Customization

### Adding Custom Security Rules
Extend the EventBridge rules to detect additional security patterns:

```yaml
# CloudFormation example
CustomSecurityRule:
  Type: AWS::Events::Rule
  Properties:
    EventPattern:
      source: ["aws.s3"]
      detail-type: ["AWS API Call via CloudTrail"]
      detail:
        eventName: ["PutBucketEncryption", "DeleteBucketEncryption"]
    Targets:
      - Arn: !Ref SecurityAlertsTopic
        Id: "CustomSecurityTarget"
```

### Enhancing Lambda Security Analysis
Modify the Lambda function to implement custom security logic:

```python
def is_suspicious_activity(event_name, source_ip, user_identity):
    # Add custom security checks
    if event_name in ['DeleteBucket', 'PutBucketPolicy']:
        return True
    
    # Check for unusual geographic locations
    if is_unusual_location(source_ip):
        return True
    
    return False
```

### Adding Cross-Region Monitoring
Extend the solution to monitor S3 buckets across multiple regions:

```hcl
# Terraform example
module "s3_security_monitoring" {
  for_each = var.monitored_regions
  source = "./modules/s3-security"
  
  region = each.value
  alert_email = var.alert_email
  cross_region_trail = true
}
```

## Troubleshooting

### Common Issues

1. **CloudTrail Permission Errors**
   - Ensure CloudTrail service has proper S3 bucket permissions
   - Verify IAM role has correct assume role policy

2. **Missing Access Logs**
   - S3 Server Access Logging may take 1-2 hours to appear
   - Check bucket policy allows logging service access

3. **EventBridge Rule Not Triggering**
   - Verify EventBridge rule pattern matches CloudTrail event structure
   - Check SNS topic permissions for EventBridge

4. **Lambda Function Errors**
   - Review CloudWatch Logs for Lambda execution errors
   - Ensure Lambda has proper IAM permissions for SNS and CloudWatch

### Debug Commands

```bash
# Check CloudTrail status
aws cloudtrail get-trail-status --name s3-security-monitoring-trail

# Verify S3 logging configuration
aws s3api get-bucket-logging --bucket source-bucket-name

# Test EventBridge rule
aws events test-event-pattern \
    --event-pattern file://event-pattern.json \
    --event file://test-event.json

# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/s3-security-monitor
```

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../s3-access-logging-security-monitoring.md)
- [AWS CloudTrail documentation](https://docs.aws.amazon.com/cloudtrail/)
- [AWS S3 Server Access Logging documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ServerLogs.html)
- [AWS EventBridge documentation](https://docs.aws.amazon.com/eventbridge/)

## Cost Optimization

### Recommendations
- Use S3 lifecycle policies to transition old access logs to cheaper storage classes
- Set appropriate CloudWatch Logs retention periods to control costs
- Monitor CloudTrail data events volume to optimize costs
- Use S3 Intelligent Tiering for access logs bucket

### Cost Monitoring
```bash
# Monitor S3 storage costs
aws s3api get-bucket-location --bucket logs-bucket-name
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name BucketSizeBytes \
    --dimensions Name=BucketName,Value=logs-bucket-name \
    --start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 86400 \
    --statistics Average
```

## Compliance Features

### Regulatory Support
- **SOX**: Provides detailed audit trails for financial data access
- **HIPAA**: Ensures comprehensive logging for healthcare data
- **PCI-DSS**: Meets logging requirements for payment card data
- **GDPR**: Supports data access monitoring and breach notification

### Audit Trail
- Immutable log files with cryptographic integrity verification
- Detailed access patterns and user identity tracking
- Retention policies aligned with regulatory requirements
- Automated reporting capabilities for compliance audits