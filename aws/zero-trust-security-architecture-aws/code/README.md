# Infrastructure as Code for Zero Trust Security Architecture with AWS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Zero Trust Security Architecture with AWS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys a comprehensive zero trust security architecture that includes:

- **Identity Layer**: IAM Identity Center with MFA enforcement
- **Network Layer**: VPC with private subnets, security groups, and VPC endpoints
- **Data Layer**: S3 buckets with KMS encryption and access controls
- **Monitoring**: Security Hub, GuardDuty, Config, and CloudWatch integration
- **Compliance**: Automated security monitoring and response capabilities

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured
- AWS account with administrative permissions
- Understanding of zero trust security principles
- Estimated cost: $50-100/month for comprehensive monitoring services

### Tool-Specific Requirements

#### CloudFormation
- AWS CLI configured with appropriate permissions
- CloudFormation service permissions

#### CDK TypeScript
- Node.js (v16 or later)
- npm or yarn package manager
- AWS CDK CLI: `npm install -g aws-cdk`

#### CDK Python
- Python 3.8 or later
- pip package manager
- AWS CDK CLI: `pip install aws-cdk-lib`

#### Terraform
- Terraform (v1.0 or later)
- AWS provider configured

### Required AWS Service Permissions

The deployment requires permissions for the following services:
- IAM (roles, policies, users)
- VPC (subnets, security groups, endpoints)
- S3 (buckets, encryption, policies)
- KMS (keys, aliases, policies)
- Security Hub (enable, configure standards)
- GuardDuty (detectors, threat intelligence)
- AWS Config (recorders, rules, delivery channels)
- CloudWatch (dashboards, alarms, logs)
- Lambda (functions, permissions)
- SNS (topics, subscriptions)
- Systems Manager (session manager, documents)

## Quick Start

### Using CloudFormation

```bash
# Create the zero trust security stack
aws cloudformation create-stack \
    --stack-name zero-trust-security-architecture \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=ProjectName,ParameterValue=zero-trust \
        ParameterKey=Environment,ParameterValue=production \
        ParameterKey=AlertEmail,ParameterValue=security-team@example.com \
    --capabilities CAPABILITY_NAMED_IAM \
    --enable-termination-protection

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name zero-trust-security-architecture \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure CDK environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --require-approval never \
    --parameters alertEmail=security-team@example.com \
    --parameters projectName=zero-trust
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure CDK environment
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Deploy the stack
cdk deploy --require-approval never \
    --parameters alertEmail=security-team@example.com \
    --parameters projectName=zero-trust
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_name = "zero-trust"
environment = "production"
alert_email = "security-team@example.com"
allowed_cidr_blocks = ["203.0.113.0/24", "198.51.100.0/24"]
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_NAME="zero-trust"
export ENVIRONMENT="production"
export ALERT_EMAIL="security-team@example.com"

# Deploy infrastructure
./scripts/deploy.sh
```

## Post-Deployment Configuration

### 1. Configure IAM Identity Center

After deployment, complete the Identity Center setup:

```bash
# Enable Identity Center (if not already enabled)
aws sso-admin create-instance

# Configure external identity provider (optional)
# Follow AWS documentation for SAML 2.0 integration
```

### 2. Configure Security Monitoring

```bash
# Subscribe to SNS alerts
aws sns subscribe \
    --topic-arn $(terraform output security_alerts_topic_arn) \
    --protocol email \
    --notification-endpoint security-team@example.com

# Confirm subscription in email
```

### 3. Test Zero Trust Controls

```bash
# Test MFA enforcement
aws sts get-caller-identity

# Test network restrictions
# Attempt access from non-approved IP range (should be denied)

# Test S3 encryption enforcement
aws s3 cp test-file.txt s3://$(terraform output secure_bucket_name)/ \
    --server-side-encryption AES256
```

## Security Considerations

⚠️ **Important Security Notes**:

1. **MFA Requirement**: All policies enforce MFA. Ensure you have MFA configured before deployment.
2. **Network Restrictions**: Policies restrict access to trusted IP ranges. Update `allowed_cidr_blocks` with your organization's IP ranges.
3. **Break-Glass Access**: Maintain alternative access methods for emergency situations.
4. **Gradual Rollout**: Test in development environments before applying to production.

## Monitoring and Alerting

The deployed infrastructure includes:

- **Security Hub**: Centralized security findings dashboard
- **GuardDuty**: Intelligent threat detection
- **Config Rules**: Continuous compliance monitoring
- **CloudWatch Alarms**: Automated alerting for security events
- **Lambda Functions**: Automated response capabilities

### Accessing Security Dashboard

```bash
# Get Security Hub console URL
echo "https://console.aws.amazon.com/securityhub/home?region=$(aws configure get region)#/findings"

# Get CloudWatch dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=$(aws configure get region)#dashboards:name=$(terraform output dashboard_name)"
```

## Customization

### Key Variables/Parameters

- **project_name**: Prefix for all resource names
- **environment**: Environment designation (dev, staging, prod)
- **alert_email**: Email for security notifications
- **allowed_cidr_blocks**: Trusted IP ranges for network access
- **session_timeout**: Maximum session duration for Identity Center
- **log_retention_days**: CloudWatch log retention period

### Extending the Architecture

1. **Additional VPCs**: Extend network architecture across multiple VPCs
2. **Cross-Region Deployment**: Deploy in multiple AWS regions
3. **Advanced Monitoring**: Add custom Config rules and GuardDuty filters
4. **Integration**: Connect with external SIEM or security tools

## Troubleshooting

### Common Issues

1. **Identity Center Not Enabled**:
   ```bash
   # Enable Identity Center manually in AWS Console
   # Then re-run deployment
   ```

2. **MFA Lock-out**:
   ```bash
   # Use root account or break-glass procedure
   # Temporarily modify conditional access policies
   ```

3. **Network Access Denied**:
   ```bash
   # Verify your IP is in allowed_cidr_blocks
   # Check security group rules
   ```

### Validation Commands

```bash
# Check Security Hub status
aws securityhub get-enabled-standards

# Verify GuardDuty detector
aws guardduty list-detectors

# Test Config compliance
aws configservice get-compliance-details-by-config-rule \
    --config-rule-name zero-trust-mfa-enabled

# Check KMS key status
aws kms describe-key --key-id $(terraform output kms_key_id)
```

## Cleanup

### Using CloudFormation

```bash
# Disable termination protection
aws cloudformation update-termination-protection \
    --stack-name zero-trust-security-architecture \
    --no-enable-termination-protection

# Delete stack
aws cloudformation delete-stack \
    --stack-name zero-trust-security-architecture

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name zero-trust-security-architecture \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy TypeScript stack
cd cdk-typescript/
cdk destroy

# Destroy Python stack
cd cdk-python/
source .venv/bin/activate  # If using virtual environment
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

Some resources may require manual cleanup:

```bash
# Delete S3 bucket contents
aws s3 rm s3://bucket-name --recursive

# Schedule KMS key deletion
aws kms schedule-key-deletion --key-id key-id --pending-window-in-days 7

# Disable Identity Center (if no longer needed)
# This must be done through the AWS Console
```

## Cost Optimization

### Expected Costs

- **Security Hub**: ~$0.0024 per finding
- **GuardDuty**: ~$4.00 per million events
- **Config**: ~$0.003 per configuration item
- **CloudWatch**: ~$0.50 per GB ingested
- **KMS**: ~$1.00 per key per month

### Cost Reduction Tips

1. **Adjust log retention**: Reduce CloudWatch log retention periods
2. **Filter findings**: Configure Security Hub to focus on critical findings
3. **Regional deployment**: Deploy only in required regions
4. **Resource tagging**: Use tags for cost allocation and optimization

## Compliance and Auditing

The infrastructure supports various compliance frameworks:

- **SOC 2**: Logging and monitoring controls
- **PCI DSS**: Encryption and access controls
- **NIST**: Zero trust architecture principles
- **CIS**: AWS security benchmarks

### Audit Reports

```bash
# Generate Config compliance report
aws configservice get-compliance-summary-by-config-rule

# Export Security Hub findings
aws securityhub get-findings --output table

# CloudTrail audit logs
aws logs describe-log-groups --log-group-name-prefix "/aws/cloudtrail"
```

## Support and Documentation

### Additional Resources

- [AWS Zero Trust Architecture Guide](https://docs.aws.amazon.com/whitepapers/latest/zero-trust-architectures-aws/zero-trust-architectures-aws.html)
- [Security Hub User Guide](https://docs.aws.amazon.com/securityhub/latest/userguide/)
- [GuardDuty User Guide](https://docs.aws.amazon.com/guardduty/latest/ug/)
- [Identity Center Administration Guide](https://docs.aws.amazon.com/singlesignon/latest/userguide/)

### Getting Help

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service status pages
3. Consult AWS documentation for specific services
4. Contact AWS Support for service-specific issues

### Contributing

To improve this infrastructure code:
1. Test changes in development environment
2. Validate security implications
3. Update documentation accordingly
4. Follow infrastructure as code best practices