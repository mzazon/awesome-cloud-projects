# Infrastructure as Code for Simple Password Generator with Lambda and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Password Generator with Lambda and S3". This serverless solution provides secure password generation using AWS Lambda with encrypted storage in Amazon S3.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

The solution deploys the following AWS resources:

- **AWS Lambda Function**: Python 3.12 runtime function for secure password generation
- **Amazon S3 Bucket**: Encrypted storage for generated passwords with versioning enabled
- **IAM Role**: Least privilege execution role for Lambda function
- **IAM Policy**: Custom policy allowing S3 access and CloudWatch logging

## Prerequisites

### General Requirements

- AWS account with appropriate permissions
- AWS CLI installed and configured (version 2.0 or later)
- Appropriate permissions for creating Lambda functions, S3 buckets, and IAM roles
- Basic understanding of serverless concepts and Python

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- Ability to create IAM roles and policies

#### CDK TypeScript
- Node.js (version 18.x or later)
- AWS CDK CLI installed globally: `npm install -g aws-cdk`
- TypeScript compiler: `npm install -g typescript`

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI installed: `npm install -g aws-cdk`
- pip package manager

#### Terraform
- Terraform (version 1.0 or later)
- AWS provider for Terraform

### Estimated Costs

- **AWS Lambda**: Free tier covers up to 1M requests/month and 400,000 GB-seconds
- **Amazon S3**: Minimal storage costs (~$0.023 per GB/month)
- **CloudWatch Logs**: Free tier covers up to 5GB of ingested logs
- **Total estimated cost**: Less than $1.00 for testing scenarios

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name password-generator-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=my-password-bucket-$(date +%s)

# Monitor deployment status
aws cloudformation describe-stacks \
    --stack-name password-generator-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name password-generator-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview deployment
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk output
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview deployment
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh

# Verify deployment
aws lambda get-function --function-name $(terraform output -raw lambda_function_name)
```

## Testing the Deployment

After successful deployment, test the password generator:

```bash
# Get the Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name password-generator-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Test password generation
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{"length": 16, "name": "test-password"}' \
    response.json

# View response
cat response.json | python3 -m json.tool

# Check generated password in S3
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name password-generator-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

aws s3 ls s3://$BUCKET_NAME/passwords/
```

## Configuration Options

### Customizable Parameters

- **BucketName**: S3 bucket name for password storage (must be globally unique)
- **LambdaFunctionName**: Name for the Lambda function
- **LambdaMemorySize**: Memory allocation for Lambda function (128-10240 MB)
- **LambdaTimeout**: Function timeout in seconds (1-900 seconds)
- **EnableVersioning**: Enable S3 bucket versioning (true/false)
- **Environment**: Deployment environment tag (dev/staging/prod)

### Security Configuration

All implementations include the following security best practices:

- **Encryption at Rest**: S3 bucket uses AES-256 server-side encryption
- **Least Privilege IAM**: Lambda execution role has minimal required permissions
- **Public Access Blocking**: S3 bucket blocks all public access
- **Versioning**: S3 bucket versioning enabled for password history
- **CloudWatch Logging**: Comprehensive logging for monitoring and debugging

## Monitoring and Logging

### CloudWatch Integration

- Lambda function logs are automatically sent to CloudWatch Logs
- Log group: `/aws/lambda/{function-name}`
- Retention period: 14 days (configurable)

### Monitoring Commands

```bash
# View recent Lambda logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/$FUNCTION_NAME \
    --order-by LastEventTime \
    --descending

# Get function metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack (this will remove all resources)
aws cloudformation delete-stack --stack-name password-generator-stack

# Monitor deletion status
aws cloudformation describe-stacks \
    --stack-name password-generator-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
cd scripts/

# Run cleanup script
./destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup Verification

After running cleanup commands, verify all resources are removed:

```bash
# Check Lambda function is deleted
aws lambda get-function --function-name $FUNCTION_NAME 2>/dev/null || echo "Lambda function not found (deleted)"

# Check S3 bucket is deleted
aws s3api head-bucket --bucket $BUCKET_NAME 2>/dev/null || echo "S3 bucket not found (deleted)"

# Check IAM role is deleted
aws iam get-role --role-name $ROLE_NAME 2>/dev/null || echo "IAM role not found (deleted)"
```

## Troubleshooting

### Common Issues

1. **IAM Permissions Error**
   ```
   Error: User is not authorized to perform action
   Solution: Ensure your AWS credentials have IAM permissions to create roles and policies
   ```

2. **S3 Bucket Name Already Exists**
   ```
   Error: Bucket name already exists
   Solution: Use a unique bucket name or add a random suffix
   ```

3. **Lambda Function Timeout**
   ```
   Error: Task timed out after 3.00 seconds
   Solution: Increase the Lambda timeout value in configuration
   ```

4. **Python Dependencies Missing**
   ```
   Error: No module named 'boto3'
   Solution: Ensure boto3 is included in Lambda deployment package
   ```

### Debug Commands

```bash
# Check AWS CLI configuration
aws sts get-caller-identity

# Validate CloudFormation template
aws cloudformation validate-template --template-body file://cloudformation.yaml

# Check CDK version
cdk --version

# Validate Terraform configuration
terraform validate
```

## Advanced Configuration

### Environment-Specific Deployments

```bash
# Development environment
export ENVIRONMENT=dev
export BUCKET_NAME="password-generator-dev-$(date +%s)"

# Production environment
export ENVIRONMENT=prod
export BUCKET_NAME="password-generator-prod-$(date +%s)"
```

### Custom Lambda Configuration

```bash
# Deploy with custom memory and timeout
aws cloudformation create-stack \
    --stack-name password-generator-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=LambdaMemorySize,ParameterValue=256 \
        ParameterKey=LambdaTimeout,ParameterValue=60
```

## Security Considerations

### Production Deployment

- Enable AWS CloudTrail for API logging
- Configure AWS Config rules for compliance monitoring
- Implement VPC endpoints for enhanced network security
- Use AWS Secrets Manager for sensitive configuration
- Enable AWS GuardDuty for threat detection

### Access Control

- Implement fine-grained IAM policies for different user roles
- Use S3 bucket policies to restrict access patterns
- Enable MFA for administrative actions
- Regular rotation of IAM access keys

## Integration Examples

### API Gateway Integration

```bash
# Create API Gateway to expose Lambda function
aws apigateway create-rest-api --name password-generator-api

# Configure Lambda proxy integration
# (See API Gateway documentation for complete setup)
```

### CloudWatch Alarms

```bash
# Create alarm for Lambda errors
aws cloudwatch put-metric-alarm \
    --alarm-name password-generator-errors \
    --alarm-description "Lambda function errors" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for specific services
3. Validate IAM permissions and resource quotas
4. Use AWS CloudFormation/CDK/Terraform documentation for syntax issues
5. Enable debug logging for detailed troubleshooting

## Version Information

- Recipe Version: 1.1
- CloudFormation: AWS native
- CDK: Latest stable version (v2.x)
- Terraform: AWS Provider v5.x
- Python Runtime: 3.12
- Last Updated: 2025-07-12