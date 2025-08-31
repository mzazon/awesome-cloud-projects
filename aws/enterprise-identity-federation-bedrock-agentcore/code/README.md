# Infrastructure as Code for Enterprise Identity Federation with Bedrock AgentCore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Identity Federation with Bedrock AgentCore".

## Overview

This solution implements a comprehensive enterprise identity federation system using Bedrock AgentCore Identity as the foundation for AI agent management, integrated with Cognito User Pools for SAML federation with corporate identity providers. The infrastructure provides secure, auditable access control for AI agents accessing both internal AWS resources and external third-party services through standardized authentication protocols.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML format)
- **CDK TypeScript**: AWS Cloud Development Kit with TypeScript
- **CDK Python**: AWS Cloud Development Kit with Python
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Configuration Language
- **Scripts**: Bash deployment and cleanup automation scripts

## Architecture Components

The infrastructure deploys the following key components:

- **Amazon Cognito User Pool** with SAML 2.0 federation for enterprise identity providers
- **AWS Lambda** functions for custom authentication flows and permission mapping
- **Bedrock AgentCore Workload Identity** for specialized AI agent identity management
- **IAM Roles and Policies** implementing least-privilege access control
- **OAuth 2.0 configuration** for third-party API integration
- **Systems Manager Parameter Store** for configuration management

## Prerequisites

### General Requirements

- AWS account with appropriate permissions for Bedrock, Cognito, IAM, and Lambda services
- AWS CLI v2 installed and configured (or CloudShell access)
- Understanding of SAML 2.0, OAuth 2.0, and enterprise identity concepts
- Access to enterprise SAML identity provider configuration
- **Bedrock AgentCore access** (currently in preview - request access through AWS Console)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- IAM permissions to create roles and policies

#### CDK (TypeScript/Python)
- Node.js 18+ (for TypeScript implementation)
- Python 3.8+ (for Python implementation)
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- CDK bootstrapped in target region

#### Terraform
- Terraform 1.0+ installed
- AWS provider 5.0+ compatible

#### Bash Scripts
- Bash shell environment
- jq for JSON processing
- AWS CLI configured with appropriate permissions

### Estimated Costs

- Development environment: $15-30/month
- Production environment: $50-100/month (varies by usage)
- Primary costs: Lambda invocations, Cognito MAU, AgentCore usage

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete infrastructure stack
aws cloudformation create-stack \
    --stack-name enterprise-identity-federation \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=EnterpriseIdPMetadataURL,ParameterValue=https://your-enterprise-idp.com/metadata \
                 ParameterKey=CallbackURL,ParameterValue=https://your-app.company.com/oauth/callback \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --tags Key=Environment,Value=Production Key=Project,Value=BedrockAgentCore

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name enterprise-identity-federation \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name enterprise-identity-federation \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export ENTERPRISE_IDP_METADATA_URL="https://your-enterprise-idp.com/metadata"
export CALLBACK_URL="https://your-app.company.com/oauth/callback"

# Deploy the stack
cdk bootstrap  # Run once per region
cdk deploy --parameters enterpriseIdPMetadataURL=${ENTERPRISE_IDP_METADATA_URL} \
           --parameters callbackURL=${CALLBACK_URL}

# View stack outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
export ENTERPRISE_IDP_METADATA_URL="https://your-enterprise-idp.com/metadata"
export CALLBACK_URL="https://your-app.company.com/oauth/callback"

# Deploy the stack
cdk bootstrap  # Run once per region
cdk deploy --parameters enterpriseIdPMetadataURL=${ENTERPRISE_IDP_METADATA_URL} \
           --parameters callbackURL=${CALLBACK_URL}

# View stack outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="enterprise_idp_metadata_url=https://your-enterprise-idp.com/metadata" \
    -var="callback_url=https://your-app.company.com/oauth/callback" \
    -var="environment=production"

# Apply the configuration
terraform apply \
    -var="enterprise_idp_metadata_url=https://your-enterprise-idp.com/metadata" \
    -var="callback_url=https://your-app.company.com/oauth/callback" \
    -var="environment=production"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export ENTERPRISE_IDP_METADATA_URL="https://your-enterprise-idp.com/metadata"
export CALLBACK_URL="https://your-app.company.com/oauth/callback"
export AWS_REGION="us-east-1"

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for confirmation before creating resources
# and display progress throughout the deployment process
```

## Configuration

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `enterprise_idp_metadata_url` | SAML metadata URL from your enterprise identity provider | `https://company.okta.com/app/metadata` |
| `callback_url` | OAuth callback URL for your application | `https://app.company.com/oauth/callback` |
| `environment` | Deployment environment (development/staging/production) | `production` |

### Optional Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `user_pool_name` | Name for the Cognito User Pool | `enterprise-ai-agents` |
| `lambda_memory_size` | Memory allocation for Lambda functions | `256` |
| `token_validity_hours` | JWT token validity period in hours | `1` |
| `max_agents_per_user` | Maximum AI agents per enterprise user | `10` |

### Environment-Specific Configuration

#### Development Environment
```bash
# Lower resource limits and costs
export MAX_AGENTS_PER_USER=3
export LAMBDA_MEMORY_SIZE=128
export TOKEN_VALIDITY_HOURS=8
```

#### Production Environment
```bash
# Production-ready configuration
export MAX_AGENTS_PER_USER=10
export LAMBDA_MEMORY_SIZE=256
export TOKEN_VALIDITY_HOURS=1
export ENABLE_MFA=true
export ENABLE_ADVANCED_SECURITY=true
```

## Post-Deployment Configuration

### 1. Enterprise Identity Provider Setup

After deployment, configure your enterprise identity provider (Okta, Azure AD, etc.) with the SAML settings:

```bash
# Get SAML configuration from stack outputs
aws cloudformation describe-stacks \
    --stack-name enterprise-identity-federation \
    --query 'Stacks[0].Outputs[?OutputKey==`SAMLEntityId`].OutputValue' \
    --output text

# Configure these values in your enterprise IdP:
# - Entity ID: From stack output
# - ACS URL: From stack output  
# - Attribute mappings: email, name, department
```

### 2. Test Authentication Flow

```bash
# Test the complete authentication flow
python3 << 'EOF'
import boto3
import json

# Initialize clients
cognito = boto3.client('cognito-idp')
agentcore = boto3.client('bedrock-agentcore-control')

# Get User Pool details
user_pools = cognito.list_user_pools(MaxResults=50)
print("Available User Pools:")
for pool in user_pools['UserPools']:
    print(f"  - {pool['Name']}: {pool['Id']}")

# Get AgentCore identities
identities = agentcore.list_workload_identities()
print("\nAgentCore Workload Identities:")
for identity in identities['workloadIdentities']:
    print(f"  - {identity['name']}: {identity['workloadIdentityArn']}")
EOF
```

### 3. Configure Agent Permissions

```bash
# Update agent permission mappings based on your enterprise roles
aws ssm put-parameter \
    --name "/enterprise/agentcore/permission-mappings" \
    --value '{
        "engineering": {
            "maxAgents": 10,
            "allowedActions": ["create", "read", "update", "delete"],
            "resourceAccess": ["bedrock", "s3", "lambda"]
        },
        "security": {
            "maxAgents": 5,
            "allowedActions": ["create", "read", "update", "delete", "audit"],
            "resourceAccess": ["bedrock", "iam", "cloudtrail"]
        },
        "general": {
            "maxAgents": 2,
            "allowedActions": ["read"],
            "resourceAccess": ["bedrock"]
        }
    }' \
    --type String \
    --overwrite
```

## Validation & Testing

### Infrastructure Validation

```bash
# Validate CloudFormation stack
aws cloudformation validate-template \
    --template-body file://cloudformation.yaml

# Test Terraform configuration
cd terraform/
terraform validate
terraform plan -detailed-exitcode

# Validate CDK synthesis
cd cdk-typescript/
cdk synth
```

### Functional Testing

```bash
# Test Cognito User Pool configuration
aws cognito-idp describe-user-pool \
    --user-pool-id $(aws cloudformation describe-stacks \
        --stack-name enterprise-identity-federation \
        --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
        --output text)

# Test Lambda function
aws lambda invoke \
    --function-name $(aws cloudformation describe-stacks \
        --stack-name enterprise-identity-federation \
        --query 'Stacks[0].Outputs[?OutputKey==`AuthHandlerFunctionName`].OutputValue' \
        --output text) \
    --payload '{"triggerSource":"PostAuthentication_Authentication","request":{"userAttributes":{"email":"test@company.com","custom:department":"engineering"}}}' \
    response.json

cat response.json
```

## Monitoring & Observability

### CloudWatch Dashboards

The infrastructure creates CloudWatch dashboards for monitoring:

- **Authentication Metrics**: Login success/failure rates, SAML assertion processing
- **Lambda Performance**: Function duration, error rates, memory utilization
- **AgentCore Activity**: Agent creation/deletion events, permission changes

### Logging Configuration

```bash
# View authentication logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/agent-auth-handler \
    --start-time $(date -d '1 hour ago' +%s)000

# Monitor Cognito events
aws logs filter-log-events \
    --log-group-name /aws/cognito/userpools \
    --filter-pattern "ERROR"
```

### Alerting Setup

Key CloudWatch alarms are configured for:

- Authentication failure threshold exceeded
- Lambda function errors
- AgentCore workload identity creation failures
- Unusual permission escalation attempts

## Security Considerations

### Least Privilege Access

The infrastructure implements least privilege principles:

- IAM roles have minimal required permissions
- Agent identities are scoped to specific resource access
- Cross-service access uses assume-role patterns

### Data Protection

- All data in transit uses TLS encryption
- Secrets stored in AWS Secrets Manager
- JWT tokens have short expiration times
- SAML assertions are validated cryptographically

### Compliance Features

- Complete audit trail through CloudTrail
- Role-based access control (RBAC)
- Separation of duties for agent management
- Regular access reviews through automated reports

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name enterprise-identity-federation

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name enterprise-identity-federation

# Verify stack deletion
aws cloudformation describe-stacks \
    --stack-name enterprise-identity-federation 2>/dev/null || echo "Stack successfully deleted"
```

### Using CDK

```bash
# TypeScript
cd cdk-typescript/
cdk destroy --force

# Python
cd cdk-python/
cdk destroy --force
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="enterprise_idp_metadata_url=https://your-enterprise-idp.com/metadata" \
    -var="callback_url=https://your-app.company.com/oauth/callback" \
    -var="environment=production"

# Clean up Terraform state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
# and verify deletion of all components
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
aws cognito-idp list-user-pools --max-items 50 | grep -i enterprise || echo "No User Pools found"
aws lambda list-functions | grep -i agent-auth || echo "No Lambda functions found"
aws bedrock-agentcore-control list-workload-identities | jq '.workloadIdentities[].name' | grep -i enterprise || echo "No AgentCore identities found"
```

## Troubleshooting

### Common Issues

#### 1. Bedrock AgentCore Access Denied
```bash
# Verify AgentCore is enabled in your region
aws bedrock-agentcore-control list-workload-identities 2>&1 | grep -i "not enabled\|access denied" && \
echo "Request AgentCore access through AWS Console"
```

#### 2. SAML Configuration Issues
```bash
# Validate SAML metadata URL
curl -f ${ENTERPRISE_IDP_METADATA_URL} > /dev/null && \
echo "SAML metadata accessible" || \
echo "SAML metadata URL unreachable"
```

#### 3. Lambda Permission Errors
```bash
# Check Lambda execution role permissions
aws iam get-role-policy \
    --role-name $(aws cloudformation describe-stacks \
        --stack-name enterprise-identity-federation \
        --query 'Stacks[0].Outputs[?OutputKey==`AuthHandlerRoleName`].OutputValue' \
        --output text) \
    --policy-name LambdaExecutionPolicy
```

### Getting Support

For issues with this infrastructure:

1. **Review CloudWatch Logs**: Check function logs and CloudTrail events
2. **Validate Configuration**: Ensure all parameters are correctly set
3. **Check Service Limits**: Verify AWS service quotas haven't been exceeded
4. **Reference Documentation**: Consult AWS documentation for each service
5. **AWS Support**: Contact AWS Support for service-specific issues

## Customization

### Adding Custom Departments

Modify the permission mapping in the Lambda function or SSM Parameter:

```python
# Add new department permissions
permission_map = {
    'finance': {
        'canCreateAgents': True,
        'canDeleteAgents': False,
        'maxAgents': 3,
        'allowedServices': ['bedrock', 's3']
    },
    # ... existing mappings
}
```

### Extending OAuth Scopes

Update the Cognito App Client configuration:

```bash
# Add additional OAuth scopes
aws cognito-idp update-user-pool-client \
    --user-pool-id ${USER_POOL_ID} \
    --client-id ${CLIENT_ID} \
    --allowed-o-auth-scopes "openid" "email" "profile" "custom:department" "custom:role"
```

### Multi-Region Deployment

Deploy the infrastructure in multiple regions for high availability:

```bash
# Deploy to multiple regions
for region in us-east-1 us-west-2 eu-west-1; do
    export AWS_REGION=$region
    ./scripts/deploy.sh
done
```

## Cost Optimization

### Development Environment

- Use smaller Lambda memory allocations (128MB)
- Implement shorter token expiration times
- Limit the number of test users

### Production Environment

- Monitor Cognito Monthly Active Users (MAU)
- Optimize Lambda memory based on CloudWatch metrics
- Use Reserved Capacity for predictable workloads
- Implement lifecycle policies for log retention

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **AWS Services**: Bedrock AgentCore, Cognito, Lambda, IAM, Systems Manager
- **Minimum AWS CLI Version**: 2.0
- **Terraform Provider Versions**: AWS Provider 5.0+, Bedrock AgentCore Provider (preview)

---

For additional information, refer to the original recipe documentation or AWS service documentation.