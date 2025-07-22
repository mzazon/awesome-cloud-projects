# Infrastructure as Code for Developing Distributed Serverless Applications with Aurora DSQL

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Developing Distributed Serverless Applications with Aurora DSQL".

## Solution Overview

This recipe demonstrates how to build a globally distributed serverless application using Aurora DSQL's active-active multi-region architecture. The solution provides strong consistency and automatic failover across regions while maintaining single-digit millisecond response times and eliminating infrastructure management overhead.

## Architecture Components

- **Aurora DSQL**: Multi-region distributed database with strong consistency
- **AWS Lambda**: Serverless compute functions in multiple regions
- **API Gateway**: Regional REST API endpoints
- **Route 53**: Global DNS and health checks (via extensions)
- **IAM**: Secure access policies and roles

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Aurora DSQL cluster management
  - Lambda function creation and management
  - API Gateway administration
  - IAM role and policy management
  - Route 53 (for DNS configuration)
- Basic understanding of multi-region architectures
- PostgreSQL knowledge for database operations

### Estimated Costs
- **Aurora DSQL**: $75-150/month for moderate usage (pay-per-use)
- **Lambda**: ~$5-20/month (based on request volume)
- **API Gateway**: ~$10-30/month (based on API calls)
- **Route 53**: ~$1-5/month (DNS queries and health checks)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions
- Understanding of CloudFormation stack management

#### CDK TypeScript
- Node.js 18+ and npm installed
- AWS CDK CLI installed: `npm install -g aws-cdk`
- TypeScript knowledge recommended

#### CDK Python
- Python 3.8+ installed
- AWS CDK CLI installed: `pip install aws-cdk-lib`
- Virtual environment recommended

#### Terraform
- Terraform 1.5+ installed
- Understanding of Terraform state management
- AWS provider configuration

## Quick Start

### Using CloudFormation

```bash
# Create the multi-region stack
aws cloudformation create-stack \
    --stack-name aurora-dsql-multi-region \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                 ParameterKey=SecondaryRegion,ParameterValue=us-east-2 \
                 ParameterKey=WitnessRegion,ParameterValue=us-west-2 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name aurora-dsql-multi-region \
    --query 'Stacks[0].StackStatus'

# Get API endpoints
aws cloudformation describe-stacks \
    --stack-name aurora-dsql-multi-region \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the application
cdk deploy --all

# View outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the application
cdk deploy --all

# View outputs
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

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
# (Script will output API endpoints and cluster information)
```

## Post-Deployment Validation

### Test Health Endpoints

```bash
# Test primary region (replace with actual endpoint)
curl -X GET "https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/health"

# Test secondary region
curl -X GET "https://your-api-id.execute-api.us-east-2.amazonaws.com/prod/health"
```

### Test Multi-Region Data Consistency

```bash
# Create user in primary region
curl -X POST "https://primary-api-endpoint/users" \
    -H "Content-Type: application/json" \
    -d '{"name":"Test User","email":"test@example.com"}'

# Verify user exists in secondary region immediately
curl -X GET "https://secondary-api-endpoint/users"
```

### Verify Aurora DSQL Cluster Status

```bash
# Check primary cluster
aws dsql get-cluster \
    --region us-east-1 \
    --cluster-identifier your-cluster-name \
    --query 'Cluster.Status'

# Check secondary cluster
aws dsql get-cluster \
    --region us-east-2 \
    --cluster-identifier your-cluster-name \
    --query 'Cluster.Status'
```

## Configuration Options

### Environment Variables

All implementations support customization through variables:

- **PRIMARY_REGION**: Primary AWS region (default: us-east-1)
- **SECONDARY_REGION**: Secondary AWS region (default: us-east-2)
- **WITNESS_REGION**: Witness region for Aurora DSQL (default: us-west-2)
- **CLUSTER_NAME_PREFIX**: Prefix for Aurora DSQL cluster names
- **LAMBDA_MEMORY_SIZE**: Memory allocation for Lambda functions (default: 512MB)
- **API_GATEWAY_STAGE**: API Gateway deployment stage (default: prod)

### CloudFormation Parameters

```yaml
Parameters:
  PrimaryRegion:
    Type: String
    Default: us-east-1
  SecondaryRegion:
    Type: String
    Default: us-east-2
  WitnessRegion:
    Type: String
    Default: us-west-2
```

### Terraform Variables

```hcl
variable "primary_region" {
  description = "Primary AWS region for Aurora DSQL cluster"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for Aurora DSQL cluster"
  type        = string
  default     = "us-east-2"
}
```

## Security Considerations

### IAM Policies
- Lambda functions use least-privilege IAM roles
- Aurora DSQL access is limited to necessary operations
- API Gateway uses proper CORS configuration

### Database Security
- Aurora DSQL clusters use encryption at rest
- IAM database authentication enabled
- Network isolation through VPC (where applicable)

### API Security
- API Gateway throttling configured
- CORS headers properly set
- Request validation enabled

## Monitoring and Observability

### CloudWatch Metrics
- Aurora DSQL cluster performance metrics
- Lambda function execution metrics
- API Gateway request and error rates

### Logging
- CloudWatch Logs for Lambda functions
- API Gateway access logs
- Aurora DSQL query logs (when enabled)

### X-Ray Tracing
- Distributed tracing across Lambda functions
- Aurora DSQL query tracing
- End-to-end request tracing

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name aurora-dsql-multi-region

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name aurora-dsql-multi-region \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# From CDK directory
cdk destroy --all

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **Aurora DSQL Cluster Creation Timeout**
   - Aurora DSQL clusters can take 10-15 minutes to become active
   - Verify witness region availability
   - Check AWS service health dashboard

2. **Lambda Function Timeout**
   - Increase timeout value in configuration
   - Check Aurora DSQL cluster status
   - Verify IAM permissions

3. **API Gateway 502 Errors**
   - Verify Lambda function permissions
   - Check Lambda execution role
   - Review CloudWatch logs for errors

4. **Cross-Region Consistency Issues**
   - Verify cluster peering configuration
   - Check multi-region properties
   - Ensure both clusters are in ACTIVE state

### Debugging Commands

```bash
# Check Aurora DSQL cluster status
aws dsql describe-clusters --region us-east-1

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Test API Gateway directly
aws apigateway test-invoke-method \
    --rest-api-id your-api-id \
    --resource-id your-resource-id \
    --http-method GET
```

## Performance Optimization

### Aurora DSQL
- Monitor query performance through CloudWatch metrics
- Optimize SQL queries for distributed architecture
- Use connection pooling in Lambda functions

### Lambda Functions
- Adjust memory allocation based on workload
- Implement connection reuse for database connections
- Use Lambda Provisioned Concurrency for consistent performance

### API Gateway
- Enable caching where appropriate
- Implement request throttling
- Use regional endpoints for better performance

## Extension Ideas

1. **Global Content Delivery**
   - Add CloudFront distribution
   - Implement Route 53 health checks
   - Configure automatic DNS failover

2. **Enhanced Security**
   - Add Amazon Cognito authentication
   - Implement API Gateway authorizers
   - Add WAF protection

3. **Advanced Monitoring**
   - Create CloudWatch dashboards
   - Set up automated alerts
   - Implement synthetic monitoring

4. **Caching Layer**
   - Add ElastiCache for Redis
   - Implement intelligent cache invalidation
   - Add cache warming strategies

## Support and Documentation

- [Aurora DSQL User Guide](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Please review and modify according to your organization's security and compliance requirements.