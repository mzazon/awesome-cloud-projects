# Infrastructure as Code for Policy Enforcement Automation with VPC Lattice and Config

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Policy Enforcement Automation with VPC Lattice and Config".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Administrator access to VPC Lattice, AWS Config, Lambda, SNS, and IAM services
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $15-25 per month for AWS Config rules, Lambda executions, and SNS notifications

> **Note**: This implementation follows AWS Well-Architected Framework security principles by implementing defense-in-depth monitoring and automated remediation capabilities.

## Architecture Overview

This solution deploys:

- **AWS Config**: Continuous monitoring and recording of VPC Lattice resources
- **Custom Config Rules**: Automated compliance evaluation using Lambda
- **Lambda Functions**: Compliance evaluation and automated remediation logic
- **SNS Topic**: Real-time notifications for compliance violations
- **IAM Roles**: Secure service-to-service authentication
- **VPC Lattice Resources**: Test service network for validation

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name vpc-lattice-policy-enforcement \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=admin@company.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name vpc-lattice-policy-enforcement \
    --query 'Stacks[0].StackStatus'

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name vpc-lattice-policy-enforcement
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=admin@company.com

# View stack outputs
cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notification-email=admin@company.com

# View stack outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="notification_email=admin@company.com"

# Apply the configuration
terraform apply -var="notification_email=admin@company.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="admin@company.com"
export AWS_REGION="us-east-1"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
echo "Deployment completed. Check AWS Console for resource status."
```

## Configuration Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `NotificationEmail` | Email address for compliance notifications | - | Yes |
| `EnvironmentName` | Environment identifier for resource naming | `prod` | No |
| `RequireAuthPolicy` | Enforce auth policy requirement on service networks | `true` | No |
| `NamePrefix` | Required prefix for compliant resource names | `secure-` | No |
| `RequireAuth` | Enforce authentication on VPC Lattice services | `true` | No |

## Post-Deployment Validation

After deployment, validate the solution:

1. **Confirm SNS Subscription**:
   ```bash
   # Check your email for SNS subscription confirmation
   # Click the confirmation link to activate notifications
   ```

2. **Verify Config Rule Status**:
   ```bash
   # List active Config rules
   aws configservice describe-config-rules \
       --query 'ConfigRules[?contains(ConfigRuleName, `lattice-policy-compliance`)].{Name:ConfigRuleName,State:ConfigRuleState}'
   ```

3. **Test Compliance Detection**:
   ```bash
   # Create a non-compliant VPC Lattice service
   aws vpc-lattice create-service \
       --name "test-service-$(date +%s)" \
       --auth-type NONE
   
   # Wait for Config evaluation (may take 5-10 minutes)
   # Check for compliance violations
   aws configservice get-compliance-details-by-config-rule \
       --config-rule-name $(aws configservice describe-config-rules \
           --query 'ConfigRules[?contains(ConfigRuleName, `lattice-policy-compliance`)].ConfigRuleName' \
           --output text) \
       --compliance-types NON_COMPLIANT
   ```

4. **Verify Notification Delivery**:
   ```bash
   # Check SNS topic metrics
   aws cloudwatch get-metric-statistics \
       --namespace AWS/SNS \
       --metric-name NumberOfMessagesPublished \
       --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
       --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
       --period 3600 \
       --statistics Sum \
       --dimensions Name=TopicName,Value=$(aws sns list-topics \
           --query 'Topics[?contains(TopicArn, `lattice-compliance-alerts`)].TopicArn' \
           --output text | cut -d: -f6)
   ```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name vpc-lattice-policy-enforcement

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name vpc-lattice-policy-enforcement

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name vpc-lattice-policy-enforcement 2>/dev/null || echo "Stack successfully deleted"
```

### Using CDK

```bash
# Navigate to appropriate CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy -var="notification_email=admin@company.com"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm when prompted for destructive actions
```

## Troubleshooting

### Common Issues

1. **Config Rule Not Evaluating**:
   - Verify AWS Config is enabled and recording VPC Lattice resources
   - Check Lambda function logs in CloudWatch
   - Ensure IAM permissions are correctly configured

2. **SNS Notifications Not Received**:
   - Confirm email subscription is confirmed
   - Check SNS topic delivery status
   - Verify Lambda function has SNS publish permissions

3. **Remediation Not Working**:
   - Check remediation Lambda function logs
   - Verify Lambda execution role has VPC Lattice permissions
   - Ensure SNS-to-Lambda subscription is active

### Debugging Commands

```bash
# Check Config service status
aws configservice describe-configuration-recorder-status

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Check SNS topic attributes
aws sns get-topic-attributes --topic-arn <TOPIC_ARN>

# View Config rule compliance
aws configservice get-compliance-summary-by-config-rule
```

## Customization

### Modifying Compliance Rules

To customize compliance evaluation logic:

1. Update the Lambda function code in your chosen IaC implementation
2. Modify the `InputParameters` for the Config rule
3. Redeploy the updated stack

### Adding Custom Remediation Actions

To extend remediation capabilities:

1. Modify the remediation Lambda function
2. Add additional IAM permissions as needed
3. Update SNS message processing logic

### Multi-Account Deployment

For organization-wide deployment:

1. Deploy in a central security account
2. Configure Config aggregation across accounts
3. Update IAM roles for cross-account access
4. Modify Lambda functions for multi-account resource access

## Security Considerations

- All IAM roles follow least privilege principles
- Lambda functions use specific permissions for required services only
- Config rules evaluate resources but cannot modify them directly
- SNS topics use server-side encryption by default
- Remediation actions are logged for audit purposes

## Cost Optimization

- Lambda functions use appropriate memory allocation for workload
- Config rules evaluate only VPC Lattice resources
- SNS notifications are targeted to reduce message volume
- CloudWatch log retention is configurable to manage storage costs

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for latest features
3. Verify IAM permissions and service quotas
4. Review CloudWatch logs for detailed error information

## Contributing

When modifying this infrastructure code:

1. Follow AWS best practices for security and cost optimization
2. Test changes in a non-production environment
3. Update documentation to reflect modifications
4. Ensure compliance with organizational policies