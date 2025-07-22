# Infrastructure as Code for Custom CloudFormation Resources with Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Custom CloudFormation Resources with Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for CloudFormation, Lambda, IAM, and S3
- Python 3.9+ (for Lambda functions)
- Node.js 18+ (for CDK TypeScript)
- Terraform 1.0+ (for Terraform deployment)
- Estimated cost: $1-5 for Lambda execution, CloudWatch logs, and S3 storage

## Quick Start

### Using CloudFormation (AWS)

Deploy the complete custom resource solution:

```bash
# Create a unique stack name
STACK_NAME="custom-resource-demo-$(date +%s)"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name ${STACK_NAME} \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=production

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name ${STACK_NAME}

# Check outputs
aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls -l
```

### Using CDK Python (AWS)

```bash
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
cdk ls -l
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output resource ARNs and URLs upon completion
```

## Architecture Overview

The infrastructure deploys the following components:

- **Lambda Function**: Handles custom resource CREATE, UPDATE, and DELETE operations
- **IAM Role**: Provides necessary permissions for Lambda execution
- **S3 Bucket**: Stores custom resource data with encryption and versioning
- **CloudWatch Log Group**: Captures Lambda execution logs
- **Custom Resource**: Demonstrates the complete lifecycle management

## Configuration Options

### Environment Variables

All implementations support the following customizable parameters:

- `Environment`: Deployment environment (development, staging, production)
- `ResourceVersion`: Version of the custom resource implementation
- `RetentionDays`: CloudWatch log retention period
- `LambdaTimeout`: Lambda function timeout in seconds
- `LambdaMemorySize`: Lambda function memory allocation

### CloudFormation Parameters

```yaml
Parameters:
  Environment:
    Type: String
    Default: 'production'
    AllowedValues: ['development', 'staging', 'production']
  
  ResourceVersion:
    Type: String
    Default: '1.0'
    
  RetentionDays:
    Type: Number
    Default: 14
    AllowedValues: [1, 3, 5, 7, 14, 30, 60, 90]
```

### CDK Configuration

```typescript
// cdk-typescript/lib/custom-resource-stack.ts
const stackProps = {
  environment: 'production',
  resourceVersion: '1.0',
  retentionDays: logs.RetentionDays.TWO_WEEKS,
  lambdaTimeout: Duration.minutes(5),
  lambdaMemorySize: 256
};
```

### Terraform Variables

```hcl
# terraform/variables.tf
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "resource_version" {
  description = "Version of the custom resource"
  type        = string
  default     = "1.0"
}
```

## Testing the Deployment

After deployment, verify the custom resource functionality:

### Test Custom Resource Operations

```bash
# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs'

# Check S3 bucket contents
S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

aws s3 ls s3://${S3_BUCKET}/ --recursive

# View CloudWatch logs
LOG_GROUP=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' \
    --output text)

aws logs describe-log-streams \
    --log-group-name ${LOG_GROUP} \
    --order-by LastEventTime \
    --descending
```

### Test Lambda Function Directly

```bash
# Get Lambda function name
LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Create test event
cat > test-event.json << EOF
{
  "RequestType": "Create",
  "ResponseURL": "https://example.com/test",
  "StackId": "test-stack-id",
  "RequestId": "test-request-id",
  "ResourceType": "Custom::TestResource",
  "LogicalResourceId": "TestResource",
  "ResourceProperties": {
    "BucketName": "${S3_BUCKET}",
    "FileName": "test-file.json",
    "DataContent": "{\"test\": \"direct-invocation\"}"
  }
}
EOF

# Invoke function
aws lambda invoke \
    --function-name ${LAMBDA_FUNCTION} \
    --payload file://test-event.json \
    --cli-binary-format raw-in-base64-out \
    response.json
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name ${STACK_NAME}

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name ${STACK_NAME}

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} || echo "Stack successfully deleted"
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

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deletion
```

## Security Considerations

### IAM Permissions

The infrastructure follows the principle of least privilege:

- Lambda execution role has minimal S3 permissions
- CloudWatch logging permissions are scoped to specific log groups
- No public access to S3 buckets
- Server-side encryption enabled for all S3 objects

### Best Practices Implemented

- **Encryption**: All S3 buckets use AES-256 encryption
- **Versioning**: S3 versioning enabled with lifecycle policies
- **Logging**: Comprehensive CloudWatch logging for all operations
- **Access Control**: Public access blocked on all S3 buckets
- **Monitoring**: CloudWatch alarms for Lambda errors and timeouts

## Troubleshooting

### Common Issues

1. **Stack Creation Fails**: Check IAM permissions and CloudFormation limits
2. **Lambda Timeout**: Increase timeout value in configuration
3. **S3 Access Denied**: Verify IAM role permissions
4. **Custom Resource Stuck**: Check Lambda function logs

### Debugging Steps

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name ${STACK_NAME}

# View Lambda logs
aws logs tail /aws/lambda/${LAMBDA_FUNCTION} --follow

# Check Lambda function configuration
aws lambda get-function --function-name ${LAMBDA_FUNCTION}
```

## Advanced Usage

### Custom Resource Properties

The custom resource accepts the following properties:

```yaml
CustomResourceDemo:
  Type: AWS::CloudFormation::CustomResource
  Properties:
    ServiceToken: !GetAtt CustomResourceFunction.Arn
    BucketName: !Ref S3Bucket
    FileName: 'custom-data.json'
    DataContent: '{"key": "value"}'
    Environment: !Ref Environment
    Version: !Ref ResourceVersion
```

### Extending the Solution

To extend the custom resource functionality:

1. **Add New Properties**: Update the Lambda function to handle additional ResourceProperties
2. **Implement Validation**: Add input validation for new properties
3. **Update Outputs**: Return additional attributes from the custom resource
4. **Add Dependencies**: Configure resource dependencies in CloudFormation

### Error Handling

The Lambda function includes comprehensive error handling:

- Input validation for required properties
- Graceful handling of S3 errors
- Proper CloudFormation response formatting
- Detailed logging for troubleshooting

## Integration with CI/CD

### GitHub Actions

```yaml
name: Deploy Custom Resource
on: [push]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Deploy with CDK
        run: |
          cd cdk-typescript/
          npm install
          cdk deploy --require-approval never
```

### AWS CodePipeline

The infrastructure can be integrated with AWS CodePipeline for automated deployments using CloudFormation or CDK.

## Cost Optimization

### Resource Costs

- **Lambda**: Pay per invocation and execution time
- **S3**: Storage costs with lifecycle policies
- **CloudWatch**: Log storage and retention costs
- **IAM**: No additional costs

### Optimization Tips

1. **Adjust Lambda Memory**: Right-size memory allocation based on usage
2. **Log Retention**: Set appropriate retention periods for CloudWatch logs
3. **S3 Lifecycle**: Configure lifecycle policies for old object versions
4. **Monitoring**: Use CloudWatch metrics to identify unused resources

## Support and Documentation

### Additional Resources

- [AWS CloudFormation Custom Resources Documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Getting Help

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review AWS service documentation
3. Examine CloudWatch logs for error details
4. Consult the AWS Support documentation

## Version History

- **v1.0**: Initial implementation with basic custom resource functionality
- **v1.1**: Added advanced error handling and validation
- **v1.2**: Enhanced security configurations and monitoring