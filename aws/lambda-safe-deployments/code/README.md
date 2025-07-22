# Infrastructure as Code for Lambda Safe Deployments with Blue-Green and Canary

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Lambda Safe Deployments with Blue-Green and Canary".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for Lambda, API Gateway, CloudWatch, and IAM
- For CDK: Node.js 18+ or Python 3.9+
- For Terraform: Terraform 1.5+ installed
- Basic understanding of serverless deployment patterns

## Quick Start

### Using CloudFormation (AWS)

```bash
aws cloudformation create-stack \
    --stack-name lambda-deployment-patterns \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=RandomSuffix,ParameterValue=$(openssl rand -hex 3)
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/
npm install
npm run build
cdk deploy
```

### Using CDK Python (AWS)

```bash
cd cdk-python/
pip install -r requirements.txt
cdk deploy
```

### Using Terraform

```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This implementation deploys:

- **Lambda Function**: Serverless function with multiple versions
- **Function Versions**: Immutable snapshots (Version 1 and Version 2)
- **Function Alias**: Production alias for traffic routing
- **API Gateway**: REST API with Lambda integration
- **IAM Role**: Execution role with CloudWatch permissions
- **CloudWatch Alarm**: Error rate monitoring for deployments

## Deployment Patterns Supported

### Blue-Green Deployment
- Instant switching between stable environments
- Zero-downtime deployments
- Immediate rollback capability
- Binary traffic switching (0% or 100%)

### Canary Deployment
- Gradual traffic shifting (e.g., 10% to new version)
- Risk mitigation through limited exposure
- Real-world validation with subset of traffic
- Automated monitoring and rollback triggers

## Key Features

1. **Function Versioning**: Immutable code artifacts for reliable deployments
2. **Alias-based Routing**: Dynamic traffic distribution between versions
3. **Weighted Traffic**: Configurable percentage-based traffic splitting
4. **Monitoring Integration**: CloudWatch metrics and alarms
5. **Instant Rollback**: Immediate reversion to previous stable version
6. **API Gateway Integration**: Stable external interface during deployments

## Testing the Deployment

After deployment, test the endpoints:

```bash
# Get API Gateway URL from stack outputs
API_URL=$(aws cloudformation describe-stacks \
    --stack-name lambda-deployment-patterns \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
    --output text)

# Test current deployment
curl -s $API_URL | jq .

# Test multiple times to see traffic distribution during canary
for i in {1..10}; do
    curl -s $API_URL | jq -r '.body' | jq -r '.version + " - " + .environment'
    sleep 1
done
```

## Monitoring and Observability

### CloudWatch Metrics
- Function invocations by version
- Error rates and duration metrics
- Custom metrics for deployment validation

### CloudWatch Alarms
- Error rate threshold monitoring
- Automated alerting for deployment issues
- Integration with rollback procedures

### Logs
- Function execution logs by version
- API Gateway access logs
- Deployment activity tracking

## Customization

### Environment Variables
Modify deployment parameters by updating variables in each implementation:

- `FUNCTION_NAME`: Name of the Lambda function
- `API_NAME`: Name of the API Gateway
- `CANARY_PERCENTAGE`: Traffic percentage for canary deployments
- `ALARM_THRESHOLD`: Error rate threshold for monitoring

### Traffic Routing
Adjust traffic distribution in the alias configuration:

```bash
# Example: 20% canary traffic
aws lambda update-alias \
    --function-name $FUNCTION_NAME \
    --name production \
    --routing-config "AdditionalVersionWeights={\"1\"=0.8}"
```

### Function Code
Update the Lambda function code in the `lambda_function.py` files within each implementation to customize the application logic.

## Security Considerations

### IAM Permissions
- Least privilege principle for Lambda execution role
- API Gateway invoke permissions properly scoped
- CloudWatch logging permissions included

### Network Security
- API Gateway configured with appropriate CORS settings
- Function environment variables for sensitive configuration
- VPC integration available for enhanced security

## Best Practices

1. **Version Management**: Always publish new versions for production deployments
2. **Alias Strategy**: Use aliases for all production traffic routing
3. **Monitoring**: Implement comprehensive monitoring before deployment
4. **Rollback Planning**: Have automated rollback procedures ready
5. **Testing**: Validate deployments in staging environments first
6. **Documentation**: Maintain deployment logs and change records

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure Lambda execution role has CloudWatch permissions
2. **API Gateway Integration**: Verify Lambda permissions for API Gateway invoke
3. **Function Versions**: Check that versions are properly published
4. **Alias Configuration**: Validate alias routing configuration

### Debugging Commands

```bash
# Check Lambda function versions
aws lambda list-versions-by-function --function-name $FUNCTION_NAME

# Verify alias configuration
aws lambda get-alias --function-name $FUNCTION_NAME --name production

# Check API Gateway integration
aws apigateway get-integration --rest-api-id $API_ID --resource-id $RESOURCE_ID --http-method GET

# Review CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation (AWS)

```bash
aws cloudformation delete-stack --stack-name lambda-deployment-patterns
```

### Using CDK (AWS)

```bash
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Advanced Deployment Strategies

### Automated Canary Analysis
Implement automated canary analysis with:
- CloudWatch metric evaluation
- Automated rollback triggers
- Custom metric collection
- Error rate threshold monitoring

### Multi-Environment Pipeline
Extend to support:
- Development environment testing
- Staging environment validation
- Production deployment gates
- Approval workflows

### Integration with CI/CD
Connect with:
- AWS CodePipeline for automated deployments
- AWS CodeDeploy for Lambda deployments
- GitHub Actions for CI/CD workflows
- Jenkins for enterprise automation

## Cost Optimization

### Resource Costs
- Lambda invocations: Pay per request model
- API Gateway calls: Pay per API call
- CloudWatch metrics: Standard metric pricing
- Estimated cost: $1-5 for testing workloads

### Optimization Strategies
- Use provisioned concurrency for consistent performance
- Implement request/response caching in API Gateway
- Optimize function memory allocation
- Use ARM-based Graviton processors for cost savings

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../lambda-function-deployment-patterns-blue-green-canary.md)
- [AWS Lambda documentation](https://docs.aws.amazon.com/lambda/)
- [AWS API Gateway documentation](https://docs.aws.amazon.com/apigateway/)
- [AWS CloudFormation documentation](https://docs.aws.amazon.com/cloudformation/)
- [CDK documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/)