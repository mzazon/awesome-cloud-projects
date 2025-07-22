# Infrastructure as Code for Automated Processing with S3 Event Triggers

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Processing with S3 Event Triggers".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an event-driven data processing pipeline that automatically processes files uploaded to S3 using:

- **S3 Bucket** with event notifications for data landing
- **Lambda Functions** for data processing and error handling
- **SQS Dead Letter Queue** for failed message handling
- **SNS Topic** for operational alerts
- **CloudWatch Alarms** for monitoring and alerting
- **IAM Roles** with least privilege permissions

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - S3 (bucket creation and configuration)
  - Lambda (function creation and invocation)
  - IAM (role and policy management)
  - SQS (queue creation and management)
  - SNS (topic creation and subscription)
  - CloudWatch (alarm creation and log access)
- For CDK: Node.js 18+ (TypeScript) or Python 3.9+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $0.25-2.00 per month for light usage

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name event-driven-data-processing \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name event-driven-data-processing \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
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
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required inputs like email address
```

## Testing the Solution

After deployment, test the event-driven processing:

1. **Upload a test file to trigger processing**:
   ```bash
   # Create test data
   echo "name,age,city" > test-data.csv
   echo "John,30,New York" >> test-data.csv
   
   # Get bucket name from stack outputs
   BUCKET_NAME=$(aws cloudformation describe-stacks \
       --stack-name event-driven-data-processing \
       --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
       --output text)
   
   # Upload file to trigger processing
   aws s3 cp test-data.csv s3://$BUCKET_NAME/data/test-data.csv
   ```

2. **Verify processing occurred**:
   ```bash
   # Check Lambda logs
   aws logs filter-log-events \
       --log-group-name /aws/lambda/data-processor-function \
       --start-time $(date -d '5 minutes ago' +%s)000
   
   # Check for processing reports
   aws s3 ls s3://$BUCKET_NAME/reports/
   ```

3. **Test error handling**:
   ```bash
   # Upload an invalid file to test error handling
   echo "invalid content" > invalid-test.txt
   aws s3 cp invalid-test.txt s3://$BUCKET_NAME/data/invalid-test.txt
   
   # Check Dead Letter Queue for messages
   sleep 15
   aws sqs get-queue-attributes \
       --queue-url $(aws cloudformation describe-stacks \
           --stack-name event-driven-data-processing \
           --query 'Stacks[0].Outputs[?OutputKey==`DLQUrl`].OutputValue' \
           --output text) \
       --attribute-names ApproximateNumberOfMessages
   ```

## Monitoring and Alerting

The solution includes comprehensive monitoring:

- **CloudWatch Alarms** for Lambda function errors and DLQ message accumulation
- **SNS Notifications** for operational alerts
- **Lambda Function Logs** in CloudWatch for debugging
- **Processing Reports** stored in S3 for audit trails

Access monitoring dashboards:
```bash
# View CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names "DataProcessorErrors" "DLQMessageCount"

# View recent Lambda invocations
aws lambda get-function \
    --function-name data-processor-function
```

## Customization

### Key Parameters

Each implementation supports customization through parameters:

- **BucketName**: Name for the S3 bucket (auto-generated if not specified)
- **NotificationEmail**: Email address for SNS notifications
- **ProcessingTimeout**: Lambda function timeout (default: 300 seconds)
- **MemorySize**: Lambda function memory allocation (default: 512 MB)
- **Environment**: Environment tag for resources (default: dev)

### CloudFormation Parameters

Customize deployment by modifying parameter values:
```bash
aws cloudformation create-stack \
    --stack-name event-driven-data-processing \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=NotificationEmail,ParameterValue=ops-team@company.com \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=ProcessingTimeout,ParameterValue=600
```

### CDK Context

For CDK implementations, customize through context variables:
```bash
# CDK TypeScript
cdk deploy -c notificationEmail=ops-team@company.com -c environment=production

# CDK Python
cdk deploy -c notificationEmail=ops-team@company.com -c environment=production
```

### Terraform Variables

Customize Terraform deployment:
```bash
# Create terraform.tfvars
cat > terraform.tfvars << EOF
notification_email = "ops-team@company.com"
environment = "production"
processing_timeout = 600
memory_size = 1024
EOF

terraform apply -var-file=terraform.tfvars
```

## File Processing Logic

The Lambda function includes basic processing logic for CSV and JSON files. To customize processing:

1. **Modify the Lambda function code** in your chosen IaC template
2. **Add new file type handlers** by extending the processing logic
3. **Implement custom validation** for your data formats
4. **Add external service integrations** (databases, APIs, etc.)

Example processing customization:
```python
def process_csv_file(bucket, key, file_size):
    """Custom CSV processing logic"""
    # Download file from S3
    obj = s3.get_object(Bucket=bucket, Key=key)
    data = obj['Body'].read().decode('utf-8')
    
    # Process CSV data
    import csv
    from io import StringIO
    
    csv_data = csv.DictReader(StringIO(data))
    processed_records = []
    
    for row in csv_data:
        # Add your processing logic here
        processed_row = transform_row(row)
        processed_records.append(processed_row)
    
    # Store processed results
    store_processed_data(bucket, key, processed_records)
```

## Security Considerations

The infrastructure implements security best practices:

- **IAM Roles** with least privilege access
- **Resource-based policies** for service-to-service communication
- **VPC endpoints** for private service communication (optional)
- **Encryption at rest** for S3 objects
- **Secure parameter handling** for sensitive configuration

## Scaling Considerations

For high-volume processing scenarios:

- **Increase Lambda memory** and timeout for larger files
- **Enable provisioned concurrency** for consistent performance
- **Implement batch processing** for multiple small files
- **Use Step Functions** for complex workflow orchestration
- **Consider SQS FIFO queues** for ordered processing requirements

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name event-driven-data-processing

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name event-driven-data-processing \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **Lambda function not triggered**:
   - Verify S3 event notification configuration
   - Check Lambda function permissions
   - Confirm file uploaded to correct prefix (`data/`)

2. **Processing errors**:
   - Check CloudWatch logs for Lambda function
   - Verify IAM permissions for S3 access
   - Review DLQ messages for failed events

3. **SNS notifications not received**:
   - Confirm email subscription to SNS topic
   - Check spam/junk folder
   - Verify CloudWatch alarm configuration

### Debug Commands

```bash
# Check Lambda function configuration
aws lambda get-function \
    --function-name data-processor-function

# View recent CloudWatch logs
aws logs tail /aws/lambda/data-processor-function --follow

# Check S3 event notification configuration
aws s3api get-bucket-notification-configuration \
    --bucket $BUCKET_NAME

# Test SNS topic
aws sns publish \
    --topic-arn $SNS_TOPIC_ARN \
    --message "Test notification"
```

## Cost Optimization

To minimize costs:

- **Use S3 Intelligent Tiering** for automatic cost optimization
- **Set Lambda memory** to minimum required for your workload
- **Configure CloudWatch log retention** to avoid excessive storage costs
- **Use S3 lifecycle policies** to transition old data to cheaper storage classes
- **Monitor CloudWatch metrics** to identify optimization opportunities

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS service documentation for specific resource types
3. Review CloudWatch logs for runtime errors
4. Validate IAM permissions for service access

## Related Resources

- [AWS S3 Event Notifications Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)