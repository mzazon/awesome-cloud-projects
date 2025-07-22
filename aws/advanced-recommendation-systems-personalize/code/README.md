# Infrastructure as Code for Building Advanced Recommendation Systems with Amazon Personalize

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Advanced Recommendation Systems with Amazon Personalize".

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
  - S3 (create buckets, read/write objects)
  - Lambda (create functions, manage roles)
  - EventBridge (create rules and targets)
  - CloudWatch (put metrics)
  - IAM (create roles and policies)
- Historical user interaction data (minimum 1,000 interactions from 25 users across 100 items)
- Estimated cost: $200-500/month for comprehensive implementation

### Tool-Specific Prerequisites

#### CloudFormation
- No additional tools required

#### CDK TypeScript
- Node.js 14.x or later
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.7 or later
- AWS CDK CLI (`pip install aws-cdk-lib`)

#### Terraform
- Terraform 1.0 or later
- AWS Provider 4.0 or later

## Quick Start

### Using CloudFormation
```bash
# Create stack with sample data generation
aws cloudformation create-stack \
    --stack-name personalize-recommendation-system \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketName,ParameterValue=my-personalize-bucket-$(date +%s) \
                 ParameterKey=DatasetGroupName,ParameterValue=ecommerce-recommendations \
    --capabilities CAPABILITY_IAM
    
# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name personalize-recommendation-system
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy PersonalizeRecommendationStack

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy PersonalizeRecommendationStack

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="bucket_name=my-personalize-bucket-$(date +%s)"

# Apply configuration
terraform apply -var="bucket_name=my-personalize-bucket-$(date +%s)" -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts and wait for deployment completion
# The script will output important ARNs and endpoints
```

## Architecture Overview

This IaC deploys a comprehensive recommendation system including:

- **Data Layer**: S3 bucket with structured directories for training data, metadata, and batch outputs
- **ML Training Pipeline**: Amazon Personalize dataset groups, schemas, and multiple solution types:
  - User-Personalization (collaborative filtering)
  - Similar-Items (content-based recommendations)
  - Trending-Now (trending content identification)
  - Popularity-Count (popular items for cold-start)
- **Inference Layer**: Real-time campaigns and batch inference capabilities
- **API Layer**: Lambda functions with A/B testing logic and recommendation filters
- **Automation**: EventBridge rules for automated model retraining
- **Monitoring**: CloudWatch metrics for A/B testing and performance tracking

## Configuration Options

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| BucketName | S3 bucket for training data | personalize-data-{timestamp} | No |
| DatasetGroupName | Personalize dataset group name | ecommerce-recommendations | No |
| MinProvisionedTPS | Minimum TPS for campaigns | 2 | No |
| RetrainingSchedule | EventBridge schedule expression | rate(7 days) | No |
| LambdaMemory | Lambda function memory (MB) | 512 | No |
| LambdaTimeout | Lambda function timeout (seconds) | 30 | No |

### Environment-Specific Customization

#### Development Environment
```bash
# Reduced TPS for cost optimization
terraform apply -var="min_provisioned_tps=1" -var="lambda_memory=256"
```

#### Production Environment
```bash
# Higher TPS and memory for performance
terraform apply -var="min_provisioned_tps=5" -var="lambda_memory=1024"
```

## Post-Deployment Steps

After successful deployment:

1. **Upload Training Data**: The infrastructure creates sample data, but you should upload your own:
   ```bash
   # Upload interactions data
   aws s3 cp your-interactions.csv s3://YOUR_BUCKET/training-data/
   
   # Upload item metadata
   aws s3 cp your-items.csv s3://YOUR_BUCKET/metadata/
   
   # Upload user metadata
   aws s3 cp your-users.csv s3://YOUR_BUCKET/metadata/
   ```

2. **Import Data and Train Models**: Run the data import and training process:
   ```bash
   # Use the provided script or follow the recipe steps
   ./scripts/start_training.sh
   ```

3. **Test Recommendations**: Once models are trained, test the API:
   ```bash
   # Get the API Gateway endpoint from outputs
   API_ENDPOINT=$(terraform output -raw api_gateway_url)
   
   # Test recommendations
   curl "${API_ENDPOINT}/recommendations/user_0001?numResults=10"
   ```

## Data Requirements

Your training data must follow these formats:

### Interactions Data (CSV)
```csv
USER_ID,ITEM_ID,TIMESTAMP,EVENT_TYPE,EVENT_VALUE
user_001,item_001,1609459200,view,1
user_001,item_002,1609459260,purchase,5
```

### Items Metadata (CSV)
```csv
ITEM_ID,CATEGORY,PRICE,BRAND,CREATION_TIMESTAMP
item_001,electronics,299.99,BrandA,1609459200
item_002,electronics,199.99,BrandB,1609459200
```

### Users Metadata (CSV)
```csv
USER_ID,AGE,GENDER,MEMBERSHIP_TYPE
user_001,25,M,premium
user_002,34,F,free
```

## API Endpoints

After deployment, the following endpoints are available:

- `GET /recommendations/{userId}` - Get personalized recommendations
- `GET /recommendations/{userId}?type=similar_items&itemId={itemId}` - Get similar items
- `GET /recommendations/{userId}?type=trending_now` - Get trending recommendations
- `GET /recommendations/{userId}?type=popularity` - Get popular items
- `GET /recommendations/{userId}?category={category}` - Get category-filtered recommendations
- `GET /recommendations/{userId}?minPrice={min}&maxPrice={max}` - Get price-filtered recommendations

## Monitoring and Observability

The infrastructure includes comprehensive monitoring:

### CloudWatch Metrics
- `PersonalizeABTest/RecommendationRequests` - Request count by strategy
- `PersonalizeABTest/ResponseTime` - API response times
- `PersonalizeABTest/NumResults` - Number of recommendations returned

### CloudWatch Dashboards
Access pre-built dashboards for:
- Recommendation API performance
- A/B testing results
- Model training status
- Campaign utilization

### Alerts
Pre-configured CloudWatch alarms for:
- High API error rates
- Campaign failures
- Training job failures
- Cost threshold breaches

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name personalize-recommendation-system

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name personalize-recommendation-system
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy PersonalizeRecommendationStack
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy PersonalizeRecommendationStack
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

The infrastructure implements security best practices:

- **IAM Roles**: Least privilege access for all services
- **Encryption**: S3 bucket encryption at rest
- **VPC Integration**: Optional VPC deployment for Lambda functions
- **Access Logging**: S3 access logging enabled
- **API Security**: API Gateway with throttling and API keys (optional)

## Troubleshooting

### Common Issues

1. **Model Training Failures**
   ```bash
   # Check solution version status
   aws personalize describe-solution-version --solution-version-arn YOUR_SOLUTION_VERSION_ARN
   ```

2. **Campaign Creation Errors**
   ```bash
   # Verify solution version is ACTIVE
   aws personalize list-solution-versions --solution-arn YOUR_SOLUTION_ARN
   ```

3. **Lambda Function Errors**
   ```bash
   # Check CloudWatch logs
   aws logs describe-log-groups --log-group-name-prefix /aws/lambda/
   ```

4. **Data Import Issues**
   ```bash
   # Check import job status
   aws personalize describe-dataset-import-job --dataset-import-job-arn YOUR_IMPORT_JOB_ARN
   ```

### Performance Optimization

- **Campaign TPS**: Adjust based on expected traffic
- **Lambda Memory**: Increase for faster cold starts
- **Batch Size**: Optimize for your recommendation volume
- **Filter Complexity**: Simplify filters for better performance

## Cost Optimization

- **Development**: Use minimum TPS (1) for campaigns
- **Batch Processing**: Use batch inference for bulk recommendations
- **Data Lifecycle**: Implement S3 lifecycle policies for old data
- **Monitoring**: Set up billing alerts and cost anomaly detection

## Support and Documentation

- [Amazon Personalize Developer Guide](https://docs.aws.amazon.com/personalize/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)
- [CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## Advanced Features

### A/B Testing Configuration
Modify the A/B testing distribution in the Lambda environment variables:
```json
{
  "AB_TEST_CONFIG": {
    "user_personalization": 0.4,
    "similar_items": 0.2,
    "trending_now": 0.2,
    "popularity": 0.2
  }
}
```

### Custom Filters
Add business-specific filters by modifying the filter expressions in the infrastructure code:
```
INCLUDE ItemID WHERE Items.CUSTOM_FIELD IN ($CUSTOM_VALUE)
```

### Multi-Region Deployment
For global applications, deploy in multiple regions and use Route 53 for traffic routing:
```bash
# Deploy in multiple regions
terraform apply -var="aws_region=us-east-1"
terraform apply -var="aws_region=eu-west-1"
```

This comprehensive infrastructure enables sophisticated recommendation systems with production-ready features including A/B testing, automated retraining, and comprehensive monitoring capabilities.