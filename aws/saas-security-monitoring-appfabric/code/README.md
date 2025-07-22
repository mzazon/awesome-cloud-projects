# Infrastructure as Code for Centralized SaaS Security Monitoring with AWS AppFabric and EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "SaaS Security Monitoring with AppFabric".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a comprehensive security monitoring system that:
- Connects to multiple SaaS applications via AWS AppFabric
- Normalizes security logs using Open Cybersecurity Schema Framework (OCSF)
- Processes events through EventBridge and Lambda
- Delivers intelligent alerts via SNS to multiple channels
- Provides scalable, serverless security monitoring

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with permissions for AppFabric, EventBridge, Lambda, SNS, S3, and IAM
- Access to supported SaaS applications (Slack, Microsoft 365, Salesforce, etc.)
- Basic understanding of event-driven architectures and security monitoring
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

## Cost Estimates

- AWS AppFabric: ~$2-10/month per connected application
- Lambda: ~$1-5/month for processing (depends on log volume)
- S3 Storage: ~$1-3/month for log storage
- EventBridge: ~$1-2/month for event processing
- SNS: ~$0.50-2/month for notifications
- **Total estimated cost**: $20-50/month depending on usage

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name saas-security-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=security@yourcompany.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name saas-security-monitoring \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name saas-security-monitoring \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment (optional)
export CDK_DEFAULT_REGION=us-east-1
export NOTIFICATION_EMAIL=security@yourcompany.com

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters NotificationEmail=security@yourcompany.com

# View stack outputs
cdk ls -l
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

# Configure environment (optional)
export CDK_DEFAULT_REGION=us-east-1
export NOTIFICATION_EMAIL=security@yourcompany.com

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters NotificationEmail=security@yourcompany.com

# View stack outputs
cdk ls -l
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the plan
terraform plan -var="notification_email=security@yourcompany.com"

# Apply the configuration
terraform apply -var="notification_email=security@yourcompany.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=security@yourcompany.com
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Post-Deployment Configuration

After deploying the infrastructure, manual configuration is required for SaaS application connections:

1. **Configure AppFabric Ingestions**:
   ```bash
   # Get the App Bundle ARN from stack outputs
   APP_BUNDLE_ARN=$(aws cloudformation describe-stacks \
       --stack-name saas-security-monitoring \
       --query 'Stacks[0].Outputs[?OutputKey==`AppBundleArn`].OutputValue' \
       --output text)
   
   echo "App Bundle ARN: $APP_BUNDLE_ARN"
   ```

2. **Use AWS Console to**:
   - Navigate to AWS AppFabric console
   - Create ingestions for your SaaS applications
   - Authorize AppFabric to access SaaS APIs
   - Configure S3 destination for security logs

3. **Confirm SNS Subscription**:
   - Check your email for SNS subscription confirmation
   - Click the confirmation link to receive alerts

## Validation & Testing

### Test the Security Monitoring Pipeline

```bash
# Get S3 bucket name from outputs
S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name saas-security-monitoring \
    --query 'Stacks[0].Outputs[?OutputKey==`SecurityLogsBucket`].OutputValue' \
    --output text)

# Create and upload a test security event
cat > test-security-event.json << EOF
{
  "metadata": {
    "version": "1.0.0",
    "product": {
      "name": "Test SaaS Application",
      "vendor_name": "Test Vendor"
    }
  },
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "class_uid": 3002,
  "category_uid": 3,
  "severity_id": 2,
  "activity_id": 1,
  "type_name": "Authentication: Logon",
  "user": {
    "name": "test.user@example.com",
    "type": "User"
  },
  "src_endpoint": {
    "ip": "192.168.1.100"
  },
  "status": "Success"
}
EOF

# Upload test event to trigger processing
aws s3 cp test-security-event.json \
    s3://${S3_BUCKET}/security-logs/test-app/$(date +%Y/%m/%d)/test-event-$(date +%s).json

# Clean up test file
rm test-security-event.json

echo "Test event uploaded. Check your email for security alert notification."
```

### Monitor System Health

```bash
# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/security-processor-* \
    --start-time $(date -d '1 hour ago' +%s)000

# View EventBridge metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name SuccessfulInvocations \
    --dimensions Name=RuleName,Value=SecurityLogProcessingRule-* \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 3600 \
    --statistics Sum
```

## Customization

### Key Configuration Parameters

All implementations support these customization options:

- **NotificationEmail**: Email address for security alerts
- **S3BucketPrefix**: Custom prefix for S3 bucket names
- **LambdaMemorySize**: Memory allocation for Lambda function (default: 256 MB)
- **LambdaTimeout**: Timeout for Lambda function (default: 60 seconds)
- **LogRetentionDays**: CloudWatch log retention period (default: 30 days)

### Environment-Specific Variables

```bash
# Development environment
export ENVIRONMENT=dev
export LOG_LEVEL=DEBUG
export ALERT_THRESHOLD=LOW

# Production environment
export ENVIRONMENT=prod
export LOG_LEVEL=INFO
export ALERT_THRESHOLD=MEDIUM
```

### Advanced Configuration

For advanced customization, modify the following components:

1. **Lambda Function Logic**: Update security processing rules in the Lambda function code
2. **EventBridge Rules**: Modify event patterns for different filtering criteria
3. **SNS Topics**: Add additional notification endpoints (Slack, PagerDuty, etc.)
4. **IAM Policies**: Adjust permissions for specific security requirements

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name saas-security-monitoring

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name saas-security-monitoring \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# TypeScript
cd cdk-typescript/
cdk destroy

# Python
cd cdk-python/
source .venv/bin/activate
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="notification_email=security@yourcompany.com"
```

### Using Bash Scripts

```bash
# Run the destruction script
./scripts/destroy.sh

# Confirm all resources are removed
./scripts/destroy.sh --verify
```

### Manual Cleanup Steps

Some resources may require manual cleanup:

1. **AppFabric Ingestions**: Remove SaaS application authorizations
2. **S3 Bucket Contents**: Empty S3 buckets if they contain data
3. **CloudWatch Logs**: Log groups may persist beyond stack deletion

## Troubleshooting

### Common Issues

1. **AppFabric Region Availability**:
   ```bash
   # Verify AppFabric is available in your region
   aws appfabric list-app-bundles --region us-east-1
   ```

2. **IAM Permissions**:
   ```bash
   # Check your IAM permissions
   aws sts get-caller-identity
   aws iam get-user
   ```

3. **Lambda Function Errors**:
   ```bash
   # Check Lambda logs for errors
   aws logs describe-log-groups --log-group-name-prefix /aws/lambda/security-processor
   ```

4. **EventBridge Rule Issues**:
   ```bash
   # List EventBridge rules
   aws events list-rules --name-prefix SecurityLogProcessingRule
   ```

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export DEBUG=true
export AWS_CLI_FILE_ENCODING=UTF-8
export AWS_DEFAULT_OUTPUT=json
```

## Security Considerations

This solution implements several security best practices:

- **Least Privilege IAM**: All roles follow principle of least privilege
- **Encryption at Rest**: S3 buckets use AES-256 encryption
- **Encryption in Transit**: All service communications use TLS
- **Network Security**: Lambda functions run in isolated execution environments
- **Access Logging**: CloudTrail integration for audit trails
- **Monitoring**: CloudWatch alarms for security events

## Support and Documentation

- [AWS AppFabric Documentation](https://docs.aws.amazon.com/appfabric/)
- [Amazon EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Open Cybersecurity Schema Framework (OCSF)](https://ocsf.io/)
- [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)

For issues with this infrastructure code, refer to the original recipe documentation or submit issues through your organization's support channels.

## Contributing

When modifying this infrastructure code:

1. Test all changes in a development environment
2. Follow AWS security best practices
3. Update documentation for any configuration changes
4. Validate IaC syntax before deployment
5. Test cleanup procedures thoroughly