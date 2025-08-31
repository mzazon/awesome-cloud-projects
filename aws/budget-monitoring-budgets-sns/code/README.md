# Infrastructure as Code for Budget Monitoring with AWS Budgets and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Budget Monitoring with AWS Budgets and SNS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)  
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions:
  - `budgets:CreateBudget`
  - `budgets:DeleteBudget`
  - `budgets:DescribeBudget`
  - `budgets:CreateNotification`
  - `budgets:DeleteNotification`
  - `sns:CreateTopic`
  - `sns:Subscribe` 
  - `sns:DeleteTopic`
  - `sns:Publish`
- Valid email address for budget notifications
- Node.js (for CDK TypeScript) or Python 3.8+ (for CDK Python)
- Terraform (for Terraform implementation)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name budget-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
                 ParameterKey=BudgetLimit,ParameterValue=100 \
    --capabilities CAPABILITY_IAM

# Monitor deployment status
aws cloudformation describe-stacks \
    --stack-name budget-monitoring-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name budget-monitoring-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export BUDGET_LIMIT="100"

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export BUDGET_LIMIT="100"

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
budget_limit = 100
budget_name = "monthly-cost-budget"
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
export NOTIFICATION_EMAIL="your-email@example.com"
export BUDGET_LIMIT="100"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment results
echo "Check your email for SNS subscription confirmation"
```

## Configuration Options

### CloudFormation Parameters

- `NotificationEmail`: Email address for budget notifications (required)
- `BudgetLimit`: Monthly budget limit in USD (default: 100)
- `BudgetName`: Name for the budget (default: auto-generated)

### CDK Environment Variables

- `NOTIFICATION_EMAIL`: Email address for budget notifications (required)
- `BUDGET_LIMIT`: Monthly budget limit in USD (default: 100)
- `AWS_REGION`: AWS region for deployment (uses CLI default if not set)

### Terraform Variables

- `notification_email`: Email address for budget notifications (required)
- `budget_limit`: Monthly budget limit in USD (default: 100)
- `budget_name`: Name for the budget (default: "monthly-cost-budget")
- `sns_topic_name`: Name for SNS topic (default: "budget-alerts")
- `aws_region`: AWS region for deployment (default: "us-east-1")

### Bash Script Environment Variables

- `NOTIFICATION_EMAIL`: Email address for budget notifications (required)
- `BUDGET_LIMIT`: Monthly budget limit in USD (default: 100)
- `AWS_REGION`: AWS region for deployment (uses CLI default)

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email for an SNS subscription confirmation message and click the confirmation link
2. **Test Notifications**: The deployment includes a test notification to verify the setup
3. **Monitor Budget**: Access AWS Budgets console to view budget status and spending

## Validation

### Verify Budget Creation

```bash
# List all budgets
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text)

# Check specific budget (replace with your budget name)
aws budgets describe-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget-name "your-budget-name"
```

### Verify SNS Topic and Subscription

```bash
# List SNS topics
aws sns list-topics

# Check subscriptions for topic (replace with your topic ARN)
aws sns list-subscriptions-by-topic --topic-arn "your-topic-arn"
```

### Test Notification

```bash
# Send test message (replace with your topic ARN)
aws sns publish \
    --topic-arn "your-topic-arn" \
    --message "Test budget notification" \
    --subject "Budget Alert Test"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name budget-monitoring-stack

# Monitor deletion status
aws cloudformation describe-stacks \
    --stack-name budget-monitoring-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# From the CDK directory (typescript or python)
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **Email Subscription Not Confirmed**
   - Check your email (including spam folder) for SNS confirmation
   - The subscription must be confirmed before notifications work

2. **Insufficient Permissions**
   - Ensure your AWS credentials have the required permissions listed in Prerequisites
   - Check CloudTrail logs for specific permission errors

3. **Budget Already Exists**
   - Budget names must be unique within an account
   - Modify the budget name parameter/variable if needed

4. **Region Issues**
   - AWS Budgets are global but SNS topics are regional
   - Ensure consistent region configuration across all resources

### Debugging

```bash
# Check AWS CLI configuration
aws configure list

# Verify account access
aws sts get-caller-identity

# Check CloudFormation events (if using CloudFormation)
aws cloudformation describe-stack-events --stack-name budget-monitoring-stack

# Check CloudWatch logs for Lambda functions (if applicable)
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
```

## Cost Considerations

- **AWS Budgets**: First 2 budgets per account are free, additional budgets cost $0.02/day
- **Amazon SNS**: First 1,000 email notifications per month are free, $0.50 per 1,000 emails thereafter
- **Total estimated cost**: $0-$1/month for typical usage

## Security Best Practices

This implementation follows AWS security best practices:

- Uses least privilege IAM permissions
- Enables encryption for SNS topics
- Implements proper resource tagging
- Follows AWS Well-Architected security guidelines

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check AWS documentation for specific services
3. Review CloudFormation/CDK/Terraform provider documentation
4. Check AWS Service Health Dashboard for service issues

## Additional Resources

- [AWS Budgets User Guide](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [Amazon SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)