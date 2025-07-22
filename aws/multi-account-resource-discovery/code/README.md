# Infrastructure as Code for Multi-Account Resource Discovery Automation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Account Resource Discovery Automation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)  
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with administrator privileges
- AWS Organizations enabled with management account access
- Multiple AWS accounts in your organization (minimum 2 for testing)
- Node.js 16+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)
- Appropriate IAM permissions for:
  - AWS Resource Explorer operations
  - AWS Config service management
  - AWS Organizations trusted access
  - Lambda function creation and execution
  - EventBridge rule management
  - S3 bucket creation and management

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name multi-account-discovery \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-discovery-system \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name multi-account-discovery

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name multi-account-discovery \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy MultiAccountDiscoveryStack

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

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy MultiAccountDiscoveryStack

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_name=my-discovery-system"

# Apply the configuration
terraform apply -var="project_name=my-discovery-system"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and wait for deployment to complete
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| ProjectName | Unique name for the project resources | multi-account-discovery | No |
| EnableScheduledDiscovery | Enable daily scheduled resource discovery | true | No |
| LambdaMemorySize | Memory allocation for Lambda function | 512 | No |
| ConfigDeliveryFrequency | Config snapshot delivery frequency | TwentyFour_Hours | No |

### CDK Configuration

Customize the deployment by modifying the stack parameters in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript example
const stack = new MultiAccountDiscoveryStack(app, 'MultiAccountDiscoveryStack', {
  projectName: 'my-discovery-system',
  enableScheduledDiscovery: true,
  lambdaMemorySize: 512,
  env: { 
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION 
  }
});
```

### Terraform Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| project_name | Unique name for project resources | "multi-account-discovery" | string |
| aws_region | AWS region for deployment | "us-east-1" | string |
| enable_scheduled_discovery | Enable scheduled discovery tasks | true | bool |
| lambda_memory_size | Lambda function memory (MB) | 512 | number |
| config_delivery_frequency | Config delivery frequency | "TwentyFour_Hours" | string |

Create a `terraform.tfvars` file for customization:

```hcl
project_name = "my-company-discovery"
aws_region = "us-west-2"
enable_scheduled_discovery = true
lambda_memory_size = 1024
```

## Post-Deployment Configuration

### 1. Member Account Setup

After deploying the management account infrastructure, configure member accounts:

```bash
# For each member account, deploy Resource Explorer index
aws resource-explorer-2 create-index \
    --type LOCAL \
    --region us-east-1 \
    --profile member-account-profile

# Enable Config service in member accounts
aws configservice put-configuration-recorder \
    --configuration-recorder name=default,roleARN=arn:aws:iam::ACCOUNT-ID:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig \
    --profile member-account-profile
```

### 2. Verify Multi-Account Discovery

Test the resource discovery functionality:

```bash
# Search for EC2 instances across all accounts
aws resource-explorer-2 search \
    --query-string "resourcetype:AWS::EC2::Instance" \
    --max-results 50

# Check Config aggregator compliance data
aws configservice get-aggregate-compliance-summary \
    --configuration-aggregator-name PROJECT_NAME-aggregator
```

### 3. Monitor Lambda Function

Check Lambda execution logs:

```bash
# View recent Lambda logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/PROJECT_NAME-processor \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name multi-account-discovery

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name multi-account-discovery
```

### Using CDK

```bash
# Destroy the CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy MultiAccountDiscoveryStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_name=my-discovery-system"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Architecture Overview

The deployed infrastructure includes:

- **AWS Resource Explorer**: Aggregated index for multi-account resource search
- **AWS Config**: Organizational aggregator for compliance monitoring
- **Amazon EventBridge**: Event routing for automated responses
- **AWS Lambda**: Intelligent event processing and automation
- **IAM Roles**: Service-linked and custom roles with least privilege
- **S3 Bucket**: Config data storage with appropriate policies
- **Config Rules**: Compliance monitoring for security best practices

## Security Considerations

### IAM Permissions

The infrastructure deploys with minimal required permissions:

- Service-linked roles for Resource Explorer and Config
- Lambda execution role with scoped permissions
- Config delivery role for S3 access
- EventBridge permissions for Lambda invocation

### Data Encryption

- S3 bucket uses server-side encryption by default
- Lambda environment variables encrypted with AWS KMS
- Config data encrypted in transit and at rest

### Network Security

- All resources deployed within AWS backbone
- No public endpoints exposed
- VPC configuration optional for enhanced isolation

## Monitoring and Observability

### CloudWatch Integration

- Lambda function metrics and logs
- Config compliance metrics
- EventBridge rule execution metrics
- Custom dashboards for operational visibility

### Cost Monitoring

Estimated monthly costs:
- Resource Explorer: $0.01 per 1000 resource API calls
- Config: $2.00 per configuration recorder per region
- Lambda: Pay-per-execution model
- S3 Storage: $0.023 per GB per month
- EventBridge: $1.00 per million events

## Troubleshooting

### Common Issues

1. **Trusted Access Not Enabled**
   ```bash
   # Enable trusted access manually
   aws organizations enable-aws-service-access \
       --service-principal resource-explorer-2.amazonaws.com
   ```

2. **Config Aggregator Permission Errors**
   ```bash
   # Verify service-linked role exists
   aws iam get-role \
       --role-name AWSServiceRoleForConfig
   ```

3. **Lambda Function Timeout**
   - Increase memory allocation in configuration
   - Check CloudWatch logs for detailed error messages
   - Verify IAM permissions for cross-service calls

4. **Resource Explorer Index Creation Failed**
   - Ensure AWS region supports Resource Explorer
   - Check account limits for Resource Explorer indexes
   - Verify IAM permissions for index management

### Debug Commands

```bash
# Check Resource Explorer index status
aws resource-explorer-2 get-index --region us-east-1

# Verify Config service status
aws configservice describe-configuration-recorders

# Test EventBridge rule targets
aws events list-targets-by-rule --rule RULE-NAME

# Check Lambda function configuration
aws lambda get-function --function-name FUNCTION-NAME
```

## Advanced Configuration

### Custom Compliance Rules

Extend the solution with additional Config rules:

```bash
# Deploy custom compliance rule
aws configservice put-config-rule \
    --config-rule file://custom-rule.json
```

### Multi-Region Setup

Deploy across multiple regions for comprehensive coverage:

```bash
# Deploy to additional regions
aws cloudformation create-stack \
    --stack-name multi-account-discovery-eu \
    --template-body file://cloudformation.yaml \
    --region eu-west-1
```

### Integration with External Systems

Configure webhooks for external system integration:

```python
# Lambda function example for external integration
def send_to_external_system(compliance_data):
    webhook_url = os.environ['WEBHOOK_URL']
    requests.post(webhook_url, json=compliance_data)
```

## Support and Documentation

- [AWS Resource Explorer Documentation](https://docs.aws.amazon.com/resource-explorer/)
- [AWS Config Multi-Account Setup](https://docs.aws.amazon.com/config/latest/developerguide/aggregate-data.html)
- [AWS Organizations Best Practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support channels.

## Version Information

- Template Version: 1.0
- Last Updated: 2025-07-12
- Compatible AWS CLI Version: 2.0+
- CDK Version: 2.0+
- Terraform Version: 1.0+