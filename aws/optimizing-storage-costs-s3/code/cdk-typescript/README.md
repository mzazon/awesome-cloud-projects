# CDK TypeScript - S3 Storage Cost Optimization

This CDK TypeScript application implements a comprehensive S3 storage cost optimization solution with intelligent tiering, lifecycle policies, and cost monitoring.

## Architecture

The solution deploys the following components:

- **S3 Bucket** with lifecycle policies for automatic storage class transitions
- **Intelligent Tiering** configuration for automated cost optimization
- **Storage Analytics** for access pattern analysis
- **CloudWatch Dashboard** for real-time storage metrics monitoring
- **AWS Budgets** for cost monitoring and alerting
- **Lambda Functions** for cost analysis and optimization recommendations
- **EventBridge Rules** for automated reporting and analysis

## Prerequisites

- AWS CLI configured with appropriate credentials
- Node.js 18.x or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- TypeScript installed (`npm install -g typescript`)

## Quick Start

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Bootstrap CDK (first time only):**
   ```bash
   cdk bootstrap
   ```

3. **Deploy the stack:**
   ```bash
   cdk deploy
   ```

4. **View the synthesized CloudFormation template:**
   ```bash
   cdk synth
   ```

## Configuration

You can customize the deployment by setting context variables in `cdk.json` or passing them via command line:

```bash
cdk deploy -c bucketName=my-custom-bucket -c budgetLimit=100 -c alertEmail=admin@company.com
```

### Available Configuration Options

- `bucketName`: Custom name for the S3 bucket (default: 'storage-optimization-demo')
- `enableIntelligentTiering`: Enable intelligent tiering (default: true)
- `enableStorageAnalytics`: Enable storage analytics (default: true)
- `budgetLimit`: Monthly budget limit in USD (default: 50)
- `alertEmail`: Email address for budget alerts (default: 'admin@example.com')
- `environment`: Environment tag (default: 'demo')

## Features

### Lifecycle Policies

The solution implements three different lifecycle policies based on data access patterns:

1. **Frequently Accessed Data** (`data/frequently-accessed/`):
   - Transitions to Standard-IA after 30 days
   - Transitions to Glacier after 90 days

2. **Infrequently Accessed Data** (`data/infrequently-accessed/`):
   - Transitions to Standard-IA after 1 day
   - Transitions to Glacier after 30 days
   - Transitions to Deep Archive after 180 days

3. **Archive Data** (`data/archive/`):
   - Transitions to Glacier after 1 day
   - Transitions to Deep Archive after 30 days

### Intelligent Tiering

Automatically optimizes storage costs by moving objects between access tiers:
- Archive Access tier after 90 days
- Deep Archive Access tier after 180 days

### Cost Monitoring

- **CloudWatch Dashboard**: Real-time visualization of storage usage by class
- **AWS Budgets**: Monthly cost monitoring with 80% threshold alerts
- **Lambda Functions**: Automated cost analysis and optimization recommendations

### Automated Analysis

- **Cost Analysis Function**: Runs weekly to generate detailed cost reports
- **Optimization Function**: Runs daily to identify optimization opportunities

## Usage

### Upload Test Data

After deployment, upload test data to see the optimization in action:

```bash
# Get bucket name from stack outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name StorageOptimizationStack \
  --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
  --output text)

# Upload sample data
echo "Frequently accessed data" > sample-file.txt
aws s3 cp sample-file.txt s3://${BUCKET_NAME}/data/frequently-accessed/
aws s3 cp sample-file.txt s3://${BUCKET_NAME}/data/infrequently-accessed/
aws s3 cp sample-file.txt s3://${BUCKET_NAME}/data/archive/
```

### Trigger Cost Analysis

```bash
# Get function name from stack outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name StorageOptimizationStack \
  --query 'Stacks[0].Outputs[?OutputKey==`CostAnalysisFunctionName`].OutputValue' \
  --output text)

# Invoke cost analysis function
aws lambda invoke \
  --function-name ${FUNCTION_NAME} \
  --payload '{"bucket_name":"'${BUCKET_NAME}'"}' \
  response.json

cat response.json
```

### View Dashboard

Access the CloudWatch dashboard using the URL provided in the stack outputs:

```bash
aws cloudformation describe-stacks \
  --stack-name StorageOptimizationStack \
  --query 'Stacks[0].Outputs[?OutputKey==`DashboardUrl`].OutputValue' \
  --output text
```

## Cost Estimates

The solution creates the following resources with associated costs:

- **S3 Bucket**: Storage costs based on data volume and storage class
- **CloudWatch Dashboard**: $3/month per dashboard
- **AWS Budgets**: First 2 budgets are free, $0.02/day for additional budgets
- **Lambda Functions**: Free tier covers most usage (1M requests/month)
- **EventBridge Rules**: $1/million events

## Monitoring

### CloudWatch Metrics

The solution monitors the following metrics:

- `BucketSizeBytes`: Storage usage by storage class
- `NumberOfObjects`: Total object count
- Custom metrics from Lambda functions

### Budget Alerts

Configured to alert when:
- Actual costs exceed 80% of budget
- Forecasted costs exceed 100% of budget

## Security

The solution implements security best practices:

- **IAM Roles**: Least privilege access for Lambda functions
- **S3 Security**: Block public access, server-side encryption
- **Resource Tagging**: Consistent tagging for cost allocation

## Cleanup

To remove all resources:

```bash
cdk destroy
```

## Customization

### Adding Custom Lifecycle Rules

Modify the `lifecycleRules` array in `lib/storage-optimization-stack.ts`:

```typescript
lifecycleRules: [
  {
    id: 'CustomRule',
    enabled: true,
    prefix: 'custom-data/',
    transitions: [
      {
        storageClass: s3.StorageClass.INFREQUENT_ACCESS,
        transitionAfter: cdk.Duration.days(7)
      }
    ]
  }
]
```

### Customizing Cost Analysis

Modify the Lambda function code in the stack to add custom cost calculations or reporting logic.

## Troubleshooting

### Common Issues

1. **Bootstrap Error**: Ensure CDK is bootstrapped in your account/region
2. **Email Validation**: Budget alerts require valid email addresses
3. **IAM Permissions**: Ensure deployment role has necessary permissions

### Debugging

Enable debug logging:

```bash
cdk deploy --debug
```

View Lambda logs:

```bash
aws logs tail /aws/lambda/StorageOptimizationStack-CostAnalysisFunction --follow
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License.