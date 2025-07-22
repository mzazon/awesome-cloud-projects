# Infrastructure as Code for Unified Identity Management System

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Unified Identity Management System".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- AWS account with appropriate permissions for:
  - Directory Service (create and manage AWS Managed Microsoft AD)
  - WorkSpaces (register directories and create workspaces)
  - RDS (create instances with Directory Service integration)
  - IAM (create roles and policies)
  - EC2 (create VPCs, subnets, security groups, and instances)
- On-premises Active Directory environment with domain administrator access (for trust relationships)
- Network connectivity between on-premises and AWS (VPN or Direct Connect) for hybrid scenarios
- Knowledge of Active Directory concepts and Windows networking
- Estimated cost: $350-450/month for AWS Managed Microsoft AD, WorkSpaces, and RDS instance

> **Note**: AWS Managed Microsoft AD requires two domain controllers for high availability at $0.20 per hour each ($292/month total). Additional costs include WorkSpaces and RDS usage.

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name hybrid-identity-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DirectoryName,ParameterValue=corp-hybrid-ad \
                 ParameterKey=VPCCidr,ParameterValue=10.0.0.0/16 \
                 ParameterKey=DirectoryPassword,ParameterValue=TempPassword123! \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name hybrid-identity-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name hybrid-identity-stack \
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
cdk deploy --parameters directoryPassword=TempPassword123!

# View outputs
cdk list --long
```

### Using CDK Python

```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters directory-password=TempPassword123!

# View outputs
cdk list --long
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="directory_password=TempPassword123!"

# Apply the configuration
terraform apply -var="directory_password=TempPassword123!"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters
# Follow the prompts to configure the deployment
```

## Architecture Overview

The infrastructure creates:

1. **AWS Managed Microsoft AD**: Fully managed Active Directory service with two domain controllers
2. **VPC and Networking**: Secure network infrastructure with subnets and security groups
3. **WorkSpaces Integration**: Directory registration for virtual desktop provisioning
4. **RDS SQL Server**: Database instance with Windows Authentication support
5. **IAM Roles**: Service roles for RDS Directory Service integration
6. **Security Groups**: Network access control for directory services

## Configuration Options

### CloudFormation Parameters

- `DirectoryName`: Name for the AWS Managed Microsoft AD directory
- `DirectoryPassword`: Password for directory admin account
- `VPCCidr`: CIDR block for the VPC (default: 10.0.0.0/16)
- `EnableWorkSpaces`: Whether to register directory with WorkSpaces
- `CreateRDSInstance`: Whether to create RDS instance with directory integration

### CDK Configuration

Modify the configuration in the CDK app files:

```typescript
// CDK TypeScript - app.ts
const directoryProps = {
  directoryName: 'corp-hybrid-ad',
  directoryPassword: 'TempPassword123!',
  vpcCidr: '10.0.0.0/16',
  enableWorkSpaces: true,
  createRDS: true
};
```

```python
# CDK Python - app.py
directory_props = {
    "directory_name": "corp-hybrid-ad",
    "directory_password": "TempPassword123!",
    "vpc_cidr": "10.0.0.0/16",
    "enable_workspaces": True,
    "create_rds": True
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
directory_name     = "corp-hybrid-ad"
directory_password = "TempPassword123!"
vpc_cidr          = "10.0.0.0/16"
region            = "us-west-2"
enable_workspaces = true
create_rds        = true
rds_instance_class = "db.t3.medium"
```

## Post-Deployment Configuration

### 1. Create Directory Users

Connect to the domain admin instance and create test users:

```powershell
# On the Windows admin instance
New-ADUser -Name "TestUser1" -UserPrincipalName "testuser1@corp-hybrid-ad.corp.local" -AccountPassword (ConvertTo-SecureString "UserPassword123!" -AsPlainText -Force) -Enabled $true

New-ADUser -Name "TestUser2" -UserPrincipalName "testuser2@corp-hybrid-ad.corp.local" -AccountPassword (ConvertTo-SecureString "UserPassword123!" -AsPlainText -Force) -Enabled $true
```

### 2. Create WorkSpaces

```bash
# Get directory ID from outputs
DIRECTORY_ID=$(terraform output -raw directory_id)  # or from CloudFormation/CDK outputs

# Create WorkSpaces for users
aws workspaces create-workspaces \
    --workspaces '[{
        "DirectoryId": "'${DIRECTORY_ID}'",
        "UserName": "testuser1",
        "BundleId": "wsb-bh8rsxt14",
        "VolumeEncryptionKey": "alias/aws/workspaces",
        "UserVolumeEncryptionEnabled": true,
        "RootVolumeEncryptionEnabled": true
    }]'
```

### 3. Configure Trust Relationship (Optional)

For hybrid scenarios with on-premises Active Directory:

```bash
# Create trust relationship
aws ds create-trust \
    --directory-id ${DIRECTORY_ID} \
    --remote-domain-name "onprem.corp.local" \
    --trust-password "TrustPassword123!" \
    --trust-direction "Two-Way" \
    --trust-type "Forest" \
    --conditional-forwarder-ip-addrs "10.1.1.10" "10.1.1.11"
```

## Validation

### 1. Verify Directory Status

```bash
# Check directory status
aws ds describe-directories \
    --directory-ids ${DIRECTORY_ID} \
    --query 'DirectoryDescriptions[0].{Status:Stage,Name:Name,DnsIpAddrs:DnsIpAddrs}'

# Verify LDAPS is enabled
aws ds describe-ldaps-settings \
    --directory-id ${DIRECTORY_ID} \
    --query 'LDAPSSettingsInfo[0].LDAPSStatus'
```

### 2. Test WorkSpaces Registration

```bash
# Verify WorkSpaces directory registration
aws workspaces describe-workspace-directories \
    --directory-ids ${DIRECTORY_ID} \
    --query 'Directories[0].{State:State,Type:DirectoryType,Name:DirectoryName}'
```

### 3. Validate RDS Integration

```bash
# Check RDS instance domain membership
aws rds describe-db-instances \
    --db-instance-identifier $(terraform output -raw rds_instance_id) \
    --query 'DBInstances[0].{Status:DBInstanceStatus,Domain:DomainMemberships[0].Domain}'
```

## Cleanup

### Using CloudFormation

```bash
# Delete WorkSpaces first (if any were created)
aws workspaces terminate-workspaces \
    --terminate-workspace-requests "WorkspaceId=ws-xxxxxxxxx"

# Wait for WorkSpaces termination
sleep 120

# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name hybrid-identity-stack

# Wait for stack deletion
aws cloudformation wait stack-delete-complete \
    --stack-name hybrid-identity-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="directory_password=TempPassword123!"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Security Considerations

1. **Directory Password**: Change default passwords immediately after deployment
2. **Network Security**: Configure security groups to allow only necessary traffic
3. **Encryption**: Enable encryption for WorkSpaces volumes and RDS storage
4. **Trust Relationships**: Use strong passwords for trust relationships
5. **Monitoring**: Enable CloudTrail logging for directory service activities
6. **Multi-Factor Authentication**: Implement MFA for administrative accounts

## Troubleshooting

### Common Issues

1. **Directory Creation Fails**: Ensure subnets are in different Availability Zones
2. **WorkSpaces Registration Fails**: Verify directory is in "Active" state
3. **RDS Integration Issues**: Check IAM role permissions and security groups
4. **Trust Relationship Problems**: Verify network connectivity and DNS resolution

### Debug Commands

```bash
# Check directory events
aws ds describe-domain-controllers --directory-id ${DIRECTORY_ID}

# View directory security groups
aws ds describe-directories --directory-ids ${DIRECTORY_ID} \
    --query 'DirectoryDescriptions[0].VpcSettings.SecurityGroupId'

# Check WorkSpaces directory status
aws workspaces describe-workspace-directories --directory-ids ${DIRECTORY_ID}
```

## Cost Optimization

- **Directory Service**: Standard edition provides basic features at lower cost
- **WorkSpaces**: Use AUTO_STOP running mode to reduce costs for part-time users
- **RDS**: Right-size instance based on actual usage patterns
- **Data Transfer**: Keep resources in same region to minimize transfer costs

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS Directory Service documentation
3. Consult the original recipe documentation
4. Check AWS support forums and documentation

## References

- [AWS Directory Service Administration Guide](https://docs.aws.amazon.com/directoryservice/latest/admin-guide/)
- [WorkSpaces Active Directory Integration](https://docs.aws.amazon.com/workspaces/latest/adminguide/active-directory.html)
- [RDS Windows Authentication Configuration](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/custom-sqlserver-WinAuth.config-ADS.html)
- [AWS Directory Service Best Practices](https://docs.aws.amazon.com/directoryservice/latest/admin-guide/ms_ad_best_practices.html)