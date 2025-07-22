# Infrastructure as Code for Business Process Automation with Step Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Business Process Automation with Step Functions".

## Overview

This recipe demonstrates how to implement enterprise business process automation using AWS Step Functions to orchestrate workflows with Lambda functions, SNS notifications, SQS queues, and human approval patterns. The solution provides a scalable, serverless approach to managing complex business processes with built-in error handling and monitoring.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

The solution deploys:
- AWS Step Functions state machine for workflow orchestration
- Lambda function for business logic processing
- SNS topic for notifications and human approval workflows
- SQS queue for task completion logging
- API Gateway for human approval callbacks
- IAM roles and policies for secure service integration

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating Step Functions, Lambda, SNS, SQS, and IAM resources
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $5-10 per month for development and testing

### Required AWS Permissions

Your AWS credentials must have permissions for:
- `stepfunctions:*`
- `lambda:*`
- `sns:*`
- `sqs:*`
- `apigateway:*`
- `iam:CreateRole`, `iam:PutRolePolicy`, `iam:AttachRolePolicy`
- `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name business-process-automation \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=business-process

# Monitor deployment
aws cloudformation wait stack-create-complete \
    --stack-name business-process-automation

# Get outputs
aws cloudformation describe-stacks \
    --stack-name business-process-automation \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

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

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

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

# The script will output resource ARNs and configuration details
```

## Testing the Deployment

After deployment, test the business process automation workflow:

```bash
# Get the State Machine ARN from outputs
STATE_MACHINE_ARN="<your-state-machine-arn>"

# Create test input
cat > test-input.json << EOF
{
  "processData": {
    "processId": "BP-001",
    "type": "expense-approval",
    "amount": 5000,
    "requestor": "test@example.com",
    "description": "Software licensing renewal",
    "processingTime": 1
  }
}
EOF

# Start execution
aws stepfunctions start-execution \
    --state-machine-arn ${STATE_MACHINE_ARN} \
    --name "test-execution-$(date +%s)" \
    --input file://test-input.json

# Monitor execution
aws stepfunctions list-executions \
    --state-machine-arn ${STATE_MACHINE_ARN} \
    --max-items 5
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name business-process-automation

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name business-process-automation
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted for resource deletion
```

## Customization

### Environment Variables

All implementations support customization through variables:

- `project_name`: Prefix for resource names (default: "business-process")
- `aws_region`: AWS region for deployment (default: current CLI region)
- `notification_email`: Email address for SNS notifications
- `lambda_timeout`: Lambda function timeout in seconds (default: 30)
- `approval_timeout`: Human approval timeout in seconds (default: 86400)

### CloudFormation Parameters

```bash
aws cloudformation create-stack \
    --stack-name business-process-automation \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=my-business-process \
        ParameterKey=NotificationEmail,ParameterValue=admin@company.com \
        ParameterKey=LambdaTimeout,ParameterValue=60
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
project_name = "my-business-process"
aws_region = "us-west-2"
notification_email = "admin@company.com"
lambda_timeout = 60
approval_timeout = 172800  # 48 hours
```

### CDK Context

Set CDK context values:

```bash
# TypeScript
cdk deploy -c project_name=my-business-process -c notification_email=admin@company.com

# Python
cdk deploy -c project_name=my-business-process -c notification_email=admin@company.com
```

## Monitoring and Observability

The deployed infrastructure includes:

### CloudWatch Integration
- Step Functions execution logs and metrics
- Lambda function logs and performance metrics
- API Gateway access logs and error tracking
- Custom metrics for business process KPIs

### X-Ray Tracing
- End-to-end request tracing across services
- Performance bottleneck identification
- Error root cause analysis

### Monitoring Dashboards
Access monitoring through:
1. AWS Step Functions Console - Visual workflow execution
2. CloudWatch Console - Metrics and logs
3. X-Ray Console - Distributed tracing

## Security Considerations

### IAM Roles and Policies
- Principle of least privilege for all service roles
- Separate execution roles for each service
- No hardcoded credentials in any implementation

### Encryption
- SNS messages encrypted in transit
- SQS messages encrypted at rest and in transit
- Lambda environment variables encrypted with KMS

### Network Security
- API Gateway with throttling and API key requirements
- VPC endpoints available for private connectivity
- Security groups with minimal required access

## Troubleshooting

### Common Issues

1. **Step Functions Execution Fails**
   - Check IAM role permissions
   - Verify Lambda function code deployment
   - Review CloudWatch logs for detailed errors

2. **Human Approval Timeout**
   - Increase timeout values in state machine definition
   - Verify SNS topic subscription and email delivery
   - Check API Gateway endpoint accessibility

3. **Lambda Function Errors**
   - Review function logs in CloudWatch
   - Verify environment variables are set correctly
   - Check function timeout and memory settings

### Debug Commands

```bash
# View Step Functions execution history
aws stepfunctions get-execution-history \
    --execution-arn <execution-arn> \
    --output table

# Check Lambda function logs
aws logs tail /aws/lambda/<function-name> --follow

# Test SNS topic
aws sns publish \
    --topic-arn <topic-arn> \
    --message "Test notification"

# Check SQS queue messages
aws sqs receive-message --queue-url <queue-url>
```

## Performance Optimization

### Step Functions Optimization
- Use Express Workflows for high-volume, short-duration processes
- Implement proper retry strategies with exponential backoff
- Optimize state machine design to minimize transitions

### Lambda Optimization
- Right-size memory allocation based on execution patterns
- Use provisioned concurrency for consistent performance
- Implement connection pooling for external service calls

### Cost Optimization
- Monitor Step Functions state transition costs
- Use appropriate Lambda memory settings
- Implement SQS message batching where applicable

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for solution overview
2. **AWS Documentation**: 
   - [Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/)
   - [Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
3. **Tool Documentation**:
   - [CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
   - [CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
   - [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)

## Next Steps

After deploying this solution, consider these enhancements:

1. **Multi-stage Approval Workflows**: Implement sequential approvals with escalation
2. **External System Integration**: Add webhooks and API integrations
3. **Advanced Monitoring**: Create custom CloudWatch dashboards and alerts
4. **Parallel Processing**: Use Step Functions Map state for batch operations
5. **Process Analytics**: Implement historical performance tracking and optimization

## License

This infrastructure code is provided as part of the AWS recipes collection. Refer to the repository license for usage terms.