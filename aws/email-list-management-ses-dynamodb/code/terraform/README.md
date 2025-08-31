# Infrastructure as Code for Email List Management with SES and DynamoDB

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete serverless email list management system using AWS services including DynamoDB for subscriber storage, Amazon SES for email delivery, and Lambda functions for subscription management and newsletter sending.

## Architecture Overview

The infrastructure deploys the following AWS resources:

- **DynamoDB Table**: Stores subscriber information with email as the primary key
- **Amazon SES Email Identity**: Verified sender identity for newsletter delivery
- **Lambda Functions**: Four serverless functions for core functionality:
  - Subscribe: Handle new subscriber registrations
  - Newsletter: Send newsletters to all active subscribers
  - List: Administrative function to view all subscribers
  - Unsubscribe: Handle unsubscription requests
- **IAM Roles & Policies**: Secure access with least-privilege permissions
- **CloudWatch Log Groups**: Centralized logging for all Lambda functions
- **Lambda Function URLs** (optional): Direct HTTPS access to functions

## Prerequisites

Before deploying this infrastructure, ensure you have:

- **AWS CLI** installed and configured with appropriate permissions
- **Terraform** version 1.5.0 or later installed
- An **AWS account** with permissions to create the following resources:
  - DynamoDB tables
  - Lambda functions
  - IAM roles and policies
  - SES email identities
  - CloudWatch log groups
- A **verified email address** for sending newsletters (will be verified during deployment)

### Required AWS Permissions

Your AWS credentials must have permissions for:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:*",
        "lambda:*",
        "iam:*",
        "ses:*",
        "logs:*",
        "events:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd aws/email-list-management-ses-dynamodb/code/terraform/
```

### 2. Initialize Terraform
```bash
terraform init
```

### 3. Configure Variables
Create a `terraform.tfvars` file with your configuration:

```hcl
# Required: Your verified email address for sending newsletters
sender_email = "your-verified-email@example.com"

# Optional: Environment and configuration
environment = "dev"
log_retention_days = 14
enable_function_urls = true
allowed_origins = ["https://yourdomain.com", "https://localhost:3000"]

# Optional: Lambda function configuration
newsletter_function_config = {
  timeout     = 300
  memory_size = 512
}

subscribe_function_config = {
  timeout     = 30
  memory_size = 256
}
```

### 4. Plan Deployment
```bash
terraform plan
```

### 5. Deploy Infrastructure
```bash
terraform apply
```

When prompted, type `yes` to confirm the deployment.

### 6. Verify SES Email Identity
After deployment, you'll receive a verification email at the sender address. **Click the verification link** before testing the newsletter functionality.

## Configuration Options

### Required Variables

| Variable | Description | Type | Example |
|----------|-------------|------|---------|
| `sender_email` | Verified email address for sending newsletters | string | `"newsletter@company.com"` |

### Optional Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `environment` | Environment name for tagging | `"dev"` | string |
| `lambda_runtime` | Python runtime version | `"python3.12"` | string |
| `log_retention_days` | CloudWatch log retention | `14` | number |
| `enable_function_urls` | Enable direct HTTPS access | `false` | bool |
| `allowed_origins` | CORS allowed origins | `["https://yourdomain.com"]` | list(string) |

### Advanced Configuration

```hcl
# Enable X-Ray tracing for debugging
enable_xray_tracing = true

# Configure Lambda function settings
newsletter_function_config = {
  timeout = 300      # 5 minutes for bulk operations
  memory_size = 512  # Higher memory for processing
}

# Additional resource tags
additional_tags = {
  CostCenter = "Marketing"
  Owner      = "DevOps Team"
}

# VPC configuration (optional)
vpc_config = {
  subnet_ids         = ["subnet-12345", "subnet-67890"]
  security_group_ids = ["sg-abcdef123"]
}
```

## Testing the Deployment

After successful deployment, test the functions using the AWS CLI:

### 1. Subscribe a Test User
```bash
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_names | jq -r '.subscribe') \
  --payload '{"email":"test@example.com","name":"Test User"}' \
  response.json && cat response.json
```

### 2. List Subscribers
```bash
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_names | jq -r '.list') \
  --payload '{}' \
  response.json && cat response.json
```

### 3. Send Test Newsletter
**Note**: Ensure your sender email is verified in SES before running this test.

```bash
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_names | jq -r '.newsletter') \
  --payload '{"subject":"Test Newsletter","message":"Welcome to our newsletter!"}' \
  response.json && cat response.json
```

### 4. Unsubscribe Test User
```bash
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_names | jq -r '.unsubscribe') \
  --payload '{"email":"test@example.com","reason":"Testing"}' \
  response.json && cat response.json
```

## Using Function URLs (Optional)

If you enabled Function URLs (`enable_function_urls = true`), you can invoke functions directly via HTTPS:

```bash
# Get function URLs
terraform output lambda_function_urls

# Subscribe via HTTP POST
curl -X POST "$(terraform output -raw lambda_function_urls | jq -r '.subscribe')" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","name":"Test User"}'

# Unsubscribe via GET (useful for email links)
curl "$(terraform output -raw lambda_function_urls | jq -r '.unsubscribe')?email=test@example.com"
```

## Integration with Web Applications

### API Gateway Integration

Use the Lambda invoke ARNs for API Gateway integration:

```json
{
  "Type": "AWS_PROXY",
  "IntegrationHttpMethod": "POST",
  "Uri": "arn:aws:apigateway:region:lambda:path/2015-03-31/functions/LAMBDA_FUNCTION_ARN/invocations"
}
```

### React/JavaScript Frontend Example

```javascript
// Subscribe function
async function subscribeUser(email, name) {
  const response = await fetch('YOUR_FUNCTION_URL', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email, name })
  });
  
  return await response.json();
}

// Newsletter sending (admin only)
async function sendNewsletter(subject, message) {
  const response = await fetch('YOUR_NEWSLETTER_URL', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer YOUR_JWT_TOKEN'
    },
    body: JSON.stringify({ subject, message })
  });
  
  return await response.json();
}
```

## Monitoring and Observability

### CloudWatch Dashboards

Create dashboards to monitor:
- Lambda function invocations and errors
- DynamoDB read/write capacity usage
- SES sending statistics
- Email bounce and complaint rates

### Recommended CloudWatch Alarms

```bash
# High error rate alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "EmailList-HighErrorRate" \
  --alarm-description "High error rate in email list functions" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=YOUR_FUNCTION_NAME

# DynamoDB throttling alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "EmailList-DynamoDB-Throttling" \
  --alarm-description "DynamoDB throttling detected" \
  --metric-name SystemErrors \
  --namespace AWS/DynamoDB \
  --statistic Sum \
  --period 300 \
  --threshold 0 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=TableName,Value=YOUR_TABLE_NAME
```

## Security Considerations

### Production Security Checklist

- [ ] Enable Function URLs only with proper authentication (`AWS_IAM`)
- [ ] Configure API Gateway with API keys and usage plans
- [ ] Set up WAF rules for DDoS protection
- [ ] Enable CloudTrail for audit logging
- [ ] Configure SES sending limits and monitoring
- [ ] Implement bounce and complaint handling
- [ ] Use AWS Secrets Manager for sensitive configuration
- [ ] Enable VPC endpoint access for Lambda functions
- [ ] Configure least-privilege IAM policies

### SES Security

```bash
# Configure SES to send bounce/complaint notifications
aws ses put-identity-notification-attributes \
  --identity your-verified-email@example.com \
  --notification-type Bounce \
  --sns-topic arn:aws:sns:region:account:bounce-topic

aws ses put-identity-notification-attributes \
  --identity your-verified-email@example.com \
  --notification-type Complaint \
  --sns-topic arn:aws:sns:region:account:complaint-topic
```

## Cost Optimization

### Estimated Monthly Costs (Low Volume)

| Service | Usage | Cost |
|---------|-------|------|
| DynamoDB | 1M read/write requests | ~$0.25 |
| Lambda | 100K requests, 1GB-sec | ~$2.08 |
| SES | 1K emails | ~$0.10 |
| CloudWatch Logs | 1GB ingested | ~$0.50 |
| **Total Estimated** | | **~$2.93/month** |

### Cost Optimization Tips

1. **DynamoDB**: Use on-demand billing for variable workloads
2. **Lambda**: Optimize memory allocation based on actual usage
3. **SES**: Request production access to avoid sandbox limitations
4. **CloudWatch**: Set appropriate log retention periods
5. **Monitoring**: Set up billing alerts for cost control

## Troubleshooting

### Common Issues

#### 1. SES Email Not Verified
**Error**: Email sending fails with "MessageRejected"
**Solution**: 
```bash
# Check verification status
aws ses get-identity-verification-attributes --identities your-email@example.com

# Resend verification email
aws ses verify-email-identity --email-address your-email@example.com
```

#### 2. Lambda Function Timeout
**Error**: Function times out during newsletter sending
**Solution**: Increase timeout in `terraform.tfvars`:
```hcl
newsletter_function_config = {
  timeout = 600  # 10 minutes
  memory_size = 1024
}
```

#### 3. DynamoDB Throttling
**Error**: `ProvisionedThroughputExceededException`
**Solution**: The default on-demand billing should handle this automatically. If issues persist, check for hot partitions.

#### 4. CORS Issues with Function URLs
**Error**: Browser blocks requests due to CORS
**Solution**: Update allowed origins:
```hcl
allowed_origins = ["https://yourdomain.com", "http://localhost:3000"]
```

### Debug Commands

```bash
# Check recent Lambda function logs
aws logs describe-log-streams \
  --log-group-name "/aws/lambda/YOUR_FUNCTION_NAME" \
  --order-by LastEventTime --descending

# Get latest log events
aws logs get-log-events \
  --log-group-name "/aws/lambda/YOUR_FUNCTION_NAME" \
  --log-stream-name "STREAM_NAME"

# Check DynamoDB table status
aws dynamodb describe-table --table-name YOUR_TABLE_NAME

# Check SES sending statistics
aws ses get-send-statistics
```

## Customization and Extensions

### Adding Email Templates

1. Create SES templates:
```bash
aws ses create-template \
  --template TemplateName=WelcomeEmail,TemplateData='{"Subject":"Welcome!","HtmlPart":"<h1>Welcome {{name}}!</h1>","TextPart":"Welcome {{name}}!"}'
```

2. Update newsletter function to use templates:
```python
ses.send_templated_email(
    Source=SENDER_EMAIL,
    Destination={'ToAddresses': [email]},
    Template='WelcomeEmail',
    TemplateData=json.dumps({'name': subscriber_name})
)
```

### Adding Bounce/Complaint Handling

1. Create SNS topics for notifications
2. Configure SES to publish to SNS
3. Add Lambda function to process notifications
4. Update subscriber status based on bounces/complaints

### Adding Analytics

1. Enable DynamoDB Streams
2. Create Lambda function to process stream events
3. Store analytics in separate DynamoDB table or send to analytics service

## Cleanup

To remove all deployed resources:

```bash
# Destroy infrastructure
terraform destroy

# Verify cleanup
aws ses list-identities
aws dynamodb list-tables
aws lambda list-functions --query 'Functions[?contains(FunctionName, `email-list`)]'
```

## Support and Contributions

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review CloudWatch logs for specific error messages
3. Consult AWS documentation for service-specific issues
4. Submit issues to the project repository

## License

This infrastructure code is provided as part of the AWS recipes collection and follows the same licensing terms as the parent project.