# Infrastructure as Code for Budget Alerts and Automated Cost Actions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Budget Alerts and Automated Cost Actions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- Appropriate AWS permissions for:
  - AWS Budgets (create/modify budgets and budget actions)
  - SNS (create topics and subscriptions)
  - Lambda (create functions and manage execution roles)
  - IAM (create roles and policies)
  - CloudWatch Logs (for Lambda logging)
  - EC2 (for automated instance control actions)
- Valid email address for budget notifications
- Estimated cost: $2-5 per month for SNS, Lambda, and CloudWatch Logs
- Note: AWS Budgets allows 2 free budgets per month, additional budgets cost $0.02 per day

## Architecture Overview

This implementation creates a comprehensive cost management solution with:

- **AWS Budgets**: Monthly cost budget with multiple alert thresholds (80%, 90%, 100%)
- **SNS Topic**: Centralized notification hub for budget alerts
- **Lambda Function**: Automated cost control actions (stops development EC2 instances)
- **IAM Roles & Policies**: Secure permissions for budget actions and Lambda execution
- **Budget Actions**: Automated policy enforcement when thresholds are exceeded

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name budget-alerts-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BudgetEmail,ParameterValue=your-email@example.com \
                 ParameterKey=BudgetLimit,ParameterValue=100 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name budget-alerts-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure parameters (edit cdk.context.json or use CLI)
cdk deploy --parameters BudgetEmail=your-email@example.com \
           --parameters BudgetLimit=100

# Verify deployment
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export BUDGET_EMAIL="your-email@example.com"
export BUDGET_LIMIT="100"

# Deploy the stack
cdk deploy

# Verify deployment
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="budget_email=your-email@example.com" \
                -var="budget_limit=100"

# Apply configuration
terraform apply -var="budget_email=your-email@example.com" \
                 -var="budget_limit=100"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export BUDGET_EMAIL="your-email@example.com"
export BUDGET_LIMIT="100"

# Deploy the solution
./scripts/deploy.sh

# Check deployment status
aws budgets describe-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget-name $(grep "BUDGET_NAME=" scripts/deploy.sh | cut -d'=' -f2 | tr -d '"')
```

## Post-Deployment Steps

1. **Confirm Email Subscription**: Check your email and confirm the SNS subscription to receive budget alerts

2. **Test Notifications**: Send a test notification to verify the system is working:
   ```bash
   # Get the SNS topic ARN (replace with your actual topic ARN)
   SNS_TOPIC_ARN=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `budget-alerts`)].TopicArn' --output text)
   
   # Send test message
   aws sns publish \
       --topic-arn "${SNS_TOPIC_ARN}" \
       --subject "Budget Alert Test" \
       --message '{"BudgetName": "Test Budget", "AccountId": "'$(aws sts get-caller-identity --query Account --output text)'", "AlertType": "ACTUAL", "Threshold": 80}'
   ```

3. **Tag Development Resources**: Ensure your development EC2 instances are tagged appropriately for automated actions:
   ```bash
   # Tag existing instances as development
   aws ec2 create-tags \
       --resources i-1234567890abcdef0 \
       --tags Key=Environment,Value=Development
   ```

## Customization

### Budget Configuration
- **Budget Amount**: Modify the budget limit in the variables/parameters
- **Time Period**: Adjust the budget time unit (MONTHLY, QUARTERLY, ANNUALLY)
- **Cost Types**: Include/exclude credits, discounts, taxes, etc.
- **Threshold Percentages**: Modify alert thresholds (default: 80%, 90%, 100%)

### Notification Settings
- **Additional Subscribers**: Add more email addresses or SMS numbers
- **Slack Integration**: Extend the Lambda function to send Slack notifications
- **Custom Alert Messages**: Modify notification content and formatting

### Automated Actions
- **Instance Filtering**: Modify Lambda function to target different instance types or tags
- **Additional Actions**: Extend automation to include RDS, Auto Scaling, or other services
- **Approval Workflows**: Add manual approval steps before executing destructive actions

### Security Configuration
- **IAM Permissions**: Adjust permissions based on your organization's requirements
- **Resource Restrictions**: Modify the budget action policy to control different resource types
- **Account Scope**: Extend to organization-wide budgets for multi-account management

## Validation

### Verify Budget Creation
```bash
# List all budgets
aws budgets describe-budgets \
    --account-id $(aws sts get-caller-identity --query Account --output text)

# Check specific budget details
aws budgets describe-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget-name YOUR_BUDGET_NAME
```

### Test Lambda Function
```bash
# Check Lambda function status
aws lambda get-function \
    --function-name YOUR_LAMBDA_FUNCTION_NAME \
    --query 'Configuration.State'

# View recent logs
aws logs tail /aws/lambda/YOUR_LAMBDA_FUNCTION_NAME --follow
```

### Verify SNS Integration
```bash
# List SNS subscriptions
aws sns list-subscriptions

# Check topic details
aws sns get-topic-attributes \
    --topic-arn YOUR_SNS_TOPIC_ARN
```

## Monitoring and Maintenance

### CloudWatch Metrics
- Monitor Lambda function execution and errors
- Track SNS delivery success rates
- Review budget alert frequency and patterns

### Cost Optimization
- Regularly review and adjust budget thresholds
- Analyze spending patterns to optimize alert timing
- Consider implementing seasonal budget adjustments

### Security Reviews
- Periodically review IAM permissions
- Update Lambda function dependencies
- Audit automated action effectiveness

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name budget-alerts-stack

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name budget-alerts-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Clean up CDK bootstrap (if no longer needed)
cdk bootstrap --show-template
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="budget_email=your-email@example.com" \
                   -var="budget_limit=100"

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
aws budgets describe-budgets \
    --account-id $(aws sts get-caller-identity --query Account --output text)
```

## Troubleshooting

### Common Issues

1. **Email Not Receiving Alerts**
   - Verify email subscription confirmation
   - Check spam/junk folders
   - Validate SNS topic permissions

2. **Lambda Function Not Triggering**
   - Verify SNS trigger configuration
   - Check Lambda execution role permissions
   - Review CloudWatch Logs for errors

3. **Budget Actions Not Working**
   - Verify AWS Budgets service role permissions
   - Check budget action configuration
   - Ensure target resources meet action criteria

4. **Permission Errors**
   - Verify IAM roles have necessary permissions
   - Check AWS account limits and quotas
   - Ensure proper trust relationships

### Getting Help

- Review AWS Budgets documentation: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
- Check AWS Lambda troubleshooting guide: https://docs.aws.amazon.com/lambda/latest/dg/troubleshooting.html
- Consult SNS troubleshooting: https://docs.aws.amazon.com/sns/latest/dg/sns-troubleshooting.html

## Advanced Configuration

### Multi-Account Setup
For organization-wide budget management:
- Use AWS Organizations consolidated billing
- Implement cross-account IAM roles
- Configure centralized SNS topics

### Integration with Other AWS Services
- Connect with AWS Cost Explorer for detailed analysis
- Integrate with AWS Cost Anomaly Detection
- Use with AWS Trusted Advisor for additional recommendations

### Compliance and Governance
- Implement AWS Config rules for budget compliance
- Use AWS CloudTrail for budget action auditing
- Configure AWS Service Catalog for standardized deployments

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Consult AWS documentation for specific services
3. Check AWS support forums and knowledge base
4. Contact AWS support for service-specific issues

---

**Note**: This infrastructure creates a production-ready budget monitoring and automated action system. Always test in a non-production environment first and ensure automated actions align with your organization's operational procedures.