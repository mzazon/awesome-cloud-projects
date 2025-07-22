# Infrastructure as Code for SSO with External Identity Providers

This directory contains Infrastructure as Code (IaC) implementations for the recipe "SSO with External Identity Providers".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS Organizations enabled with management account access
- Administrative access to external identity provider (Active Directory, Okta, Azure AD, etc.)
- SAML metadata from your identity provider
- Appropriate AWS permissions for:
  - IAM Identity Center administration
  - Organizations management
  - Identity Store management
  - CloudTrail configuration
- For CDK deployments: Node.js 18+ and Python 3.8+
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $0.50-$2.00 per user per month (depending on usage)

> **Note**: IAM Identity Center is available at no additional charge for workforce users. Additional charges may apply for application integrations and advanced features.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name sso-external-idp-stack \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=IdentityProviderName,ParameterValue=MyExternalIdP \
        ParameterKey=SAMLMetadataDocument,ParameterValue=file://saml-metadata.xml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment
aws cloudformation wait stack-create-complete \
    --stack-name sso-external-idp-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name sso-external-idp-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk bootstrap
cdk deploy SSOExternalIdPStack

# View outputs
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk bootstrap
cdk deploy SSOExternalIdPStack

# View outputs
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="identity_provider_name=MyExternalIdP" \
    -var="saml_metadata_document=file://saml-metadata.xml"

# Apply the configuration
terraform apply \
    -var="identity_provider_name=MyExternalIdP" \
    -var="saml_metadata_document=file://saml-metadata.xml"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export IDENTITY_PROVIDER_NAME="MyExternalIdP"
export SAML_METADATA_FILE="saml-metadata.xml"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/validate.sh
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `IdentityProviderName` | Name for the external identity provider | `ExternalIdP` | Yes |
| `SAMLMetadataDocument` | Path to SAML metadata XML file | - | Yes |
| `EnableSCIM` | Enable SCIM user provisioning | `true` | No |
| `SessionDuration` | Default session duration for permission sets | `PT8H` | No |
| `EnableCloudTrail` | Enable CloudTrail logging | `true` | No |

### CDK Configuration

Both TypeScript and Python CDK implementations support the same configuration through context variables:

```bash
# Set context variables
cdk deploy \
    --context identityProviderName=MyExternalIdP \
    --context enableSCIM=true \
    --context sessionDuration=PT8H \
    --context enableCloudTrail=true
```

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `identity_provider_name` | Name for the external identity provider | `string` | `"ExternalIdP"` | No |
| `saml_metadata_document` | SAML metadata XML content | `string` | - | Yes |
| `enable_scim` | Enable SCIM user provisioning | `bool` | `true` | No |
| `session_duration` | Default session duration for permission sets | `string` | `"PT8H"` | No |
| `enable_cloudtrail` | Enable CloudTrail logging | `bool` | `true` | No |
| `aws_region` | AWS region for deployment | `string` | `"us-east-1"` | No |

Create a `terraform.tfvars` file to customize your deployment:

```hcl
identity_provider_name = "MyCompanyIdP"
saml_metadata_document = file("./saml-metadata.xml")
enable_scim = true
session_duration = "PT4H"
enable_cloudtrail = true
aws_region = "us-west-2"
```

## Architecture Components

The infrastructure deploys the following components:

### Core IAM Identity Center Resources
- IAM Identity Center instance configuration
- Identity store for local user management
- External identity provider integration
- SAML 2.0 authentication configuration

### Permission Sets
- **AdministratorAccess**: Full administrative permissions (4-hour session)
- **DeveloperAccess**: PowerUser permissions with custom S3 access (8-hour session)
- **ReadOnlyAccess**: Read-only access across AWS services (12-hour session)

### Security and Compliance
- CloudTrail logging for audit trails
- Attribute-based access control (ABAC) configuration
- Least privilege permission policies
- Session duration controls

### Automation Features
- SCIM endpoint for automated user provisioning
- Account assignment automation
- Permission set provisioning across organization accounts

## Post-Deployment Configuration

After deploying the infrastructure, complete these manual steps:

### 1. Configure External Identity Provider

1. Retrieve the SAML sign-in URL from the deployment outputs
2. Configure your identity provider with AWS IAM Identity Center as a service provider
3. Set up attribute mappings for user attributes (department, cost center, etc.)
4. Test authentication flow

### 2. Enable SCIM Provisioning (Optional)

1. Generate SCIM access token in AWS Console:
   - Navigate to IAM Identity Center
   - Go to Settings > Identity source
   - Click "Enable automatic provisioning"
   - Copy the SCIM endpoint and access token

2. Configure your identity provider with SCIM settings:
   - SCIM endpoint URL (from deployment outputs)
   - Bearer token (generated in step 1)
   - Enable user and group provisioning

### 3. Assign User Access

1. Create user assignments:
   ```bash
   # Using AWS CLI
   aws sso-admin create-account-assignment \
       --instance-arn $(terraform output -raw sso_instance_arn) \
       --target-id YOUR_ACCOUNT_ID \
       --target-type AWS_ACCOUNT \
       --permission-set-arn $(terraform output -raw developer_permission_set_arn) \
       --principal-type USER \
       --principal-id USER_ID
   ```

2. Or use the AWS Console:
   - Navigate to IAM Identity Center
   - Go to AWS accounts
   - Select target account
   - Assign users and groups to permission sets

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name sso-external-idp-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name sso-external-idp-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy SSOExternalIdPStack

# Clean up CDK assets (optional)
cdk bootstrap --toolkit-stack-name CDKToolkit --termination-protection false
aws cloudformation delete-stack --stack-name CDKToolkit
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="identity_provider_name=MyExternalIdP" \
    -var="saml_metadata_document=file://saml-metadata.xml"

# Clean up state files (optional)
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm all resources are deleted
./scripts/validate.sh --check-cleanup
```

## Troubleshooting

### Common Issues

1. **Permission Set Provisioning Fails**
   - Ensure AWS Organizations is properly configured
   - Verify account is not suspended
   - Check IAM permissions for the deployment role

2. **SAML Authentication Issues**
   - Validate SAML metadata XML format
   - Check identity provider certificate validity
   - Verify ACS URL configuration

3. **SCIM Provisioning Errors**
   - Confirm SCIM endpoint is accessible
   - Validate bearer token permissions
   - Check network connectivity from identity provider

### Debugging Commands

```bash
# Check IAM Identity Center status
aws sso-admin list-instances

# Verify permission sets
aws sso-admin list-permission-sets \
    --instance-arn $(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)

# Check account assignments
aws sso-admin list-accounts-for-provisioned-permission-set \
    --instance-arn $(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text) \
    --permission-set-arn PERMISSION_SET_ARN

# View CloudTrail logs for SSO events
aws logs filter-log-events \
    --log-group-name aws-sso-audit-logs \
    --filter-pattern "{ $.eventSource = \"sso.amazonaws.com\" }"
```

## Security Considerations

- **Least Privilege**: Permission sets follow least privilege principles
- **Session Management**: Different session durations based on access level
- **Audit Logging**: CloudTrail captures all SSO activities
- **Attribute-Based Access**: Supports dynamic policies based on user attributes
- **Encryption**: All data encrypted in transit and at rest

## Cost Optimization

- IAM Identity Center is free for workforce users
- CloudTrail charges apply for log storage
- Consider log retention policies to manage costs
- Monitor usage with AWS Cost Explorer

## Customization

### Adding Custom Permission Sets

1. **Using Terraform**: Add new permission set resources in `main.tf`
2. **Using CloudFormation**: Add resources to the template
3. **Using CDK**: Create new permission set constructs

### Modifying Attribute Mappings

Update the attribute mapping configuration to include additional user attributes from your identity provider:

```json
{
    "AccessControlAttributes": [
        {
            "Key": "Department",
            "Value": {
                "Source": ["${path:enterprise.department}"]
            }
        },
        {
            "Key": "ProjectCode",
            "Value": {
                "Source": ["${path:enterprise.project}"]
            }
        }
    ]
}
```

## Support

- For infrastructure issues: Check AWS CloudFormation/CDK documentation
- For IAM Identity Center: See [AWS SSO Documentation](https://docs.aws.amazon.com/singlesignon/)
- For SAML integration: Review [SAML Federation Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_saml.html)
- For SCIM provisioning: See [SCIM Integration Guide](https://docs.aws.amazon.com/singlesignon/latest/userguide/how-to-with-scim.html)