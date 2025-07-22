# Infrastructure as Code for AI-Powered Infrastructure Code Generation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "AI-Powered Infrastructure Code Generation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys an automated system that leverages Amazon Q Developer's AI capabilities integrated with AWS Infrastructure Composer to generate, validate, and deploy infrastructure code templates. The solution includes:

- **S3 Bucket**: Storage for infrastructure templates with versioning and encryption
- **Lambda Function**: Automated template processing and validation
- **IAM Role**: Secure permissions for Lambda execution
- **S3 Event Notifications**: Automatic trigger for template processing
- **CloudWatch Logs**: Monitoring and debugging capabilities

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 (bucket creation, object operations)
  - Lambda (function creation, execution)
  - IAM (role and policy management)
  - CloudFormation (stack operations)
  - CloudWatch (log access)
- Visual Studio Code with AWS Toolkit extension (for full Q Developer experience)
- Amazon Q Developer authentication (AWS Builder ID or IAM Identity Center)
- Basic understanding of infrastructure as code concepts

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name q-developer-infrastructure \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ApplicationName,ParameterValue=QDeveloperApp \
                 ParameterKey=Environment,ParameterValue=dev

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name q-developer-infrastructure

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name q-developer-infrastructure \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters ApplicationName=QDeveloperApp \
           --parameters Environment=dev

# View outputs
cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters ApplicationName=QDeveloperApp \
           --parameters Environment=dev

# View outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan -var="application_name=QDeveloperApp" \
               -var="environment=dev"

# Apply the configuration
terraform apply -var="application_name=QDeveloperApp" \
                -var="environment=dev" \
                -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts for configuration
```

## Testing the Deployment

After deployment, test the AI-powered infrastructure generation:

1. **Upload a test template to trigger processing:**
   ```bash
   # Get bucket name from stack outputs
   BUCKET_NAME=$(aws cloudformation describe-stacks \
       --stack-name q-developer-infrastructure \
       --query 'Stacks[0].Outputs[?OutputKey==`TemplateBucketName`].OutputValue' \
       --output text)
   
   # Create a test CloudFormation template
   cat > test-template.json << 'EOF'
   {
       "AWSTemplateFormatVersion": "2010-09-09",
       "Description": "Test template for Q Developer automation",
       "Resources": {
           "TestParameter": {
               "Type": "AWS::SSM::Parameter",
               "Properties": {
                   "Name": "/test/q-developer-validation",
                   "Type": "String",
                   "Value": "Template validation successful"
               }
           }
       }
   }
   EOF
   
   # Upload to trigger processing
   aws s3 cp test-template.json s3://${BUCKET_NAME}/templates/test-template.json
   ```

2. **Monitor Lambda execution:**
   ```bash
   # Get Lambda function name from outputs
   FUNCTION_NAME=$(aws cloudformation describe-stacks \
       --stack-name q-developer-infrastructure \
       --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
       --output text)
   
   # Check recent logs
   aws logs filter-log-events \
       --log-group-name /aws/lambda/${FUNCTION_NAME} \
       --start-time $(date -d '5 minutes ago' +%s)000
   ```

3. **Verify validation results:**
   ```bash
   # Check for validation results
   aws s3 ls s3://${BUCKET_NAME}/validation-results/
   
   # Download and view results
   aws s3 cp s3://${BUCKET_NAME}/validation-results/test-template-validation.json ./
   cat test-template-validation.json
   ```

## Configuration

### CloudFormation Parameters

- `ApplicationName`: Name prefix for resources (default: QDeveloperApp)
- `Environment`: Deployment environment (default: dev)

### CDK Configuration

Modify the following in the CDK code:
- Application name and environment in the app configuration
- Lambda function timeout and memory settings
- S3 bucket policies and encryption settings

### Terraform Variables

Key variables in `terraform/variables.tf`:
- `application_name`: Application name prefix
- `environment`: Deployment environment
- `lambda_timeout`: Lambda function timeout in seconds
- `lambda_memory_size`: Lambda function memory allocation

## Customization

### Adding Custom Validation Rules

Extend the Lambda function to include additional validation logic:

1. **Security scanning**: Add checks for security best practices
2. **Cost estimation**: Integrate AWS Cost Explorer APIs
3. **Compliance validation**: Add organization-specific compliance rules

### Integration with CI/CD

Connect the infrastructure to your deployment pipeline:

1. **GitHub Actions**: Add workflow triggers for template uploads
2. **AWS CodePipeline**: Create pipeline stages for template validation
3. **GitOps**: Integrate with infrastructure repositories

### Amazon Q Developer Integration

For the complete AI-powered experience:

1. **Install AWS Toolkit**: In VS Code, install the AWS Toolkit extension
2. **Authenticate Q Developer**: Set up AWS Builder ID or IAM Identity Center
3. **Use Q Developer**: Generate infrastructure templates using natural language prompts
4. **Upload templates**: Save generated templates to the S3 bucket for automatic processing

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda function execution:
```bash
# View recent log events
aws logs filter-log-events \
    --log-group-name /aws/lambda/[FUNCTION_NAME] \
    --start-time $(date -d '1 hour ago' +%s)000
```

### S3 Event Notifications

Verify S3 event configuration:
```bash
# Check bucket notification configuration
aws s3api get-bucket-notification-configuration \
    --bucket [BUCKET_NAME]
```

### Lambda Function Status

Check function health:
```bash
# Get function information
aws lambda get-function --function-name [FUNCTION_NAME]

# Check function configuration
aws lambda get-function-configuration --function-name [FUNCTION_NAME]
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name q-developer-infrastructure

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name q-developer-infrastructure
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

- **IAM Roles**: All IAM roles follow the principle of least privilege
- **S3 Security**: Bucket has public access blocked and encryption enabled
- **Lambda Security**: Function runs with minimal required permissions
- **Event Security**: S3 events are filtered to specific prefixes and file types

## Cost Optimization

- **Lambda**: Pay-per-execution model with configurable memory and timeout
- **S3**: Lifecycle policies can be added for cost optimization
- **CloudWatch Logs**: Consider log retention policies to manage costs

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **AWS Documentation**: Check AWS service documentation for latest features
3. **Provider Documentation**: Review CloudFormation, CDK, or Terraform documentation
4. **Community Support**: Use AWS forums and Stack Overflow for community help

## Version Information

- **CloudFormation**: Uses latest AWS resource specifications
- **CDK**: Compatible with AWS CDK v2
- **Terraform**: Uses AWS Provider 5.x
- **Python**: Compatible with Python 3.11+
- **Node.js**: Compatible with Node.js 18+

## Related Resources

- [Amazon Q Developer Documentation](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/)
- [AWS Infrastructure Composer Guide](https://docs.aws.amazon.com/infrastructure-composer/latest/dg/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)