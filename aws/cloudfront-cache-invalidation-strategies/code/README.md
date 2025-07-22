# Infrastructure as Code for CloudFront Cache Invalidation Strategies

This directory contains Infrastructure as Code (IaC) implementations for the recipe "CloudFront Cache Invalidation Strategies".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an intelligent CloudFront cache invalidation system that:

- Automatically detects content changes through EventBridge
- Processes invalidation requests with Lambda functions
- Optimizes costs through intelligent batch processing
- Provides comprehensive monitoring with CloudWatch
- Logs all invalidation activities in DynamoDB

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - CloudFront distributions and invalidations
  - Lambda functions and IAM roles
  - EventBridge custom buses and rules
  - S3 buckets and event notifications
  - DynamoDB tables and streams
  - SQS queues and dead letter queues
  - CloudWatch dashboards and alarms
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)
- Estimated cost: $20-50/month for testing environment

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name cloudfront-invalidation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=cf-invalidation-demo

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name cloudfront-invalidation-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name cloudfront-invalidation-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --all

# Get stack outputs
cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --all

# Get stack outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and wait for completion
# The script will output important resource information
```

## Post-Deployment Testing

After deployment, test the invalidation system:

1. **Verify CloudFront Distribution**:
   ```bash
   # Get distribution domain from outputs
   DISTRIBUTION_DOMAIN=$(aws cloudformation describe-stacks \
       --stack-name cloudfront-invalidation-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`DistributionDomain`].OutputValue' \
       --output text)
   
   # Test initial content access
   curl -I https://${DISTRIBUTION_DOMAIN}/
   ```

2. **Test Automated Invalidation**:
   ```bash
   # Update content in S3 to trigger invalidation
   S3_BUCKET=$(aws cloudformation describe-stacks \
       --stack-name cloudfront-invalidation-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
       --output text)
   
   echo '<html><body><h1>Updated Content</h1></body></html>' > /tmp/test.html
   aws s3 cp /tmp/test.html s3://${S3_BUCKET}/index.html
   ```

3. **Monitor Invalidation Logs**:
   ```bash
   # Check DynamoDB for invalidation records
   DDB_TABLE=$(aws cloudformation describe-stacks \
       --stack-name cloudfront-invalidation-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`DynamoDBTableName`].OutputValue' \
       --output text)
   
   aws dynamodb scan --table-name ${DDB_TABLE} --limit 5
   ```

## Monitoring and Observability

The solution includes comprehensive monitoring:

- **CloudWatch Dashboard**: Real-time metrics for CloudFront performance, Lambda function execution, and event processing
- **CloudWatch Alarms**: Automated alerts for high invalidation costs, function failures, or performance degradation
- **DynamoDB Logging**: Complete audit trail of all invalidation activities with cost tracking
- **Lambda Logs**: Detailed execution logs for troubleshooting and optimization

Access the CloudWatch dashboard through the AWS Console or use the dashboard URL from the stack outputs.

## Cost Optimization Features

The solution implements several cost optimization strategies:

- **Batch Processing**: Groups multiple invalidation requests to reduce API calls
- **Intelligent Path Optimization**: Eliminates redundant invalidations and uses wildcards when beneficial
- **Dead Letter Queue**: Prevents failed invalidations from causing repeated charges
- **Smart Filtering**: Only invalidates content that actually changed based on file types and dependencies

## Customization

### Environment Variables

Each implementation supports customization through variables:

- `ProjectName`: Prefix for all resource names
- `S3BucketName`: Name for the origin content bucket
- `NotificationEmail`: Email address for CloudWatch alarms
- `Environment`: Deployment environment (dev, staging, prod)

### Content Types

The Lambda function includes intelligent invalidation logic for different content types:

- **HTML Files**: Invalidates specific file and directory index
- **CSS/JS Files**: Invalidates asset and dependent HTML pages
- **Images**: Invalidates specific image paths
- **API Content**: Invalidates API endpoints and JSON responses

Modify the Lambda function code to add custom invalidation logic for your specific content types.

### Cache Behaviors

The CloudFront distribution includes optimized cache behaviors:

- **Default Behavior**: Standard caching for HTML content
- **API Content**: Shorter TTL for dynamic content
- **Static Assets**: Longer TTL for CSS, JS, and images

Adjust cache behaviors in the IaC templates to match your content strategy.

## Security Considerations

The solution implements security best practices:

- **Origin Access Control**: Secure S3 access without public bucket permissions
- **IAM Least Privilege**: Minimal permissions for all service roles
- **Encryption**: Encrypted storage for DynamoDB and S3 content
- **VPC Endpoints**: Private network access where applicable

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name cloudfront-invalidation-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name cloudfront-invalidation-stack
```

### Using CDK

```bash
# Destroy all stacks
cdk destroy --all

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **CloudFront Distribution Deployment**: 
   - CloudFront distributions take 15-20 minutes to deploy
   - Wait for `aws cloudfront wait distribution-deployed` to complete

2. **Lambda Function Timeouts**:
   - Check CloudWatch logs for execution details
   - Verify IAM permissions for CloudFront and DynamoDB access

3. **S3 Event Notifications**:
   - Ensure EventBridge configuration is enabled on the S3 bucket
   - Verify EventBridge rules are targeting the correct Lambda function

4. **High Invalidation Costs**:
   - Review DynamoDB logs for invalidation patterns
   - Adjust batch processing settings in Lambda function
   - Consider increasing cache TTL for frequently changing content

### Debug Commands

```bash
# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/[FUNCTION_NAME] \
    --start-time $(date -d '1 hour ago' '+%s')000

# Verify EventBridge rule targets
aws events list-targets-by-rule \
    --rule [RULE_NAME] \
    --event-bus-name [EVENT_BUS_NAME]

# Check SQS queue messages
aws sqs receive-message \
    --queue-url [QUEUE_URL] \
    --max-number-of-messages 10
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for architectural details
2. Check AWS CloudFormation/CDK documentation for resource-specific issues
3. Consult AWS support for service-specific problems
4. Review CloudWatch logs for runtime issues

## Advanced Configuration

### Multi-Environment Deployment

Deploy to multiple environments using parameter overrides:

```bash
# Development environment
aws cloudformation create-stack \
    --stack-name cloudfront-invalidation-dev \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=dev \
                ParameterKey=ProjectName,ParameterValue=cf-invalidation-dev

# Production environment
aws cloudformation create-stack \
    --stack-name cloudfront-invalidation-prod \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=prod \
                ParameterKey=ProjectName,ParameterValue=cf-invalidation-prod
```

### Custom Invalidation Logic

Extend the Lambda function to support custom invalidation patterns:

1. Modify the `processS3Event` function for new content types
2. Add custom event sources to EventBridge rules
3. Implement environment-specific invalidation strategies
4. Add integration with CI/CD pipelines for deployment-triggered invalidations

### Performance Optimization

Monitor and optimize the solution:

- Review CloudWatch metrics for cache hit rates
- Analyze DynamoDB logs for invalidation patterns
- Adjust Lambda function memory and timeout settings
- Optimize EventBridge rule filters for better performance

## Version History

- **1.0**: Initial implementation with basic invalidation logic
- **1.1**: Added batch processing and cost optimization
- **1.2**: Enhanced monitoring and intelligent path optimization
- **1.3**: Added multi-environment support and advanced customization options