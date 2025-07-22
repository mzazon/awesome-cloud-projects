# Infrastructure as Code for Email Notification Automation with SES

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Email Notification Automation with SES".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for SES, Lambda, EventBridge, IAM, S3, and CloudWatch
- Verified email addresses in Amazon SES for sender and recipient
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

> **Important**: Ensure you have verified email addresses in SES before deployment. In SES sandbox mode, both sender and recipient emails must be verified.

## Architecture Overview

This solution deploys:
- Amazon SES email templates and configuration
- AWS Lambda function for email processing
- Amazon EventBridge custom bus and rules
- IAM roles and policies with least privilege
- CloudWatch monitoring and alarms
- S3 bucket for Lambda deployment packages

## Quick Start

### Using CloudFormation

```bash
# Set your email addresses
export SENDER_EMAIL="your-verified-sender@example.com"
export RECIPIENT_EMAIL="your-verified-recipient@example.com"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name email-automation-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=SenderEmail,ParameterValue=${SENDER_EMAIL} \
             ParameterKey=RecipientEmail,ParameterValue=${RECIPIENT_EMAIL} \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name email-automation-stack
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set environment variables
export SENDER_EMAIL="your-verified-sender@example.com"
export RECIPIENT_EMAIL="your-verified-recipient@example.com"

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters senderEmail=${SENDER_EMAIL} \
           --parameters recipientEmail=${RECIPIENT_EMAIL}
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
export SENDER_EMAIL="your-verified-sender@example.com"
export RECIPIENT_EMAIL="your-verified-recipient@example.com"

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters senderEmail=${SENDER_EMAIL} \
           --parameters recipientEmail=${RECIPIENT_EMAIL}
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
sender_email = "your-verified-sender@example.com"
recipient_email = "your-verified-recipient@example.com"
project_name = "email-automation"
aws_region = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export SENDER_EMAIL="your-verified-sender@example.com"
export RECIPIENT_EMAIL="your-verified-recipient@example.com"

# Deploy infrastructure
./scripts/deploy.sh
```

## Testing the Deployment

After successful deployment, test the email automation system:

```bash
# Get the EventBridge bus name from outputs
EVENT_BUS_NAME=$(aws cloudformation describe-stacks \
    --stack-name email-automation-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`EventBusName`].OutputValue' \
    --output text)

# Send a test email notification event
aws events put-events \
    --entries '[
      {
        "Source": "custom.application",
        "DetailType": "Email Notification Request",
        "Detail": "{\"emailConfig\":{\"recipient\":\"'${RECIPIENT_EMAIL}'\",\"subject\":\"Test Notification\"},\"title\":\"System Alert\",\"message\":\"This is a test notification from the automated email system.\"}",
        "EventBusName": "'${EVENT_BUS_NAME}'"
      }
    ]'

# Check Lambda logs for processing results
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name email-automation-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

aws logs filter-log-events \
    --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
    --start-time $(date -d '5 minutes ago' +%s)000
```

## Monitoring and Observability

The deployment includes CloudWatch monitoring:

- **Lambda Function Metrics**: Invocations, errors, duration
- **SES Metrics**: Send rate, bounce rate, complaint rate
- **EventBridge Metrics**: Rule invocations, failed invocations
- **Custom Alarms**: Lambda errors, SES bounces

Access CloudWatch dashboard:
```bash
aws cloudwatch list-dashboards
```

## Customization

### Environment Variables

All implementations support these customizable parameters:

- `SENDER_EMAIL`: Verified email address for sending notifications
- `RECIPIENT_EMAIL`: Default recipient email address
- `PROJECT_NAME`: Prefix for resource naming (default: "email-automation")
- `AWS_REGION`: AWS region for deployment (default: "us-east-1")

### Email Templates

Modify the email template in the SES configuration:
- **Subject**: Supports dynamic variables like `{{subject}}`
- **HTML Body**: Rich HTML formatting with variables
- **Text Body**: Plain text alternative

### Event Patterns

Customize EventBridge rules for different event patterns:
- Source filtering
- Detail-type matching
- Content-based routing
- Priority handling

### Lambda Function

Enhance the email processing logic:
- Add recipient validation
- Implement rate limiting
- Add email personalization
- Integrate with external APIs

## Cleanup

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name email-automation-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name email-automation-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Cost Optimization

To minimize costs:

1. **SES**: Pay only for emails sent (free tier: 62,000 emails/month)
2. **Lambda**: Pay per invocation and duration (free tier: 1M requests/month)
3. **EventBridge**: Pay per published event (free tier: 100M events/month)
4. **CloudWatch**: Monitor log retention and metrics storage

Estimated monthly cost for moderate usage (1,000 emails/month): $1-5

## Security Considerations

The deployment implements several security best practices:

- **IAM Least Privilege**: Lambda execution role has minimal required permissions
- **Email Verification**: SES requires verified sender and recipient addresses
- **Encryption**: All data encrypted in transit and at rest
- **VPC**: Optional VPC deployment for enhanced network security
- **Monitoring**: CloudWatch alarms for anomaly detection

## Troubleshooting

### Common Issues

1. **Email not verified**: Ensure both sender and recipient emails are verified in SES
2. **Lambda timeout**: Increase timeout in function configuration
3. **EventBridge rule not triggering**: Check event pattern matching
4. **Permission errors**: Verify IAM role permissions

### Debug Commands

```bash
# Check SES verification status
aws ses get-identity-verification-attributes \
    --identities ${SENDER_EMAIL} ${RECIPIENT_EMAIL}

# View Lambda function logs
aws logs tail /aws/lambda/${FUNCTION_NAME} --follow

# Check EventBridge rule metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name InvocationsCount \
    --dimensions Name=RuleName,Value=email-rule \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

## Performance Optimization

For high-volume email processing:

1. **Lambda Concurrency**: Configure reserved concurrency
2. **SES Sending Limits**: Request increased sending quotas
3. **EventBridge**: Use multiple rules for load distribution
4. **Error Handling**: Implement dead letter queues for failed events

## Compliance and Governance

- **Data Privacy**: Follow GDPR/CCPA requirements for email data
- **Retention**: Configure log retention policies
- **Audit**: Enable CloudTrail for API activity logging
- **Tagging**: Use consistent resource tagging for cost allocation

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review AWS service documentation
3. Consult CloudFormation/CDK/Terraform provider documentation
4. Review CloudWatch logs for detailed error information

## Additional Resources

- [AWS SES Developer Guide](https://docs.aws.amazon.com/ses/latest/dg/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)