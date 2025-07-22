# Infrastructure as Code for Security Scanning Automation with Inspector

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Security Scanning Automation with Inspector".

## Solution Overview

This solution implements an automated security scanning pipeline using Amazon Inspector for vulnerability assessment and AWS Security Hub for centralized security findings management. The infrastructure includes:

- Amazon Inspector configuration for EC2, ECR, and Lambda scanning
- AWS Security Hub with compliance standards enabled
- EventBridge rules for automated security event processing
- Lambda functions for security response automation
- SNS topics for security alerting
- Custom Security Hub insights for vulnerability tracking
- Automated compliance reporting capabilities

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - Amazon Inspector
  - AWS Security Hub
  - Amazon EventBridge
  - AWS Lambda
  - Amazon SNS
  - AWS IAM (for role creation)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python and Lambda functions)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $50-100/month for scanning 50 EC2 instances, 20 ECR repositories, and 10 Lambda functions

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name automated-security-scanning \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=security@yourdomain.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name automated-security-scanning \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name automated-security-scanning \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy AutomatedSecurityScanningStack \
    --parameters notificationEmail=security@yourdomain.com

# View stack outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy AutomatedSecurityScanningStack \
    --parameters notificationEmail=security@yourdomain.com

# View deployment outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="notification_email=security@yourdomain.com" \
    -var="aws_region=us-east-1"

# Apply the configuration
terraform apply \
    -var="notification_email=security@yourdomain.com" \
    -var="aws_region=us-east-1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="security@yourdomain.com"
export AWS_REGION="us-east-1"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/deploy.sh --status
```

## Configuration Options

### CloudFormation Parameters

- `NotificationEmail`: Email address for security alerts (required)
- `Environment`: Environment name for resource tagging (default: "production")
- `EnableComplianceReporting`: Enable automated compliance reporting (default: true)
- `ComplianceReportingSchedule`: Schedule for compliance reports (default: "rate(7 days)")

### CDK Context Variables

```json
{
  "notificationEmail": "security@yourdomain.com",
  "environment": "production",
  "enableComplianceReporting": true,
  "complianceReportingSchedule": "rate(7 days)",
  "inspectorScanMode": "EC2_HYBRID",
  "ecrRescanDuration": "DAYS_30"
}
```

### Terraform Variables

- `notification_email`: Email address for security alerts (required)
- `aws_region`: AWS region for deployment (default: "us-east-1")
- `environment`: Environment name for resource tagging (default: "production")
- `enable_compliance_reporting`: Enable automated compliance reporting (default: true)
- `inspector_scan_mode`: Inspector scanning mode (default: "EC2_HYBRID")
- `ecr_rescan_duration`: ECR container rescan frequency (default: "DAYS_30")

## Post-Deployment Configuration

### 1. Confirm SNS Subscription

After deployment, check your email for an SNS subscription confirmation:

```bash
# List SNS subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn $(terraform output -raw sns_topic_arn)
```

### 2. Verify Inspector Coverage

```bash
# Check Inspector scanning coverage
aws inspector2 get-coverage-statistics \
    --filter-criteria '{
        "resourceType": [{"comparison": "EQUALS", "value": "EC2_INSTANCE"}]
    }'
```

### 3. Review Security Hub Findings

```bash
# Get recent Security Hub findings
aws securityhub get-findings \
    --filters '{
        "CreatedAt": [{
            "Start": "'$(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S.%3NZ')'",
            "End": "'$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')'"
        }]
    }' \
    --max-items 10
```

### 4. Test Security Event Processing

```bash
# Trigger a test security event
aws events put-events \
    --entries '[{
        "Source": "aws.securityhub",
        "DetailType": "Security Hub Findings - Imported",
        "Detail": "{\"findings\":[{\"Id\":\"test-finding\",\"Title\":\"Test Security Finding\",\"Severity\":{\"Label\":\"HIGH\"},\"Resources\":[{\"Id\":\"test-resource\",\"Type\":\"AwsEc2Instance\"}]}]}"
    }]'
```

## Monitoring and Validation

### Security Hub Dashboard

Access the Security Hub console to view:
- Security findings summary
- Compliance status by standard
- Custom insights and trending data
- Resource-specific vulnerability reports

### CloudWatch Logs

Monitor Lambda function execution:

```bash
# View security response handler logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/security-response-handler"

# View compliance reporting logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/compliance-report-generator"
```

### EventBridge Metrics

Monitor event processing:

```bash
# View EventBridge rule metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name SuccessfulInvocations \
    --dimensions Name=RuleName,Value=security-findings-rule \
    --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S') \
    --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
    --period 300 \
    --statistics Sum
```

## Customization

### Adding Custom Security Standards

Modify the Security Hub configuration to include additional compliance standards:

```bash
# Enable PCI DSS standard
aws securityhub batch-enable-standards \
    --standards-subscription-requests '[{
        "StandardsArn": "arn:aws:securityhub:us-east-1::standard/pci-dss/v/3.2.1"
    }]'
```

### Custom Response Actions

Extend the Lambda response function to include custom remediation actions:

1. Edit the Lambda function code in `lambda-functions/security-response-handler.py`
2. Add custom logic for specific finding types
3. Redeploy using your chosen IaC method

### Additional Notification Channels

Add Slack, Microsoft Teams, or other notification integrations:

```bash
# Add Slack webhook to SNS topic
aws sns subscribe \
    --topic-arn $(terraform output -raw sns_topic_arn) \
    --protocol https \
    --notification-endpoint https://hooks.slack.com/your-webhook-url
```

## Troubleshooting

### Common Issues

1. **Inspector not scanning resources**
   - Verify IAM permissions for Inspector service role
   - Check that resources have required tags (if using tag-based filtering)
   - Ensure EC2 instances are in supported AMI types

2. **Security Hub findings not appearing**
   - Confirm Security Hub is enabled in the correct region
   - Verify Inspector findings integration is enabled
   - Check EventBridge rule configuration

3. **Lambda function failures**
   - Review CloudWatch Logs for error details
   - Verify IAM permissions for Lambda execution role
   - Check SNS topic permissions

4. **Missing SNS notifications**
   - Confirm email subscription is confirmed
   - Verify EventBridge rule is triggering correctly
   - Check Lambda function is processing events

### Debug Commands

```bash
# Check Security Hub status
aws securityhub describe-hub

# List Inspector assessments
aws inspector2 list-findings --max-results 10

# View EventBridge rule details
aws events describe-rule --name security-findings-rule

# Check Lambda function configuration
aws lambda get-function --function-name security-response-handler
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name automated-security-scanning

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name automated-security-scanning \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the infrastructure
cdk destroy AutomatedSecurityScanningStack

# Confirm destruction
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="notification_email=security@yourdomain.com" \
    -var="aws_region=us-east-1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
./scripts/destroy.sh --verify
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove these resources:

```bash
# Disable Security Hub
aws securityhub disable-security-hub

# Disable Inspector
aws inspector2 disable --resource-types EC2 ECR LAMBDA

# Delete any remaining SNS subscriptions
aws sns list-subscriptions --query 'Subscriptions[?contains(TopicArn, `security-alerts`)]'
```

## Security Considerations

### IAM Permissions

The solution follows the principle of least privilege:
- Inspector service role has minimal scanning permissions
- Lambda functions have specific permissions for their tasks
- Security Hub has read-only access to findings sources

### Data Protection

- All communications use HTTPS/TLS encryption
- SNS messages are encrypted in transit
- Lambda function logs are encrypted in CloudWatch
- No sensitive data is stored in plaintext

### Network Security

- Lambda functions run in VPC if specified
- Security groups restrict access to necessary ports only
- EventBridge rules use precise event filtering

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult AWS documentation for specific services:
   - [Amazon Inspector User Guide](https://docs.aws.amazon.com/inspector/latest/user/)
   - [AWS Security Hub User Guide](https://docs.aws.amazon.com/securityhub/latest/userguide/)
   - [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update documentation to reflect any changes
3. Follow AWS security best practices
4. Validate all IaC implementations work consistently
5. Update version numbers appropriately

## License

This infrastructure code is provided as-is for educational and implementation purposes. Please review and adapt according to your organization's requirements and policies.