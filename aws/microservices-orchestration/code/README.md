# Infrastructure as Code for Microservices Orchestration with EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Microservices Orchestration with EventBridge".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates an event-driven microservices architecture that includes:

- Custom EventBridge event bus for decoupled messaging
- Step Functions state machine for workflow orchestration
- Lambda functions for microservices (Order, Payment, Inventory, Notification)
- DynamoDB table for order data persistence
- IAM roles with least privilege access
- CloudWatch logging and monitoring
- EventBridge rules for event routing

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for EventBridge, Step Functions, Lambda, DynamoDB, and CloudWatch
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Bash shell environment

### Required AWS Permissions

Your AWS credentials must have permissions to create and manage:
- IAM roles and policies
- Lambda functions
- Step Functions state machines
- EventBridge event buses and rules
- DynamoDB tables
- CloudWatch log groups and dashboards

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name event-driven-microservices \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=microservices-demo

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name event-driven-microservices

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name event-driven-microservices \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk ls --long
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

# The script will create all resources and provide output information
```

## Testing the Deployment

After deployment, test the event-driven architecture:

```bash
# Get the Order Service function name from outputs
ORDER_FUNCTION_NAME="your-order-function-name"

# Submit a test order
aws lambda invoke \
    --function-name ${ORDER_FUNCTION_NAME} \
    --payload '{
        "customerId": "customer-123",
        "items": [
            {"productId": "prod-001", "quantity": 2, "price": 29.99}
        ],
        "totalAmount": 59.98
    }' \
    test-response.json

# View the response
cat test-response.json

# Monitor Step Functions execution in AWS Console
echo "Check Step Functions console for workflow execution status"
```

## Monitoring and Observability

### CloudWatch Dashboard

Access the created CloudWatch dashboard to monitor:
- Lambda function invocations and errors
- Step Functions execution metrics
- EventBridge rule metrics
- DynamoDB table metrics

### Step Functions Console

Monitor workflow executions in the Step Functions console:
- Visual execution history
- State transition details
- Error handling and retries
- Execution duration and costs

### CloudWatch Logs

View detailed logs for troubleshooting:
- Lambda function logs: `/aws/lambda/[function-name]`
- Step Functions logs: `/aws/stepfunctions/[state-machine-name]`

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name event-driven-microservices

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name event-driven-microservices
```

### Using CDK

```bash
# Navigate to the CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the infrastructure
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm when prompted for destructive actions
```

## Customization

### Configuration Variables

Each implementation supports customization through variables:

- **ProjectName**: Prefix for all resource names
- **Environment**: Environment tag for resources (dev, staging, prod)
- **LogRetentionDays**: CloudWatch log retention period
- **LambdaMemorySize**: Memory allocation for Lambda functions
- **DynamoDBReadCapacity**: DynamoDB read capacity units
- **DynamoDBWriteCapacity**: DynamoDB write capacity units

### CloudFormation Parameters

Modify parameters in the CloudFormation template or provide them during stack creation:

```bash
aws cloudformation create-stack \
    --stack-name event-driven-microservices \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=my-project \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=LogRetentionDays,ParameterValue=30
```

### CDK Configuration

Modify the configuration in the CDK app files or use context values:

```bash
# CDK TypeScript
cdk deploy -c projectName=my-project -c environment=production

# CDK Python
cdk deploy -c projectName=my-project -c environment=production
```

### Terraform Variables

Create a `terraform.tfvars` file or set variables during apply:

```bash
# Using tfvars file
cat > terraform.tfvars << EOF
project_name = "my-project"
environment = "production"
log_retention_days = 30
EOF

terraform apply

# Or set variables during apply
terraform apply \
    -var="project_name=my-project" \
    -var="environment=production"
```

## Cost Optimization

### Development Environment

For cost-effective development:
- Use minimal DynamoDB capacity units
- Set short CloudWatch log retention periods
- Use smaller Lambda memory allocations
- Implement resource scheduling for non-24/7 workloads

### Production Environment

For production deployments:
- Enable DynamoDB auto-scaling
- Use appropriate Lambda memory sizing based on performance testing
- Implement proper log retention policies
- Enable AWS X-Ray for distributed tracing (additional cost)

## Security Considerations

### IAM Roles

All implementations follow the principle of least privilege:
- Lambda functions have minimal required permissions
- Step Functions can only invoke specified Lambda functions
- EventBridge rules have targeted resource access

### Network Security

Consider additional security measures:
- Deploy Lambda functions in VPC for sensitive workloads
- Use VPC endpoints for AWS service communication
- Implement AWS WAF for API Gateway endpoints (if added)

### Data Protection

- DynamoDB encryption at rest is enabled by default
- CloudWatch logs are encrypted
- Consider implementing field-level encryption for sensitive data

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**
   - Verify your AWS credentials have sufficient permissions
   - Check CloudTrail logs for detailed error information

2. **Lambda Function Failures**
   - Check CloudWatch logs for specific error messages
   - Verify environment variables are set correctly

3. **Step Functions Execution Failures**
   - Review the execution history in Step Functions console
   - Check individual Lambda function logs
   - Verify EventBridge rule configurations

4. **DynamoDB Access Issues**
   - Confirm table creation completed successfully
   - Verify IAM role permissions for DynamoDB access

### Debug Mode

Enable debug logging by setting environment variables:

```bash
# For Terraform
export TF_LOG=DEBUG

# For AWS CLI
export AWS_CLI_COMMAND_TIMEOUT=0
export AWS_CLI_READ_TIMEOUT=0
```

## Support

For issues with this infrastructure code, refer to:
- Original recipe documentation
- AWS service documentation
- Provider-specific documentation (Terraform, CDK)
- AWS Support (if you have a support plan)

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow the original recipe architecture patterns
3. Maintain backward compatibility
4. Update documentation accordingly

## Version History

- **v1.0**: Initial implementation with basic event-driven architecture
- **v1.1**: Added comprehensive monitoring and error handling
- **v1.2**: Enhanced security with least privilege IAM roles