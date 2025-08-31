# Infrastructure as Code for Simple Environment Health Check with Systems Manager and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Environment Health Check with Systems Manager and SNS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- At least one EC2 instance with SSM Agent installed and running
- Valid email address for SNS notifications
- For CDK deployments: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.5+ installed
- Appropriate AWS permissions for:
  - Systems Manager (SSM) operations
  - SNS topic and subscription management
  - Lambda function creation and execution
  - EventBridge rule creation
  - IAM role and policy management

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name environment-health-check \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name environment-health-check \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name environment-health-check \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set notification email (required)
export NOTIFICATION_EMAIL="your-email@example.com"

# Bootstrap CDK (if first time using CDK in this region)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# View stack outputs
npx cdk ls --long
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set notification email (required)
export NOTIFICATION_EMAIL="your-email@example.com"

# Bootstrap CDK (if first time using CDK in this region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls --long
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your email
echo 'notification_email = "your-email@example.com"' > terraform.tfvars

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set notification email
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Architecture Components

This IaC deploys the following AWS resources:

- **SNS Topic**: For health alert notifications
- **SNS Subscription**: Email subscription for alerts
- **Lambda Function**: Health check logic and compliance reporting
- **IAM Role**: Service role for Lambda with necessary permissions
- **IAM Policy**: Custom policy for Systems Manager and SNS access
- **EventBridge Rules**: 
  - Scheduled rule for periodic health checks (every 5 minutes)
  - Event-driven rule for compliance state change notifications
- **EventBridge Targets**: Lambda function and SNS topic targets
- **Lambda Permissions**: Allow EventBridge to invoke the function

## Configuration Options

### Environment Variables

- `NOTIFICATION_EMAIL`: Email address for health alert notifications (required)
- `AWS_REGION`: AWS region for deployment (defaults to current CLI region)
- `HEALTH_CHECK_SCHEDULE`: Schedule expression for health checks (default: "rate(5 minutes)")

### Customizable Parameters

- **Health Check Frequency**: Modify the EventBridge schedule expression
- **Email Recipients**: Add multiple SNS subscriptions for different notification channels
- **Lambda Memory**: Adjust function memory allocation (default: 256MB)
- **Lambda Timeout**: Configure function timeout (default: 60 seconds)
- **Compliance Type**: Customize the compliance type name (default: "Custom:EnvironmentHealth")

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email and confirm the SNS subscription
2. **Verify Instance Coverage**: Ensure your EC2 instances have SSM Agent installed and are managed
3. **Test Health Checks**: Manually invoke the Lambda function to verify functionality
4. **Monitor Compliance**: Check Systems Manager compliance dashboard for health status

## Monitoring and Validation

### Verify Deployment

```bash
# Check SNS topic
aws sns list-topics --query 'Topics[?contains(TopicArn, `environment-health-alerts`)]'

# Verify Lambda function
aws lambda list-functions --query 'Functions[?contains(FunctionName, `environment-health-check`)]'

# Check EventBridge rules
aws events list-rules --query 'Rules[?contains(Name, `health-check`)]'

# Test Lambda function
aws lambda invoke \
    --function-name $(aws lambda list-functions --query 'Functions[?contains(FunctionName, `environment-health-check`)].FunctionName' --output text) \
    --payload '{"source":"manual-test"}' \
    response.json && cat response.json
```

### Monitor Health Checks

```bash
# View compliance summary
aws ssm list-compliance-summaries \
    --query 'ComplianceSummaryItems[?ComplianceType==`Custom:EnvironmentHealth`]'

# Check Lambda logs
aws logs tail /aws/lambda/$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `environment-health-check`)].FunctionName' --output text) --follow

# View EventBridge rule metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name SuccessfulInvocations \
    --dimensions Name=RuleName,Value=$(aws events list-rules --query 'Rules[?contains(Name, `health-check-schedule`)].Name' --output text) \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name environment-health-check

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name environment-health-check \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Destroy the stack
npx cdk destroy

# Confirm destruction
npx cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Destroy the stack
cdk destroy

# Deactivate virtual environment
deactivate
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm all resources are removed
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
./scripts/destroy.sh --verify
```

## Troubleshooting

### Common Issues

1. **Email Subscription Not Confirmed**: Check your email (including spam folder) and confirm the SNS subscription
2. **No EC2 Instances Found**: Ensure you have running EC2 instances with SSM Agent installed
3. **Permission Errors**: Verify your AWS credentials have sufficient permissions for all required services
4. **Lambda Function Timeouts**: Check CloudWatch logs for detailed error information

### Debug Commands

```bash
# Check IAM role permissions
aws iam get-role --role-name $(aws iam list-roles --query 'Roles[?contains(RoleName, `HealthCheckLambdaRole`)].RoleName' --output text)

# Verify EventBridge rule configuration
aws events describe-rule --name $(aws events list-rules --query 'Rules[?contains(Name, `health-check-schedule`)].Name' --output text)

# Test SNS topic publishing
aws sns publish \
    --topic-arn $(aws sns list-topics --query 'Topics[?contains(TopicArn, `environment-health-alerts`)].TopicArn' --output text) \
    --subject "Test Health Alert" \
    --message "Test notification from environment health monitoring system."
```

### Performance Optimization

- **Lambda Memory**: Increase memory allocation if processing many instances
- **Check Frequency**: Adjust EventBridge schedule based on your monitoring requirements
- **Compliance Retention**: Configure compliance data retention policies in Systems Manager
- **Cost Management**: Monitor SNS usage and Lambda invocations for cost optimization

## Security Considerations

- **Least Privilege**: IAM roles follow least privilege principle
- **Encryption**: SNS topics use default AWS managed encryption
- **VPC Integration**: Lambda function can be configured for VPC deployment if required
- **Access Logging**: Enable CloudTrail for audit logging of all API calls

## Cost Estimation

Approximate monthly costs (US East 1 region):

- **Lambda**: ~$0.20 (free tier covers 1M requests and 400,000 GB-seconds)
- **SNS**: ~$0.50 per million notifications
- **EventBridge**: ~$1.00 per million events
- **Systems Manager**: No additional charges for compliance features
- **CloudWatch Logs**: ~$0.50 per GB ingested

Total estimated monthly cost: **$1.00-$3.00** depending on usage

## Support

For issues with this infrastructure code, refer to:

1. **Original Recipe**: `../simple-environment-health-check-ssm-sns.md`
2. **AWS Documentation**: 
   - [Systems Manager Compliance](https://docs.aws.amazon.com/systems-manager/latest/userguide/compliance-about.html)
   - [EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
   - [Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
3. **AWS Support**: Contact AWS Support for service-specific issues
4. **Community**: AWS forums and Stack Overflow for community support

## Contributing

To improve this IaC implementation:

1. Test changes in a development environment
2. Ensure all IaC types remain synchronized
3. Update documentation for any new parameters or outputs
4. Follow AWS best practices and security guidelines