# Infrastructure as Code for Interactive Data Analytics with Bedrock AgentCore Code Interpreter

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Interactive Data Analytics with Bedrock AgentCore Code Interpreter".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an intelligent data analytics system that combines natural language processing with secure code execution capabilities. The infrastructure includes:

- **AWS Bedrock AgentCore Code Interpreter**: Secure sandboxed code execution environment
- **AWS Lambda**: Serverless orchestration function for workflow coordination
- **Amazon S3**: Scalable data storage for raw datasets and analysis results
- **Amazon API Gateway**: Managed API endpoint for external access
- **Amazon CloudWatch**: Comprehensive monitoring, logging, and alerting
- **Amazon SQS**: Dead letter queue for error handling and recovery
- **IAM Roles and Policies**: Least privilege security configuration

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions for Bedrock, S3, Lambda, CloudWatch, API Gateway, SQS, and IAM
- Understanding of data analytics workflows and AWS serverless architectures
- Access to AWS Bedrock AgentCore (preview feature - ensure your account has access)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2.0 or later
- Appropriate IAM permissions for CloudFormation stack operations

#### CDK TypeScript
- Node.js 16.x or later
- AWS CDK v2.100 or later
- TypeScript 4.9 or later
- npm or yarn package manager

#### CDK Python
- Python 3.8 or later
- AWS CDK v2.100 or later
- pip package manager
- virtualenv (recommended)

#### Terraform
- Terraform v1.5 or later
- AWS Provider v5.0 or later
- Basic understanding of Terraform workflows

### Estimated Costs
- Development/Testing: $15-25 per day
- Production: $50-150 per day (depending on usage)
- Key cost drivers: Bedrock inference, Lambda execution, S3 storage, API Gateway requests

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name interactive-analytics-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name interactive-analytics-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name interactive-analytics-stack \
    --query 'Stacks[0].Outputs'
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
cdk deploy --require-approval never

# View outputs
cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
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

# The script will output the API endpoint and other important information
```

## Post-Deployment Verification

After successful deployment, verify the system is working:

### Test the Analytics API

```bash
# Get the API endpoint from outputs
API_ENDPOINT="<your-api-endpoint-from-outputs>"

# Test with a simple analytics query
curl -X POST "${API_ENDPOINT}/analytics" \
    -H "Content-Type: application/json" \
    -d '{
        "query": "Analyze the sales data and provide insights on regional performance"
    }'
```

### Upload Sample Data

```bash
# Get bucket names from outputs
RAW_DATA_BUCKET="<your-raw-data-bucket-from-outputs>"

# Upload sample dataset
aws s3 cp sample_data.csv s3://${RAW_DATA_BUCKET}/datasets/
```

### Monitor Execution

```bash
# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/

# View metrics
aws cloudwatch list-metrics --namespace Analytics/CodeInterpreter
```

## Configuration Options

### Environment Variables

All implementations support these configuration parameters:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Deployment environment | dev | No |
| ProjectName | Project identifier for resource naming | interactive-analytics | No |
| DataRetentionDays | Data retention period in days | 90 | No |
| LambdaTimeout | Lambda function timeout in seconds | 300 | No |
| LambdaMemorySize | Lambda function memory in MB | 512 | No |
| CodeInterpreterTimeout | Code interpreter session timeout | 3600 | No |
| EnableXRayTracing | Enable AWS X-Ray tracing | false | No |

### CloudFormation Parameters

```bash
aws cloudformation create-stack \
    --stack-name interactive-analytics-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=prod \
        ParameterKey=DataRetentionDays,ParameterValue=365 \
        ParameterKey=EnableXRayTracing,ParameterValue=true
```

### CDK Context Variables

```bash
# Set context variables for CDK deployment
cdk deploy \
    -c environment=prod \
    -c dataRetentionDays=365 \
    -c enableXRayTracing=true
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
environment = "prod"
project_name = "my-analytics"
data_retention_days = 365
enable_xray_tracing = true
lambda_timeout = 600
lambda_memory_size = 1024
```

## Monitoring and Observability

### CloudWatch Dashboards

The deployment creates a CloudWatch dashboard with key metrics:

- Code Interpreter execution count and errors
- Lambda function duration and errors
- API Gateway request count and latency
- S3 bucket object count and size

### Alarms

Pre-configured CloudWatch alarms monitor:

- High error rates (>3 errors in 10 minutes)
- Long execution times (>4 minutes average)
- API Gateway 5xx errors
- Dead letter queue message count

### Logs

Monitor these log groups:

- `/aws/lambda/<function-name>`: Lambda execution logs
- `/aws/bedrock/agentcore/<interpreter-name>`: Code Interpreter logs
- `/aws/apigateway/<api-id>`: API Gateway access logs

## Security Considerations

### IAM Roles and Policies

The infrastructure implements least privilege access:

- **Lambda Execution Role**: Access to Bedrock, S3, CloudWatch, and SQS
- **Code Interpreter Role**: Restricted S3 access for data processing
- **API Gateway Role**: Limited to invoke Lambda functions

### Data Protection

- All S3 buckets use server-side encryption (AES-256)
- S3 bucket versioning enabled for data protection
- CloudWatch Logs encrypted at rest
- API Gateway supports HTTPS only

### Network Security

- Code Interpreter runs in isolated sandboxed environment
- Lambda functions use VPC endpoints when configured
- API Gateway implements throttling and rate limiting

## Troubleshooting

### Common Issues

1. **Bedrock Access Denied**
   - Ensure your AWS account has access to Bedrock AgentCore
   - Verify the region supports Bedrock services
   - Check IAM permissions for Bedrock operations

2. **Lambda Timeout**
   - Increase timeout value for complex analyses
   - Monitor memory usage and adjust if needed
   - Check Code Interpreter execution time

3. **S3 Access Issues**
   - Verify bucket policies and IAM permissions
   - Check bucket encryption settings
   - Ensure cross-region access is configured if needed

4. **API Gateway 5xx Errors**
   - Check Lambda function logs for errors
   - Verify API Gateway integration configuration
   - Monitor throttling limits

### Debug Commands

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/<function-name> --follow

# Test Lambda function directly
aws lambda invoke \
    --function-name <function-name> \
    --payload '{"query": "test"}' \
    response.json

# Check Code Interpreter status
aws bedrock-agentcore list-code-interpreters

# Monitor API Gateway metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name Count \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 3600 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Empty S3 buckets first (required)
aws s3 rm s3://<raw-data-bucket> --recursive
aws s3 rm s3://<results-bucket> --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name interactive-analytics-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name interactive-analytics-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy --require-approval never
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Remove state files (optional)
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Cost Optimization

### Tips for Reducing Costs

1. **Data Lifecycle Management**
   - Configure S3 lifecycle policies to transition data to cheaper storage classes
   - Set appropriate data retention periods
   - Delete unnecessary analysis results regularly

2. **Lambda Optimization**
   - Right-size memory allocation based on actual usage
   - Use provisioned concurrency sparingly
   - Monitor and optimize function duration

3. **Bedrock Usage**
   - Monitor token usage and optimize prompts
   - Use appropriate model sizes for your use case
   - Implement caching for repeated analyses

4. **Monitoring**
   - Set up billing alerts
   - Use AWS Cost Explorer to track spending
   - Regularly review and optimize resource usage

### Resource Cleanup Automation

Consider implementing automated cleanup:

```bash
# Example: Delete old analysis results
aws s3api list-objects-v2 \
    --bucket <results-bucket> \
    --query "Contents[?LastModified<'2024-01-01'].Key" \
    --output text | xargs -I {} aws s3 rm s3://<results-bucket>/{}
```

## Advanced Configuration

### VPC Integration

For enhanced security, consider deploying Lambda functions in a VPC:

```yaml
# CloudFormation example
VpcConfig:
  SecurityGroupIds:
    - !Ref LambdaSecurityGroup
  SubnetIds:
    - !Ref PrivateSubnet1
    - !Ref PrivateSubnet2
```

### Custom Domain

Configure a custom domain for the API Gateway:

```bash
# Create ACM certificate (in us-east-1 for global distribution)
aws acm request-certificate \
    --domain-name api.yourdomain.com \
    --validation-method DNS

# Configure custom domain in API Gateway
aws apigatewayv2 create-domain-name \
    --domain-name api.yourdomain.com \
    --certificate-arn <certificate-arn>
```

### Multi-Region Deployment

For high availability, consider multi-region deployment:

- Deploy infrastructure in multiple AWS regions
- Use S3 Cross-Region Replication for data redundancy
- Implement Route 53 health checks for failover

## Integration Examples

### CI/CD Pipeline Integration

Example GitHub Actions workflow:

```yaml
name: Deploy Analytics Infrastructure
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Deploy with CDK
        run: |
          cd cdk-typescript/
          npm install
          cdk deploy --require-approval never
```

### Application Integration

Example Python client:

```python
import requests
import json

# Configure API endpoint
api_endpoint = "https://your-api-id.execute-api.us-east-1.amazonaws.com/prod"

# Submit analytics query
response = requests.post(
    f"{api_endpoint}/analytics",
    headers={"Content-Type": "application/json"},
    data=json.dumps({
        "query": "Analyze customer behavior patterns and predict churn risk"
    })
)

result = response.json()
print(f"Analysis results: {result}")
```

## Support and Resources

### Documentation Links

- [AWS Bedrock Developer Guide](https://docs.aws.amazon.com/bedrock/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Community Resources

- [AWS Samples GitHub Repository](https://github.com/aws-samples)
- [AWS Architecture Center](https://aws.amazon.com/architecture/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service documentation
3. Check AWS service health status
4. Consult the original recipe documentation
5. Contact AWS Support for service-specific issues

---

**Note**: This infrastructure code implements the complete solution described in the "Interactive Data Analytics with Bedrock AgentCore Code Interpreter" recipe. Ensure you understand the costs and security implications before deploying to production environments.