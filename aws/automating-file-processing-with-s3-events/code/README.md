# Infrastructure as Code for Automating File Processing with S3 Event Notifications

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automating File Processing with S3 Event Notifications".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys an event-driven file processing architecture using:
- S3 bucket with intelligent event routing
- SNS topic for fan-out notifications
- SQS queue for batch processing
- Lambda function for immediate processing
- CloudWatch Logs for monitoring
- IAM roles and policies for secure access

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for S3, Lambda, SNS, SQS, IAM, and CloudWatch
- For CDK: Node.js 16+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+

### Required AWS Permissions

Your AWS user/role needs permissions for:
- S3 bucket creation and configuration
- Lambda function creation and management
- SNS topic creation and configuration
- SQS queue creation and configuration
- IAM role and policy management
- CloudWatch Logs management

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name s3-event-processing-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketNamePrefix,ParameterValue=my-org \
    --capabilities CAPABILITY_IAM

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name s3-event-processing-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Deploy infrastructure
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

# Check deployment status
aws s3 ls | grep file-processing-demo
```

## Testing the Deployment

After deployment, test the event-driven processing:

1. **Test SNS notifications** (uploads/ prefix):
   ```bash
   echo "Test file for SNS" > test-sns.txt
   aws s3 cp test-sns.txt s3://[bucket-name]/uploads/test-sns.txt
   # Check email for notification
   ```

2. **Test SQS batch processing** (batch/ prefix):
   ```bash
   echo "Test file for SQS" > test-sqs.txt
   aws s3 cp test-sqs.txt s3://[bucket-name]/batch/test-sqs.txt
   
   # Check SQS queue for messages
   aws sqs receive-message --queue-url [queue-url]
   ```

3. **Test Lambda immediate processing** (immediate/ prefix):
   ```bash
   echo "Test file for Lambda" > test-lambda.txt
   aws s3 cp test-lambda.txt s3://[bucket-name]/immediate/test-lambda.txt
   
   # Check Lambda logs
   aws logs describe-log-streams \
       --log-group-name /aws/lambda/[function-name] \
       --order-by LastEventTime --descending
   ```

## Customization

### Key Parameters

Each implementation supports customization through parameters/variables:

- **BucketNamePrefix**: Prefix for the S3 bucket name (generates unique bucket)
- **NotificationEmail**: Email address for SNS notifications
- **LambdaTimeout**: Lambda function timeout in seconds (default: 30)
- **LambdaMemorySize**: Lambda function memory allocation in MB (default: 128)
- **Environment**: Deployment environment (dev/staging/prod)

### CloudFormation Parameters
```bash
aws cloudformation create-stack \
    --parameters \
    ParameterKey=BucketNamePrefix,ParameterValue=mycompany \
    ParameterKey=NotificationEmail,ParameterValue=admin@mycompany.com \
    ParameterKey=Environment,ParameterValue=production
```

### Terraform Variables
Create a `terraform.tfvars` file:
```hcl
bucket_name_prefix  = "mycompany"
notification_email  = "admin@mycompany.com"
environment        = "production"
lambda_timeout     = 60
lambda_memory_size = 256
```

### CDK Context
```bash
# TypeScript/Python
cdk deploy --context bucketNamePrefix=mycompany \
           --context notificationEmail=admin@mycompany.com \
           --context environment=production
```

## Monitoring and Troubleshooting

### CloudWatch Logs
Monitor Lambda function execution:
```bash
# View recent log events
aws logs filter-log-events \
    --log-group-name /aws/lambda/[function-name] \
    --start-time $(date -d '1 hour ago' +%s)000
```

### SQS Queue Monitoring
```bash
# Check queue attributes
aws sqs get-queue-attributes \
    --queue-url [queue-url] \
    --attribute-names All
```

### SNS Topic Monitoring
```bash
# List topic subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn [topic-arn]
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name s3-event-processing-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name s3-event-processing-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletions when prompted
```

## Cost Considerations

This implementation uses several AWS services with associated costs:

- **S3**: Storage costs + request costs for event notifications
- **Lambda**: Invocation costs + compute duration costs
- **SNS**: Message publishing costs + delivery costs
- **SQS**: Message requests + data transfer
- **CloudWatch Logs**: Log ingestion and storage costs

### Cost Optimization Tips

1. **Set S3 lifecycle policies** to transition files to cheaper storage classes
2. **Configure Lambda memory allocation** based on actual usage patterns
3. **Use SQS batch processing** to reduce individual message costs
4. **Set CloudWatch Logs retention periods** to control log storage costs
5. **Monitor usage with AWS Cost Explorer** and set up billing alerts

## Security Considerations

### Implemented Security Features

- **Least privilege IAM policies** for all services
- **Resource-based policies** restricting cross-service access
- **Source ARN conditions** preventing unauthorized access
- **Encrypted CloudWatch Logs** (when supported by region)

### Additional Security Recommendations

1. **Enable S3 bucket encryption** for data at rest
2. **Use VPC endpoints** for private communication between services
3. **Enable AWS CloudTrail** for API call auditing
4. **Implement S3 bucket notifications** for security monitoring
5. **Use AWS Secrets Manager** for sensitive configuration data

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   - Verify IAM policies allow required actions
   - Check resource-based policies are correctly configured
   - Ensure cross-service permissions are properly set

2. **Events Not Triggering**
   - Verify S3 event notification configuration
   - Check prefix/suffix filters match uploaded file paths
   - Confirm destination services are accessible

3. **Lambda Function Timeouts**
   - Increase function timeout if processing takes longer
   - Optimize function code for better performance
   - Consider using SQS for longer-running tasks

4. **SQS Messages Not Processing**
   - Check queue visibility timeout settings
   - Verify message retention periods
   - Monitor dead letter queue for failed messages

### Debug Commands

```bash
# Check S3 event configuration
aws s3api get-bucket-notification-configuration \
    --bucket [bucket-name]

# Test Lambda function directly
aws lambda invoke \
    --function-name [function-name] \
    --payload file://test-event.json \
    response.json

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=[function-name] \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for architecture details
2. Check AWS service documentation for current best practices
3. Consult provider-specific troubleshooting guides
4. Review CloudWatch Logs for detailed error information

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Compatible AWS CLI**: v2.x
- **Compatible CDK**: v2.x
- **Compatible Terraform**: 1.0+