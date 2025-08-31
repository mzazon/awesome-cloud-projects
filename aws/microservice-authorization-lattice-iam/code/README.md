# Infrastructure as Code for Microservice Authorization with VPC Lattice and IAM

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Microservice Authorization with VPC Lattice and IAM".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure implements a zero-trust microservice authorization framework using:

- **VPC Lattice Service Network**: Application networking layer with IAM authentication
- **VPC Lattice Service**: Exposes order service with fine-grained access controls
- **Lambda Functions**: Microservices (product service client, order service provider)
- **IAM Roles**: Service identity management for zero-trust authentication
- **Authorization Policies**: Fine-grained access control with conditional logic
- **CloudWatch**: Monitoring, logging, and alerting for authorization events

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for:
  - VPC Lattice (service networks, services, auth policies)
  - IAM (roles, policies)
  - Lambda (functions, permissions)
  - CloudWatch (log groups, alarms)
- Basic understanding of IAM roles, policies, and JSON syntax
- Familiarity with microservices architecture concepts

## Estimated Costs

- **VPC Lattice**: ~$0.025 per processed request + data processing charges
- **Lambda**: Pay-per-invocation (free tier: 1M requests/month)
- **CloudWatch**: Log storage and alarm monitoring (~$0.10-$0.50 for testing)

> **Note**: VPC Lattice is available in select AWS regions. Verify regional availability before deployment.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name microservice-authorization-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name microservice-authorization-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name microservice-authorization-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time in region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time in region)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

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

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Validation & Testing

After deployment, validate the infrastructure:

### 1. Verify VPC Lattice Resources

```bash
# Get service network ID from outputs
SERVICE_NETWORK_ID=$(aws cloudformation describe-stacks \
    --stack-name microservice-authorization-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceNetworkId`].OutputValue' \
    --output text)

# Check service network status
aws vpc-lattice get-service-network \
    --service-network-identifier $SERVICE_NETWORK_ID
```

### 2. Test Lambda Functions

```bash
# Get function names from outputs
PRODUCT_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name microservice-authorization-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ProductServiceFunction`].OutputValue' \
    --output text)

# Test product service
aws lambda invoke \
    --function-name $PRODUCT_FUNCTION \
    --payload '{"test": "authorized_request"}' \
    response.json && cat response.json
```

### 3. Monitor Authorization Events

```bash
# Check access logs
LOG_GROUP="/aws/vpclattice/microservices-network"
aws logs describe-log-streams \
    --log-group-name $LOG_GROUP \
    --order-by LastEventTime \
    --descending
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name microservice-authorization-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name microservice-authorization-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the stack
cdk destroy --force
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are deleted
./scripts/verify-cleanup.sh
```

## Customization

### Environment Variables

All implementations support customization through variables:

- **Environment**: Deployment environment (dev, staging, prod)
- **ResourcePrefix**: Prefix for resource naming
- **Region**: AWS region for deployment
- **EnableLogging**: Enable/disable CloudWatch logging
- **AlertThreshold**: Threshold for authorization failure alerts

### CloudFormation Parameters

```yaml
Parameters:
  Environment:
    Type: String
    Default: demo
    AllowedValues: [dev, staging, prod]
  
  ResourcePrefix:
    Type: String
    Default: microservice-auth
  
  EnableDetailedLogging:
    Type: String
    Default: "true"
    AllowedValues: ["true", "false"]
```

### CDK Context Variables

```json
{
  "environment": "demo",
  "resourcePrefix": "microservice-auth",
  "enableDetailedLogging": true,
  "alertThreshold": 5
}
```

### Terraform Variables

```hcl
variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource naming"
  type        = string
  default     = "microservice-auth"
}
```

## Security Considerations

### IAM Permissions

The infrastructure implements least privilege access:

- **Service Roles**: Each microservice has minimal required permissions
- **Authorization Policies**: Fine-grained access control with conditions
- **Resource Isolation**: Services can only access authorized resources

### Network Security

- **Zero-Trust Architecture**: All communications require authentication
- **VPC Lattice Auth**: IAM-based service-to-service authorization
- **Access Logging**: Comprehensive audit trail for all requests

### Monitoring & Alerting

- **CloudWatch Alarms**: Alert on authorization failures
- **Access Logs**: Detailed logging of all service interactions
- **Metrics**: Real-time visibility into authorization performance

## Troubleshooting

### Common Issues

1. **VPC Lattice Not Available**: Verify region supports VPC Lattice
2. **IAM Permission Errors**: Ensure deployment role has necessary permissions
3. **Lambda Timeout**: Increase timeout for Lambda functions if needed
4. **Authorization Failures**: Check auth policy conditions and IAM roles

### Debug Commands

```bash
# Check VPC Lattice service status
aws vpc-lattice get-service --service-identifier <SERVICE_ID>

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/

# Test IAM role permissions
aws sts assume-role --role-arn <ROLE_ARN> --role-session-name test

# Validate authorization policy
aws vpc-lattice get-auth-policy --resource-identifier <SERVICE_ID>
```

## Architecture Benefits

- **Zero-Trust Security**: Every request is authenticated and authorized
- **Scalable Communication**: Service mesh scales with microservice growth
- **Fine-Grained Control**: Conditional access based on multiple factors
- **Operational Visibility**: Comprehensive monitoring and logging
- **Cross-VPC Communication**: Seamless networking across VPC boundaries

## Extensions & Enhancements

Consider these enhancements for production deployments:

1. **Multi-Environment Support**: Separate auth policies per environment
2. **Cross-Account Access**: Use AWS RAM for cross-account service sharing
3. **External Identity Integration**: Connect to enterprise identity providers
4. **Advanced Monitoring**: Implement X-Ray tracing and custom metrics
5. **Automated Policy Management**: Use Lambda to dynamically update policies

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS VPC Lattice documentation
3. Validate IAM permissions and policies
4. Review CloudWatch logs for detailed error information
5. Consult AWS support for service-specific issues

## Additional Resources

- [AWS VPC Lattice Documentation](https://docs.aws.amazon.com/vpc-lattice/)
- [VPC Lattice Auth Policies](https://docs.aws.amazon.com/vpc-lattice/latest/ug/auth-policies.html)
- [AWS Well-Architected Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
- [VPC Lattice Best Practices](https://docs.aws.amazon.com/vpc-lattice/latest/ug/security-best-practices.html)