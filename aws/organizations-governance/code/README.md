# Infrastructure as Code for Organizations Multi-Account Governance with SCPs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Organizations Multi-Account Governance with SCPs".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- Organization management permissions in AWS account
- Understanding of AWS IAM policies and JSON syntax
- Multiple AWS accounts or ability to create new accounts
- Estimated cost: $50-100/month for CloudTrail, Config, and logging services

> **Note**: Service Control Policies are only available in organizations with all features enabled, not just consolidated billing.

## Quick Start

### Using CloudFormation

```bash
# Deploy the organization governance infrastructure
aws cloudformation create-stack \
    --stack-name multi-account-governance \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=OrganizationName,ParameterValue=enterprise-org \
                 ParameterKey=CloudTrailBucketName,ParameterValue=org-cloudtrail-bucket \
                 ParameterKey=ConfigBucketName,ParameterValue=org-config-bucket

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name multi-account-governance \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
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
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws organizations describe-organization
```

## Architecture Overview

This implementation creates:

- AWS Organization with all features enabled
- Organizational Units (Production, Development, Sandbox, Security)
- Service Control Policies for cost control, security baseline, and region restrictions
- Organization-wide CloudTrail for audit logging
- Consolidated billing and cost allocation setup
- CloudWatch dashboard for governance monitoring

## Customization

### Parameters and Variables

Each implementation supports customization through variables:

- **Organization Name**: Custom name for your AWS Organization
- **CloudTrail Bucket**: S3 bucket name for organization-wide audit logs
- **Config Bucket**: S3 bucket name for AWS Config data
- **Budget Amount**: Monthly budget limit for cost monitoring
- **Allowed Regions**: List of approved AWS regions for resource deployment
- **Cost Control Tags**: Required tags for cost allocation and resource tracking

### CloudFormation Parameters

Modify the following parameters in your CloudFormation deployment:

```yaml
Parameters:
  OrganizationName:
    Type: String
    Default: enterprise-org
  CloudTrailBucketName:
    Type: String
    Default: org-cloudtrail-bucket
  ConfigBucketName:
    Type: String
    Default: org-config-bucket
  BudgetAmount:
    Type: Number
    Default: 5000
```

### CDK Context

Configure CDK context in `cdk.json`:

```json
{
  "context": {
    "organizationName": "enterprise-org",
    "cloudTrailBucket": "org-cloudtrail-bucket",
    "configBucket": "org-config-bucket",
    "budgetAmount": 5000,
    "allowedRegions": ["us-east-1", "us-west-2", "eu-west-1"]
  }
}
```

### Terraform Variables

Customize deployment in `terraform.tfvars`:

```hcl
organization_name      = "enterprise-org"
cloudtrail_bucket_name = "org-cloudtrail-bucket"
config_bucket_name     = "org-config-bucket"
budget_amount          = 5000
allowed_regions        = ["us-east-1", "us-west-2", "eu-west-1"]
cost_control_tags      = ["Department", "Project", "Environment", "Owner"]
```

## Service Control Policies

The implementation includes three main Service Control Policies:

### 1. Cost Control Policy
- Prevents provisioning of expensive instance types (8xlarge and above)
- Restricts high-cost RDS instances
- Enforces mandatory cost allocation tags
- Applied to Production and Development OUs

### 2. Security Baseline Policy
- Prevents root user actions
- Protects CloudTrail and AWS Config from being disabled
- Enforces S3 encryption requirements
- Applied to Production OU

### 3. Region Restriction Policy
- Limits resource deployment to approved regions
- Allows global services (IAM, CloudFront, etc.)
- Applied to Sandbox OU to prevent expensive regional sprawl

## Validation and Testing

After deployment, validate the governance framework:

```bash
# Verify organization structure
aws organizations list-organizational-units \
    --parent-id $(aws organizations describe-organization \
                  --query Organization.Id --output text)

# Test SCP enforcement (should fail)
aws ec2 run-instances \
    --image-id ami-0abcdef1234567890 \
    --instance-type m5.8xlarge \
    --max-count 1 \
    --min-count 1 \
    --dry-run

# Check CloudTrail status
aws cloudtrail get-trail-status \
    --name "OrganizationTrail"

# View governance dashboard
aws cloudwatch get-dashboard \
    --dashboard-name "OrganizationGovernance"
```

## Monitoring and Compliance

The deployment includes:

- **CloudWatch Dashboard**: Real-time governance metrics
- **CloudTrail Logging**: Organization-wide API activity tracking
- **Cost Budgets**: Automated budget monitoring and alerts
- **Policy Compliance**: SCP enforcement across organizational units

Access the CloudWatch dashboard to monitor:
- Organization account metrics
- Policy violation attempts
- Cost trending and budget status
- Audit trail activity

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name multi-account-governance

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name multi-account-governance \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the infrastructure
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

- **Least Privilege**: All IAM roles follow least privilege principles
- **Encryption**: S3 buckets are encrypted with AES-256
- **Audit Logging**: Comprehensive CloudTrail logging across all accounts
- **Policy Enforcement**: SCPs prevent security and cost violations
- **Access Control**: Organization management restricted to authorized users

## Cost Optimization

The governance framework includes several cost optimization features:

- **Instance Type Restrictions**: Prevents expensive instance types
- **Regional Limits**: Controls resource deployment geography
- **Budget Monitoring**: Automated cost tracking and alerts
- **Tagging Enforcement**: Mandatory cost allocation tags
- **Consolidated Billing**: Unified billing across all accounts

## Troubleshooting

### Common Issues

1. **SCP Conflicts**: If legitimate operations are blocked, review SCP conditions
2. **CloudTrail Permissions**: Ensure proper S3 bucket policies for CloudTrail delivery
3. **Organization Limits**: Check AWS service limits for organizations and accounts
4. **IAM Permissions**: Verify sufficient permissions for organization management

### Debug Commands

```bash
# Check organization status
aws organizations describe-organization

# List attached policies
aws organizations list-policies-for-target \
    --target-id <ou-id> \
    --filter SERVICE_CONTROL_POLICY

# Validate SCP syntax
aws organizations describe-policy \
    --policy-id <policy-id>

# Check CloudTrail delivery
aws cloudtrail describe-trails \
    --trail-name-list "OrganizationTrail"
```

## Support

- **AWS Documentation**: [AWS Organizations User Guide](https://docs.aws.amazon.com/organizations/)
- **Best Practices**: [AWS Multi-Account Strategy](https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/)
- **Service Control Policies**: [SCP User Guide](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- **Cost Management**: [AWS Cost Management](https://docs.aws.amazon.com/cost-management/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.

## Next Steps

After successful deployment, consider these enhancements:

1. **Account Automation**: Implement automated account provisioning
2. **Advanced Monitoring**: Set up AWS Security Hub and Config rules
3. **Cost Anomaly Detection**: Configure automated cost anomaly detection
4. **Compliance Automation**: Integrate with AWS Config for compliance monitoring
5. **Policy Testing**: Implement automated SCP testing framework