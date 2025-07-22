# Infrastructure as Code for Lambda Cost Optimization with Compute Optimizer

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Lambda Cost Optimization with Compute Optimizer".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Lambda function management
  - Compute Optimizer access
  - CloudWatch metrics access
  - IAM role creation (for new Lambda functions)
- Existing Lambda functions with at least 14 days of execution history
- Basic understanding of Lambda memory allocation and cost structure

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name lambda-cost-optimizer \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name lambda-cost-optimizer \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Preview deployment
cdk diff

# Deploy infrastructure
cdk deploy

# List deployed resources
cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Preview deployment
cdk diff

# Deploy infrastructure
cdk deploy

# List deployed resources
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# Show deployed resources
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws compute-optimizer get-enrollment-status
```

## Infrastructure Components

This solution deploys and configures:

- **AWS Compute Optimizer**: Machine learning service for resource optimization
- **CloudWatch Metrics**: Performance monitoring and data collection
- **IAM Roles**: Appropriate permissions for Compute Optimizer access
- **Lambda Functions**: Test functions for validation (optional)
- **CloudWatch Alarms**: Performance monitoring post-optimization
- **S3 Bucket**: Storage for optimization reports and analysis data

## Configuration Options

### Environment Variables

Set these environment variables before deployment:

```bash
export AWS_REGION=us-east-1
export ENVIRONMENT=dev
export SAVINGS_THRESHOLD=1.00
export ENABLE_MONITORING=true
```

### CloudFormation Parameters

- `Environment`: Deployment environment (dev, staging, prod)
- `SavingsThreshold`: Minimum monthly savings to trigger optimization ($)
- `EnableMonitoring`: Whether to create CloudWatch alarms
- `NotificationEmail`: Email for optimization alerts

### Terraform Variables

Customize in `terraform.tfvars`:

```hcl
environment = "dev"
savings_threshold = 1.00
enable_monitoring = true
notification_email = "admin@company.com"
create_test_function = true
```

### CDK Configuration

Modify stack parameters in the CDK app files:

```typescript
// TypeScript
const optimizerStack = new LambdaCostOptimizerStack(app, 'LambdaCostOptimizer', {
  environment: 'dev',
  savingsThreshold: 1.00,
  enableMonitoring: true
});
```

```python
# Python
optimizer_stack = LambdaCostOptimizerStack(
    app, "LambdaCostOptimizer",
    environment="dev",
    savings_threshold=1.00,
    enable_monitoring=True
)
```

## Post-Deployment Steps

### 1. Enable Compute Optimizer

```bash
# Verify Compute Optimizer is enabled
aws compute-optimizer get-enrollment-status

# If not active, enable it
aws compute-optimizer put-enrollment-status --status Active
```

### 2. Wait for Data Collection

Compute Optimizer requires at least 14 days of CloudWatch metrics to generate reliable recommendations. For immediate testing with existing functions:

```bash
# Check if your functions have sufficient metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=your-function-name \
    --start-time $(date -d '14 days ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 3600 \
    --statistics Sum
```

### 3. Generate Initial Report

```bash
# Get optimization recommendations
aws compute-optimizer get-lambda-function-recommendations \
    --output table

# Export detailed recommendations
aws compute-optimizer get-lambda-function-recommendations \
    --output json > optimization-recommendations.json
```

### 4. Apply Optimizations

```bash
# Review recommendations first
cat optimization-recommendations.json | jq '.lambdaFunctionRecommendations[] | {functionName, finding, currentMemorySize, recommendedMemorySize: .memorySizeRecommendationOptions[0].memorySize, savings: .memorySizeRecommendationOptions[0].estimatedMonthlySavings.value}'

# Apply optimizations with threshold
python3 << 'EOF'
import json
import subprocess

with open('optimization-recommendations.json', 'r') as f:
    data = json.load(f)

for rec in data['lambdaFunctionRecommendations']:
    if rec['finding'] != 'Optimized':
        options = rec.get('memorySizeRecommendationOptions', [])
        if options and options[0].get('estimatedMonthlySavings', {}).get('value', 0) >= 1.00:
            function_name = rec['functionName']
            new_memory = options[0]['memorySize']
            
            subprocess.run([
                'aws', 'lambda', 'update-function-configuration',
                '--function-name', function_name,
                '--memory-size', str(new_memory)
            ])
            print(f"Updated {function_name} to {new_memory}MB")
EOF
```

## Monitoring and Validation

### Performance Monitoring

```bash
# Monitor function performance after optimization
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value=your-function-name \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Average,Maximum

# Check error rates
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Errors \
    --dimensions Name=FunctionName,Value=your-function-name \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

### Cost Analysis

```bash
# Check current month Lambda costs
CURRENT_MONTH=$(date '+%Y-%m-01')
NEXT_MONTH=$(date -d '+1 month' '+%Y-%m-01')

aws ce get-cost-and-usage \
    --time-period Start=$CURRENT_MONTH,End=$NEXT_MONTH \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --filter '{"Dimensions":{"Key":"SERVICE","Values":["AWS Lambda"]}}'
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name lambda-cost-optimizer

# Monitor deletion progress
aws cloudformation describe-stacks --stack-name lambda-cost-optimizer
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Clean up CDK context
rm -rf cdk.out/
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

# Disable Compute Optimizer (optional)
aws compute-optimizer put-enrollment-status --status Inactive
```

## Troubleshooting

### Common Issues

**Compute Optimizer not generating recommendations:**
- Ensure functions have at least 50 invocations over 14 days
- Verify CloudWatch metrics are being collected
- Check IAM permissions for Compute Optimizer

**Permission errors:**
```bash
# Verify required permissions
aws iam get-role --role-name ComputeOptimizerServiceRole
aws iam list-attached-role-policies --role-name ComputeOptimizerServiceRole
```

**Memory optimization failures:**
```bash
# Check function configuration limits
aws lambda get-account-settings

# Verify function isn't in use during update
aws lambda get-function --function-name your-function-name
```

### Rollback Procedures

**Revert memory changes:**
```bash
# Restore previous memory configuration
aws lambda update-function-configuration \
    --function-name your-function-name \
    --memory-size 512  # Previous value
```

**Disable optimizations:**
```bash
# Pause automatic optimizations
aws compute-optimizer put-enrollment-status --status Inactive
```

## Best Practices

1. **Gradual Implementation**: Start with non-critical functions
2. **Monitor Performance**: Watch for 24-48 hours after changes
3. **Set Thresholds**: Only optimize functions with significant savings potential
4. **Regular Reviews**: Check recommendations monthly
5. **Document Changes**: Keep track of optimization history
6. **Test Rollbacks**: Ensure you can revert changes quickly

## Cost Optimization Tips

- Focus on high-invocation functions for maximum impact
- Consider CPU-bound vs memory-bound workload characteristics
- Monitor cold start times after memory reductions
- Use Lambda Power Tuning for fine-grained optimization
- Implement cost alerts for unexpected increases

## Support

For issues with this infrastructure code:
- Review the original recipe documentation
- Check AWS Compute Optimizer documentation
- Verify CloudWatch metrics collection
- Consult AWS Lambda optimization best practices

## Additional Resources

- [AWS Compute Optimizer User Guide](https://docs.aws.amazon.com/compute-optimizer/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [AWS Lambda Power Tuning](https://github.com/alexcasalboni/aws-lambda-power-tuning)
- [AWS Cost Management](https://aws.amazon.com/aws-cost-management/)