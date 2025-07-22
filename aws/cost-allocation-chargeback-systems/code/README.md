# Infrastructure as Code for Cost Allocation and Chargeback Systems

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost Allocation and Chargeback Systems".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with Organizations and consolidated billing enabled
- Management account access with billing permissions
- Appropriate IAM permissions for:
  - AWS Organizations
  - Cost Explorer
  - AWS Budgets
  - Lambda functions
  - SNS topics
  - S3 buckets
  - IAM roles and policies
  - EventBridge rules
  - Cost Anomaly Detection
- Node.js 16+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $5-20/month for automation resources (Lambda, SNS, S3 storage)

> **Note**: This recipe requires management account access to fully implement cost allocation features. Some features may take 24-48 hours to become available after activation.

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name cost-allocation-chargeback-system \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=cost-allocation \
                 ParameterKey=Environment,ParameterValue=prod \
                 ParameterKey=NotificationEmail,ParameterValue=finance@company.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name cost-allocation-chargeback-system \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=finance@company.com

# View stack outputs
cdk ls --long
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
cdk deploy --parameters notificationEmail=finance@company.com

# View stack outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="notification_email=finance@company.com"

# Apply the infrastructure
terraform apply -var="notification_email=finance@company.com"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="finance@company.com"
export PROJECT_NAME="cost-allocation"
export ENVIRONMENT="prod"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Configuration Options

### CloudFormation Parameters
- `ProjectName`: Name prefix for all resources (default: cost-allocation)
- `Environment`: Environment name (default: prod)
- `NotificationEmail`: Email address for budget and anomaly notifications
- `EngineeringBudgetAmount`: Monthly budget for Engineering department (default: 1000)
- `MarketingBudgetAmount`: Monthly budget for Marketing department (default: 500)
- `OperationsBudgetAmount`: Monthly budget for Operations department (default: 750)

### CDK Configuration
Configure the deployment by setting context values in `cdk.json` or passing parameters:
```json
{
  "context": {
    "projectName": "cost-allocation",
    "environment": "prod",
    "notificationEmail": "finance@company.com",
    "budgets": {
      "engineering": 1000,
      "marketing": 500,
      "operations": 750
    }
  }
}
```

### Terraform Variables
Create a `terraform.tfvars` file or set variables via command line:
```hcl
project_name = "cost-allocation"
environment = "prod"
notification_email = "finance@company.com"
aws_region = "us-east-1"

department_budgets = {
  engineering = 1000
  marketing   = 500
  operations  = 750
}

cost_anomaly_threshold = 100
```

## Post-Deployment Configuration

### 1. Activate Cost Allocation Tags
```bash
# Enable cost allocation tags for Department and Project
aws ce create-cost-category-definition \
    --name "CostCenter" \
    --rules file://cost-category-rules.json
```

### 2. Configure Department Tags
Ensure all AWS resources are tagged with appropriate department values:
- `Department: Engineering`
- `Department: Marketing`
- `Department: Operations`

### 3. Set Up Email Subscriptions
```bash
# Get SNS topic ARN from outputs
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name cost-allocation-chargeback-system \
    --query 'Stacks[0].Outputs[?OutputKey==`CostAllocationTopicArn`].OutputValue' \
    --output text)

# Subscribe additional email addresses
aws sns subscribe \
    --topic-arn $SNS_TOPIC_ARN \
    --protocol email \
    --notification-endpoint additional-email@company.com
```

### 4. Test the System
```bash
# Manually trigger the cost allocation Lambda function
LAMBDA_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name cost-allocation-chargeback-system \
    --query 'Stacks[0].Outputs[?OutputKey==`CostProcessorFunctionName`].OutputValue' \
    --output text)

aws lambda invoke \
    --function-name $LAMBDA_FUNCTION_NAME \
    --payload '{"test": true}' \
    response.json

cat response.json
```

## Monitoring and Validation

### Check Cost and Usage Reports
```bash
# Verify CUR report configuration
aws cur describe-report-definitions

# List generated reports in S3
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name cost-allocation-chargeback-system \
    --query 'Stacks[0].Outputs[?OutputKey==`CostReportsBucket`].OutputValue' \
    --output text)

aws s3 ls s3://$BUCKET_NAME/cost-reports/ --recursive
```

### Monitor Budget Status
```bash
# Check budget utilization
aws budgets describe-budgets \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --query 'Budgets[*].[BudgetName,BudgetLimit.Amount,CalculatedSpend.ActualSpend.Amount]' \
    --output table
```

### Validate Cost Anomaly Detection
```bash
# Check anomaly detectors
aws ce get-anomaly-detectors

# View recent anomalies
aws ce get-anomalies \
    --date-interval Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d)
```

## Cleanup

### Using CloudFormation
```bash
# Empty S3 bucket first (if not using DeletionPolicy: Retain)
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name cost-allocation-chargeback-system \
    --query 'Stacks[0].Outputs[?OutputKey==`CostReportsBucket`].OutputValue' \
    --output text)

aws s3 rm s3://$BUCKET_NAME --recursive

# Delete the stack
aws cloudformation delete-stack \
    --stack-name cost-allocation-chargeback-system

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name cost-allocation-chargeback-system \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript/Python
```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm cleanup
terraform show
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
./scripts/status.sh
```

## Architecture Components

The deployed infrastructure includes:

### Core Resources
- **S3 Bucket**: Stores Cost and Usage Reports (CUR)
- **SNS Topic**: Delivers cost notifications and alerts
- **Lambda Function**: Processes cost data and generates reports
- **EventBridge Rule**: Schedules monthly cost processing
- **IAM Roles**: Provides least-privilege access for automation

### Cost Management
- **Cost Categories**: Defines department-based cost allocation
- **Department Budgets**: Monitors spending against allocated amounts
- **Cost Anomaly Detection**: Identifies unusual spending patterns
- **Cost and Usage Reports**: Provides detailed billing data

### Automation
- **Monthly Processing**: Automated cost allocation report generation
- **Budget Alerts**: Proactive notifications for budget thresholds
- **Anomaly Alerts**: Early warning for unusual spending patterns

## Security Considerations

- IAM roles follow least-privilege principle
- S3 bucket includes encryption at rest
- SNS topics use IAM-based access control
- Lambda functions run with minimal required permissions
- Cost data access restricted to billing administrators

## Troubleshooting

### Common Issues

1. **Cost data not appearing**: Cost allocation tags may take 24-48 hours to activate
2. **Lambda timeout errors**: Increase function timeout in large organizations
3. **SNS delivery failures**: Verify email subscriptions are confirmed
4. **Budget alerts not triggering**: Check tag-based cost filters

### Debug Commands
```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/cost-allocation

# Verify SNS topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn $SNS_TOPIC_ARN

# Test Cost Explorer API access
aws ce get-cost-and-usage \
    --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
    --granularity DAILY \
    --metrics BlendedCost
```

## Customization

### Adding New Departments
1. Update cost category definitions
2. Create additional budgets
3. Modify Lambda function processing logic
4. Update notification routing

### Integration with External Systems
- Modify Lambda function to call external APIs
- Add SQS queues for reliable message delivery
- Implement webhook endpoints for real-time updates

### Advanced Analytics
- Connect to Amazon QuickSight for dashboards
- Export data to data warehouses
- Implement predictive analytics with SageMaker

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS CloudFormation/CDK documentation
3. Review AWS Cost Management documentation
4. Consult AWS support for billing-related issues

## Additional Resources

- [AWS Cost Management User Guide](https://docs.aws.amazon.com/cost-management/)
- [AWS Organizations User Guide](https://docs.aws.amazon.com/organizations/)
- [AWS Cost and Usage Reports User Guide](https://docs.aws.amazon.com/cur/)
- [AWS Budgets User Guide](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-managing-costs.html)