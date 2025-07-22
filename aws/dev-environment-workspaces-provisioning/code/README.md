# Infrastructure as Code for Development Environment Provisioning with WorkSpaces

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Development Environment Provisioning with WorkSpaces".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution automates the provisioning of standardized WorkSpaces Personal environments with pre-configured development tools and security policies. The infrastructure includes:

- **Lambda Function**: Orchestrates WorkSpaces provisioning and configuration
- **EventBridge Rule**: Schedules automated provisioning workflows
- **Systems Manager Document**: Defines development environment configuration
- **IAM Roles and Policies**: Provides secure access permissions
- **Secrets Manager**: Stores Active Directory credentials securely

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Active Directory setup (Simple AD, Managed Microsoft AD, or AD Connector)
- VPC with subnets in at least two Availability Zones for WorkSpaces deployment
- Appropriate AWS permissions for:
  - WorkSpaces (create, describe, modify, terminate)
  - Lambda (create, invoke, manage)
  - Systems Manager (create documents, send commands)
  - IAM (create roles and policies)
  - Secrets Manager (create and access secrets)
  - EventBridge (create rules and targets)
- Basic knowledge of Python, JSON, and AWS automation services
- Estimated cost: $200-400/month for 10 developer WorkSpaces (Standard bundle, auto-stop billing)

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure stack
aws cloudformation create-stack \
    --stack-name workspaces-automation \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DirectoryId,ParameterValue=d-906734e6b2 \
                 ParameterKey=BundleId,ParameterValue=wsb-b0s22j3d7 \
                 ParameterKey=ADServiceUsername,ParameterValue=workspaces-service

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name workspaces-automation \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Review the deployment (optional)
cdk diff

# Deploy the stack
cdk deploy

# View stack outputs
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

# Review the deployment (optional)
cdk diff

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure:
# - Directory ID (your WorkSpaces directory)
# - Bundle ID (your WorkSpaces bundle)
# - Target users list
# - AD service account credentials
```

## Configuration Parameters

### Required Parameters

- **DirectoryId**: Your WorkSpaces directory identifier (e.g., `d-906734e6b2`)
- **BundleId**: WorkSpaces bundle identifier for development environments (e.g., `wsb-b0s22j3d7`)
- **ADServiceUsername**: Active Directory service account for WorkSpaces operations
- **ADServicePassword**: Password for the AD service account (stored securely in Secrets Manager)

### Optional Parameters

- **TargetUsers**: List of developers who should have WorkSpaces (default: `["developer1", "developer2", "developer3"]`)
- **AutoStopTimeout**: Minutes before WorkSpaces auto-stop (default: 60)
- **ScheduleExpression**: EventBridge schedule for automation (default: `rate(24 hours)`)
- **DevelopmentTools**: Comma-separated list of tools to install (default: `git,vscode,nodejs,python,docker`)

### Environment Variables (for scripts)

```bash
export AWS_REGION=us-east-1
export PROJECT_NAME=devenv-automation
export DIRECTORY_ID=d-906734e6b2
export BUNDLE_ID=wsb-b0s22j3d7
export TARGET_USERS="developer1,developer2,developer3"
```

## Testing the Deployment

### Verify Lambda Function
```bash
# Check Lambda function status
aws lambda get-function \
    --function-name devenv-automation-provisioner-* \
    --query 'Configuration.[FunctionName,State,Runtime]'

# Test the function with sample event
aws lambda invoke \
    --function-name devenv-automation-provisioner-* \
    --payload '{"test": true}' \
    response.json
```

### Verify Systems Manager Document
```bash
# List SSM documents
aws ssm describe-document \
    --name devenv-automation-dev-setup-* \
    --query 'Document.[Name,Status,DocumentType]'
```

### Verify EventBridge Rule
```bash
# Check rule configuration
aws events describe-rule \
    --name devenv-automation-daily-provisioning-* \
    --query '[Name,State,ScheduleExpression]'
```

### Manual WorkSpaces Provisioning Test
```bash
# Trigger the automation manually
aws lambda invoke \
    --function-name devenv-automation-provisioner-* \
    --payload file://test-event.json \
    response.json

# Check the response
cat response.json | jq '.'
```

## Monitoring and Troubleshooting

### CloudWatch Logs
```bash
# View Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/devenv-automation"

# Tail log events
aws logs tail /aws/lambda/devenv-automation-provisioner-* --follow
```

### WorkSpaces Status
```bash
# Check WorkSpaces status
aws workspaces describe-workspaces \
    --directory-id YOUR_DIRECTORY_ID \
    --query 'Workspaces[*].[WorkspaceId,UserName,State]' \
    --output table
```

### Common Issues

1. **Lambda Function Timeout**: Increase timeout if WorkSpaces provisioning takes longer than expected
2. **IAM Permissions**: Ensure the Lambda execution role has all required permissions
3. **Directory Configuration**: Verify WorkSpaces directory is properly configured and accessible
4. **Bundle Availability**: Confirm the specified bundle ID is available in your region

## Security Considerations

- **Secrets Management**: AD credentials are stored in AWS Secrets Manager with encryption
- **IAM Least Privilege**: Lambda role includes only necessary permissions
- **WorkSpaces Encryption**: All WorkSpaces are created with volume encryption enabled
- **Network Security**: WorkSpaces are deployed within your VPC security boundaries
- **Audit Logging**: All automation activities are logged in CloudWatch

## Cost Optimization

- **Auto-Stop Billing**: WorkSpaces use AUTO_STOP mode to minimize costs during idle periods
- **Right-Sizing**: Monitor usage and adjust bundle sizes based on developer needs
- **Scheduled Automation**: Daily checks prevent over-provisioning of unused WorkSpaces
- **Lifecycle Management**: Automated decommissioning when developers leave teams

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name workspaces-automation

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name workspaces-automation \
    --query 'Stacks[0].StackStatus'
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
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
```

### Manual Cleanup (if needed)
```bash
# Remove any remaining WorkSpaces
aws workspaces terminate-workspaces \
    --terminate-workspace-requests WorkspaceId=ws-xxxxxxxxx

# Delete EventBridge rule
aws events delete-rule --name devenv-automation-daily-provisioning-*

# Delete Lambda function
aws lambda delete-function --function-name devenv-automation-provisioner-*

# Delete IAM resources
aws iam delete-role --role-name devenv-automation-lambda-role-*
```

## Customization

### Adding Development Tools

Modify the Systems Manager document to include additional tools:

```json
{
  "developmentTools": {
    "default": "git,vscode,nodejs,python,docker,maven,gradle,postman"
  }
}
```

### Team-Specific Configurations

Create separate Lambda functions for different teams with customized:
- Bundle configurations (different instance sizes)
- Tool installations (frontend vs backend vs data science)
- Security policies
- Cost allocation tags

### Integration with CI/CD

Connect the automation to your CI/CD pipeline:
- Trigger provisioning on team member onboarding
- Integrate with HR systems for automatic lifecycle management
- Add approval workflows for WorkSpaces requests

## Extension Ideas

1. **Self-Service Portal**: Build a web interface for developers to request WorkSpaces
2. **Cost Dashboard**: Create CloudWatch dashboards for usage and cost tracking  
3. **Backup Automation**: Implement automated WorkSpaces backup strategies
4. **Compliance Monitoring**: Add AWS Config rules for WorkSpaces compliance
5. **Multi-Region Support**: Extend automation to support multiple AWS regions

## Support

For issues with this infrastructure code:
1. Check the CloudWatch logs for the Lambda function
2. Verify all prerequisites are met
3. Review AWS service limits and quotas
4. Consult the [AWS WorkSpaces documentation](https://docs.aws.amazon.com/workspaces/)
5. Refer to the original recipe documentation for detailed implementation guidance

## Contributing

When modifying this infrastructure:
1. Test changes in a development environment first
2. Update documentation to reflect any parameter changes
3. Validate security configurations meet organizational requirements
4. Consider backward compatibility with existing deployments