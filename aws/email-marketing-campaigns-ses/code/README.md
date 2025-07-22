# Infrastructure as Code for Email Marketing Campaigns with SES

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Email Marketing Campaigns with SES".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon SES (Simple Email Service)
  - Amazon SNS (Simple Notification Service)
  - Amazon S3 (Simple Storage Service)
  - Amazon CloudWatch
  - AWS Lambda (for automation)
  - AWS EventBridge (for scheduling)
  - IAM roles and policies
- Domain ownership for sender identity verification
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

> **Important**: Amazon SES starts in sandbox mode. For production use, request a sending limit increase through the AWS Support Center.

## Architecture Overview

This solution deploys:
- **Amazon SES** configuration with domain verification and email templates
- **S3 bucket** for storing email templates and subscriber lists
- **SNS topic** for email event notifications (bounces, complaints, deliveries)
- **SES configuration set** for email tracking and analytics
- **CloudWatch dashboard** for monitoring campaign performance
- **EventBridge rules** for automated campaign scheduling
- **Lambda function** for bounce and complaint handling

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name email-marketing-stack \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=SenderDomain,ParameterValue=yourdomain.com \
        ParameterKey=SenderEmail,ParameterValue=marketing@yourdomain.com \
        ParameterKey=NotificationEmail,ParameterValue=admin@yourdomain.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name email-marketing-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Set required environment variables
export SENDER_DOMAIN=yourdomain.com
export SENDER_EMAIL=marketing@yourdomain.com
export NOTIFICATION_EMAIL=admin@yourdomain.com

# Deploy the stack
npx cdk deploy

# View outputs
npx cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Set required environment variables
export SENDER_DOMAIN=yourdomain.com
export SENDER_EMAIL=marketing@yourdomain.com
export NOTIFICATION_EMAIL=admin@yourdomain.com

# Deploy the stack
cdk deploy

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
sender_domain = "yourdomain.com"
sender_email = "marketing@yourdomain.com"
notification_email = "admin@yourdomain.com"
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

# Set required environment variables
export SENDER_DOMAIN=yourdomain.com
export SENDER_EMAIL=marketing@yourdomain.com
export NOTIFICATION_EMAIL=admin@yourdomain.com

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts for domain verification
```

## Post-Deployment Configuration

### 1. Domain Verification

After deployment, you must verify your domain with Amazon SES:

```bash
# Get DKIM tokens for DNS configuration
aws sesv2 get-email-identity \
    --email-identity yourdomain.com \
    --query 'DkimAttributes.Tokens' \
    --output table
```

Add the DKIM CNAME records to your domain's DNS configuration as displayed in the output.

### 2. Email Templates

The deployment creates sample email templates. To customize them:

```bash
# List available templates
aws sesv2 list-email-templates

# Update template content
aws sesv2 update-email-template \
    --template-name welcome-campaign \
    --template-content file://your-template.json
```

### 3. Subscriber Lists

Upload your subscriber lists to the created S3 bucket:

```bash
# Upload subscriber list
aws s3 cp subscribers.json s3://email-marketing-bucket-xxxxx/subscribers/

# Verify upload
aws s3 ls s3://email-marketing-bucket-xxxxx/subscribers/
```

### 4. SNS Subscription Confirmation

Check your notification email for SNS subscription confirmation and click the confirmation link.

## Monitoring and Analytics

### CloudWatch Dashboard

Access the pre-configured dashboard:

```bash
# Open CloudWatch console
aws cloudwatch get-dashboard \
    --dashboard-name EmailMarketingDashboard \
    --query 'DashboardBody' \
    --output text
```

### Key Metrics to Monitor

- **Send Rate**: Number of emails sent per time period
- **Bounce Rate**: Should remain below 5%
- **Complaint Rate**: Should remain below 0.1%
- **Delivery Rate**: Percentage of successful deliveries
- **Open Rate**: Engagement metric for campaign effectiveness
- **Click-through Rate**: Conversion metric for campaign success

### Alarms and Notifications

The deployment includes CloudWatch alarms for:
- High bounce rate (>5%)
- High complaint rate (>0.1%)
- Sending quota approaching limits
- Configuration set delivery issues

## Sending Your First Campaign

### Using the AWS CLI

```bash
# Send bulk personalized emails
aws sesv2 send-bulk-email \
    --from-email-address marketing@yourdomain.com \
    --destinations file://destinations.json \
    --template-name welcome-campaign \
    --default-template-data '{"name":"Customer","unsubscribe_url":"https://yourdomain.com/unsubscribe"}' \
    --configuration-set-name marketing-campaigns
```

### Destinations File Format

Create a `destinations.json` file:

```json
[
    {
        "Destination": {
            "ToAddresses": ["customer1@example.com"]
        },
        "ReplacementTemplateData": "{\"name\":\"John Doe\",\"unsubscribe_url\":\"https://yourdomain.com/unsubscribe\"}"
    },
    {
        "Destination": {
            "ToAddresses": ["customer2@example.com"]
        },
        "ReplacementTemplateData": "{\"name\":\"Jane Smith\",\"unsubscribe_url\":\"https://yourdomain.com/unsubscribe\"}"
    }
]
```

## Cost Optimization

### SES Pricing

- **Sending**: $0.10 per 1,000 emails
- **Receiving**: $0.09 per 1,000 emails
- **Data Transfer**: Standard AWS data transfer rates
- **Dedicated IP**: $24.95 per month (optional)

### Cost Monitoring

```bash
# Check current month's SES usage
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --query 'ResultsByTime[0].Groups[?Keys[0]==`Amazon Simple Email Service`]'
```

## Security Best Practices

### 1. IAM Least Privilege

The deployment follows least privilege principles:
- SES sending permissions only for specific domains
- S3 access limited to campaign bucket
- SNS publishing limited to email events
- CloudWatch access for monitoring only

### 2. Email Authentication

- **SPF Records**: Configure SPF records for your domain
- **DKIM**: Enabled automatically through SES configuration
- **DMARC**: Implement DMARC policy for enhanced security

### 3. Bounce and Complaint Handling

- Automated suppression list management
- Real-time bounce and complaint processing
- Compliance with CAN-SPAM and GDPR requirements

## Troubleshooting

### Common Issues

1. **Domain Verification Failing**
   - Check DNS propagation (can take 24-72 hours)
   - Verify DKIM records are correctly configured
   - Ensure no existing conflicting DNS records

2. **High Bounce Rate**
   - Review subscriber list quality
   - Check email validation before sending
   - Monitor suppression list for patterns

3. **Emails Going to Spam**
   - Verify SPF, DKIM, and DMARC configuration
   - Review email content for spam triggers
   - Consider dedicated IP for high-volume sending

4. **API Rate Limits**
   - Check sending quotas in SES console
   - Implement exponential backoff for API calls
   - Request limit increases if needed

### Debugging Commands

```bash
# Check SES sending statistics
aws sesv2 get-account-sending-enabled

# View configuration set details
aws sesv2 get-configuration-set \
    --configuration-set-name marketing-campaigns

# Check suppression list
aws sesv2 get-suppressed-destination \
    --email-address problematic@example.com

# View recent CloudWatch logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/bounce-handler \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Empty S3 bucket first (if versioning is enabled)
aws s3 rm s3://email-marketing-bucket-xxxxx --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name email-marketing-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name email-marketing-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# TypeScript
cd cdk-typescript/
npx cdk destroy

# Python
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SENDER_DOMAIN` | Domain for sending emails | Required |
| `SENDER_EMAIL` | Email address for sending | Required |
| `NOTIFICATION_EMAIL` | Email for notifications | Required |
| `AWS_REGION` | AWS region for deployment | `us-east-1` |
| `BUCKET_PREFIX` | S3 bucket name prefix | `email-marketing` |
| `CONFIG_SET_NAME` | SES configuration set name | `marketing-campaigns` |

### Template Customization

Modify the email templates in your deployment:

1. **Welcome Campaign**: Edit `templates/welcome-campaign.json`
2. **Product Promotion**: Edit `templates/product-promotion.json`
3. **Newsletter**: Create `templates/newsletter.json`

### Advanced Configuration

- **Custom Lambda Functions**: Add to `src/` directory
- **Additional SNS Topics**: Modify configuration for different event types
- **Enhanced Analytics**: Add custom CloudWatch metrics
- **A/B Testing**: Implement template variations

## Integration Examples

### CRM Integration

```python
# Example: Sync with Salesforce
import boto3
from salesforce_api import Salesforce

def sync_subscribers():
    ses_client = boto3.client('sesv2')
    sf = Salesforce(username='...', password='...', security_token='...')
    
    # Get contacts from Salesforce
    contacts = sf.query("SELECT Email, Name FROM Contact WHERE Email != null")
    
    # Update subscriber list in S3
    # Implementation details...
```

### Webhook Integration

```javascript
// Example: Handle webhook events
const AWS = require('aws-sdk');
const ses = new AWS.SESV2();

exports.handler = async (event) => {
    const { eventType, mail } = JSON.parse(event.Records[0].Sns.Message);
    
    if (eventType === 'bounce') {
        await ses.putSuppressedDestination({
            EmailAddress: mail.destination[0],
            Reason: 'BOUNCE'
        }).promise();
    }
    
    return { statusCode: 200 };
};
```

## Support

For issues with this infrastructure code:

1. Check the [Amazon SES documentation](https://docs.aws.amazon.com/ses/)
2. Review the [AWS SES best practices guide](https://docs.aws.amazon.com/ses/latest/dg/best-practices.html)
3. Refer to the original recipe documentation
4. Contact AWS Support for service-specific issues

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Ensure all security best practices are maintained
3. Update documentation accordingly
4. Validate with multiple deployment methods

## License

This infrastructure code is provided as-is for educational and reference purposes. Refer to your organization's policies for production use.