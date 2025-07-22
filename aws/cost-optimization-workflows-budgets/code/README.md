# Infrastructure as Code for Cost Optimization Workflows with Budgets

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost Optimization Workflows with Budgets".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)  
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrative permissions for Cost Management, Budgets, SNS, and Lambda services
- Basic understanding of AWS cost management concepts and IAM permissions
- Valid email address for budget notifications
- Node.js 14+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

## Estimated Costs

- **AWS Budgets**: $0.02 per day per budget after the first two free budgets
- **Amazon SNS**: $0.50 per million notifications
- **AWS Lambda**: $0.20 per million requests (free tier: 1M requests/month)
- **Cost Optimization Hub**: No additional charge
- **Total estimated monthly cost**: $5-15 for typical usage

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name cost-optimization-workflow \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
                 ParameterKey=MonthlyCostBudget,ParameterValue=1000 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name cost-optimization-workflow

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name cost-optimization-workflow \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure your deployment
export CDK_DEFAULT_REGION=us-east-1
export NOTIFICATION_EMAIL=your-email@example.com
export MONTHLY_BUDGET_AMOUNT=1000

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure your deployment
export CDK_DEFAULT_REGION=us-east-1
export NOTIFICATION_EMAIL=your-email@example.com  
export MONTHLY_BUDGET_AMOUNT=1000

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values:
# notification_email = "your-email@example.com"
# monthly_budget_amount = 1000
# aws_region = "us-east-1"

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export MONTHLY_BUDGET_AMOUNT=1000
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/deploy.sh --status
```

## Post-Deployment Configuration

### 1. Confirm Email Subscription

After deployment, check your email for SNS subscription confirmation and click the confirmation link.

### 2. Enable Cost Optimization Hub

The Cost Optimization Hub needs to be manually enabled:

```bash
# Enable Cost Optimization Hub
aws cost-optimization-hub update-preferences \
    --savings-estimation-mode AFTER_DISCOUNTS \
    --member-account-discount-visibility STANDARD
```

### 3. Verify Budget Creation

Check that budgets were created successfully:

```bash
# List all budgets
aws budgets describe-budgets \
    --account-id $(aws sts get-caller-identity --query Account --output text)
```

## Validation & Testing

### Test Budget Notifications

```bash
# Check SNS topic and subscriptions
aws sns list-topics --query 'Topics[?contains(TopicArn, `cost-optimization`)]'

# List budget notifications
aws budgets describe-notifications \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget-name monthly-cost-budget
```

### Test Lambda Function

```bash
# Invoke the cost optimization Lambda function
aws lambda invoke \
    --function-name cost-optimization-handler \
    --payload '{"test": "validation"}' \
    /tmp/lambda-response.json

# View the response
cat /tmp/lambda-response.json
```

### Check Cost Anomaly Detection

```bash
# Verify anomaly detectors
aws ce get-anomaly-detectors

# Check anomaly subscriptions  
aws ce get-anomaly-subscriptions
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name cost-optimization-workflow

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cost-optimization-workflow
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Destroy the stack
cdk destroy --force

# Clean up bootstrap resources (optional)
# cdk bootstrap --toolkit-stack-name CDKToolkit --termination-protection false
# aws cloudformation delete-stack --stack-name CDKToolkit
```

### Using CDK Python

```bash
cd cdk-python/

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Destroy the stack
cdk destroy --force

# Deactivate virtual environment
deactivate
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -auto-approve

# Clean up state files (optional)
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Key Configuration Options

| Parameter | Description | Default | CloudFormation | CDK | Terraform |
|-----------|-------------|---------|----------------|-----|-----------|
| NotificationEmail | Email for budget alerts | - | ✅ | ✅ | ✅ |
| MonthlyCostBudget | Monthly budget limit (USD) | 1000 | ✅ | ✅ | ✅ |
| EC2UsageHours | EC2 usage budget (hours) | 2000 | ✅ | ✅ | ✅ |
| RIUtilizationThreshold | RI utilization threshold (%) | 80 | ✅ | ✅ | ✅ |
| Environment | Environment tag | dev | ✅ | ✅ | ✅ |

### Advanced Customization

#### Multi-Account Setup

For AWS Organizations with consolidated billing:

```bash
# Enable Cost Optimization Hub for organization
aws cost-optimization-hub update-preferences \
    --savings-estimation-mode AFTER_DISCOUNTS \
    --member-account-discount-visibility ALL

# Create organization-level budgets
aws budgets create-budget \
    --account-id $(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text) \
    --budget file://org-budget.json
```

#### Custom Cost Allocation Tags

Modify the Terraform variables or CloudFormation parameters to include custom tags:

```hcl
# terraform/variables.tf
variable "cost_allocation_tags" {
  description = "Tags for cost allocation"
  type        = map(string)
  default = {
    Department = "Engineering"
    Project    = "CostOptimization" 
    Owner      = "DevOps"
  }
}
```

#### Slack Integration

Add Slack webhook integration to SNS:

```bash
# Subscribe Slack webhook to SNS topic
aws sns subscribe \
    --topic-arn arn:aws:sns:us-east-1:123456789012:cost-optimization-alerts \
    --protocol https \
    --notification-endpoint https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
```

## Architecture Overview

The deployed infrastructure includes:

- **AWS Cost Optimization Hub**: Centralized cost optimization recommendations
- **AWS Budgets**: Monthly cost, EC2 usage, and RI utilization budgets
- **Amazon SNS**: Notification hub for budget and anomaly alerts
- **AWS Lambda**: Automated cost optimization processing
- **Cost Anomaly Detection**: ML-powered spending anomaly detection
- **IAM Roles & Policies**: Least-privilege access controls

## Monitoring & Maintenance

### CloudWatch Logs

Monitor Lambda function execution:

```bash
# View Lambda logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/cost-optimization

# Tail logs in real-time
aws logs tail /aws/lambda/cost-optimization-handler --follow
```

### Cost Optimization Recommendations

Regularly check for new recommendations:

```bash
# List current recommendations
aws cost-optimization-hub list-recommendations \
    --include-all-recommendations \
    --max-results 20
```

### Budget Performance

Monitor budget performance:

```bash
# Get budget utilization
aws budgets describe-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget-name monthly-cost-budget
```

## Security Considerations

- All IAM roles follow least-privilege principles
- SNS topics use resource-based policies to restrict access
- Lambda functions have minimal required permissions
- Cost data access is limited to necessary services
- Budget actions use separate IAM roles with specific restrictions

## Troubleshooting

### Common Issues

1. **Email subscription not confirmed**
   - Check spam folder for SNS confirmation email
   - Manually confirm subscription via AWS Console

2. **Lambda function timeouts**
   - Increase timeout in function configuration
   - Check CloudWatch logs for specific errors

3. **Budget notifications not received**
   - Verify SNS topic permissions
   - Check budget notification configuration

4. **Cost Optimization Hub not showing recommendations**
   - Wait 24-48 hours after enabling for initial analysis
   - Ensure sufficient resource usage for recommendations

### Support Resources

- [AWS Cost Optimization Hub Documentation](https://docs.aws.amazon.com/cost-optimization-hub/)
- [AWS Budgets User Guide](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-managing-costs.html)
- [AWS Cost Anomaly Detection](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/ce-anomaly-detection.html)

## Contributing

When modifying the infrastructure:

1. Update all IaC implementations consistently
2. Test deployments in a non-production environment
3. Update documentation for any new parameters
4. Validate security best practices
5. Test cleanup procedures

## License

This infrastructure code is provided as-is under the same license as the parent recipe repository.