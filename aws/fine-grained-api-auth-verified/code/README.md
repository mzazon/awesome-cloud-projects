# Infrastructure as Code for Fine-Grained API Authorization with Verified Permissions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Fine-Grained API Authorization with Verified Permissions".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements an attribute-based access control (ABAC) system using:

- **Amazon Verified Permissions**: Centralized authorization engine with Cedar policy language
- **Amazon Cognito**: User authentication and identity management
- **API Gateway**: Secure API endpoints with custom authorization
- **Lambda Functions**: Authorization logic and business operations
- **DynamoDB**: Document storage and metadata

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Verified Permissions (full access)
  - Cognito (full access)
  - API Gateway (full access)
  - Lambda (full access)
  - DynamoDB (full access)
  - IAM (role and policy management)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- jq (for JSON processing in bash scripts)

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name fine-grained-authorization \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=RandomSuffix,ParameterValue=$(openssl rand -hex 3)
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build
cdk deploy --parameters randomSuffix=$(openssl rand -hex 3)
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk deploy --parameters randomSuffix=$(openssl rand -hex 3)
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan -var="random_suffix=$(openssl rand -hex 3)"
terraform apply -var="random_suffix=$(openssl rand -hex 3)"
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Post-Deployment Setup

After infrastructure deployment, you'll need to:

1. **Create Test Users**: Use the AWS Console or CLI to create users in the Cognito User Pool
2. **Configure Cedar Policies**: Review and adjust the generated Cedar policies for your use case
3. **Test Authorization**: Use the provided test scripts to validate different access scenarios

### Creating Test Users

```bash
# Set your deployed resources (replace with actual values from outputs)
export USER_POOL_ID="your-user-pool-id"
export USER_POOL_CLIENT_ID="your-client-id"

# Create admin user
aws cognito-idp admin-create-user \
    --user-pool-id "${USER_POOL_ID}" \
    --username "admin@company.com" \
    --temporary-password "TempPass123!" \
    --message-action SUPPRESS \
    --user-attributes \
        Name=email,Value="admin@company.com" \
        Name=custom:department,Value="IT" \
        Name=custom:role,Value="Admin"

# Set permanent password
aws cognito-idp admin-set-user-password \
    --user-pool-id "${USER_POOL_ID}" \
    --username "admin@company.com" \
    --password "AdminPass123!" \
    --permanent
```

## Testing the Solution

### Authentication Test

```bash
# Get access token for admin user
ADMIN_AUTH=$(aws cognito-idp admin-initiate-auth \
    --user-pool-id "${USER_POOL_ID}" \
    --client-id "${USER_POOL_CLIENT_ID}" \
    --auth-flow ADMIN_NO_SRP_AUTH \
    --auth-parameters USERNAME="admin@company.com",PASSWORD="AdminPass123!")

ADMIN_TOKEN=$(echo "${ADMIN_AUTH}" | jq -r '.AuthenticationResult.AccessToken')
```

### API Testing

```bash
# Test document creation (use API endpoint from deployment outputs)
curl -X POST "https://your-api-id.execute-api.region.amazonaws.com/prod/documents" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "title": "Test Document",
        "content": "This is a test document"
    }'
```

## Cedar Policy Examples

The solution includes several Cedar policies for different authorization scenarios:

### View Policy
```cedar
permit(
    principal,
    action == Action::"ViewDocument",
    resource
) when {
    principal.department == resource.department ||
    principal.role == "Manager" ||
    principal.role == "Admin"
};
```

### Edit Policy
```cedar
permit(
    principal,
    action == Action::"EditDocument",
    resource
) when {
    (principal.sub == resource.owner) ||
    (principal.role == "Manager" && principal.department == resource.department) ||
    principal.role == "Admin"
};
```

### Delete Policy
```cedar
permit(
    principal,
    action == Action::"DeleteDocument",
    resource
) when {
    principal.role == "Admin"
};
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name fine-grained-authorization
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
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

## Customization

### Key Variables/Parameters

- **RandomSuffix**: Unique identifier for resource naming
- **UserPoolName**: Name for the Cognito User Pool
- **PolicyStoreName**: Name for the Verified Permissions Policy Store
- **ApiName**: Name for the API Gateway
- **Region**: AWS region for deployment

### Modifying Cedar Policies

To customize authorization logic:

1. Edit the Cedar policy files in your chosen IaC implementation
2. Adjust the conditions based on your organizational requirements
3. Redeploy the infrastructure to apply changes

### Adding Custom User Attributes

To add new user attributes for authorization:

1. Update the Cognito User Pool schema in your IaC
2. Modify the Cedar policies to reference new attributes
3. Update the Lambda authorizer to extract new attributes from JWT tokens

## Security Considerations

- **Least Privilege**: The solution implements least privilege access through Cedar policies
- **Token Validation**: JWT tokens are validated against Cognito's public keys
- **Encryption**: All data is encrypted in transit and at rest
- **Audit Trail**: Authorization decisions are logged for compliance

## Monitoring and Logging

The solution includes:

- **CloudWatch Logs**: Lambda function execution logs
- **API Gateway Logs**: Request/response logging
- **Verified Permissions Logs**: Authorization decision logging
- **CloudTrail**: API-level audit trail

## Troubleshooting

### Common Issues

1. **Token Validation Errors**: Ensure JWT tokens are valid and not expired
2. **Policy Evaluation Failures**: Check Cedar policy syntax and logic
3. **Lambda Function Errors**: Review CloudWatch logs for detailed error messages
4. **API Gateway 403 Errors**: Verify custom authorizer configuration

### Debug Steps

1. Check CloudWatch logs for Lambda functions
2. Verify Cognito user attributes are correctly set
3. Test Cedar policies using the Verified Permissions console
4. Validate API Gateway method configurations

## Performance Considerations

- **Authorization Caching**: The Lambda authorizer caches results for 5 minutes
- **Cold Start Optimization**: Lambda functions are configured for optimal cold start performance
- **DynamoDB Performance**: Uses on-demand billing mode for automatic scaling

## Cost Optimization

- **Verified Permissions**: Charged per authorization request
- **Lambda**: Pay-per-invocation model
- **API Gateway**: REST API pricing
- **DynamoDB**: On-demand billing based on usage
- **Cognito**: Free tier includes 50,000 monthly active users

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for latest features
3. Refer to Cedar policy language documentation
4. Use AWS support channels for service-specific issues

## Related Resources

- [Amazon Verified Permissions User Guide](https://docs.aws.amazon.com/verifiedpermissions/latest/userguide/)
- [Cedar Policy Language Documentation](https://docs.cedarpolicy.com/)
- [AWS Security Best Practices](https://docs.aws.amazon.com/security/latest/userguide/best-practices.html)
- [API Gateway Lambda Authorizer Documentation](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-lambda-authorizer-lambda-function-create.html)