# Infrastructure as Code for Advanced API Gateway Deployment Strategies

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Advanced API Gateway Deployment Strategies".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - API Gateway (full access)
  - Lambda (full access)
  - CloudWatch (alarms and metrics)
  - IAM (role creation and policy attachment)
  - Route 53 (if using custom domains)
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $10-20 for testing environment

> **Note**: This recipe implements advanced API Gateway features including canary deployments which may incur additional charges beyond basic API Gateway usage.

## Architecture Overview

This infrastructure implements:

- **Blue-Green Deployment**: Two identical environments (Blue/Green) with instant switchover capability
- **Canary Releases**: Gradual traffic shifting (10% → 25% → 50% → 100%) with automated monitoring
- **Lambda Backend**: Separate functions for Blue and Green environments
- **CloudWatch Monitoring**: Automated alarms for error rates and latency
- **API Gateway Stages**: Production and staging environments with different configurations

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name advanced-api-deployment-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-api-project

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name advanced-api-deployment-stack \
    --query 'Stacks[0].StackStatus'

# Get API endpoint
aws cloudformation describe-stacks \
    --stack-name advanced-api-deployment-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Review deployment plan
cdk diff

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk ls --long
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Review deployment plan
cdk diff

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk ls --long
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

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the interactive prompts for configuration
# The script will create all resources and provide endpoint URLs

# To clean up later
./scripts/destroy.sh
```

## Testing the Deployment

After deployment, test the blue-green and canary functionality:

### 1. Test Blue Environment (Production)

```bash
# Get API endpoint from your deployment outputs
API_ENDPOINT="https://your-api-id.execute-api.region.amazonaws.com"

# Test production stage (Blue environment)
curl -s "${API_ENDPOINT}/production/hello" | jq '.'
# Expected: {"environment": "blue", "version": "v1.0.0", ...}
```

### 2. Test Green Environment (Staging)

```bash
# Test staging stage (Green environment)
curl -s "${API_ENDPOINT}/staging/hello" | jq '.'
# Expected: {"environment": "green", "version": "v2.0.0", ...}
```

### 3. Test Canary Traffic Distribution

```bash
# Test canary distribution (run multiple times)
for i in {1..20}; do
    response=$(curl -s "${API_ENDPOINT}/production/hello")
    environment=$(echo $response | jq -r '.environment')
    echo "Request $i: Environment = $environment"
    sleep 1
done
# Expected: Mix of "blue" and "green" responses based on canary percentage
```

### 4. Monitor CloudWatch Metrics

```bash
# View CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names "your-api-name-4xx-errors" "your-api-name-5xx-errors" "your-api-name-high-latency"

# Get API Gateway metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name Count \
    --dimensions Name=ApiName,Value=your-api-name Name=Stage,Value=production \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Deployment Strategies

### Canary Deployment Workflow

1. **Initial State**: 100% traffic to Blue environment
2. **Canary Start**: 10% traffic to Green, 90% to Blue
3. **Progressive Shift**: Gradually increase Green traffic (25%, 50%, 100%)
4. **Monitoring**: CloudWatch alarms monitor error rates and latency
5. **Rollback**: Automatic rollback if thresholds exceeded
6. **Promotion**: Full traffic shift to Green upon successful validation

### Blue-Green Deployment Workflow

1. **Deploy Green**: Update Green environment with new code
2. **Test Staging**: Validate Green environment in staging
3. **Canary Phase**: Use canary deployment for gradual validation
4. **Traffic Switch**: Atomic switch from Blue to Green
5. **Standby**: Keep Blue environment for instant rollback

## Configuration Options

### Environment Variables

Most implementations support these configuration options:

- `PROJECT_NAME`: Base name for all resources (default: advanced-api-deployment)
- `AWS_REGION`: AWS region for deployment (default: us-east-1)
- `CANARY_PERCENTAGE`: Initial canary traffic percentage (default: 10)
- `ERROR_THRESHOLD`: Error rate threshold for alarms (default: 5)
- `LATENCY_THRESHOLD`: Response time threshold in ms (default: 5000)

### Customization Parameters

- **Lambda Runtime**: Modify function runtime versions
- **API Gateway Settings**: Adjust throttling and caching settings
- **CloudWatch Alarms**: Customize alarm thresholds and actions
- **Monitoring**: Configure additional metrics and dashboards

## Operational Procedures

### Manual Traffic Shifting

```bash
# Increase canary traffic to 25%
aws apigateway update-stage \
    --rest-api-id YOUR_API_ID \
    --stage-name production \
    --patch-operations "op=replace,path=/canarySettings/percentTraffic,value=25"

# Promote to full production (100% Green)
aws apigateway update-stage \
    --rest-api-id YOUR_API_ID \
    --stage-name production \
    --patch-operations "op=remove,path=/canarySettings"
```

### Emergency Rollback

```bash
# Immediate rollback to Blue environment
aws apigateway update-stage \
    --rest-api-id YOUR_API_ID \
    --stage-name production \
    --patch-operations "op=remove,path=/canarySettings"
```

### Monitoring Commands

```bash
# Check deployment status
aws apigateway get-stage \
    --rest-api-id YOUR_API_ID \
    --stage-name production \
    --query 'canarySettings'

# View recent error rates
aws logs filter-log-events \
    --log-group-name API-Gateway-Execution-Logs_YOUR_API_ID/production \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name advanced-api-deployment-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name advanced-api-deployment-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Navigate to your CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions for all services
2. **Resource Limits**: Check AWS service quotas for API Gateway and Lambda in your region
3. **Deployment Timeouts**: Some resources may take time to propagate; wait and retry
4. **Canary Not Working**: Verify canary settings are applied correctly using AWS CLI

### Debug Commands

```bash
# Check API Gateway configuration
aws apigateway get-rest-api --rest-api-id YOUR_API_ID

# Verify Lambda functions exist
aws lambda list-functions --query 'Functions[?contains(FunctionName, `blue`) || contains(FunctionName, `green`)]'

# Check CloudWatch alarm states
aws cloudwatch describe-alarms --state-value ALARM
```

### Validation Steps

1. **API Endpoints**: Verify both `/production/hello` and `/staging/hello` return expected responses
2. **Traffic Distribution**: Confirm canary traffic splitting works as expected
3. **Monitoring**: Check that CloudWatch alarms are created and functional
4. **Rollback**: Test emergency rollback procedures
5. **Cleanup**: Verify all resources are properly removed during cleanup

## Security Considerations

- **IAM Roles**: All Lambda functions use least-privilege IAM roles
- **API Gateway**: Configure API keys and usage plans for production use
- **CloudWatch**: Logs may contain sensitive data; configure retention policies
- **Network**: Consider VPC endpoints for enhanced security
- **Encryption**: Enable encryption in transit for all API communications

## Performance Optimization

- **Caching**: Enable API Gateway caching for improved response times
- **Lambda**: Optimize function memory and timeout settings
- **Monitoring**: Set up detailed CloudWatch metrics and alarms
- **Throttling**: Configure API Gateway throttling to prevent abuse

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for the latest API changes
3. Verify your AWS permissions and service quotas
4. Test in a development environment before production deployment

## Additional Resources

- [AWS API Gateway Documentation](https://docs.aws.amazon.com/apigateway/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)