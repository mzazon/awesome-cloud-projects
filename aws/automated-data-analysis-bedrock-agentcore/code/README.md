# Infrastructure as Code for Automated Data Analysis with Bedrock AgentCore Runtime

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Data Analysis with Bedrock AgentCore Runtime".

## Solution Overview

This recipe implements an automated data analysis system using AWS Bedrock AgentCore Runtime with Code Interpreter to process datasets uploaded to S3 and generate insights automatically. The serverless architecture scales automatically and provides enterprise-grade security for sensitive data analysis workloads.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure includes:
- **S3 Buckets**: Separate buckets for input data and analysis results with encryption and versioning
- **Lambda Function**: Orchestrator function that triggers AgentCore sessions on file uploads
- **IAM Roles and Policies**: Secure access controls following least privilege principles
- **S3 Event Notifications**: Automated triggering of analysis workflows
- **CloudWatch Dashboard**: Monitoring and observability for the analysis pipeline
- **Bedrock AgentCore Integration**: AI-powered data analysis with code interpreter capabilities

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - Bedrock AgentCore services
  - Lambda functions
  - S3 buckets
  - IAM roles and policies
  - CloudWatch dashboards
- Access to Amazon Bedrock AgentCore (may require account allowlisting)
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+

> **Note**: Bedrock AgentCore is currently in preview and may require account allowlisting. Contact AWS Support if you need access to the service.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name bedrock-data-analysis \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name bedrock-data-analysis \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name bedrock-data-analysis \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
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

# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Preview changes
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

# Check deployment status
./scripts/deploy.sh --status
```

## Testing the Deployment

Once deployed, test the automated data analysis system:

```bash
# Set variables from deployment outputs
DATA_BUCKET_NAME="your-data-bucket-name"
RESULTS_BUCKET_NAME="your-results-bucket-name"

# Create sample dataset
cat > sample-dataset.csv << EOF
product_id,category,price,quantity_sold,customer_rating,sales_date
1,Electronics,299.99,45,4.5,2024-01-15
2,Books,19.99,123,4.2,2024-01-16
3,Clothing,79.99,67,4.1,2024-01-17
4,Electronics,199.99,89,4.8,2024-01-18
5,Books,24.99,156,4.0,2024-01-19
EOF

# Upload dataset to trigger analysis
aws s3 cp sample-dataset.csv s3://${DATA_BUCKET_NAME}/datasets/

# Monitor Lambda function logs
aws logs tail "/aws/lambda/data-analysis-orchestrator" --follow

# Check analysis results
aws s3 ls s3://${RESULTS_BUCKET_NAME}/analysis-results/ --recursive
```

## Configuration Options

### Environment Variables

All implementations support these configurable parameters:

- `Environment`: Deployment environment (dev, staging, prod)
- `ProjectName`: Project identifier for resource naming
- `RetentionDays`: CloudWatch logs retention period
- `LambdaTimeout`: Lambda function timeout in seconds
- `LambdaMemorySize`: Lambda function memory allocation

### Security Configuration

- **S3 Encryption**: Server-side encryption enabled by default
- **IAM Policies**: Least privilege access controls
- **VPC Configuration**: Optional VPC deployment for enhanced security
- **Resource Tagging**: Comprehensive tagging for governance

## Monitoring and Observability

The deployment includes:

- **CloudWatch Dashboard**: Real-time metrics for Lambda executions and errors
- **CloudWatch Logs**: Detailed logging for troubleshooting
- **CloudWatch Alarms**: Optional alerting for error conditions
- **X-Ray Tracing**: Optional distributed tracing for performance analysis

Access the dashboard:
```bash
# Get dashboard URL from outputs
aws cloudformation describe-stacks \
    --stack-name bedrock-data-analysis \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
    --output text
```

## Cost Optimization

Estimated monthly costs for typical usage:
- **Lambda**: $2-5 (pay per execution)
- **S3 Storage**: $1-3 (depends on data volume)
- **Bedrock AgentCore**: $5-10 (varies by analysis complexity)
- **CloudWatch**: $1-2 (logs and metrics)

**Total**: $9-20 per month for moderate usage

Cost optimization features:
- Serverless architecture (pay-per-use)
- S3 lifecycle policies for data archival
- Lambda memory optimization
- CloudWatch log retention policies

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name bedrock-data-analysis

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name bedrock-data-analysis \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

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
# Clean up all resources
./scripts/destroy.sh

# Confirm when prompted
```

## Customization

### Adding New File Types

Modify the Lambda function to support additional file formats:

1. **CloudFormation**: Update the Lambda function code in the template
2. **CDK**: Modify the Lambda function definition in the stack
3. **Terraform**: Update the Lambda function resource
4. **Scripts**: Edit the Python code in the deployment script

### Enhancing Analysis Capabilities

Extend the solution with:

- **Custom Analysis Models**: Integrate additional Bedrock foundation models
- **Advanced Visualizations**: Add support for more chart types and interactive plots
- **Data Quality Checks**: Implement validation rules before analysis
- **Report Generation**: Create automated report generation workflows

### Security Enhancements

- **VPC Deployment**: Deploy Lambda functions in private subnets
- **KMS Encryption**: Use customer-managed keys for encryption
- **API Gateway**: Add authentication for file upload endpoints
- **WAF Integration**: Protect web interfaces with AWS WAF

## Troubleshooting

### Common Issues

1. **Bedrock AgentCore Access Denied**
   ```bash
   # Check if account has AgentCore access
   aws bedrock-agentcore list-code-interpreters
   ```

2. **Lambda Timeout Errors**
   ```bash
   # Increase timeout in configuration
   # CloudFormation: Update Timeout parameter
   # CDK: Modify timeout property
   # Terraform: Update timeout variable
   ```

3. **S3 Permission Errors**
   ```bash
   # Verify IAM role permissions
   aws iam get-role-policy --role-name DataAnalysisOrchestratorRole --policy-name S3AccessPolicy
   ```

### Debug Mode

Enable detailed logging:

```bash
# Set environment variable for Lambda function
aws lambda update-function-configuration \
    --function-name data-analysis-orchestrator \
    --environment Variables='{LOG_LEVEL=DEBUG}'
```

## Support and Documentation

- [AWS Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/what-is-bedrock-agentcore.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS S3 Event Notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/NotificationHowTo.html)
- [CloudWatch Monitoring](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs.html)

## Contributing

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult AWS documentation for specific services
4. Review CloudWatch logs for detailed error information

## License

This infrastructure code is provided under the same license as the parent recipe repository.