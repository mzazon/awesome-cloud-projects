# Infrastructure Policy Validation with CloudFormation Guard - CDK TypeScript

This CDK TypeScript application implements an automated infrastructure policy validation pipeline using AWS CloudFormation Guard. It creates the necessary AWS resources to enforce organizational infrastructure standards through policy-as-code validation.

## Architecture

The application creates:

- **S3 Bucket**: Secure storage for CloudFormation Guard rules, templates, and validation reports
- **IAM Role**: Service role with least-privilege permissions for validation operations  
- **Lambda Function**: Automated validation engine that processes templates against Guard rules
- **EventBridge Rules**: Scheduled and event-driven triggers for validation workflows
- **CloudWatch Logs**: Centralized logging and monitoring for validation activities

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- CloudFormation Guard CLI installed locally (optional, for local testing)
- Appropriate AWS permissions for creating resources

## Installation

1. Clone the repository and navigate to the CDK TypeScript directory:

```bash
git clone <repository-url>
cd aws/infrastructure-policy-validation-cloudformation-guard/code/cdk-typescript/
```

2. Install dependencies:

```bash
npm install
```

3. Bootstrap CDK (if not already done):

```bash
cdk bootstrap
```

## Configuration

### Environment Variables

Set the following environment variables before deployment:

```bash
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
```

### Context Configuration

You can customize the deployment through CDK context:

```bash
# Set environment type
cdk deploy -c environment=production

# Enable CDK Nag validation
cdk deploy -c enableCdkNag=true

# Custom resource prefix
cdk deploy -c resourcePrefix=my-org-guard
```

### Stack Configuration

The stack accepts the following configuration properties:

- `resourcePrefix`: Prefix for all resource names (default: 'cfn-guard')
- `enableVersioning`: Enable S3 bucket versioning (default: true)
- `enableAccessLogging`: Enable S3 access logging (default: true)
- `kmsKeyId`: KMS key ID for S3 bucket encryption (optional)

## Deployment

### Standard Deployment

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy the stack
cdk deploy

# View differences before deployment
cdk diff
```

### Production Deployment

```bash
# Deploy with production configuration
cdk deploy -c environment=production -c enableCdkNag=true
```

### Multi-Account Deployment

```bash
# Deploy to specific account and region
cdk deploy --profile production --region us-west-2
```

## Usage

### Uploading Guard Rules

After deployment, upload your CloudFormation Guard rules to the S3 bucket:

```bash
# Get bucket name from stack outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name InfrastructurePolicyValidationStack \
    --query 'Stacks[0].Outputs[?OutputKey==`GuardRulesBucketName`].OutputValue' \
    --output text)

# Upload Guard rules
aws s3 cp security-rules.guard s3://${BUCKET_NAME}/guard-rules/security/
aws s3 cp compliance-rules.guard s3://${BUCKET_NAME}/guard-rules/compliance/
```

### Validating Templates

#### Automated Validation

Templates uploaded to the `templates/` prefix are automatically validated:

```bash
# Upload template for validation
aws s3 cp my-template.yaml s3://${BUCKET_NAME}/templates/
```

#### Manual Validation

Trigger validation manually using the Lambda function:

```bash
# Get function name from stack outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name InfrastructurePolicyValidationStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ValidationFunctionName`].OutputValue' \
    --output text)

# Trigger validation
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{"template_key": "templates/my-template.yaml"}' \
    response.json

# View results
cat response.json
```

### Monitoring

View validation results in CloudWatch Logs:

```bash
# View Lambda function logs
aws logs tail /aws/lambda/${FUNCTION_NAME} --follow

# View validation results
aws logs tail /aws/events/cfn-guard-validation-results --follow
```

## Testing

### Unit Tests

```bash
# Run unit tests
npm test

# Run tests in watch mode
npm run test:watch
```

### Lint and Format

```bash
# Run linter
npm run lint

# Fix lint issues
npm run lint:fix
```

### CDK Validation

```bash
# Enable CDK Nag during synthesis
export ENABLE_CDK_NAG=true
cdk synth
```

## Customization

### Adding Custom Guard Rules

Create Guard rules following the [CloudFormation Guard syntax](https://docs.aws.amazon.com/cfn-guard/latest/ug/writing-rules.html):

```guard
# Example: EC2 instances must use approved AMIs
rule ec2_approved_amis {
    AWS::EC2::Instance {
        Properties {
            ImageId in ["ami-12345678", "ami-87654321"]
        }
    }
}
```

### Extending the Lambda Function

The validation Lambda function can be extended to support additional workflows:

1. Custom validation logic
2. Integration with external systems
3. Advanced reporting capabilities
4. Slack/email notifications

### Adding CI/CD Integration

Integrate with your CI/CD pipeline:

```yaml
# Example GitHub Actions workflow
- name: Validate CloudFormation Template
  run: |
    aws lambda invoke \
      --function-name ${{ env.VALIDATION_FUNCTION }} \
      --payload '{"template_key": "templates/${{ env.TEMPLATE_NAME }}"}' \
      validation-result.json
    
    # Check validation result and fail if non-compliant
    if grep -q '"status": "fail"' validation-result.json; then
      echo "Template validation failed"
      exit 1
    fi
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure your AWS credentials have sufficient permissions
2. **Bucket Already Exists**: The S3 bucket name must be globally unique
3. **Lambda Timeout**: Increase timeout for large template validations
4. **Memory Limits**: Increase Lambda memory for complex validations

### Debug Mode

Enable debug logging:

```bash
# Set debug log level
aws lambda update-function-configuration \
    --function-name ${FUNCTION_NAME} \
    --environment Variables='{LOG_LEVEL=DEBUG}'
```

### Validation Failures

Check CloudWatch Logs for detailed error messages:

```bash
aws logs filter-log-events \
    --log-group-name /aws/lambda/${FUNCTION_NAME} \
    --filter-pattern "ERROR"
```

## Security Considerations

- All S3 buckets use encryption and block public access
- IAM roles follow least-privilege principles
- CDK Nag validates security best practices
- Access logging is enabled for audit trails
- VPC endpoints can be added for private connectivity

## Cost Optimization

- S3 lifecycle policies automatically transition old objects to cheaper storage
- Lambda functions use appropriate memory sizing
- CloudWatch log retention is set to reasonable periods
- Non-current S3 versions are automatically deleted

## Cleanup

Remove all resources created by the stack:

```bash
# Empty S3 buckets first (if needed)
aws s3 rm s3://${BUCKET_NAME} --recursive

# Destroy the CDK stack
cdk destroy
```

## Support

For issues and questions:

1. Check CloudWatch Logs for error details
2. Review the [CloudFormation Guard documentation](https://docs.aws.amazon.com/cfn-guard/latest/ug/)
3. Consult the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
4. Open an issue in the repository

## License

This project is licensed under the MIT-0 License. See the LICENSE file for details.