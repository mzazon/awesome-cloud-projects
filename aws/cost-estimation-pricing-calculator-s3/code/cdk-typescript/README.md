# Cost Estimation Planning with Pricing Calculator and S3 - CDK TypeScript

This directory contains a complete AWS CDK TypeScript application for implementing the "Cost Estimation Planning with Pricing Calculator and S3" recipe. The application creates a centralized system for storing, organizing, and monitoring AWS cost estimates with automated lifecycle management and budget alerts.

## Architecture

The CDK application deploys:

- **S3 Bucket**: Secure storage for cost estimates with versioning and encryption
- **Lifecycle Policies**: Automatic transition to cost-effective storage classes
- **SNS Topic**: Notifications for budget alerts and cost monitoring
- **AWS Budget**: Configurable spending limits with threshold alerts
- **IAM Policies**: Least privilege access controls following AWS best practices
- **Custom Resource**: Automated S3 folder structure creation for organization

## Prerequisites

- AWS CLI installed and configured
- Node.js 18+ installed
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for S3, SNS, Budgets, and IAM

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (First-time setup)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Deploy with default configuration
cdk deploy

# Deploy with custom project name and budget
cdk deploy --context projectName=my-project --context budgetLimit=100.00
```

### 4. Verify Deployment

```bash
# List stack outputs
aws cloudformation describe-stacks \
    --stack-name CostEstimationStack \
    --query 'Stacks[0].Outputs'
```

## Configuration Options

The CDK application supports the following configuration parameters via CDK context:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `projectName` | `web-app-migration` | Name for project folder and budget |
| `environment` | `dev` | Environment (dev/staging/prod) |
| `budgetLimit` | `50.00` | Monthly budget limit in USD |
| `alertThreshold` | `80` | Budget alert threshold percentage |
| `enable-cdk-nag` | `false` | Enable CDK Nag security checks |

### Example Custom Deployment

```bash
cdk deploy --context projectName=mobile-app \
           --context environment=prod \
           --context budgetLimit=200.00 \
           --context alertThreshold=75 \
           --context enable-cdk-nag=true
```

## CDK Commands

```bash
# Synthesize CloudFormation template
cdk synth

# Compare deployed stack with current state
cdk diff

# Deploy the stack
cdk deploy

# Destroy the stack
cdk destroy

# List all stacks
cdk list
```

## Security Features

### CDK Nag Integration

Enable security best practice validation:

```bash
# Deploy with CDK Nag security checks
cdk deploy --context enable-cdk-nag=true
```

### Security Controls Implemented

- **S3 Bucket Encryption**: Server-side encryption with AWS managed keys
- **Block Public Access**: All public access blocked on S3 bucket
- **SSL Enforcement**: HTTPS required for all S3 operations
- **IAM Least Privilege**: Minimal permissions for budget service access
- **Versioning**: Enabled for estimate history and recovery
- **Resource Tagging**: Comprehensive tags for cost allocation

## Cost Optimization Features

### S3 Lifecycle Management

The application automatically transitions estimate files through storage classes:

- **0-30 days**: S3 Standard (immediate access)
- **30-90 days**: S3 Standard-IA (infrequent access)
- **90-365 days**: S3 Glacier (archival)
- **365+ days**: S3 Deep Archive (long-term archival)

### Budget Monitoring

- **Actual Spending Alerts**: Notifications when spending exceeds threshold
- **Forecasted Spending Alerts**: Early warnings based on usage trends
- **Tag-based Filtering**: Budget applies only to tagged resources

## Usage Instructions

### 1. Create Cost Estimates

1. Visit [AWS Pricing Calculator](https://calculator.aws/)
2. Create detailed cost estimates for your planned resources
3. Save estimates with descriptive names
4. Export estimates as PDF and CSV files

### 2. Upload Estimates to S3

```bash
# Get bucket name from stack outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name CostEstimationStack \
    --query 'Stacks[0].Outputs[?OutputKey==`CostEstimatesBucketName`].OutputValue' \
    --output text)

# Upload estimate with metadata
aws s3 cp my-estimate.csv \
    s3://${BUCKET_NAME}/projects/my-project/estimate-$(date +%Y%m%d).csv \
    --metadata "project=my-project,created-by=finance-team" \
    --tagging "Project=my-project&Department=Finance"
```

### 3. Monitor Costs

The system automatically:
- Monitors spending against budgets
- Sends SNS notifications when thresholds are exceeded
- Applies lifecycle policies to optimize storage costs
- Maintains estimate history with versioning

## Folder Structure

The S3 bucket is organized with the following structure:

```
cost-estimates-{suffix}/
├── estimates/
│   ├── 2025/
│   │   ├── Q1/
│   │   ├── Q2/
│   │   ├── Q3/
│   │   └── Q4/
├── projects/
│   └── {project-name}/
└── archived/
```

## Monitoring and Alerts

### SNS Topic Subscription

Subscribe to budget alerts:

```bash
# Get topic ARN from stack outputs
TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name CostEstimationStack \
    --query 'Stacks[0].Outputs[?OutputKey==`BudgetAlertsTopicArn`].OutputValue' \
    --output text)

# Subscribe email to alerts
aws sns subscribe \
    --topic-arn ${TOPIC_ARN} \
    --protocol email \
    --notification-endpoint your-email@company.com
```

### CloudWatch Integration

The budget automatically integrates with CloudWatch for:
- Cost anomaly detection
- Spending trend analysis
- Custom metric creation for dashboards

## Customization

### Adding New Project

```bash
# Deploy with new project configuration
cdk deploy --context projectName=new-project-name
```

### Modifying Lifecycle Policies

Edit the `lifecycleRules` in `lib/cost-estimation-stack.ts`:

```typescript
lifecycleRules: [
  {
    id: 'CustomLifecycle',
    enabled: true,
    prefix: 'estimates/',
    transitions: [
      {
        storageClass: s3.StorageClass.INFREQUENT_ACCESS,
        transitionAfter: cdk.Duration.days(15), // Custom: 15 days
      },
      // Add more transitions as needed
    ],
  },
],
```

### Adding Email Notifications

Extend the stack to include email subscriptions:

```typescript
// Add to stack constructor
this.budgetAlertsTopic.addSubscription(
  new snsSubscriptions.EmailSubscription('finance@company.com')
);
```

## Testing

### Unit Tests

```bash
# Run tests
npm test

# Run tests in watch mode
npm run test:watch
```

### Integration Testing

```bash
# Synthesize template for validation
cdk synth

# Deploy to test environment
cdk deploy --context environment=test
```

## Troubleshooting

### Common Issues

1. **Budget Creation Fails**
   - Verify AWS Budgets service is available in your region
   - Check IAM permissions for budgets:CreateBudget

2. **S3 Folder Creation Fails**
   - Verify Lambda execution role has S3:PutObject permissions
   - Check bucket name uniqueness

3. **CDK Nag Warnings**
   - Review security suppressions in the code
   - Use `--context enable-cdk-nag=false` to disable temporarily

### Debug Mode

Enable verbose logging:

```bash
# Deploy with debug logging
cdk deploy --verbose

# Synthesize with debug output
cdk synth --verbose
```

## Cleanup

### Remove All Resources

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
aws cloudformation describe-stacks --stack-name CostEstimationStack
```

### Manual Cleanup (if needed)

```bash
# Empty S3 bucket before stack deletion
aws s3 rm s3://${BUCKET_NAME} --recursive
aws s3api delete-bucket --bucket ${BUCKET_NAME}
```

## Integration with Other Systems

### CI/CD Pipeline Integration

```yaml
# Example GitHub Actions workflow
- name: Deploy Cost Estimation Stack
  run: |
    npm install
    cdk deploy --require-approval never \
      --context projectName=${{ github.event.repository.name }} \
      --context environment=${{ github.ref_name }}
```

### Terraform Integration

Export CDK template for Terraform import:

```bash
# Generate CloudFormation template
cdk synth --output cdk.out

# Use CDK template with Terraform
terraform import aws_cloudformation_stack.cost_estimation CostEstimationStack
```

## Support and Maintenance

- **Updates**: Regularly update CDK version and dependencies
- **Security**: Review CDK Nag findings and apply security patches
- **Monitoring**: Set up CloudWatch dashboards for cost tracking
- **Documentation**: Keep README updated with configuration changes

For issues or questions, refer to:
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Pricing Calculator User Guide](https://docs.aws.amazon.com/pricing-calculator/)
- [AWS Budgets Documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)