# Infrastructure as Code for Optimizing Costs with Automated Savings Plans

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Optimizing Costs with Automated Savings Plans".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- At least 60 days of historical usage data in your AWS account
- Appropriate IAM permissions for:
  - Cost Explorer API access
  - Savings Plans API access
  - Lambda function management
  - S3 bucket operations
  - IAM role creation
  - CloudWatch access
  - EventBridge rule management
- Basic understanding of AWS compute services (EC2, Lambda, Fargate)
- Estimated cost: $0.01 per Cost Explorer API call + Lambda execution costs (under $5/month)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name savings-plans-recommendations \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=LookbackDays,ParameterValue=SIXTY_DAYS \
                 ParameterKey=TermInYears,ParameterValue=ONE_YEAR \
                 ParameterKey=PaymentOption,ParameterValue=NO_UPFRONT

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name savings-plans-recommendations \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for configuration options and deploy all resources
```

## Configuration Options

### Common Parameters

- **LookbackDays**: Analysis period for historical data (SEVEN_DAYS, THIRTY_DAYS, SIXTY_DAYS)
- **TermInYears**: Savings Plans term length (ONE_YEAR, THREE_YEARS)
- **PaymentOption**: Payment method (NO_UPFRONT, PARTIAL_UPFRONT, ALL_UPFRONT)
- **Region**: AWS region for deployment (defaults to current CLI region)

### CloudFormation Parameters

```yaml
Parameters:
  LookbackDays:
    Type: String
    Default: SIXTY_DAYS
    AllowedValues: [SEVEN_DAYS, THIRTY_DAYS, SIXTY_DAYS]
  
  TermInYears:
    Type: String
    Default: ONE_YEAR
    AllowedValues: [ONE_YEAR, THREE_YEARS]
  
  PaymentOption:
    Type: String
    Default: NO_UPFRONT
    AllowedValues: [NO_UPFRONT, PARTIAL_UPFRONT, ALL_UPFRONT]
```

### CDK Configuration

Modify the configuration in `app.ts` or `app.py`:

```typescript
const config = {
  lookbackDays: 'SIXTY_DAYS',
  termInYears: 'ONE_YEAR',
  paymentOption: 'NO_UPFRONT',
  analysisSchedule: 'rate(30 days)'
};
```

### Terraform Variables

```hcl
variable "lookback_days" {
  description = "Analysis period for historical data"
  type        = string
  default     = "SIXTY_DAYS"
  validation {
    condition     = contains(["SEVEN_DAYS", "THIRTY_DAYS", "SIXTY_DAYS"], var.lookback_days)
    error_message = "Valid values are SEVEN_DAYS, THIRTY_DAYS, or SIXTY_DAYS."
  }
}

variable "term_in_years" {
  description = "Savings Plans term length"
  type        = string
  default     = "ONE_YEAR"
  validation {
    condition     = contains(["ONE_YEAR", "THREE_YEARS"], var.term_in_years)
    error_message = "Valid values are ONE_YEAR or THREE_YEARS."
  }
}

variable "payment_option" {
  description = "Payment method for Savings Plans"
  type        = string
  default     = "NO_UPFRONT"
  validation {
    condition     = contains(["NO_UPFRONT", "PARTIAL_UPFRONT", "ALL_UPFRONT"], var.payment_option)
    error_message = "Valid values are NO_UPFRONT, PARTIAL_UPFRONT, or ALL_UPFRONT."
  }
}
```

## Deployed Resources

This infrastructure creates the following AWS resources:

1. **Lambda Function**: Core analysis engine for Savings Plans recommendations
2. **S3 Bucket**: Storage for analysis reports and historical data
3. **IAM Role**: Service role with permissions for Cost Explorer and Savings Plans APIs
4. **EventBridge Rule**: Automated scheduling for monthly analysis
5. **CloudWatch Log Group**: Centralized logging for Lambda function
6. **CloudWatch Dashboard**: Monitoring and observability for the solution

## Usage

### Manual Analysis

After deployment, trigger analysis manually:

```bash
# Get the Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name savings-plans-recommendations \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Invoke the function
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{"lookback_days": "SIXTY_DAYS", "term_years": "ONE_YEAR", "payment_option": "NO_UPFRONT"}' \
    --output-file response.json

# View results
cat response.json | jq '.body' | jq -r . | jq .
```

### Automated Analysis

The solution automatically runs monthly analysis via EventBridge. View the CloudWatch dashboard to monitor execution:

```bash
# Get dashboard URL
aws cloudwatch get-dashboard \
    --dashboard-name "SavingsPlansRecommendations" \
    --query 'DashboardBody' --output text
```

### Accessing Reports

Generated reports are stored in S3:

```bash
# Get S3 bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name savings-plans-recommendations \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

# List available reports
aws s3 ls s3://$BUCKET_NAME/savings-plans-recommendations/ --recursive

# Download latest report
aws s3 cp s3://$BUCKET_NAME/savings-plans-recommendations/latest.json ./latest-report.json
```

## Monitoring and Troubleshooting

### CloudWatch Logs

```bash
# View recent logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/savings-plans-analyzer" \
    --start-time $(date -d '1 hour ago' +%s)000 \
    --query 'events[*].message' --output text
```

### Lambda Function Metrics

```bash
# Get function metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
    --start-time $(date -d '1 day ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 3600 \
    --statistics Average,Maximum
```

### Common Issues

1. **Insufficient Historical Data**: Ensure your account has at least 60 days of usage data
2. **API Rate Limits**: Cost Explorer APIs are rate-limited; the function includes retry logic
3. **IAM Permissions**: Verify the Lambda execution role has all required permissions
4. **Regional Availability**: Some Cost Explorer features may not be available in all regions

## Security Considerations

- Lambda function uses IAM roles with least-privilege access
- S3 bucket has server-side encryption enabled by default
- All API calls are logged to CloudWatch for audit purposes
- No sensitive data is stored in environment variables or function code

## Cost Optimization

- Lambda function runs on-demand with minimal resource requirements
- S3 storage costs are minimal for recommendation reports
- Cost Explorer API calls are the primary cost driver ($0.01 per call)
- EventBridge scheduling incurs no additional charges

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name savings-plans-recommendations

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name savings-plans-recommendations \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Customization

### Adding New Savings Plans Types

Modify the Lambda function to analyze additional Savings Plans types:

```python
# Add new types to the analysis
sp_types = ['COMPUTE_SP', 'EC2_INSTANCE_SP', 'SAGEMAKER_SP', 'LAMBDA_SP']
```

### Custom Notification Integration

Extend the solution to send notifications via SNS or integrate with Slack:

```python
# Add SNS notification after analysis
sns_client = boto3.client('sns')
sns_client.publish(
    TopicArn='arn:aws:sns:region:account:topic',
    Message=json.dumps(results),
    Subject='Monthly Savings Plans Recommendations'
)
```

### Multi-Account Analysis

For AWS Organizations, modify the function to analyze across multiple accounts:

```python
# Iterate through organization accounts
org_client = boto3.client('organizations')
accounts = org_client.list_accounts()['Accounts']

for account in accounts:
    # Assume role in each account and run analysis
    pass
```

## Support

For issues with this infrastructure code, refer to:

1. The original recipe documentation
2. AWS Cost Explorer API documentation
3. AWS Savings Plans documentation
4. Provider-specific documentation (CloudFormation, CDK, Terraform)

## Contributing

When modifying this infrastructure:

1. Follow AWS best practices for security and cost optimization
2. Update all IaC implementations consistently
3. Test changes in a development environment first
4. Update documentation to reflect changes
5. Consider backward compatibility for existing deployments