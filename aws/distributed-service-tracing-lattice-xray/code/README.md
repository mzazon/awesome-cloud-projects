# Infrastructure as Code for Distributed Service Tracing with VPC Lattice and X-Ray

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Distributed Service Tracing with VPC Lattice and X-Ray". This solution demonstrates comprehensive distributed observability by combining VPC Lattice's service mesh capabilities with AWS X-Ray application-level tracing to provide end-to-end visibility into microservices request flows.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML format)
- **CDK TypeScript**: AWS Cloud Development Kit with TypeScript
- **CDK Python**: AWS Cloud Development Kit with Python
- **Terraform**: HashiCorp infrastructure as code with AWS provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a complete distributed tracing solution featuring:

- **VPC Lattice Service Network**: Provides service mesh networking with built-in observability
- **Lambda Microservices**: Three interconnected services (Order, Payment, Inventory) with X-Ray instrumentation
- **AWS X-Ray**: Application-level distributed tracing with detailed performance insights
- **CloudWatch Integration**: Comprehensive logging and metrics collection
- **Observability Dashboard**: Pre-configured CloudWatch dashboard for monitoring

## Prerequisites

### General Requirements

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - VPC Lattice (service networks, services, target groups)
  - Lambda (functions, layers, execution roles)
  - IAM (roles, policies)
  - X-Ray (tracing, service maps)
  - CloudWatch (dashboards, logs, metrics)
  - EC2 (VPC, subnets for Lambda functions)
- Estimated cost: $10-15 for testing period

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions
- No additional tools required

#### CDK TypeScript
- Node.js 18+ and npm
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- TypeScript: `npm install -g typescript`

#### CDK Python
- Python 3.8+ with pip
- AWS CDK v2: `pip install aws-cdk-lib`
- Virtual environment recommended

#### Terraform
- Terraform 1.0+ installed
- AWS provider configured

#### Bash Scripts
- Bash shell environment
- jq for JSON processing: `sudo apt-get install jq` (Linux) or `brew install jq` (macOS)

## Quick Start

### Using CloudFormation

Deploy the complete infrastructure:

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name distributed-tracing-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=EnvironmentName,ParameterValue=dev \
        ParameterKey=VpcCidr,ParameterValue=10.0.0.0/16

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name distributed-tracing-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name distributed-tracing-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

Deploy with TypeScript CDK:

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

# View stack outputs
cdk deploy --outputs-file outputs.json
cat outputs.json
```

### Using CDK Python

Deploy with Python CDK:

```bash
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# List stack information
cdk ls -l
```

### Using Terraform

Deploy with Terraform:

```bash
cd terraform/

# Initialize Terraform
terraform init

# Preview deployment plan
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output

# Generate dependency graph (optional)
terraform graph | dot -Tpng > graph.png
```

### Using Bash Scripts

Deploy using automated scripts:

```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy infrastructure
./deploy.sh

# The script will:
# - Validate prerequisites
# - Create all AWS resources
# - Configure services and networking
# - Set up observability components
# - Generate test traffic
# - Display deployment summary
```

## Validation & Testing

After deployment, validate the solution:

### 1. Test Service Connectivity

```bash
# Get the order service function name from outputs
ORDER_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name distributed-tracing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`OrderServiceFunction`].OutputValue' \
    --output text)

# Invoke order service to generate traces
aws lambda invoke \
    --function-name ${ORDER_FUNCTION_NAME} \
    --payload '{"order_id": "test-123", "customer_id": "customer-456", "items": [{"product_id": "prod-789", "quantity": 2, "price": 50.00}]}' \
    response.json

cat response.json
```

### 2. Verify X-Ray Traces

```bash
# Check X-Ray traces
aws xray get-trace-summaries \
    --time-range-type TimeRangeByStartTime \
    --start-time $(date -d '10 minutes ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --query 'TraceSummaries[*].[Id,Duration,ResponseTime]' \
    --output table
```

### 3. Access CloudWatch Dashboard

```bash
# Get dashboard URL
DASHBOARD_NAME=$(aws cloudformation describe-stacks \
    --stack-name distributed-tracing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudWatchDashboard`].OutputValue' \
    --output text)

echo "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
```

### 4. Generate Load Test Traffic

Run the included test generator to create realistic traffic patterns:

```bash
# If using Terraform, the test script is included
cd terraform/lambda_code/
python3 test_generator.py

# For other deployments, invoke the test function
TEST_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name distributed-tracing-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`TestGeneratorFunction`].OutputValue' \
    --output text)

aws lambda invoke \
    --function-name ${TEST_FUNCTION_NAME} \
    --payload '{"num_requests": 50}' \
    test-response.json
```

## Monitoring and Observability

### X-Ray Service Map

Access the X-Ray service map to visualize service dependencies:

1. Navigate to AWS X-Ray console
2. Click "Service Map" in the left navigation
3. Select the appropriate time range
4. Explore service interactions and performance metrics

### CloudWatch Dashboard

The deployment creates a comprehensive dashboard with:

- VPC Lattice request metrics (count, latency, errors)
- Lambda performance metrics (duration, invocations, errors)
- X-Ray trace metrics (traces received, latency distribution, error rates)

### Log Analysis

Use CloudWatch Insights to analyze application logs:

```bash
# Query order service logs
aws logs start-query \
    --log-group-name "/aws/lambda/order-service-*" \
    --start-time $(date -d '1 hour ago' +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, @message | filter @message like /ORDER/ | sort @timestamp desc'
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name distributed-tracing-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name distributed-tracing-stack

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name distributed-tracing-stack 2>/dev/null || echo "Stack successfully deleted"
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Destroy the stack
cdk destroy

# Confirm when prompted
# Enter 'y' to proceed with deletion
```

### Using CDK Python

```bash
cd cdk-python/

# Activate virtual environment (if using)
source .venv/bin/activate

# Destroy the stack
cdk destroy

# Deactivate virtual environment (if using)
deactivate
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
# Enter 'yes' to proceed with deletion

# Clean up state files (optional)
rm -f terraform.tfstate*
```

### Using Bash Scripts

```bash
cd scripts/

# Run cleanup script
./destroy.sh

# The script will:
# - Prompt for confirmation
# - Delete resources in proper order
# - Handle dependencies automatically
# - Provide deletion status
```

## Customization

### Key Parameters

Each implementation supports customization through variables:

- **Environment Name**: Prefix for resource naming (default: "dev")
- **VPC Configuration**: CIDR blocks and availability zones
- **Lambda Settings**: Memory allocation, timeout values, runtime versions
- **Monitoring**: CloudWatch retention periods, alarm thresholds
- **Networking**: Subnet configurations, security group rules

### CloudFormation Parameters

Edit parameters in the template or provide via CLI:

```bash
aws cloudformation create-stack \
    --parameters \
        ParameterKey=EnvironmentName,ParameterValue=production \
        ParameterKey=LambdaMemorySize,ParameterValue=512 \
        ParameterKey=LogRetentionDays,ParameterValue=30
```

### CDK Context

Modify `cdk.json` to customize deployment:

```json
{
  "context": {
    "environment": "production",
    "lambda_memory": 512,
    "log_retention_days": 30,
    "enable_detailed_monitoring": true
  }
}
```

### Terraform Variables

Create `terraform.tfvars` file:

```hcl
environment_name = "production"
lambda_memory_size = 512
log_retention_days = 30
vpc_cidr = "10.1.0.0/16"
enable_xray_insights = true
```

## Advanced Configuration

### Multi-Region Deployment

To deploy across multiple regions:

1. **CloudFormation**: Deploy stack in each target region
2. **CDK**: Use CDK Pipelines for cross-region deployment
3. **Terraform**: Use multiple provider blocks with aliases
4. **Scripts**: Modify region variables in deploy.sh

### Production Hardening

For production deployments, consider:

- **Security**: Enable AWS Config rules for compliance monitoring
- **Networking**: Use private subnets and VPC endpoints
- **Monitoring**: Add custom CloudWatch alarms and SNS notifications
- **Backup**: Enable point-in-time recovery for stateful resources
- **Scaling**: Configure auto-scaling for Lambda concurrency

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy Distributed Tracing
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      # For CDK deployment
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
      
      - name: Deploy with CDK
        run: |
          cd cdk-typescript
          npm install
          cdk deploy --require-approval never
```

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure your AWS credentials have sufficient permissions
2. **VPC Limits**: Check VPC and subnet limits in your account
3. **Lambda Concurrency**: Monitor for throttling during high load
4. **X-Ray Sampling**: Adjust sampling rules if trace volume is too high

### Debug Commands

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name distributed-tracing-stack

# View Lambda logs
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/order-service-*" \
    --order-by LastEventTime \
    --descending \
    --max-items 1

# Check X-Ray service statistics
aws xray get-service-graph \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

### Performance Optimization

- **Lambda**: Increase memory allocation for compute-intensive operations
- **X-Ray**: Adjust sampling rates to balance cost and observability
- **VPC Lattice**: Monitor target group health and adjust health check settings
- **CloudWatch**: Use log retention policies to manage costs

## Cost Optimization

### Estimated Costs (per month)

- **Lambda**: $5-10 (based on invocations and duration)
- **X-Ray**: $2-5 (based on trace volume)
- **VPC Lattice**: $3-8 (based on processed data)
- **CloudWatch**: $1-3 (logs and metrics storage)

### Cost-Saving Tips

1. **Lambda**: Use Graviton2 processors and optimize memory allocation
2. **X-Ray**: Implement intelligent sampling strategies
3. **Logs**: Set appropriate retention periods
4. **Monitoring**: Use CloudWatch alarms to detect and respond to cost spikes

## Security Considerations

This implementation follows AWS security best practices:

- **IAM**: Least privilege access with specific resource ARNs
- **Encryption**: Data in transit and at rest encryption
- **Networking**: VPC isolation and security group restrictions
- **Compliance**: AWS Config integration for continuous compliance monitoring

## Support and Documentation

### Additional Resources

- [Original Recipe Documentation](../distributed-service-tracing-lattice-xray.md)
- [AWS VPC Lattice Documentation](https://docs.aws.amazon.com/vpc-lattice/)
- [AWS X-Ray Developer Guide](https://docs.aws.amazon.com/xray/latest/devguide/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)

### Community Support

- [AWS re:Post](https://repost.aws/) for technical questions
- [AWS Architecture Center](https://aws.amazon.com/architecture/) for architectural guidance
- [GitHub Issues](https://github.com/aws/aws-cdk/issues) for CDK-specific issues

For issues with this infrastructure code, refer to the original recipe documentation or AWS service-specific documentation.

---

**Last Updated**: 2025-07-12  
**Recipe Version**: 1.1  
**IaC Generator Version**: 1.3