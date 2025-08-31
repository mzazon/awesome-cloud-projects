# Enterprise Identity Federation with Bedrock AgentCore - CDK TypeScript

This CDK TypeScript application implements a comprehensive enterprise identity federation system using Bedrock AgentCore Identity as the foundation for AI agent management, integrated with Cognito User Pools for SAML federation with corporate identity providers.

## Architecture Overview

The solution implements:

- **Cognito User Pool** with enterprise-grade security policies and SAML 2.0 federation
- **Lambda Authentication Handler** for custom business logic and permission mapping
- **IAM Roles and Policies** implementing least-privilege access for AI agents
- **Bedrock AgentCore Integration** for specialized AI agent identity management
- **OAuth 2.0 Flows** for secure token exchange and third-party API integration
- **SSM Parameter Store** for centralized configuration management

## Prerequisites

1. **AWS Account** with appropriate permissions for:
   - Amazon Cognito
   - AWS Lambda
   - AWS IAM
   - Amazon Bedrock (with AgentCore preview access)
   - AWS Systems Manager Parameter Store

2. **Development Environment**:
   - Node.js 18+ and npm 8+
   - AWS CLI v2 configured
   - AWS CDK v2 installed globally: `npm install -g aws-cdk`
   - TypeScript installed: `npm install -g typescript`

3. **Enterprise Prerequisites**:
   - Access to enterprise SAML identity provider configuration
   - Understanding of SAML 2.0, OAuth 2.0, and enterprise identity concepts
   - Bedrock AgentCore preview access (request through AWS console)

## Installation

1. **Install Dependencies**:
   ```bash
   npm install
   ```

2. **Compile TypeScript**:
   ```bash
   npm run build
   ```

3. **Bootstrap CDK** (if not already done):
   ```bash
   npm run bootstrap
   ```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
# Required: AWS Account and Region
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Optional: Enterprise SAML IdP Metadata URL
export ENTERPRISE_IDP_METADATA_URL="https://your-enterprise-idp.com/metadata"

# Optional: OAuth Callback URLs (comma-separated)
export OAUTH_CALLBACK_URLS="https://your-app.company.com/oauth/callback,https://localhost:8080/callback"

# Optional: Authorized Email Domains (comma-separated)
export AUTHORIZED_EMAIL_DOMAINS="@company.com,@enterprise.org"
```

### CDK Context

Alternatively, you can set configuration via CDK context:

```bash
cdk deploy -c enterpriseIdpMetadataUrl="https://your-enterprise-idp.com/metadata" \
           -c oauthCallbackUrls="https://your-app.company.com/oauth/callback" \
           -c authorizedEmailDomains="@company.com,@enterprise.org"
```

## Deployment

### 1. Deploy the Stack

```bash
# Deploy with default configuration
npm run deploy

# Or deploy with specific configuration
cdk deploy -c enterpriseIdpMetadataUrl="https://your-idp.com/metadata"
```

### 2. Create Bedrock AgentCore Workload Identity

After stack deployment, create the AgentCore workload identity using the output command:

```bash
# Use the command from stack outputs
aws bedrock-agentcore-control create-workload-identity \
    --name enterprise-agent-XXXXXX \
    --allowed-resource-oauth2-return-urls '["https://your-app.company.com/oauth/callback"]'
```

### 3. Configure Enterprise SAML Identity Provider

If you didn't provide the SAML metadata URL during deployment, configure it manually:

```bash
# Get the User Pool ID from stack outputs
USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name EnterpriseIdentityFederationStack \
    --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
    --output text)

# Create SAML identity provider
aws cognito-idp create-identity-provider \
    --user-pool-id $USER_POOL_ID \
    --provider-name "EnterpriseSSO" \
    --provider-type "SAML" \
    --provider-details '{
        "MetadataURL": "https://your-enterprise-idp.com/metadata",
        "SLORedirectBindingURI": "https://your-enterprise-idp.com/slo",
        "SSORedirectBindingURI": "https://your-enterprise-idp.com/sso"
    }' \
    --attribute-mapping '{
        "email": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
        "name": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
        "custom:department": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/department"
    }'
```

## Validation and Testing

### 1. Verify Stack Deployment

```bash
# Check stack status
aws cloudformation describe-stacks \
    --stack-name EnterpriseIdentityFederationStack \
    --query 'Stacks[0].StackStatus'

# List stack outputs
aws cloudformation describe-stacks \
    --stack-name EnterpriseIdentityFederationStack \
    --query 'Stacks[0].Outputs'
```

### 2. Test Lambda Function

```bash
# Get Lambda function name from outputs
LAMBDA_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name EnterpriseIdentityFederationStack \
    --query 'Stacks[0].Outputs[?OutputKey==`AuthenticationHandlerArn`].OutputValue' \
    --output text | cut -d':' -f7)

# Create test event
cat > test-event.json << 'EOF'
{
    "triggerSource": "PostAuthentication_Authentication",
    "request": {
        "userAttributes": {
            "email": "test.user@company.com",
            "custom:department": "engineering"
        }
    },
    "response": {}
}
EOF

# Test Lambda function
aws lambda invoke \
    --function-name $LAMBDA_FUNCTION_NAME \
    --payload file://test-event.json \
    --output-file lambda-response.json

cat lambda-response.json
```

### 3. Verify Cognito Configuration

```bash
# Get User Pool ID
USER_POOL_ID=$(aws cloudformation describe-stacks \
    --stack-name EnterpriseIdentityFederationStack \
    --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
    --output text)

# Verify User Pool configuration
aws cognito-idp describe-user-pool \
    --user-pool-id $USER_POOL_ID \
    --query 'UserPool.{Name:Name,Id:Id,Status:Status,LambdaConfig:LambdaConfig}'

# List identity providers
aws cognito-idp list-identity-providers \
    --user-pool-id $USER_POOL_ID
```

### 4. Test AgentCore Workload Identity

```bash
# List workload identities
aws bedrock-agentcore-control list-workload-identities

# Get specific workload identity (replace with your identity name)
aws bedrock-agentcore-control get-workload-identity \
    --name enterprise-agent-XXXXXX
```

## Customization

### Department-Based Permissions

The Lambda function includes department-based permission mapping. Modify the `determine_agent_permissions` function in `app.ts` to customize:

```python
# Example permission mapping in Lambda function
permission_map = {
    'engineering': {
        'canCreateAgents': True,
        'canDeleteAgents': True,
        'maxAgents': 10,
        'allowedServices': ['bedrock', 's3', 'lambda']
    },
    'security': {
        'canCreateAgents': True,
        'canDeleteAgents': True,
        'maxAgents': 5,
        'allowedServices': ['bedrock', 'iam', 'cloudtrail']
    },
    'general': {
        'canCreateAgents': False,
        'canDeleteAgents': False,
        'maxAgents': 2,
        'allowedServices': ['bedrock']
    }
}
```

### IAM Policies

Customize the AgentCore access policies in the `AgentCoreAccessPolicy` managed policy:

```typescript
// Add or modify IAM policy statements
new iam.PolicyStatement({
  effect: iam.Effect.ALLOW,
  actions: [
    'bedrock:InvokeModel',
    'bedrock:InvokeModelWithResponseStream',
    'bedrock:ListFoundationModels',
    // Add additional Bedrock actions as needed
  ],
  resources: ['*'],
  conditions: {
    StringEquals: {
      'aws:RequestedRegion': this.region,
    },
  },
}),
```

### OAuth Configuration

Modify OAuth flows and scopes in the User Pool Client configuration:

```typescript
oAuth: {
  flows: {
    authorizationCodeGrant: true,
    implicitCodeGrant: true,
    // clientCredentials: true, // Uncomment for machine-to-machine flows
  },
  scopes: [
    cognito.OAuthScope.OPENID,
    cognito.OAuthScope.EMAIL,
    cognito.OAuthScope.PROFILE,
    cognito.OAuthScope.COGNITO_ADMIN,
    // Add custom scopes as needed
  ],
  callbackUrls: ['https://your-app.company.com/oauth/callback'],
  logoutUrls: ['https://your-app.company.com/logout'],
},
```

## Development

### Build and Test

```bash
# Compile TypeScript
npm run build

# Watch for changes
npm run watch

# Run linting
npm run lint

# Fix linting issues
npm run lint:fix

# Format code
npm run format

# Run tests
npm test

# Run tests in watch mode
npm run test:watch
```

### CDK Commands

```bash
# Show differences between deployed stack and local changes
npm run diff

# Synthesize CloudFormation template
npm run synth

# Deploy stack
npm run deploy

# Destroy stack
npm run destroy
```

## Cleanup

### 1. Delete Bedrock AgentCore Workload Identity

```bash
# Delete workload identity (replace with your identity name)
aws bedrock-agentcore-control delete-workload-identity \
    --name enterprise-agent-XXXXXX
```

### 2. Destroy CDK Stack

```bash
npm run destroy
```

### 3. Clean Local Files

```bash
npm run clean
```

## Security Considerations

### Production Deployment

For production environments, consider these security enhancements:

1. **Enable MFA**: Configure mandatory MFA for all users
2. **Network Isolation**: Deploy in private subnets with VPC endpoints
3. **Secrets Management**: Use AWS Secrets Manager for sensitive configuration
4. **Monitoring**: Enable CloudTrail, CloudWatch, and X-Ray for comprehensive monitoring
5. **Compliance**: Implement additional controls for regulatory requirements (SOC 2, ISO 27001)

### IAM Best Practices

1. **Least Privilege**: Review and minimize IAM permissions regularly
2. **Role Separation**: Use different roles for different AI agent types
3. **Conditional Access**: Implement additional IAM conditions based on context
4. **Audit Trails**: Enable comprehensive logging for all actions

### OAuth Security

1. **Token Rotation**: Implement automatic token rotation
2. **Scope Limitation**: Use minimal OAuth scopes required
3. **PKCE**: Enable Proof Key for Code Exchange for public clients
4. **State Validation**: Always validate OAuth state parameters

## Troubleshooting

### Common Issues

1. **Bedrock AgentCore Access**: Ensure you have preview access enabled
2. **SAML Configuration**: Verify metadata URL is accessible and valid
3. **Lambda Permissions**: Check CloudWatch logs for authentication errors
4. **OAuth Flows**: Verify callback URLs match exactly

### Debug Commands

```bash
# View CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name EnterpriseIdentityFederationStack

# Check Lambda logs
aws logs tail /aws/lambda/agent-auth-handler-XXXXXX --follow

# Verify IAM role policies
aws iam list-attached-role-policies \
    --role-name AgentCoreExecutionRole-XXXXXX
```

## Support

For issues and questions:

1. Check the [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
2. Review [Amazon Cognito Documentation](https://docs.aws.amazon.com/cognito/)
3. Consult [Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock-agentcore/)
4. Open issues in the project repository

## License

This project is licensed under the MIT License. See the LICENSE file for details.