# Infrastructure as Code for Scalable Webhook Processing with SQS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable Webhook Processing with SQS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates a robust webhook processing system that includes:

- **API Gateway**: REST API endpoint for webhook ingestion
- **SQS**: Primary message queue and dead letter queue for reliability
- **Lambda**: Serverless function for processing webhook payloads
- **DynamoDB**: Storage for webhook history and audit trails
- **CloudWatch**: Monitoring and alerting for system health
- **IAM**: Roles and policies for secure service integration

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating API Gateway, SQS, Lambda, DynamoDB, IAM, and CloudWatch resources
- For CDK implementations: Node.js 18+ and AWS CDK v2
- For Terraform: Terraform v1.0+
- Estimated cost: $5-15/month for development and testing

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name webhook-processing-system \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=webhook-demo

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name webhook-processing-system \
    --query 'Stacks[0].StackStatus'

# Get webhook endpoint URL
aws cloudformation describe-stacks \
    --stack-name webhook-processing-system \
    --query 'Stacks[0].Outputs[?OutputKey==`WebhookEndpointUrl`].OutputValue' \
    --output text
```

### Using CDK TypeScript
```bash
# Install dependencies
cd cdk-typescript/
npm install

# Deploy the stack
cdk deploy

# Get webhook endpoint URL
cdk ls --long
```

### Using CDK Python
```bash
# Set up virtual environment
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# Get webhook endpoint URL
cdk ls --long
```

### Using Terraform
```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# Get webhook endpoint URL
terraform output webhook_endpoint_url
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the webhook endpoint URL
```

## Testing Your Deployment

After deployment, test the webhook endpoint:

```bash
# Replace with your actual endpoint URL
WEBHOOK_URL="https://your-api-id.execute-api.region.amazonaws.com/prod/webhooks"

# Send test webhook
curl -X POST $WEBHOOK_URL \
    -H "Content-Type: application/json" \
    -d '{
        "type": "payment.completed",
        "transaction_id": "txn_123456",
        "amount": 99.99,
        "currency": "USD",
        "customer_id": "cust_789"
    }'
```

Expected response:
```json
{
    "message": "Webhook received and queued for processing",
    "requestId": "request-id-here"
}
```

## Monitoring and Validation

### Check SQS Queue Status
```bash
# Get queue URL (replace with your queue name)
QUEUE_URL=$(aws sqs get-queue-url --queue-name webhook-processing-queue-* --query QueueUrl --output text)

# Check queue attributes
aws sqs get-queue-attributes \
    --queue-url $QUEUE_URL \
    --attribute-names ApproximateNumberOfMessages
```

### Check DynamoDB Records
```bash
# List webhook processing records
aws dynamodb scan \
    --table-name webhook-history-* \
    --limit 5 \
    --query 'Items[*].[webhook_id.S,timestamp.S,webhook_type.S,status.S]' \
    --output table
```

### Monitor Lambda Function
```bash
# Check Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/webhook-processor

# View recent logs
aws logs tail /aws/lambda/webhook-processor-* --follow
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name webhook-processing-system

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name webhook-processing-system \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
# Destroy infrastructure
cd terraform/
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Configuration Options

### Environment Variables
Set these environment variables to customize the deployment:

```bash
export AWS_REGION=us-east-1                    # AWS region
export PROJECT_NAME=webhook-demo               # Project identifier
export WEBHOOK_QUEUE_NAME=custom-queue         # Custom queue name
export WEBHOOK_TABLE_NAME=custom-table         # Custom table name
export LAMBDA_MEMORY_SIZE=256                  # Lambda memory (MB)
export LAMBDA_TIMEOUT=30                       # Lambda timeout (seconds)
```

### CloudFormation Parameters
```yaml
Parameters:
  ProjectName:
    Type: String
    Default: webhook-processing
    Description: Project name for resource naming
  
  LambdaMemorySize:
    Type: Number
    Default: 256
    Description: Lambda function memory size in MB
  
  LambdaTimeout:
    Type: Number
    Default: 30
    Description: Lambda function timeout in seconds
```

### Terraform Variables
```bash
# Create terraform.tfvars file
cat > terraform/terraform.tfvars << EOF
project_name = "webhook-demo"
lambda_memory_size = 256
lambda_timeout = 30
queue_visibility_timeout = 300
dlq_max_receive_count = 3
EOF
```

## Security Considerations

This implementation includes several security best practices:

- **IAM Roles**: Least privilege access for all services
- **API Gateway**: Regional endpoints with throttling
- **SQS**: Message encryption in transit and at rest
- **Lambda**: VPC isolation (optional, configure in variables)
- **DynamoDB**: Encryption at rest enabled
- **CloudWatch**: Comprehensive logging and monitoring

### Additional Security Enhancements
Consider implementing these additional security measures:

1. **API Authentication**: Add API keys or OAuth to API Gateway
2. **Webhook Signature Verification**: Validate webhook signatures in Lambda
3. **VPC Endpoints**: Use VPC endpoints for private API communication
4. **WAF Integration**: Add Web Application Firewall for API Gateway
5. **Secrets Manager**: Store sensitive configuration in AWS Secrets Manager

## Troubleshooting

### Common Issues

1. **Webhook Not Processing**
   - Check SQS queue has messages
   - Verify Lambda function has proper permissions
   - Check CloudWatch logs for errors

2. **API Gateway 403 Errors**
   - Verify IAM role has SQS permissions
   - Check API Gateway resource policies
   - Ensure proper integration configuration

3. **Lambda Function Errors**
   - Check function logs in CloudWatch
   - Verify environment variables are set
   - Check DynamoDB table permissions

4. **High Costs**
   - Monitor API Gateway request volume
   - Check Lambda invocation frequency
   - Review DynamoDB read/write capacity

### Debug Commands

```bash
# Check API Gateway logs
aws logs describe-log-groups --log-group-name-prefix API-Gateway-Execution-Logs

# Check Lambda function configuration
aws lambda get-function --function-name webhook-processor-*

# Check SQS queue attributes
aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names All

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=webhook-processor-* \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Customization

### Extending the Lambda Function
The Lambda function can be customized for your specific webhook processing needs:

```python
def process_webhook(payload):
    """
    Customize this function based on your webhook processing needs
    """
    # Add your specific processing logic here
    # Examples:
    # - Validate webhook signatures
    # - Transform data formats
    # - Integrate with external APIs
    # - Implement business logic
    
    processed = {
        'processed_at': datetime.utcnow().isoformat(),
        'payload_size': len(json.dumps(payload)),
        'custom_field': 'your_custom_logic_here'
    }
    
    return processed
```

### Adding Additional Queues
To process different webhook types with separate queues:

1. Create additional SQS queues in your IaC
2. Modify API Gateway to route based on webhook type
3. Create specialized Lambda functions for each webhook type

### Implementing Dead Letter Queue Processing
Add a separate Lambda function to process failed messages:

```python
def dlq_handler(event, context):
    """
    Process messages from dead letter queue
    """
    for record in event['Records']:
        # Log failed message details
        # Send alerts to operations team
        # Attempt manual processing
        # Store in long-term failure audit table
        pass
```

## Performance Optimization

### Lambda Optimization
- Use provisioned concurrency for consistent performance
- Optimize memory allocation based on processing requirements
- Implement connection pooling for DynamoDB and external APIs

### SQS Optimization
- Tune batch size and visibility timeout
- Use SQS FIFO queues for ordered processing
- Implement message deduplication for critical webhooks

### DynamoDB Optimization
- Use appropriate partition keys for even distribution
- Implement time-based partitioning for high-volume scenarios
- Consider DynamoDB on-demand for variable workloads

## Cost Optimization

### Monitoring Costs
- Use AWS Cost Explorer to track resource costs
- Set up billing alerts for unexpected charges
- Monitor API Gateway request volumes

### Cost Reduction Strategies
- Use Lambda provisioned concurrency only when needed
- Implement intelligent batching for DynamoDB writes
- Use S3 for long-term webhook archive storage
- Consider reserved capacity for predictable workloads

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for detailed implementation guidance
2. **AWS Documentation**: Check AWS service documentation for specific configuration issues
3. **Community Support**: Use AWS forums and Stack Overflow for community help
4. **AWS Support**: Contact AWS Support for production issues

## Contributing

To contribute improvements to this IaC:

1. Test changes thoroughly in a development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any configuration changes
4. Ensure all IaC implementations remain synchronized