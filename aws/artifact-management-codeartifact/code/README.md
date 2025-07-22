# Infrastructure as Code for Artifact Management with CodeArtifact

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Artifact Management with CodeArtifact".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for CodeArtifact, IAM, and KMS
- Node.js and npm (for testing npm functionality)
- Python and pip (for testing Python functionality)
- For CDK deployments: CDK CLI installed (`npm install -g aws-cdk`)
- For Terraform deployments: Terraform >= 1.0 installed

### Required AWS Permissions

Your AWS user/role needs permissions for:
- `codeartifact:*` (for CodeArtifact operations)
- `iam:CreateRole`, `iam:CreatePolicy`, `iam:AttachRolePolicy` (for IAM setup)
- `kms:CreateKey`, `kms:DescribeKey` (for encryption)
- `sts:GetCallerIdentity` (for account information)

## Architecture Overview

The infrastructure creates:
- CodeArtifact domain with KMS encryption
- Repository hierarchy (npm-store, pypi-store, team-dev, production)
- External connections to public registries (npmjs, PyPI)
- Upstream repository relationships
- IAM policies for different access levels
- Repository permission policies

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name codeartifact-management \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DomainName,ParameterValue=my-company-domain-$(date +%s)

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name codeartifact-management

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name codeartifact-management \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
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

# The script will output configuration details and test commands
```

## Post-Deployment Configuration

After deploying the infrastructure, configure your development environment:

### Configure npm

```bash
# Get the team repository endpoint
DOMAIN_NAME="your-domain-name"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Login to CodeArtifact for npm
aws codeartifact login \
    --tool npm \
    --domain ${DOMAIN_NAME} \
    --domain-owner ${AWS_ACCOUNT_ID} \
    --repository team-dev
```

### Configure pip

```bash
# Login to CodeArtifact for pip
aws codeartifact login \
    --tool pip \
    --domain ${DOMAIN_NAME} \
    --domain-owner ${AWS_ACCOUNT_ID} \
    --repository team-dev
```

### Test Package Installation

```bash
# Test npm package installation
npm install lodash

# Test pip package installation
pip install requests

# Verify packages are cached in CodeArtifact
aws codeartifact list-packages \
    --domain ${DOMAIN_NAME} \
    --repository team-dev
```

## Validation & Testing

### Verify Infrastructure

```bash
# List created domains
aws codeartifact list-domains

# List repositories in domain
aws codeartifact list-repositories-in-domain \
    --domain ${DOMAIN_NAME}

# Check external connections
aws codeartifact list-repositories \
    --query 'repositories[?externalConnections!=null]'
```

### Test Package Operations

```bash
# Test authentication token generation
aws codeartifact get-authorization-token \
    --domain ${DOMAIN_NAME} \
    --query 'authorizationToken' \
    --output text

# Test repository endpoints
aws codeartifact get-repository-endpoint \
    --domain ${DOMAIN_NAME} \
    --repository team-dev \
    --format npm

aws codeartifact get-repository-endpoint \
    --domain ${DOMAIN_NAME} \
    --repository team-dev \
    --format pypi
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name codeartifact-management

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name codeartifact-management
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources:

```bash
# Reset package manager configurations
npm config delete registry
pip config unset global.index-url

# List and delete repositories
aws codeartifact list-repositories-in-domain \
    --domain ${DOMAIN_NAME} \
    --query 'repositories[].name' \
    --output text

# Delete each repository (replace REPO_NAME)
aws codeartifact delete-repository \
    --domain ${DOMAIN_NAME} \
    --repository REPO_NAME

# Delete domain
aws codeartifact delete-domain \
    --domain ${DOMAIN_NAME}
```

## Customization

### Variables and Parameters

Each implementation supports customization through variables:

- **Domain Name**: Customize the CodeArtifact domain name
- **Repository Names**: Modify repository names for your organization
- **Region**: Deploy to different AWS regions
- **KMS Key**: Use existing KMS keys or create new ones
- **IAM Policies**: Customize access permissions

### CloudFormation Parameters

Edit the Parameters section in `cloudformation.yaml`:

```yaml
Parameters:
  DomainName:
    Type: String
    Default: my-company-domain
    Description: Name for the CodeArtifact domain
  
  EnableKmsEncryption:
    Type: String
    Default: true
    AllowedValues: [true, false]
    Description: Enable KMS encryption for the domain
```

### Terraform Variables

Modify `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
domain_name = "my-company-domain"
repository_names = {
  npm_store  = "npm-store"
  pypi_store = "pypi-store"
  team_repo  = "team-dev"
  prod_repo  = "production"
}
```

### CDK Configuration

Both CDK implementations support environment variables and context values:

```bash
# Set environment variables
export CODEARTIFACT_DOMAIN_NAME="my-company-domain"
export AWS_REGION="us-east-1"

# Or use CDK context
cdk deploy -c domainName=my-company-domain
```

## Cost Considerations

CodeArtifact pricing includes:
- **Storage**: $0.05 per GB-month (first 100GB free)
- **Requests**: $0.05 per 10,000 requests (first 100,000 free)

Typical costs for development teams:
- Small team (< 10 developers): $0-5/month
- Medium team (10-50 developers): $5-25/month
- Large organization (50+ developers): $25-100/month

## Security Best Practices

The infrastructure implements several security best practices:

1. **Encryption**: KMS encryption for domain storage
2. **IAM Integration**: Fine-grained access controls
3. **Repository Policies**: Resource-based permissions
4. **Token Authentication**: Time-limited access tokens
5. **Upstream Controls**: Controlled package promotion

### Additional Security Considerations

- Regularly rotate authorization tokens
- Implement package scanning in CI/CD pipelines
- Use repository policies for cross-account access
- Monitor package usage with CloudTrail
- Implement approval workflows for production promotions

## Troubleshooting

### Common Issues

1. **Authentication Failures**
   ```bash
   # Regenerate authorization token
   aws codeartifact get-authorization-token \
       --domain ${DOMAIN_NAME} \
       --duration-seconds 3600
   ```

2. **Package Installation Errors**
   ```bash
   # Verify repository endpoint
   aws codeartifact get-repository-endpoint \
       --domain ${DOMAIN_NAME} \
       --repository team-dev \
       --format npm
   
   # Check external connections
   aws codeartifact describe-repository \
       --domain ${DOMAIN_NAME} \
       --repository npm-store
   ```

3. **Permission Denied Errors**
   ```bash
   # Verify IAM permissions
   aws iam get-user-policy \
       --user-name your-username \
       --policy-name CodeArtifactAccess
   
   # Check repository policies
   aws codeartifact get-repository-permissions-policy \
       --domain ${DOMAIN_NAME} \
       --repository team-dev
   ```

### Logs and Monitoring

Monitor CodeArtifact usage through:
- CloudTrail for API calls
- CloudWatch for service metrics
- Cost Explorer for usage costs

## Integration Examples

### CI/CD Pipeline Integration

```bash
# In your CI/CD pipeline
aws codeartifact login --tool npm \
    --domain ${DOMAIN_NAME} \
    --repository team-dev

# Build and test
npm install
npm test

# Publish (if authorized)
npm publish
```

### Cross-Account Access

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT-B:root"
      },
      "Action": "codeartifact:ReadFromRepository",
      "Resource": "*"
    }
  ]
}
```

## Support

For issues with this infrastructure code:

1. Check the [AWS CodeArtifact documentation](https://docs.aws.amazon.com/codeartifact/)
2. Review the original recipe documentation
3. Consult AWS support for service-specific issues
4. Use AWS forums for community support

## Additional Resources

- [AWS CodeArtifact User Guide](https://docs.aws.amazon.com/codeartifact/latest/ug/)
- [CodeArtifact API Reference](https://docs.aws.amazon.com/codeartifact/latest/APIReference/)
- [Package Manager Integration](https://docs.aws.amazon.com/codeartifact/latest/ug/using-generic.html)
- [Security Best Practices](https://docs.aws.amazon.com/codeartifact/latest/ug/security.html)