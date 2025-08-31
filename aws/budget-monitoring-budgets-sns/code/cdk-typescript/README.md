# Budget Monitoring CDK TypeScript Application

This AWS CDK TypeScript application implements a comprehensive budget monitoring solution using AWS Budgets and Amazon SNS for real-time cost tracking and notifications.

## Architecture

The application creates:

- **AWS Budget**: Monthly cost budget with configurable spending limits
- **Multi-threshold Alerts**: 80% and 100% actual spend, 80% forecasted spend
- **SNS Topic**: Reliable notification delivery with email subscription
- **IAM Permissions**: Secure cross-service communication
- **CDK Nag Integration**: Security best practices validation

## Features

- ✅ Real-time cost monitoring and alerting
- ✅ Machine learning-based cost forecasting
- ✅ Email notifications for budget thresholds
- ✅ Configurable budget amounts and notification settings
- ✅ Security best practices with CDK Nag
- ✅ Comprehensive error handling and validation
- ✅ CloudFormation outputs for integration

## Prerequisites

- Node.js 18+ installed
- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Valid email address for notifications

### Required AWS Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "budgets:*",
        "sns:*",
        "iam:PassRole",
        "iam:CreateRole",
        "iam:AttachRolePolicy"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment

```bash
# Set your notification email
export NOTIFICATION_EMAIL="your-email@example.com"

# Optionally set AWS account and region
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"
```

### 3. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### 4. Deploy the Stack

```bash
# Deploy with default $100 budget
cdk deploy

# Deploy with custom budget amount
cdk deploy -c budgetAmount=200 -c notificationEmail=admin@company.com
```

### 5. Confirm Email Subscription

Check your email for an SNS confirmation message and click the confirmation link to activate notifications.

## Configuration Options

### CDK Context Parameters

```bash
# Set budget amount (default: 100 USD)
cdk deploy -c budgetAmount=250

# Set notification email
cdk deploy -c notificationEmail=finance@company.com

# Set environment and cost center for tagging
cdk deploy -c environment=production -c costCenter=finance
```

### Environment Variables

```bash
export NOTIFICATION_EMAIL="your-email@example.com"
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"
```

## Available Commands

```bash
# Build TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm run test

# Synthesize CloudFormation
npm run synth

# Deploy stack
npm run deploy

# View differences
npm run diff

# Destroy stack
npm run destroy
```

## Testing

```bash
# Run unit tests
npm test

# Run tests in watch mode
npm run test:watch

# Send test notification
aws sns publish \
  --topic-arn <SNS_TOPIC_ARN> \
  --message "Test budget alert" \
  --subject "Budget Monitoring Test"
```

## Monitoring and Validation

### Check Budget Status

```bash
# Get budget details
aws budgets describe-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name <BUDGET_NAME>
```

### Verify Notifications

```bash
# List SNS subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn <SNS_TOPIC_ARN>
```

### View Cost Data

```bash
# Get current month costs
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost
```

## Cost Considerations

- **AWS Budgets**: First 2 budgets are free, additional budgets cost $0.02/day
- **SNS**: $0.50 per 1 million email notifications
- **CloudWatch**: Free tier includes basic monitoring

## Security Features

### CDK Nag Integration

The application includes CDK Nag for security validation:

```typescript
import { AwsSolutionsChecks } from 'cdk-nag';
AwsSolutionsChecks.check(budgetStack);
```

### IAM Permissions

- Least privilege access for AWS Budgets to SNS
- Account-scoped conditions for cross-service access
- No overly permissive wildcard policies

### Data Protection

- Email addresses are validated before use
- SNS topic policies restrict access to AWS Budgets service
- No sensitive data stored in CloudFormation outputs

## Troubleshooting

### Common Issues

1. **Email not confirmed**: Check spam folder and confirm SNS subscription
2. **Deployment fails**: Verify AWS permissions and account limits
3. **No notifications**: Check budget configuration and SNS topic policy

### Debug Commands

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name BudgetMonitoringStack

# Verify SNS topic policy
aws sns get-topic-attributes --topic-arn <SNS_TOPIC_ARN>

# Check budget notifications
aws budgets describe-notifications-for-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name <BUDGET_NAME>
```

## Customization

### Extending the Solution

1. **Multiple Budgets**: Create service-specific or department-specific budgets
2. **Slack Integration**: Add Slack webhook subscription to SNS topic
3. **Lambda Actions**: Trigger automated responses when thresholds are exceeded
4. **Dashboard Integration**: Connect to QuickSight for cost visualization

### Code Structure

```
├── app.ts                    # Main CDK application entry point
├── lib/
│   └── budget-monitoring-stack.ts  # Core stack implementation
├── package.json              # Dependencies and scripts
├── tsconfig.json            # TypeScript configuration
├── cdk.json                 # CDK configuration and context
└── README.md               # This documentation
```

## Support

For issues and questions:

1. Check the [AWS Budgets documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
2. Review [CDK TypeScript examples](https://github.com/aws-samples/aws-cdk-examples/tree/master/typescript)
3. Consult [AWS SNS documentation](https://docs.aws.amazon.com/sns/latest/dg/welcome.html)

## License

This code is released under the MIT License. See LICENSE file for details.