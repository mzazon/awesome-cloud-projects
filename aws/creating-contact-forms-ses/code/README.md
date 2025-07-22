# Infrastructure as Code for Creating Contact Forms with SES and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Creating Contact Forms with SES and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for Lambda, API Gateway, SES, and IAM
- A verified email address in Amazon SES for sending notifications
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name contact-form-backend \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=SenderEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name contact-form-backend

# Get the API endpoint URL
aws cloudformation describe-stacks \
    --stack-name contact-form-backend \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set required environment variables
export SENDER_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy --parameters senderEmail=$SENDER_EMAIL

# The API endpoint URL will be displayed in the output
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment and install dependencies
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Set required environment variables
export SENDER_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy --parameters senderEmail=$SENDER_EMAIL

# The API endpoint URL will be displayed in the output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your configuration
cat > terraform.tfvars << EOF
sender_email = "your-email@example.com"
project_name = "contact-form"
environment = "prod"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Get the API endpoint URL
terraform output api_endpoint_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export SENDER_EMAIL=your-email@example.com

# Deploy the infrastructure
./scripts/deploy.sh

# The API endpoint URL will be displayed after successful deployment
```

## Configuration

### Required Parameters

- **sender_email**: The verified email address that will send contact form notifications
- **project_name**: Name prefix for all created resources (default: "contact-form")
- **environment**: Environment tag for resources (default: "prod")

### Optional Parameters

- **lambda_timeout**: Lambda function timeout in seconds (default: 30)
- **lambda_memory**: Lambda function memory in MB (default: 128)
- **api_stage_name**: API Gateway stage name (default: "prod")

## Testing the Deployment

Once deployed, test your contact form backend:

```bash
# Get the API endpoint URL (replace with your actual endpoint)
API_ENDPOINT="https://your-api-id.execute-api.region.amazonaws.com/prod/contact"

# Test the API with curl
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "name": "John Doe",
        "email": "john@example.com",
        "subject": "Test Message",
        "message": "This is a test message from the contact form."
    }' \
    $API_ENDPOINT

# Expected response: {"message": "Email sent successfully", "messageId": "..."}
```

## Architecture

The deployed infrastructure includes:

- **Lambda Function**: Processes contact form submissions and sends emails
- **API Gateway**: REST API with CORS enabled for web browser access
- **IAM Role**: Lambda execution role with SES permissions
- **SES Configuration**: Email service for sending notifications

## Security Features

- IAM roles follow least privilege principles
- API Gateway includes rate limiting and throttling
- CORS headers configured for secure cross-origin requests
- Email address validation and input sanitization
- CloudWatch logging for monitoring and debugging

## Monitoring and Logs

- Lambda function logs are available in CloudWatch Logs
- API Gateway access logs can be enabled for request tracking
- SES sending statistics available in SES console
- CloudWatch metrics for monitoring function performance

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name contact-form-backend

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name contact-form-backend
```

### Using CDK

```bash
# From the CDK directory (TypeScript or Python)
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Adding Form Validation

Modify the Lambda function code to include additional validation rules:

```python
# Example: Add phone number validation
import re

def validate_phone(phone):
    pattern = r'^\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}$'
    return re.match(pattern, phone) is not None
```

### Integrating with Frontend

Use the API endpoint in your web application:

```javascript
// Example: JavaScript fetch request
async function submitContactForm(formData) {
    const response = await fetch('YOUR_API_ENDPOINT', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify(formData)
    });
    
    const result = await response.json();
    return result;
}
```

### Adding Auto-Response

Extend the Lambda function to send confirmation emails:

```python
# Send confirmation email to form submitter
ses_client.send_email(
    Source=sender_email,
    Destination={'ToAddresses': [email]},
    Message={
        'Subject': {'Data': 'Thank you for contacting us'},
        'Body': {'Text': {'Data': 'We received your message and will respond soon.'}}
    }
)
```

## Cost Optimization

- **Lambda**: First 1M requests/month are free, then $0.0000002 per request
- **API Gateway**: $1.00 per million API calls
- **SES**: 62,000 free emails/month from Lambda, then $0.0001 per email
- **CloudWatch**: Basic monitoring included, detailed logs charged per GB

Estimated monthly cost for typical usage (100 form submissions):
- Lambda: $0.00 (within free tier)
- API Gateway: $0.00 (within free tier)
- SES: $0.00 (within free tier)
- **Total: Less than $0.01/month**

## Troubleshooting

### Common Issues

1. **Email not verified in SES**
   - Verify your sender email address in the SES console
   - Check your email for the verification link

2. **CORS errors in browser**
   - Ensure API Gateway CORS is properly configured
   - Check that preflight OPTIONS requests are handled

3. **Lambda function timeout**
   - Increase timeout value if processing takes longer
   - Check CloudWatch logs for detailed error messages

4. **Permission errors**
   - Verify IAM role has necessary SES permissions
   - Check that API Gateway can invoke Lambda function

### Debug Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/contact-form"

# Test Lambda function directly
aws lambda invoke \
    --function-name contact-form-processor \
    --payload '{"body": "{\"name\":\"Test\",\"email\":\"test@example.com\",\"message\":\"Test\"}"}' \
    response.json

# Check SES sending quota
aws ses get-send-quota
```

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../simple-contact-form-backend-ses-lambda-api-gateway.md)
- [AWS Lambda documentation](https://docs.aws.amazon.com/lambda/)
- [Amazon SES documentation](https://docs.aws.amazon.com/ses/)
- [API Gateway documentation](https://docs.aws.amazon.com/apigateway/)

## Version History

- **v1.0**: Initial implementation with CloudFormation, CDK, Terraform, and Bash scripts
- **v1.1**: Added enhanced error handling and validation
- **v1.2**: Improved security configurations and monitoring