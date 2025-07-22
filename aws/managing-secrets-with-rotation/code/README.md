# Infrastructure as Code for Managing Secrets with Automated Rotation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Managing Secrets with Automated Rotation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Secrets Manager (full access)
  - AWS Lambda (create/manage functions)
  - AWS IAM (create/manage roles and policies)
  - AWS KMS (create/manage keys)
  - Amazon CloudWatch (create/manage dashboards and alarms)
- Basic understanding of secrets management and rotation concepts
- Estimated cost: $2-5 per month for secrets storage and rotation executions

> **Note**: This infrastructure creates billable resources. AWS Secrets Manager charges $0.40 per secret per month plus $0.05 per 10,000 API calls.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name secrets-manager-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=SecretName,ParameterValue=my-db-secret \
                 ParameterKey=RotationSchedule,ParameterValue="rate(7 days)"

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name secrets-manager-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name secrets-manager-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

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

# Check deployment status
echo "Deployment completed. Check AWS console for resources."
```

## Configuration Options

### CloudFormation Parameters

- `SecretName`: Name for the database secret (default: demo-db-credentials)
- `RotationSchedule`: Rotation schedule expression (default: rate(7 days))
- `KMSKeyAlias`: Alias for the KMS encryption key (default: alias/secrets-manager-key)
- `Environment`: Environment tag for resources (default: Demo)

### CDK Configuration

Modify the following in the CDK code:

```typescript
// CDK TypeScript - app.ts
const secretsManagerStack = new SecretsManagerStack(app, 'SecretsManagerStack', {
  secretName: 'my-db-credentials',
  rotationSchedule: 'rate(7 days)',
  environment: 'Production'
});
```

```python
# CDK Python - app.py
secrets_manager_stack = SecretsManagerStack(
    app, "SecretsManagerStack",
    secret_name="my-db-credentials",
    rotation_schedule="rate(7 days)",
    environment="Production"
)
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
secret_name = "my-db-credentials"
rotation_schedule = "rate(7 days)"
environment = "Production"
kms_key_alias = "alias/secrets-manager-key"
```

## Validation

After deployment, validate your infrastructure:

### Verify Secret Creation

```bash
# List secrets
aws secretsmanager list-secrets

# Describe specific secret
aws secretsmanager describe-secret \
    --secret-id <your-secret-name>

# Check rotation status
aws secretsmanager describe-secret \
    --secret-id <your-secret-name> \
    --query 'RotationEnabled'
```

### Test Secret Retrieval

```bash
# Retrieve secret value
aws secretsmanager get-secret-value \
    --secret-id <your-secret-name> \
    --query SecretString \
    --output text
```

### Verify Lambda Function

```bash
# List Lambda functions
aws lambda list-functions \
    --query 'Functions[?contains(FunctionName, `rotation`)]'

# Check function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda"
```

### Test Rotation

```bash
# Trigger manual rotation
aws secretsmanager rotate-secret \
    --secret-id <your-secret-name>

# Check rotation status
aws secretsmanager describe-secret \
    --secret-id <your-secret-name> \
    --query 'VersionIdsToStages'
```

## Monitoring

### CloudWatch Dashboard

Access the created dashboard:

```bash
# List dashboards
aws cloudwatch list-dashboards

# Get dashboard details
aws cloudwatch get-dashboard \
    --dashboard-name <dashboard-name>
```

### CloudWatch Alarms

Monitor rotation failures:

```bash
# List alarms
aws cloudwatch describe-alarms \
    --alarm-names <alarm-name>

# Check alarm state
aws cloudwatch describe-alarms \
    --state-value ALARM
```

## Security Considerations

### IAM Permissions

The infrastructure creates minimal IAM roles with least-privilege access:

- Lambda execution role with Secrets Manager and KMS permissions
- Cross-account access policies with tag-based conditions
- CloudWatch monitoring permissions

### Encryption

- All secrets are encrypted at rest using customer-managed KMS keys
- Automatic key rotation policies applied
- Secure transport (TLS 1.2+) for all API communications

### Access Control

- Resource-based policies for cross-account access
- Tag-based conditional access
- VPC endpoint support for private connectivity

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name secrets-manager-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name secrets-manager-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm destruction
# Type 'y' when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   - Ensure your AWS credentials have sufficient permissions
   - Check IAM policies and resource-based policies

2. **Rotation Failures**
   - Check Lambda function logs in CloudWatch
   - Verify database connectivity from Lambda
   - Ensure proper VPC configuration if using private subnets

3. **KMS Access Issues**
   - Verify KMS key policies allow necessary actions
   - Check cross-account permissions for KMS keys

4. **Resource Limits**
   - Check AWS service quotas for your region
   - Ensure sufficient Lambda concurrent executions

### Debug Commands

```bash
# Check CloudTrail for API calls
aws logs filter-log-events \
    --log-group-name CloudTrail/SecretManagerAPI \
    --start-time 1609459200000

# Validate resource policies
aws secretsmanager validate-resource-policy \
    --resource-policy file://policy.json

# Test Lambda function
aws lambda invoke \
    --function-name <rotation-function-name> \
    --payload '{"test": "true"}' \
    response.json
```

## Cost Optimization

### Monitoring Costs

- Use AWS Cost Explorer to track Secrets Manager costs
- Set up billing alerts for unexpected charges
- Monitor rotation frequency to optimize costs

### Cost Reduction Strategies

- Use appropriate rotation schedules (not too frequent)
- Clean up unused secrets regularly
- Use resource tagging for cost allocation
- Consider secret consolidation where appropriate

## Advanced Configuration

### Multi-Region Deployment

For high availability, consider deploying across multiple regions:

```bash
# Deploy to additional regions
aws cloudformation create-stack \
    --stack-name secrets-manager-stack-eu \
    --template-body file://cloudformation.yaml \
    --region eu-west-1 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
```

### Integration with Applications

Example application integration:

```python
import boto3
import json

def get_secret(secret_name, region_name):
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )
    
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

# Usage
credentials = get_secret('my-db-credentials', 'us-east-1')
```

## Support

For issues with this infrastructure code:

1. Check the AWS Secrets Manager documentation
2. Review CloudWatch logs for error details
3. Consult the original recipe documentation
4. Check AWS service health dashboard
5. Contact AWS support for service-specific issues

## References

- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)