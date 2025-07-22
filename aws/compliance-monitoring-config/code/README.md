# Infrastructure as Code for Compliance Monitoring with AWS Config

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Compliance Monitoring with AWS Config".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive compliance monitoring system using:

- **AWS Config**: Continuous resource configuration tracking
- **Config Rules**: Compliance evaluation (managed and custom)
- **Lambda Functions**: Custom rule evaluation and automated remediation
- **EventBridge**: Event-driven remediation triggers
- **SNS**: Compliance notifications
- **CloudWatch**: Monitoring dashboards and alarms
- **S3**: Configuration data storage
- **IAM Roles**: Secure service permissions

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Config (full access)
  - Lambda (create/manage functions)
  - IAM (create/manage roles and policies)
  - S3 (create/manage buckets)
  - SNS (create/manage topics)
  - CloudWatch (create dashboards and alarms)
  - EventBridge (create/manage rules)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Cost Considerations

**Estimated monthly cost: $10-30**

- AWS Config: $0.003 per configuration item recorded
- Lambda: $0.20 per 1M requests + compute time
- S3: $0.023 per GB stored
- SNS: $0.50 per 1M notifications
- CloudWatch: $0.50 per dashboard + $0.10 per alarm

> **Note**: Costs depend on the number of resources monitored and rule evaluations performed. Use resource-specific recording to control costs.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name compliance-monitoring-config \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name compliance-monitoring-config \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name compliance-monitoring-config \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Review changes
cdk diff

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Review changes
cdk diff

# Deploy the stack
cdk deploy

# Deactivate virtual environment when done
deactivate
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

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"

# Deploy the solution
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration Options

### Environment Variables

- `AWS_REGION`: AWS region for deployment (default: us-east-1)
- `NOTIFICATION_EMAIL`: Email address for compliance notifications
- `STACK_NAME`: CloudFormation stack name (default: compliance-monitoring-config)
- `RESOURCE_PREFIX`: Prefix for resource names (default: config-compliance)

### Customizable Parameters

#### CloudFormation Parameters

- `NotificationEmail`: Email for SNS notifications
- `ConfigBucketName`: S3 bucket name for Config data
- `EnableCustomRules`: Enable custom Lambda-based Config rules
- `ResourceTypes`: Comma-separated list of resource types to monitor

#### CDK Context Values

```json
{
  "notification-email": "your-email@example.com",
  "config-bucket-name": "custom-config-bucket-name",
  "enable-custom-rules": true,
  "resource-types": ["AWS::EC2::Instance", "AWS::S3::Bucket"]
}
```

#### Terraform Variables

```hcl
# terraform.tfvars
notification_email = "your-email@example.com"
config_bucket_name = "custom-config-bucket-name"
enable_custom_rules = true
resource_types = ["AWS::EC2::Instance", "AWS::S3::Bucket", "AWS::EC2::SecurityGroup"]
```

## Post-Deployment Verification

### 1. Verify Config Service Status

```bash
# Check Config recorder status
aws configservice get-status

# List Config rules
aws configservice describe-config-rules --query 'ConfigRules[].ConfigRuleName'
```

### 2. Test Compliance Monitoring

```bash
# Create a test EC2 instance without required tags
aws ec2 run-instances \
    --image-id ami-0abcdef1234567890 \
    --instance-type t2.micro

# Wait 60 seconds for Config to detect the resource
sleep 60

# Check compliance status
aws configservice get-compliance-summary-by-config-rule
```

### 3. View CloudWatch Dashboard

Navigate to CloudWatch Console → Dashboards → "ConfigComplianceDashboard"

### 4. Test SNS Notifications

Subscribe to the SNS topic created by the deployment to receive compliance notifications.

## Monitoring and Maintenance

### CloudWatch Metrics

Monitor these key metrics in the CloudWatch dashboard:

- **Config Rule Compliance**: Number of compliant/non-compliant resources
- **Remediation Function Performance**: Lambda invocation metrics
- **Config Service Health**: Delivery channel status

### Regular Maintenance Tasks

1. **Review Compliance Trends**: Weekly review of compliance dashboard
2. **Update Config Rules**: Monthly review of rule effectiveness
3. **Cost Optimization**: Monitor Config costs and adjust resource scope
4. **Security Review**: Quarterly review of IAM permissions and configurations

## Troubleshooting

### Common Issues

#### Config Recorder Not Starting

```bash
# Check IAM role permissions
aws iam get-role --role-name ConfigServiceRole

# Verify S3 bucket policy
aws s3api get-bucket-policy --bucket your-config-bucket
```

#### Lambda Function Errors

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/ConfigRemediation

# View recent errors
aws logs filter-log-events \
    --log-group-name /aws/lambda/ConfigRemediation-function \
    --filter-pattern "ERROR"
```

#### Missing Compliance Data

```bash
# Force rule evaluation
aws configservice start-config-rules-evaluation \
    --config-rule-names rule-name

# Check delivery channel status
aws configservice describe-delivery-channels
```

### Debug Mode

Enable debug logging by setting environment variables:

```bash
export DEBUG=true
export LOG_LEVEL=DEBUG
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name compliance-monitoring-config

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name compliance-monitoring-config \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources in this order:

1. Config Rules
2. Configuration Recorder
3. Delivery Channel
4. Lambda Functions
5. EventBridge Rules
6. CloudWatch Dashboards and Alarms
7. SNS Topics
8. S3 Bucket (empty first)
9. IAM Roles and Policies

## Security Considerations

### IAM Best Practices

- All roles follow least privilege principle
- Cross-service permissions are explicitly defined
- No hardcoded credentials in any implementation

### Data Protection

- Config data stored in encrypted S3 bucket
- Lambda function environment variables encrypted
- SNS topics support encryption in transit

### Network Security

- Lambda functions run in isolated execution environment
- No public internet access required for core functionality
- Security groups follow minimal access principles

## Advanced Customization

### Adding Custom Config Rules

1. Create new Lambda function with rule evaluation logic
2. Add Config rule pointing to Lambda function
3. Update IAM permissions for Lambda execution
4. Test rule evaluation with sample resources

### Integrating with External Systems

- **SIEM Integration**: Forward SNS notifications to security tools
- **ServiceNow Integration**: Create incidents for compliance violations
- **Slack/Teams**: Send notifications to collaboration platforms

### Multi-Account Deployment

For organization-wide compliance monitoring:

1. Deploy in master account with AWS Organizations
2. Use Config organizational rules for centralized management
3. Set up cross-account IAM roles for access
4. Aggregate compliance data using Config aggregator

## Support and Resources

### AWS Documentation

- [AWS Config Developer Guide](https://docs.aws.amazon.com/config/latest/developerguide/)
- [Config Rules Reference](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config.html)
- [Config Remediation Guide](https://docs.aws.amazon.com/config/latest/developerguide/setup-autoremediation.html)

### Best Practices

- [AWS Config Best Practices](https://docs.aws.amazon.com/config/latest/developerguide/best-practices.html)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [Cost Optimization Guide](https://aws.amazon.com/config/pricing/)

### Community Resources

- [AWS Config GitHub Examples](https://github.com/awslabs/aws-config-rules)
- [AWS Samples Repository](https://github.com/aws-samples/)
- [AWS Architecture Center](https://aws.amazon.com/architecture/)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the project repository.