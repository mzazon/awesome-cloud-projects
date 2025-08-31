# Infrastructure as Code for Intelligent Web Scraping with AgentCore Browser and Code Interpreter

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Intelligent Web Scraping with AgentCore Browser and Code Interpreter".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions for Bedrock AgentCore, Lambda, S3, IAM, CloudWatch, EventBridge, and SQS services
- Access to Amazon Bedrock AgentCore preview (Browser and Code Interpreter services)
- Node.js 18+ (for CDK TypeScript implementation)
- Python 3.11+ (for CDK Python implementation)
- Terraform 1.5+ (for Terraform implementation)
- Appropriate IAM permissions for resource creation and management
- Estimated cost: $10-25 per month for development usage (AgentCore preview pricing, Lambda executions, S3 storage)

> **Note**: Amazon Bedrock AgentCore is currently in preview and subject to change. Ensure you have access to the preview in your AWS region and understand that service APIs may evolve.

## Quick Start

### Using CloudFormation (AWS)
```bash
# Deploy the infrastructure stack
aws cloudformation create-stack \
    --stack-name intelligent-scraper-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=intelligent-scraper

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name intelligent-scraper-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name intelligent-scraper-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)
```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --require-approval never

# View deployed resources
npx cdk ls
```

### Using CDK Python (AWS)
```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View deployed resources
cdk ls
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
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

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Architecture Overview

The infrastructure deploys the following AWS resources:

- **Lambda Function**: Orchestrates the intelligent scraping workflow
- **S3 Buckets**: Store input configurations and output results with encryption
- **IAM Role**: Provides Lambda with permissions for AgentCore and S3 access
- **CloudWatch**: Monitors execution with custom dashboard and log groups
- **EventBridge**: Schedules automated scraping executions
- **SQS Dead Letter Queue**: Handles failed execution scenarios
- **AgentCore Browser Sessions**: AI-powered web navigation (preview service)
- **AgentCore Code Interpreter**: Secure data processing environment (preview service)

## Configuration Options

### Environment Variables

All implementations support customization through parameters/variables:

- `ProjectName`: Unique project identifier (default: "intelligent-scraper")
- `S3BucketPrefix`: Prefix for S3 bucket names
- `LambdaTimeout`: Lambda function timeout in seconds (default: 900)
- `LambdaMemorySize`: Lambda memory allocation in MB (default: 1024)
- `ScheduleExpression`: EventBridge schedule expression (default: "rate(6 hours)")
- `Environment`: Deployment environment (default: "production")

### Example Customization

For CloudFormation:
```bash
aws cloudformation create-stack \
    --stack-name intelligent-scraper-dev \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=scraper-dev \
        ParameterKey=LambdaTimeout,ParameterValue=600 \
        ParameterKey=Environment,ParameterValue=development
```

For Terraform:
```bash
terraform apply \
    -var="project_name=scraper-dev" \
    -var="lambda_timeout=600" \
    -var="environment=development"
```

## Testing the Deployment

After deployment, test the intelligent scraping functionality:

```bash
# Get Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name intelligent-scraper-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Create test payload
cat > test-payload.json << EOF
{
  "bucket_input": "your-input-bucket-name",
  "bucket_output": "your-output-bucket-name",
  "test_mode": true
}
EOF

# Execute test run
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload file://test-payload.json \
    response.json

# Check results
cat response.json | jq '.'
```

## Monitoring and Observability

### CloudWatch Dashboard

Access the monitoring dashboard:
```bash
# Get dashboard URL
aws cloudwatch get-dashboard \
    --dashboard-name "intelligent-scraper-monitoring"
```

### Log Analysis

View Lambda execution logs:
```bash
# Get recent logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
    --start-time $(date -d '1 hour ago' +%s)000
```

### Metrics

Monitor key metrics:
- Scraping job success rate
- Data points extracted per execution
- Lambda function duration and errors
- S3 storage utilization

## Security Considerations

The infrastructure implements several security best practices:

- **Least Privilege IAM**: Lambda role has minimal required permissions
- **S3 Encryption**: All buckets use AES-256 server-side encryption
- **VPC Isolation**: Optional VPC deployment for network isolation
- **Resource Tagging**: Comprehensive tagging for governance
- **Dead Letter Queue**: Secure handling of failed executions

## Troubleshooting

### Common Issues

1. **AgentCore Access**: Ensure your AWS account has access to Bedrock AgentCore preview
2. **IAM Permissions**: Verify Lambda execution role has required permissions
3. **S3 Bucket Names**: Bucket names must be globally unique
4. **Region Availability**: AgentCore services may not be available in all regions

### Debug Commands

```bash
# Check Lambda function configuration
aws lambda get-function --function-name ${FUNCTION_NAME}

# Verify IAM role permissions
aws iam get-role-policy \
    --role-name intelligent-scraper-lambda-role \
    --policy-name intelligent-scraper-lambda-policy

# Test S3 bucket access
aws s3 ls s3://your-bucket-name/
```

## Cost Optimization

### Usage Monitoring

Monitor costs using AWS Cost Explorer and set up billing alerts:

```bash
# Create billing alarm (requires CloudWatch billing metrics)
aws cloudwatch put-metric-alarm \
    --alarm-name "intelligent-scraper-cost-alert" \
    --alarm-description "Alert when monthly costs exceed threshold" \
    --metric-name EstimatedCharges \
    --namespace AWS/Billing \
    --statistic Maximum \
    --period 86400 \
    --threshold 50 \
    --comparison-operator GreaterThanThreshold
```

### Cost Optimization Tips

- Use S3 Intelligent Tiering for long-term data storage
- Adjust Lambda memory allocation based on actual usage
- Optimize EventBridge schedule frequency
- Implement data lifecycle policies for automated cleanup

## Cleanup

### Using CloudFormation (AWS)
```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name intelligent-scraper-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name intelligent-scraper-stack
```

### Using CDK (AWS)
```bash
# For TypeScript
cd cdk-typescript/
npx cdk destroy

# For Python
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
# Execute cleanup script
./scripts/destroy.sh

# Verify resource deletion
./scripts/destroy.sh --verify
```

### Manual Cleanup Verification

Ensure all resources are properly deleted:

```bash
# Check for remaining S3 buckets
aws s3 ls | grep intelligent-scraper

# Verify Lambda function deletion
aws lambda list-functions --query 'Functions[?contains(FunctionName, `intelligent-scraper`)]'

# Check CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/intelligent-scraper"
```

## Customization

### Adding New Scraping Scenarios

1. Update the scraper configuration in S3:
```json
{
  "scraping_scenarios": [
    {
      "name": "custom_scenario",
      "target_url": "https://example.com",
      "extraction_rules": {
        "titles": {"selector": "h1", "attribute": "textContent"}
      }
    }
  ]
}
```

2. Deploy updated configuration:
```bash
aws s3 cp updated-config.json s3://your-input-bucket/scraper-config.json
```

### Extending Data Processing

Modify the Lambda function to include additional analysis:
- Integrate with Amazon Comprehend for NLP
- Add Amazon Rekognition for image analysis
- Implement custom ML models with SageMaker

## Integration Examples

### CI/CD Pipeline Integration

Example GitHub Actions workflow:
```yaml
name: Deploy Intelligent Scraper
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy with Terraform
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

### API Gateway Integration

Add REST API endpoint for manual triggering:
```bash
# Create API Gateway to trigger Lambda
aws apigateway create-rest-api --name intelligent-scraper-api
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../intelligent-web-scraping-browser-codeinterpreter.md)
2. Review AWS Bedrock AgentCore documentation
3. Consult provider-specific documentation:
   - [AWS CloudFormation](https://docs.aws.amazon.com/cloudformation/)
   - [AWS CDK](https://docs.aws.amazon.com/cdk/)
   - [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Contributing

When contributing to this infrastructure code:

1. Follow AWS Well-Architected Framework principles
2. Implement appropriate security measures
3. Include comprehensive documentation
4. Test all deployment scenarios
5. Validate cleanup procedures

## Version History

- **v1.0**: Initial implementation with basic AgentCore integration
- **v1.1**: Added production optimizations and monitoring enhancements

---

> **Important**: This infrastructure deploys preview AWS services. Monitor AWS announcements for service updates and pricing changes as AgentCore transitions from preview to general availability.