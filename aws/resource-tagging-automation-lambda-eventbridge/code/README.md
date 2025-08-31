# Infrastructure as Code for Resource Tagging Automation with Lambda and EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Resource Tagging Automation with Lambda and EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements automated resource tagging using:
- EventBridge rules to capture CloudTrail resource creation events
- Lambda function for processing events and applying standardized tags
- IAM roles with appropriate permissions for cross-service tagging
- Resource Groups for organizing and managing tagged resources

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrative permissions for:
  - IAM (roles, policies)
  - Lambda (function creation and execution)
  - EventBridge (rules and targets)
  - Resource Groups (group creation and management)
  - CloudTrail (must be enabled for event capture)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Appropriate AWS permissions for resource creation and tagging

> **Note**: CloudTrail must be enabled in your AWS account to capture resource creation events for the automation to function properly.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name resource-tagging-automation \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name resource-tagging-automation \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name resource-tagging-automation \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk ls --long
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

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk ls --long
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
aws lambda list-functions --query 'Functions[?contains(FunctionName, `auto-tagger`)].FunctionName'
```

## Configuration Options

### Environment Variables
Set these variables before deployment to customize the solution:

```bash
export AWS_REGION="us-east-1"                    # Target AWS region
export ENVIRONMENT="production"                  # Environment tag value
export COST_CENTER="engineering"                 # Cost center for tagging
export LAMBDA_TIMEOUT="60"                       # Lambda function timeout (seconds)
export LAMBDA_MEMORY="256"                       # Lambda memory allocation (MB)
```

### Customizable Parameters

- **Environment**: Target environment (production, staging, development)
- **CostCenter**: Default cost center for resource tagging
- **LambdaTimeout**: Function execution timeout (default: 60 seconds)
- **LambdaMemory**: Memory allocation for Lambda function (default: 256 MB)
- **TaggingScope**: Resource types to include in automated tagging

## Testing the Deployment

After deployment, test the automated tagging system:

```bash
# Create a test EC2 instance to trigger tagging
aws ec2 run-instances \
    --image-id $(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*" \
            "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text) \
    --instance-type t2.micro \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-auto-tagging}]'

# Wait for Lambda processing (30 seconds)
sleep 30

# Verify automated tags were applied
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=test-auto-tagging" \
    --query 'Reservations[].Instances[].Tags[?Key==`AutoTagged`]'
```

## Monitoring and Troubleshooting

### Check Lambda Function Logs
```bash
# View recent log events
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/auto-tagger-*" \
    --order-by LastEventTime --descending --max-items 1

# Get log events
aws logs get-log-events \
    --log-group-name "/aws/lambda/auto-tagger-*" \
    --log-stream-name "<LOG_STREAM_NAME>"
```

### Validate EventBridge Rule
```bash
# Check rule status
aws events describe-rule --name "resource-creation-rule-*"

# List rule targets
aws events list-targets-by-rule --rule "resource-creation-rule-*"
```

### Monitor Resource Group
```bash
# List resources in auto-tagged group
aws resource-groups list-group-resources \
    --group-name "auto-tagged-resources-*" \
    --query 'ResourceIdentifiers[*].[ResourceType,ResourceArn]' \
    --output table
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name resource-tagging-automation

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name resource-tagging-automation \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

## Cost Considerations

This solution uses serverless components with pay-per-use pricing:

- **Lambda**: $0.20 per 1M requests + compute time charges
- **EventBridge**: $1.00 per million events
- **CloudWatch Logs**: $0.50 per GB ingested + storage costs
- **Resource Groups**: No additional charges

Estimated monthly cost: $0.50 - $2.00 for typical usage patterns.

## Security Features

The IaC implementations include security best practices:

- IAM roles with least privilege access
- Resource-level permissions for tagging operations
- CloudWatch logging for audit trails
- Encrypted logs at rest
- VPC endpoint support for private communications

## Customization

### Adding New Resource Types
To extend tagging to additional AWS services, modify the EventBridge rule pattern and Lambda function logic:

1. Update EventBridge rule to include new service API calls
2. Add corresponding tagging logic in Lambda function
3. Ensure IAM role has permissions for new resource types

### Custom Tagging Logic
Modify the Lambda function to implement organization-specific tagging rules:

- Conditional tags based on resource attributes
- Integration with external systems (CMDB, ServiceNow)
- Time-based or schedule-driven tagging policies
- User identity-based tag assignments

### Integration with Cost Management
Extend the solution for advanced cost management:

- AWS Budgets integration for tag-based spending alerts
- Cost Explorer API integration for automated reporting
- Resource optimization recommendations based on tag analysis

## Troubleshooting

### Common Issues

1. **Tags not applied**: Check CloudTrail is enabled and EventBridge rule is active
2. **Permission errors**: Verify IAM role has necessary tagging permissions
3. **Lambda timeouts**: Increase timeout value or optimize function code
4. **Missing events**: Confirm EventBridge rule pattern matches target API calls

### Debug Steps

1. Check Lambda function logs in CloudWatch
2. Verify EventBridge rule metrics and invocations
3. Test Lambda function with sample CloudTrail events
4. Validate IAM permissions using policy simulator

## Support

For issues with this infrastructure code:
- Review the original recipe documentation
- Check AWS service documentation for latest API changes
- Validate CloudTrail configuration and event delivery
- Monitor CloudWatch metrics for system health

## Contributing

When modifying this infrastructure code:
- Follow AWS Well-Architected Framework principles
- Test changes in non-production environments
- Update documentation for any configuration changes  
- Validate security implications of modifications