# Infrastructure as Code for Optimizing Personalized Recommendations with A/B Testing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Optimizing Personalized Recommendations with A/B Testing".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Personalize (full access)
  - Lambda functions
  - API Gateway
  - DynamoDB
  - IAM roles and policies
  - S3 buckets
- Sample user interaction data (minimum 1,000 users, 1,000 items, 25,000 interactions)
- Understanding of recommendation systems and A/B testing concepts

## Architecture Overview

This implementation creates a comprehensive real-time recommendation platform featuring:

- **Multiple Personalize Models**: User-personalization, item-to-item similarity, and popularity-based algorithms
- **A/B Testing Framework**: Intelligent traffic splitting with consistent user assignments
- **Real-time APIs**: Sub-100ms recommendation delivery via API Gateway and Lambda
- **Event Tracking**: Comprehensive analytics pipeline for measuring recommendation effectiveness
- **Data Storage**: DynamoDB tables for user profiles, item catalogs, and real-time events
- **Fallback Systems**: Reliability mechanisms for high-availability operations

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name personalize-ab-testing-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=personalize-ab-test \
                 ParameterKey=BucketName,ParameterValue=personalize-data-$(date +%s)

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name personalize-ab-testing-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name personalize-ab-testing-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy PersonalizeAbTestingStack

# View outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy PersonalizeAbTestingStack

# View outputs
cdk output
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

# The script will:
# - Create S3 bucket for training data
# - Set up IAM roles and policies
# - Create DynamoDB tables
# - Deploy Lambda functions
# - Configure API Gateway
# - Load sample data
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to complete the Personalize setup:

### 1. Create Personalize Dataset Group

```bash
# Get the deployed Lambda function name
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name personalize-ab-testing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`PersonalizeManagerFunction`].OutputValue' \
    --output text)

# Create dataset group
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{
        "action": "create_dataset_group",
        "dataset_group_name": "personalize-ab-test-dataset-group"
    }' \
    response.json

cat response.json
```

### 2. Import Training Data

The deployment automatically uploads sample data to S3. Import this data into Personalize:

```bash
# Import interactions dataset
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{
        "action": "import_data",
        "dataset_arn": "YOUR_DATASET_ARN",
        "job_name": "interactions-import-job",
        "s3_data_source": "s3://YOUR_BUCKET/training-data/interactions.csv",
        "role_arn": "YOUR_PERSONALIZE_ROLE_ARN"
    }' \
    response.json
```

### 3. Train Models and Create Campaigns

```bash
# Create solutions for each algorithm
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{
        "action": "create_solution",
        "solution_name": "user-personalization-solution",
        "dataset_group_arn": "YOUR_DATASET_GROUP_ARN",
        "recipe_arn": "arn:aws:personalize:::recipe/aws-user-personalization"
    }' \
    response.json

# Monitor training progress and create campaigns once solutions are active
```

## Testing the Deployment

### 1. Test A/B Assignment

```bash
# Get API endpoint from stack outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name personalize-ab-testing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Test A/B test assignment
curl -X POST ${API_ENDPOINT}/recommendations \
    -H "Content-Type: application/json" \
    -d '{"user_id": "user_00001", "num_results": 5}'
```

### 2. Test Event Tracking

```bash
# Track user interaction
curl -X POST ${API_ENDPOINT}/events \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": "user_00001",
        "event_type": "view",
        "item_id": "item_00001",
        "session_id": "session_123"
    }'
```

### 3. Verify Data Storage

```bash
# Check A/B test assignments
aws dynamodb scan \
    --table-name personalize-ab-test-ab-assignments \
    --limit 5

# Check tracked events
aws dynamodb scan \
    --table-name personalize-ab-test-events \
    --limit 5
```

## Customization

### Environment Variables

Each implementation supports customization through variables:

- **ProjectName**: Prefix for all resources (default: "personalize-ab-test")
- **AWS Region**: Deployment region
- **DynamoDB Capacity**: Read/write capacity units for tables
- **Lambda Memory**: Memory allocation for Lambda functions
- **API Gateway Settings**: Throttling and caching configuration

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
project_name = "my-personalize-project"
aws_region   = "us-west-2"
environment  = "production"

dynamodb_read_capacity  = 10
dynamodb_write_capacity = 5

lambda_memory_size = 256
lambda_timeout     = 30
```

### CDK Customization

Modify the CDK app files to adjust:

- Resource configurations
- IAM permissions
- Monitoring and alerting
- Cost optimization settings

## Monitoring and Analytics

### CloudWatch Metrics

The deployment includes CloudWatch monitoring for:

- Lambda function performance
- API Gateway request metrics
- DynamoDB performance
- Error rates and latency

### A/B Test Analytics

Query DynamoDB to analyze A/B test performance:

```bash
# Get assignment distribution
aws dynamodb scan \
    --table-name personalize-ab-test-ab-assignments \
    --select COUNT \
    --filter-expression "attribute_exists(Variant)"

# Analyze event patterns
aws dynamodb scan \
    --table-name personalize-ab-test-events \
    --filter-expression "EventType = :event_type" \
    --expression-attribute-values '{":event_type":{"S":"purchase"}}'
```

## Cost Optimization

### Estimated Costs

- **Personalize Training**: $300-500 for multiple models
- **Real-time Campaigns**: $0.20 per TPS hour
- **Lambda**: Pay-per-request (typically under $50/month)
- **DynamoDB**: Based on read/write capacity
- **API Gateway**: $3.50 per million requests

### Cost Management

1. **Use Personalize Batch Inference** for bulk recommendations
2. **Implement caching** with ElastiCache for frequently requested recommendations
3. **Optimize DynamoDB capacity** based on actual usage patterns
4. **Monitor Lambda duration** and optimize memory allocation

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name personalize-ab-testing-stack

# Monitor deletion progress
aws cloudformation wait stack-delete-complete \
    --stack-name personalize-ab-testing-stack
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy PersonalizeAbTestingStack
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

# The script will:
# - Delete Personalize campaigns and solutions
# - Remove Lambda functions
# - Delete DynamoDB tables
# - Clean up S3 bucket
# - Remove IAM roles and policies
```

## Troubleshooting

### Common Issues

1. **Personalize Training Fails**
   - Verify training data format and minimum requirements
   - Check IAM permissions for Personalize service role
   - Ensure S3 bucket is in the same region

2. **Lambda Timeout Errors**
   - Increase timeout value in function configuration
   - Optimize code for better performance
   - Check DynamoDB capacity and throttling

3. **API Gateway 5xx Errors**
   - Check Lambda function logs in CloudWatch
   - Verify Lambda permissions for API Gateway
   - Review IAM role configurations

4. **A/B Test Assignment Issues**
   - Verify DynamoDB table permissions
   - Check consistent hashing implementation
   - Review user ID format requirements

### Debug Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/personalize-ab-test

# View recent Lambda errors
aws logs filter-log-events \
    --log-group-name /aws/lambda/personalize-ab-test-ab-test-router \
    --filter-pattern "ERROR"

# Check API Gateway access logs
aws logs filter-log-events \
    --log-group-name API-Gateway-Execution-Logs
```

## Security Considerations

### IAM Best Practices

- Least privilege access for all roles
- Separate roles for different service components
- Regular review and rotation of credentials

### Data Protection

- Encryption at rest for DynamoDB tables
- Encryption in transit for API communications
- Secure handling of user interaction data

### Network Security

- VPC deployment options available
- API Gateway with AWS WAF integration
- Private subnets for sensitive components

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation
3. Verify IAM permissions and resource limits
4. Monitor CloudWatch logs for detailed error messages

## Advanced Features

### Multi-Region Deployment

Extend the infrastructure for multi-region deployments:

- Cross-region DynamoDB replication
- Route 53 health checks and failover
- Regional Personalize campaigns

### Enhanced Analytics

Integrate with additional AWS analytics services:

- Amazon Kinesis for real-time streaming
- Amazon QuickSight for business intelligence
- Amazon Elasticsearch for log analytics

### ML Pipeline Automation

Implement automated model retraining:

- Step Functions for orchestration
- EventBridge for scheduled triggers
- Automated A/B test result analysis

---

**Note**: This infrastructure implements a production-ready recommendation system with comprehensive A/B testing capabilities. Monitor costs carefully during initial deployment and testing phases.