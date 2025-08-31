# Infrastructure as Code for Simple Configuration Management with Parameter Store and CloudShell

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Configuration Management with Parameter Store and CloudShell".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate credentials
- IAM permissions for Systems Manager Parameter Store operations:
  - `ssm:PutParameter`
  - `ssm:GetParameter`
  - `ssm:GetParameters`
  - `ssm:GetParametersByPath`
  - `ssm:DescribeParameters`
  - `ssm:DeleteParameter`
- KMS permissions for SecureString parameters (using default AWS managed key)
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: Less than $1 for standard parameters (first 10,000 API calls are free monthly)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name parameter-store-config-demo \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AppName,ParameterValue=myapp-demo \
    --capabilities CAPABILITY_IAM

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name parameter-store-config-demo \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters appName=myapp-demo

# List all stacks
npx cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters appName=myapp-demo

# List all stacks
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -var="app_name=myapp-demo"

# Apply the configuration
terraform apply -var="app_name=myapp-demo"

# Show outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh myapp-demo

# Check deployment status
aws ssm describe-parameters \
    --parameter-filters "Key=Name,Option=BeginsWith,Values=/myapp-demo" \
    --query 'Parameters[].[Name,Type]' \
    --output table
```

## What Gets Deployed

This infrastructure creates the following AWS Systems Manager Parameter Store parameters:

### Standard Parameters (String type)
- `/[app-name]/database/url` - Database connection URL
- `/[app-name]/config/environment` - Application environment setting
- `/[app-name]/features/debug-mode` - Debug mode feature flag

### Secure Parameters (SecureString type, KMS encrypted)
- `/[app-name]/api/third-party-key` - Third-party API key (encrypted)
- `/[app-name]/database/password` - Database password (encrypted)

### List Parameters (StringList type)
- `/[app-name]/api/allowed-origins` - CORS allowed origins list
- `/[app-name]/deployment/regions` - Supported deployment regions list

## Testing Your Deployment

After deployment, test parameter retrieval using AWS CLI:

```bash
# Set your app name
export APP_NAME="myapp-demo"  # Or whatever you used during deployment

# Retrieve standard parameter
aws ssm get-parameter \
    --name "/${APP_NAME}/database/url" \
    --query "Parameter.Value" \
    --output text

# Retrieve encrypted parameter with decryption
aws ssm get-parameter \
    --name "/${APP_NAME}/api/third-party-key" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text

# Get all parameters by path
aws ssm get-parameters-by-path \
    --path "/${APP_NAME}" \
    --recursive \
    --with-decryption \
    --output table

# Count total parameters
aws ssm get-parameters-by-path \
    --path "/${APP_NAME}" \
    --recursive \
    --query 'length(Parameters)' \
    --output text
```

## Configuration Management Script

All implementations include a configuration management script that provides these operations:

```bash
# Get all parameters for an application
./config-manager.sh /myapp-demo get

# Count parameters under a path
./config-manager.sh /myapp-demo count

# Backup configuration to JSON file
./config-manager.sh /myapp-demo backup
```

The script demonstrates practical patterns for:
- Bulk parameter retrieval
- Configuration backup and restore
- Parameter inventory management
- Environment variable export

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name parameter-store-config-demo

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name parameter-store-config-demo
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npx cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="app_name=myapp-demo"
```

### Using Bash Scripts
```bash
# Destroy infrastructure
./scripts/destroy.sh myapp-demo

# Verify cleanup
aws ssm describe-parameters \
    --parameter-filters "Key=Name,Option=BeginsWith,Values=/myapp-demo" \
    --query 'Parameters[]' \
    --output text
```

## Customization

### Available Parameters

Each implementation supports customization through variables/parameters:

- **AppName/app_name**: Application namespace for parameter organization (default: `myapp-demo`)
- **Environment**: Environment suffix for parameter paths (default: `development`)
- **KmsKeyId**: KMS key ID for SecureString encryption (default: `alias/aws/ssm`)

### Example Customizations

```bash
# CloudFormation with custom parameters
aws cloudformation create-stack \
    --stack-name my-config-stack \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=AppName,ParameterValue=production-app \
        ParameterKey=Environment,ParameterValue=prod

# Terraform with custom variables
terraform apply \
    -var="app_name=production-app" \
    -var="environment=prod"

# CDK with parameters
cdk deploy --parameters appName=production-app --parameters environment=prod
```

### Adding New Parameters

To add new parameters to your configuration:

1. **CloudFormation**: Add new `AWS::SSM::Parameter` resources in the template
2. **CDK**: Add new `ssm.StringParameter` or `ssm.StringListParameter` constructs
3. **Terraform**: Add new `aws_ssm_parameter` resources
4. **Bash Scripts**: Add new `aws ssm put-parameter` commands

### Parameter Organization Best Practices

- Use hierarchical paths: `/app/service/parameter-name`
- Group related parameters under common prefixes
- Use environment-specific paths: `/prod/app/` vs `/dev/app/`
- Implement consistent naming conventions
- Use descriptive parameter descriptions

## Security Considerations

### IAM Permissions

The infrastructure follows least privilege principles:

- Parameters use resource-based access patterns
- SecureString parameters require KMS decrypt permissions
- Applications should use IAM roles rather than access keys

### Encryption

- SecureString parameters are encrypted at rest using AWS KMS
- Uses AWS managed key `alias/aws/ssm` by default
- Customer managed keys can be specified for additional control

### Access Patterns

- Use IAM policies to restrict parameter access by path
- Implement resource-based policies for cross-account access
- Monitor parameter access using AWS CloudTrail

## Troubleshooting

### Common Issues

1. **Access Denied**: Verify IAM permissions for Parameter Store operations
2. **KMS Decrypt Errors**: Ensure KMS permissions for SecureString parameters
3. **Parameter Not Found**: Check parameter path and name spelling
4. **Deployment Failures**: Verify AWS CLI configuration and credentials

### Debugging Commands

```bash
# Check current AWS identity
aws sts get-caller-identity

# List all parameters (requires broad permissions)
aws ssm describe-parameters --max-items 50

# Check parameter history
aws ssm get-parameter-history --name "/myapp-demo/database/url"

# Validate parameter value format
aws ssm get-parameter --name "/myapp-demo/api/allowed-origins" \
    --query "Parameter.Value" --output text | tr ',' '\n'
```

## Advanced Usage

### Integration with Applications

Example Python code for loading configuration:

```python
import boto3
import os

def load_config(app_name, region='us-east-1'):
    ssm = boto3.client('ssm', region_name=region)
    
    # Get all parameters for the application
    response = ssm.get_parameters_by_path(
        Path=f'/{app_name}',
        Recursive=True,
        WithDecryption=True
    )
    
    # Convert to dictionary
    config = {}
    for param in response['Parameters']:
        key = param['Name'].replace(f'/{app_name}/', '').replace('/', '_').upper()
        config[key] = param['Value']
    
    return config

# Usage
config = load_config('myapp-demo')
db_url = config.get('DATABASE_URL')
```

### Parameter Policies

Advanced parameters support policies for:
- Automatic expiration
- Change notifications
- Access logging

```bash
# Create parameter with expiration policy
aws ssm put-parameter \
    --name "/myapp/temp/session-key" \
    --value "temporary-value" \
    --type "SecureString" \
    --policies '[{"Type":"Expiration","Version":"1.0","Attributes":{"Timestamp":"2024-12-31T23:59:59Z"}}]'
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../simple-configuration-management-parameter-store-cloudshell.md)
2. Review [AWS Systems Manager Parameter Store documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
3. Consult provider-specific documentation:
   - [CloudFormation SSM resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/AWS_SSM.html)
   - [CDK SSM module](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_ssm-readme.html)
   - [Terraform AWS Provider SSM](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter)

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update documentation to reflect changes
3. Follow the provider's best practices and style guides
4. Validate security implications of changes
5. Update the cleanup procedures if new resources are added