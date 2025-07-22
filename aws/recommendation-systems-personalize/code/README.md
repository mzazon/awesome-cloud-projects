# Infrastructure as Code for Building Recommendation Systems with Amazon Personalize

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Recommendation Systems with Amazon Personalize".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- AWS account with Amazon Personalize, API Gateway, Lambda, and S3 permissions
- Historical interaction data (minimum 1,000 interactions, 25 unique users, 100 unique items)
- Understanding of machine learning concepts, REST APIs, and serverless architecture
- Estimated cost: $50-150/month for training and inference (depends on data size and request volume)

> **Note**: Amazon Personalize requires a minimum amount of data to train effective models. Insufficient data will result in poor recommendation quality.

## Quick Start

### Using CloudFormation

```bash
# Create stack with required parameters
aws cloudformation create-stack \
    --stack-name recommendation-system-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DatasetGroupName,ParameterValue=ecommerce-recommendations \
                ParameterKey=SolutionName,ParameterValue=user-personalization \
                ParameterKey=CampaignName,ParameterValue=real-time-recommendations \
                ParameterKey=LambdaFunctionName,ParameterValue=recommendation-api \
                ParameterKey=APIName,ParameterValue=recommendation-api \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name recommendation-system-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name recommendation-system-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy RecommendationSystemStack

# Get outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy RecommendationSystemStack

# Get outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy infrastructure
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters and deploy all resources
```

## Architecture Overview

The infrastructure deploys:

1. **Amazon Personalize Resources**:
   - Dataset Group for organizing ML resources
   - Interactions Dataset with proper schema
   - Solution using User-Personalization recipe
   - Campaign for real-time inference

2. **API Infrastructure**:
   - API Gateway REST API with proper resource hierarchy
   - Lambda function for recommendation processing
   - IAM roles with least privilege permissions

3. **Data Storage**:
   - S3 bucket for training data storage
   - Sample interaction data for testing

4. **Monitoring**:
   - CloudWatch metrics and alarms
   - API Gateway stage with detailed metrics

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| DatasetGroupName | Name for Personalize dataset group | `ecommerce-recommendations` |
| SolutionName | Name for ML solution | `user-personalization` |
| CampaignName | Name for inference campaign | `real-time-recommendations` |
| LambdaFunctionName | Name for API Lambda function | `recommendation-api` |
| APIName | Name for API Gateway | `recommendation-api` |
| MinProvisionedTPS | Minimum TPS for campaign | `1` |

### CDK Configuration

Modify the configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript example
const config = {
  datasetGroupName: 'ecommerce-recommendations',
  solutionName: 'user-personalization',
  campaignName: 'real-time-recommendations',
  minProvisionedTPS: 1
};
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
dataset_group_name = "ecommerce-recommendations"
solution_name = "user-personalization"
campaign_name = "real-time-recommendations"
lambda_function_name = "recommendation-api"
api_name = "recommendation-api"
min_provisioned_tps = 1
```

## Deployment Process

### Phase 1: Data Preparation (5-10 minutes)
- S3 bucket creation
- Sample data upload
- IAM role setup

### Phase 2: Personalize Setup (90-120 minutes)
- Dataset group and schema creation
- Data import job (10-15 minutes)
- Model training (60-90 minutes)
- Campaign deployment (5-10 minutes)

### Phase 3: API Deployment (5-10 minutes)
- Lambda function deployment
- API Gateway configuration
- Integration setup

### Phase 4: Monitoring Setup (2-5 minutes)
- CloudWatch metrics activation
- Alarm configuration

> **Warning**: Model training typically requires 60-90 minutes and incurs charges based on training time. Monitor training progress through the AWS console or CLI.

## Testing Your Deployment

### 1. Validate Personalize Campaign

```bash
# Get campaign ARN from outputs
CAMPAIGN_ARN=$(aws cloudformation describe-stacks \
    --stack-name recommendation-system-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`CampaignArn`].OutputValue' \
    --output text)

# Test recommendations directly
aws personalize-runtime get-recommendations \
    --campaign-arn $CAMPAIGN_ARN \
    --user-id user1 \
    --num-results 5
```

### 2. Test API Gateway Endpoint

```bash
# Get API URL from outputs
API_URL=$(aws cloudformation describe-stacks \
    --stack-name recommendation-system-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
    --output text)

# Test API endpoint
curl -X GET "$API_URL/recommendations/user1?numResults=5" \
     -H "Content-Type: application/json"
```

### 3. Performance Testing

```bash
# Test concurrent requests
for i in {1..10}; do
    curl -X GET "$API_URL/recommendations/user$i?numResults=10" \
         -H "Content-Type: application/json" &
done
wait
```

## Monitoring and Maintenance

### CloudWatch Metrics

Monitor these key metrics:
- API Gateway: Request count, latency, errors
- Lambda: Duration, errors, throttles
- Personalize: Campaign utilization, recommendation latency

### Cost Optimization

1. **Campaign Scaling**: Adjust `MinProvisionedTPS` based on actual traffic
2. **Data Refresh**: Schedule model retraining based on data freshness needs
3. **API Caching**: Enable API Gateway caching for frequently requested recommendations

### Model Retraining

Set up scheduled retraining:
1. Use EventBridge to trigger retraining on schedule
2. Monitor model performance metrics
3. Update campaigns with new solution versions

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name recommendation-system-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name recommendation-system-stack
```

### Using CDK

```bash
# From the CDK directory
cdk destroy RecommendationSystemStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

### IAM Permissions

The infrastructure implements least privilege access:
- Personalize service role: Read-only access to S3 training data
- Lambda execution role: Personalize inference permissions only
- API Gateway: No authentication by default (consider adding API keys or Cognito)

### Data Protection

- Training data stored in S3 with server-side encryption
- API responses include CORS headers for web applications
- Consider implementing API throttling for production use

### Production Hardening

For production deployments:
1. Enable API Gateway API keys or authentication
2. Implement request throttling and rate limiting
3. Add WAF protection for API Gateway
4. Enable detailed CloudTrail logging
5. Use VPC endpoints for private access

## Troubleshooting

### Common Issues

1. **Model Training Failures**:
   - Check minimum data requirements (1,000+ interactions)
   - Verify data format matches schema
   - Ensure sufficient unique users and items

2. **API Gateway 5xx Errors**:
   - Check Lambda function logs in CloudWatch
   - Verify IAM permissions for Lambda
   - Check campaign availability

3. **High Latency**:
   - Monitor campaign TPS utilization
   - Consider increasing MinProvisionedTPS
   - Implement API Gateway caching

### Debugging Commands

```bash
# Check Personalize resources
aws personalize list-dataset-groups
aws personalize list-solutions
aws personalize list-campaigns

# Check Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Check API Gateway metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name Count \
    --dimensions Name=ApiName,Value=recommendation-api \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum
```

## Customization

### Adding Business Logic

Extend the Lambda function to include:
- Content filtering based on inventory
- Price-based recommendations
- Category-specific recommendations
- A/B testing logic

### Multiple Models

Deploy multiple Personalize solutions:
- User-Personalization for general recommendations
- Similar-Items for item-to-item recommendations
- Popularity-Count for trending items

### Real-time Data Integration

Integrate with streaming data:
- Amazon Kinesis for real-time event collection
- Personalize Event Tracker for incremental learning
- Lambda triggers for automatic model updates

## Cost Estimation

### Training Costs
- Model training: ~$2-5 per training hour
- Typical training time: 1-2 hours
- Retraining frequency: Monthly (recommended)

### Inference Costs
- Campaign hosting: $0.20 per TPS-hour
- Inference requests: $0.0003 per request
- Minimum 1 TPS = ~$144/month base cost

### Additional Costs
- API Gateway: $3.50 per million requests
- Lambda: $0.20 per 1M requests + compute time
- S3 storage: $0.023 per GB/month
- CloudWatch: $0.50 per million requests

## Support

For issues with this infrastructure code:
1. Check the AWS documentation for service-specific guidance
2. Review CloudWatch logs for error details
3. Consult the original recipe documentation
4. Consider AWS Support for production issues

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Adapt according to your security and compliance requirements.