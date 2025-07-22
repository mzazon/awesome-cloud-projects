# CDK Python Application: Fine-Grained API Authorization

This CDK Python application deploys a complete infrastructure for building fine-grained API authorization using Amazon Verified Permissions with Cedar policies and Amazon Cognito for identity management.

## Architecture Overview

The application creates:

- **Amazon Cognito User Pool**: Identity management with custom attributes for department and role
- **Amazon Verified Permissions**: Policy store with Cedar policies for attribute-based access control (ABAC)
- **API Gateway**: REST API with custom Lambda authorizer
- **Lambda Functions**: Authorization logic and business operations
- **DynamoDB**: Document storage with metadata
- **Test Users**: Pre-configured users with different roles and departments

## Cedar Policies Implemented

1. **View Policy**: Users can view documents if they belong to the same department, are managers, or admins
2. **Edit Policy**: Users can edit documents if they own them, are department managers, or admins
3. **Delete Policy**: Only admins can delete documents

## Prerequisites

- AWS CLI configured with appropriate permissions
- Python 3.8 or later
- Node.js 18 or later (for CDK CLI)
- AWS CDK CLI installed (`npm install -g aws-cdk`)

## Quick Start

### 1. Install Dependencies

```bash
# Install Python dependencies
pip install -r requirements.txt

# Install CDK CLI if not already installed
npm install -g aws-cdk
```

### 2. Bootstrap CDK (if first time using CDK in your account/region)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy the infrastructure
cdk deploy
```

### 4. Test the Deployment

After deployment, the stack outputs will provide:
- API Gateway endpoint URL
- Cognito User Pool ID and Client ID
- Verified Permissions Policy Store ID
- DynamoDB table name

## Testing Authorization

### Test Users Created

The application creates three test users:

1. **admin@company.com** (IT/Admin) - Full access to all operations
2. **manager@company.com** (Sales/Manager) - Can view/edit Sales department documents
3. **employee@company.com** (Sales/Employee) - Limited access based on ownership

### Authentication

Use AWS CLI or SDK to authenticate users and obtain JWT tokens:

```bash
# Example: Authenticate admin user
aws cognito-idp admin-initiate-auth \
    --user-pool-id <USER_POOL_ID> \
    --client-id <CLIENT_ID> \
    --auth-flow ADMIN_NO_SRP_AUTH \
    --auth-parameters USERNAME=admin@company.com,PASSWORD=<PASSWORD>
```

### API Testing

Once authenticated, use the JWT token to test API endpoints:

```bash
# Create a document
curl -X POST <API_ENDPOINT>/documents \
    -H "Authorization: Bearer <JWT_TOKEN>" \
    -H "Content-Type: application/json" \
    -d '{"title": "Test Document", "content": "Test content"}'

# Get a document
curl -X GET <API_ENDPOINT>/documents/<DOCUMENT_ID> \
    -H "Authorization: Bearer <JWT_TOKEN>"

# Update a document
curl -X PUT <API_ENDPOINT>/documents/<DOCUMENT_ID> \
    -H "Authorization: Bearer <JWT_TOKEN>" \
    -H "Content-Type: application/json" \
    -d '{"title": "Updated Title", "content": "Updated content"}'

# Delete a document (admin only)
curl -X DELETE <API_ENDPOINT>/documents/<DOCUMENT_ID> \
    -H "Authorization: Bearer <JWT_TOKEN>"
```

## Project Structure

```
├── app.py                 # Main CDK application
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration
└── README.md             # This file
```

## Key Components

### Lambda Authorizer Function

The authorizer function:
- Validates JWT tokens from Cognito
- Extracts user attributes (department, role)
- Calls Verified Permissions for authorization decisions
- Returns IAM policy allowing or denying access

### Business Logic Function

The business function:
- Handles CRUD operations for documents
- Stores documents in DynamoDB with metadata
- Uses user context from the authorizer

### Cedar Policies

The policies implement sophisticated authorization logic considering:
- User attributes (department, role)
- Resource properties (owner, department)
- Action types (ViewDocument, EditDocument, DeleteDocument)

## Customization

### Adding New Policies

To add new Cedar policies, modify the `_create_cedar_policies` method in `app.py`:

```python
new_policy = verifiedpermissions.CfnPolicy(
    self,
    "NewPolicy",
    policy_store_id=self.policy_store.attr_policy_store_id,
    definition=verifiedpermissions.CfnPolicy.PolicyDefinitionProperty(
        static=verifiedpermissions.CfnPolicy.StaticPolicyDefinitionProperty(
            description="Your policy description",
            statement="permit(...) when { ... };",
        )
    ),
)
```

### Modifying User Attributes

Update the Cognito User Pool custom attributes in the `_create_cognito_resources` method:

```python
custom_attributes={
    "department": cognito.StringAttribute(mutable=True),
    "role": cognito.StringAttribute(mutable=True),
    "team": cognito.StringAttribute(mutable=True),  # New attribute
},
```

### Adding API Endpoints

Extend the API Gateway configuration in the `_create_api_gateway` method to add new resources and methods.

## Security Considerations

- User passwords must be set manually after deployment (users are created without passwords)
- JWT token validation ensures only authenticated users can access the API
- Cedar policies provide fine-grained authorization based on user attributes
- DynamoDB access is restricted to the business logic Lambda function
- All Lambda functions follow least privilege principles

## Cleanup

To remove all resources:

```bash
cdk destroy
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**: Ensure user passwords are set and JWT tokens are valid
2. **Authorization Denials**: Check Cedar policy logic and user attributes
3. **API Gateway 500 Errors**: Check Lambda function logs in CloudWatch
4. **DynamoDB Access Issues**: Verify IAM permissions for Lambda functions

### Logging

- Lambda function logs are available in CloudWatch Logs
- API Gateway access logs can be enabled for debugging
- Verified Permissions provides decision logs for policy evaluation

## Additional Resources

- [Amazon Verified Permissions Documentation](https://docs.aws.amazon.com/verifiedpermissions/)
- [Cedar Policy Language Reference](https://docs.cedarpolicy.com/)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [Amazon Cognito User Pool Documentation](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-identity-pools.html)

## Support

For issues with this CDK application, please refer to:
- AWS CDK GitHub repository
- AWS Documentation
- AWS Support (if you have a support plan)