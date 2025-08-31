# Infrastructure as Code for Cost Monitoring with Cost Explorer and Budgets

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost Monitoring with Cost Explorer and Budgets".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate IAM permissions for:
  - Cost Explorer API access
  - AWS Budgets management
  - SNS topic creation and management
  - CloudFormation/CDK deployment (for respective implementations)
- Valid email address for budget notifications
- Basic understanding of AWS billing and cost management

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name cost-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
                 ParameterKey=MonthlyBudgetAmount,ParameterValue=100.00 \
    --capabilities CAPABILITY_IAM

# Monitor deployment status
aws cloudformation describe-stacks \
    --stack-name cost-monitoring-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set required context variables
npx cdk context --set notificationEmail your-email@example.com
npx cdk context --set monthlyBudgetAmount 100.00

# Deploy the stack
npx cdk deploy

# View outputs
npx cdk output
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export MONTHLY_BUDGET_AMOUNT=100.00

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
monthly_budget_amount = 100.00
aws_region = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export MONTHLY_BUDGET_AMOUNT="100.00"

# Deploy resources
./scripts/deploy.sh
```

## Configuration Options

### Budget Settings
- **Monthly Budget Amount**: Set your desired monthly spending limit (default: $100.00)
- **Alert Thresholds**: Configured at 50%, 75%, 90% of budget amount
- **Forecasting Alert**: Set at 100% of budget for predictive warnings

### Notification Settings
- **Email Address**: Primary notification endpoint for budget alerts
- **SNS Topic**: Configurable topic name for budget notifications
- **Alert Types**: Both actual and forecasted spending alerts

### Cost Explorer Settings
- **Time Period**: Monthly granularity with 13 months of historical data
- **Metrics**: BlendedCost tracking across all AWS services
- **Grouping**: Service-level cost breakdown and analysis

## Validation Steps

After deployment, verify your cost monitoring setup:

1. **Confirm Email Subscription**:
   ```bash
   # Check SNS subscription status
   aws sns list-subscriptions-by-topic \
       --topic-arn $(aws sns list-topics \
           --query 'Topics[?contains(TopicArn, `budget-alerts`)].TopicArn' \
           --output text)
   ```

2. **Verify Budget Configuration**:
   ```bash
   # List all budgets
   aws budgets describe-budgets \
       --account-id $(aws sts get-caller-identity --query Account --output text)
   ```

3. **Test Cost Explorer Access**:
   ```bash
   # Query current month costs
   aws ce get-cost-and-usage \
       --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
       --granularity MONTHLY \
       --metrics BlendedCost \
       --group-by Type=DIMENSION,Key=SERVICE
   ```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name cost-monitoring-stack

# Monitor deletion status
aws cloudformation describe-stacks \
    --stack-name cost-monitoring-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
npx cdk destroy     # or cdk destroy for Python
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
aws budgets describe-budgets \
    --account-id $(aws sts get-caller-identity --query Account --output text)
```

## Cost Considerations

- **Cost Explorer API**: $0.01 per paginated request
- **AWS Budgets**: First two budgets are free, $0.02 per budget per day thereafter
- **SNS**: $0.50 per million notifications for email delivery
- **CloudFormation/CDK**: No additional charges for infrastructure deployment

> **Note**: The primary costs are from Cost Explorer API usage. Console access to Cost Explorer is free.

## Customization

### Budget Modifications
- Adjust alert thresholds by modifying the percentage values in templates
- Add service-specific budgets by filtering cost categories
- Implement tag-based cost allocation for department or project tracking

### Notification Enhancements
- Add SMS notifications by including phone numbers in SNS subscriptions
- Integrate with AWS Lambda for automated responses to budget alerts
- Configure multiple email addresses for different alert thresholds

### Advanced Monitoring
- Extend with AWS Cost Anomaly Detection for intelligent anomaly identification
- Implement Reserved Instance utilization budgets
- Add custom cost categories for detailed business unit allocation

## Troubleshooting

### Common Issues

1. **Email Notifications Not Received**:
   - Check spam folder for SNS confirmation email
   - Verify email address in SNS subscription
   - Confirm subscription status is "Confirmed"

2. **Cost Explorer Access Denied**:
   - Ensure account has billing permissions
   - Verify Cost Explorer is enabled for the account
   - Check IAM policies include Cost Explorer API permissions

3. **Budget Creation Failures**:
   - Validate account ID format and permissions
   - Ensure unique budget names across the account
   - Check SNS topic ARN format and accessibility

### Support Resources

- [AWS Cost Management Documentation](https://docs.aws.amazon.com/aws-cost-management/)
- [AWS Budgets User Guide](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [Cost Explorer API Reference](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_Operations_AWS_Cost_Explorer_Service.html)

## Security Best Practices

- Use least privilege IAM policies for cost management access
- Enable CloudTrail logging for budget and cost management API calls
- Regularly review and rotate SNS topic access permissions
- Implement MFA for accounts with billing access
- Monitor Cost Explorer API usage to prevent unexpected charges

## Integration Examples

### CI/CD Pipeline Integration
```bash
# Example integration with deployment pipeline
if [ "$ENVIRONMENT" = "production" ]; then
    ./scripts/deploy.sh
    echo "Cost monitoring enabled for production environment"
fi
```

### Multi-Account Setup
- Deploy budgets in each member account for granular control
- Use AWS Organizations for consolidated billing visibility
- Implement cross-account SNS notifications for centralized alerting

For detailed implementation guidance, refer to the original recipe documentation or AWS Cost Management best practices.