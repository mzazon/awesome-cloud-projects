# Real-Time Recommendations with Personalize and A/B Testing - Terraform Infrastructure

This Terraform configuration deploys a complete real-time recommendation system using Amazon Personalize with sophisticated A/B testing capabilities on AWS.

## Architecture Overview

The infrastructure creates:

- **Amazon Personalize** integration for ML-powered recommendations
- **A/B Testing Framework** with consistent user assignment
- **Real-time API Gateway** endpoints for recommendations and event tracking
- **Lambda Functions** for recommendation serving, A/B testing, and event processing
- **DynamoDB Tables** for user profiles, item catalog, A/B assignments, and events
- **S3 Bucket** for Personalize training data
- **CloudWatch** monitoring and alerting
- **KMS Encryption** for data at rest

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - Personalize (full access)
  - Lambda, API Gateway, DynamoDB
  - S3, IAM, CloudWatch, KMS
- Sample recommendation data (users, items, interactions)

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd aws/real-time-recommendations-personalize-ab-testing/code/terraform/
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Review and Customize Variables** (optional):
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your preferences
   ```

4. **Plan Deployment**:
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

6. **Note Important Outputs**:
   ```bash
   terraform output
   ```

## Configuration Variables

### Core Settings
- `project_name`: Project identifier for resource naming (default: "personalize-ab-test")
- `environment`: Environment name - dev/staging/prod (default: "dev")
- `aws_region`: AWS region for deployment (default: "us-west-2")

### DynamoDB Configuration
- `dynamodb_billing_mode`: Billing mode - PROVISIONED or PAY_PER_REQUEST (default: "PAY_PER_REQUEST")
- `dynamodb_read_capacity`: Read capacity units for provisioned mode (default: 10)
- `dynamodb_write_capacity`: Write capacity units for provisioned mode (default: 5)

### Lambda Configuration
- `lambda_timeout`: Function timeout in seconds (default: 30)
- `lambda_memory_size`: Memory allocation in MB (default: 256)
- `lambda_runtime`: Runtime version (default: "python3.9")

### A/B Testing Configuration
- `ab_test_variants`: Traffic distribution for variants (default: 33%/33%/34%)
- `personalize_recipes`: Recipe configurations for different algorithms

### Security & Monitoring
- `enable_vpc_endpoints`: Enable VPC endpoints for services (default: false)
- `log_retention_days`: CloudWatch log retention period (default: 14)
- `kms_key_deletion_window`: KMS key deletion window in days (default: 7)

## Deployment Steps

### 1. Infrastructure Deployment

```bash
# Initialize and apply Terraform
terraform init
terraform apply -auto-approve

# Get outputs
API_ENDPOINT=$(terraform output -raw recommendations_endpoint)
PROJECT_NAME=$(terraform output -raw project_name_with_suffix)
S3_BUCKET=$(terraform output -raw s3_bucket_name)
```

### 2. Data Preparation

```bash
# Upload training data to S3
aws s3 cp sample-data/ s3://${S3_BUCKET}/training-data/ --recursive

# Load sample data into DynamoDB (use provided Python scripts)
python3 load_sample_data.py
```

### 3. Personalize Model Training

The Personalize models need to be trained before the system can provide recommendations:

```bash
# Use the Personalize Manager Lambda to create resources
aws lambda invoke \
    --function-name ${PROJECT_NAME}-personalize-manager \
    --payload '{
        "action": "create_dataset_group",
        "dataset_group_name": "'${PROJECT_NAME}'-dataset-group",
        "domain": "ECOMMERCE"
    }' \
    response.json

# Continue with dataset creation, data import, solution training, and campaign deployment
# (See detailed Personalize setup guide in the original recipe)
```

### 4. Testing the System

```bash
# Test A/B test assignment
curl -X POST ${API_ENDPOINT} \
    -H "Content-Type: application/json" \
    -d '{"user_id": "test-user-001", "num_results": 5}'

# Test event tracking
EVENTS_ENDPOINT=$(terraform output -raw events_endpoint)
curl -X POST ${EVENTS_ENDPOINT} \
    -H "Content-Type: application/json" \
    -d '{
        "user_id": "test-user-001",
        "event_type": "view",
        "item_id": "test-item-001"
    }'
```

## Key Resources Created

### Lambda Functions
- **A/B Test Router**: Routes users to recommendation variants using consistent hashing
- **Recommendation Engine**: Serves personalized recommendations with metadata enrichment
- **Event Tracker**: Captures user interactions for analytics and model training
- **Personalize Manager**: Manages Personalize resources and workflows

### DynamoDB Tables
- **Users Table**: User profiles and metadata
- **Items Table**: Product catalog with category index
- **A/B Assignments Table**: User variant assignments for consistent testing
- **Events Table**: User interaction events with TTL for automatic cleanup

### API Gateway
- **HTTP API**: Low-latency endpoints for recommendations and event tracking
- **CORS Configuration**: Enabled for web application integration
- **Logging & Monitoring**: Comprehensive access logs and metrics

### Monitoring & Security
- **CloudWatch Dashboard**: Real-time metrics and performance monitoring
- **Metric Alarms**: Automated alerting for Lambda errors and high latency
- **KMS Encryption**: Customer-managed keys for all data at rest
- **IAM Roles**: Least-privilege access for all services

## Cost Optimization

### DynamoDB
- Uses PAY_PER_REQUEST billing by default for cost efficiency
- Implements TTL for automatic data cleanup
- Point-in-time recovery enabled for data protection

### Lambda
- Right-sized memory allocation (256MB default)
- Optimized timeout settings
- CloudWatch log retention limits

### Personalize
- Campaigns use minimum provisioned TPS (1) by default
- Configurable recipe selection for cost vs. accuracy trade-offs

## Security Features

### Data Protection
- All DynamoDB tables encrypted with customer-managed KMS keys
- S3 bucket encryption with KMS
- Public access blocked on S3 bucket

### Access Control
- IAM roles with least-privilege access
- Lambda functions can only access required DynamoDB tables
- API Gateway with CORS configuration

### Monitoring
- CloudWatch logs encrypted with KMS
- Comprehensive metric alarms for error detection
- Access logging for API Gateway

## Troubleshooting

### Common Issues

1. **Lambda Function Errors**:
   ```bash
   # Check CloudWatch logs
   aws logs describe-log-groups --log-group-name-prefix /aws/lambda/${PROJECT_NAME}
   ```

2. **DynamoDB Access Issues**:
   ```bash
   # Verify table permissions
   aws dynamodb describe-table --table-name ${PROJECT_NAME}-users
   ```

3. **API Gateway Issues**:
   ```bash
   # Check API Gateway logs
   aws logs describe-log-groups --log-group-name-prefix /aws/apigateway/${PROJECT_NAME}
   ```

### Performance Tuning

1. **Lambda Memory Allocation**:
   - Monitor CloudWatch metrics for memory usage
   - Adjust `lambda_memory_size` variable if needed

2. **DynamoDB Capacity**:
   - Switch to PROVISIONED mode for predictable workloads
   - Use DynamoDB auto-scaling for variable traffic

3. **API Gateway Throttling**:
   - Configure custom throttling limits
   - Implement caching for frequently requested data

## Cleanup

### Destroy Infrastructure
```bash
# Remove all resources
terraform destroy -auto-approve

# Verify S3 bucket is empty (if force_destroy is false)
aws s3 ls s3://${S3_BUCKET}
```

### Cost Monitoring
```bash
# Check costs using the cost allocation tags
aws ce get-cost-and-usage \
    --time-period Start=2025-01-01,End=2025-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Advanced Configuration

### Custom Personalize Recipes
Edit the `personalize_recipes` variable to include additional or custom recipes:

```hcl
personalize_recipes = [
  {
    name        = "user-personalization"
    recipe_arn  = "arn:aws:personalize:::recipe/aws-user-personalization"
    description = "User-Personalization Algorithm"
  },
  {
    name        = "custom-recipe"
    recipe_arn  = "arn:aws:personalize:us-west-2:123456789012:recipe/my-custom-recipe"
    description = "Custom Algorithm"
  }
]
```

### VPC Integration
Enable VPC endpoints for private communication:

```hcl
enable_vpc_endpoints = true
```

### Enhanced Monitoring
Enable CloudWatch Insights for advanced log analysis:

```hcl
enable_cloudwatch_insights = true
log_retention_days = 30
```

## Support

- Review the original recipe documentation for detailed implementation guidance
- Check AWS Personalize documentation for service-specific configurations
- Monitor CloudWatch dashboards and alarms for system health

## License

This infrastructure code is provided as part of the AWS recipe collection. See individual service documentation for licensing terms.