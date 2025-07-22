# Infrastructure as Code for Automating Email Processing with SES and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automating Email Processing with SES and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating SES, Lambda, S3, SNS, and IAM resources
- A verified domain in Amazon SES for email receiving
- Node.js (for CDK TypeScript implementation)
- Python 3.9+ (for CDK Python implementation)
- Terraform v1.0+ (for Terraform implementation)

> **Important**: SES email receiving is only available in specific AWS regions. Ensure your target region supports SES email receiving functionality.

## Quick Start

### Using CloudFormation

```bash
# Set required parameters
export DOMAIN_NAME="example.com"  # Replace with your verified domain
export NOTIFICATION_EMAIL="your-email@example.com"  # Replace with your email

# Deploy the stack
aws cloudformation create-stack \
    --stack-name serverless-email-processing \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DomainName,ParameterValue=${DOMAIN_NAME} \
                 ParameterKey=NotificationEmail,ParameterValue=${NOTIFICATION_EMAIL} \
    --capabilities CAPABILITY_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name serverless-email-processing

# Get outputs
aws cloudformation describe-stacks \
    --stack-name serverless-email-processing \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set context variables
npx cdk context --set domainName="example.com"
npx cdk context --set notificationEmail="your-email@example.com"

# Bootstrap CDK (if first time)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --require-approval never

# View outputs
npx cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export DOMAIN_NAME="example.com"
export NOTIFICATION_EMAIL="your-email@example.com"

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
domain_name = "example.com"
notification_email = "your-email@example.com"
aws_region = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export DOMAIN_NAME="example.com"
export NOTIFICATION_EMAIL="your-email@example.com"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/validate.sh
```

## Post-Deployment Configuration

After deploying the infrastructure, you need to complete the DNS configuration:

1. **Add MX Record**: Add an MX record to your domain's DNS configuration:
   - Priority: 10
   - Value: `inbound-smtp.{your-region}.amazonaws.com`

2. **Confirm SNS Subscription**: Check your email for the SNS subscription confirmation and click the confirmation link.

3. **Test Email Processing**: Send test emails to the configured email addresses (e.g., `support@yourdomain.com`, `invoices@yourdomain.com`) to verify the system is working.

## Email Addresses Configured

The system automatically processes emails sent to:

- `support@{your-domain}` - Creates support tickets with automated replies
- `invoices@{your-domain}` - Processes invoices with confirmation emails
- Any email to these addresses will trigger appropriate automated responses

## Monitoring and Logs

### CloudWatch Logs

View Lambda function logs:

```bash
# List log groups
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# View recent logs
aws logs tail /aws/lambda/email-processor --follow
```

### S3 Email Storage

Check stored emails:

```bash
# List stored emails
aws s3 ls s3://email-processing-bucket/emails/ --recursive

# Download an email for inspection
aws s3 cp s3://email-processing-bucket/emails/message-id.txt ./
```

### SNS Notifications

Monitor SNS topic activity:

```bash
# Get SNS topic metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/SNS \
    --metric-name NumberOfMessagesPublished \
    --dimensions Name=TopicName,Value=email-notifications \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name serverless-email-processing

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name serverless-email-processing
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy --force
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Customization

### Environment Variables

All implementations support these customization options:

- `DOMAIN_NAME`: Your verified domain for email receiving
- `NOTIFICATION_EMAIL`: Email address for SNS notifications
- `AWS_REGION`: AWS region for deployment (ensure SES receiving is supported)
- `BUCKET_PREFIX`: Custom prefix for S3 bucket names
- `FUNCTION_TIMEOUT`: Lambda function timeout in seconds (default: 60)
- `MEMORY_SIZE`: Lambda function memory allocation (default: 256MB)

### Lambda Function Customization

To modify email processing logic:

1. Edit the Lambda function code in the respective implementation
2. Update the processing rules for different email types
3. Add additional email address patterns
4. Integrate with external systems (CRM, ticketing systems)

### Security Customization

- **IAM Policies**: Modify IAM roles to follow least privilege principle
- **Encryption**: Enable S3 bucket encryption and SNS topic encryption
- **VPC**: Deploy Lambda function in VPC for enhanced security
- **Email Filtering**: Add SES receipt rules for spam filtering

## Troubleshooting

### Common Issues

1. **Domain Not Verified**: Ensure your domain is verified in SES and MX record is configured
2. **Permission Errors**: Verify IAM permissions for all services
3. **Region Issues**: Confirm SES email receiving is available in your region
4. **Lambda Timeout**: Increase timeout if processing large emails with attachments

### Debug Commands

```bash
# Check SES domain verification status
aws ses get-identity-verification-attributes --identities ${DOMAIN_NAME}

# Test Lambda function
aws lambda invoke \
    --function-name email-processor \
    --payload '{"test": "true"}' \
    response.json

# Check S3 bucket permissions
aws s3api get-bucket-policy --bucket email-processing-bucket
```

## Cost Optimization

- **S3 Lifecycle**: Configure lifecycle policies to archive old emails to cheaper storage classes
- **Lambda Memory**: Optimize memory allocation based on actual usage patterns
- **SNS Filtering**: Use SNS message filtering to reduce notification costs
- **SES Quotas**: Monitor SES sending quotas to avoid throttling charges

## Security Best Practices

- Enable CloudTrail logging for all API calls
- Use SES configuration sets for sending metrics
- Implement email content scanning for malicious attachments
- Regular security review of IAM policies
- Enable VPC endpoints for private communication

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for configuration details
2. Review AWS service documentation for specific service issues
3. Verify all prerequisites are met
4. Check CloudWatch logs for detailed error messages

## Additional Resources

- [AWS SES Developer Guide](https://docs.aws.amazon.com/ses/latest/dg/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)