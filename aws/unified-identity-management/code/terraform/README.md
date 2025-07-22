# Terraform Infrastructure for Hybrid Identity Management with AWS Directory Service

This Terraform configuration creates a complete hybrid identity management solution using AWS Managed Microsoft AD, Amazon WorkSpaces, and RDS SQL Server with Windows Authentication integration.

## Architecture Overview

The infrastructure creates:

- **AWS Managed Microsoft AD**: Fully managed Active Directory service with high availability
- **Amazon WorkSpaces**: Virtual desktop infrastructure integrated with the directory
- **RDS SQL Server**: Database with Windows Authentication support
- **VPC Networking**: Secure network infrastructure with public and private subnets
- **Security Groups**: Granular network access controls
- **IAM Roles**: Service integration and permissions management
- **CloudTrail**: Optional auditing and compliance logging
- **Domain Management**: EC2 instance for Active Directory administration

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate permissions
2. **Terraform** version >= 1.0 installed
3. **AWS Account** with permissions for:
   - Directory Service (create and manage directories)
   - WorkSpaces (create and manage virtual desktops)
   - RDS (create and manage database instances)
   - EC2 (create instances, VPCs, security groups)
   - IAM (create roles and policies)
   - CloudWatch and CloudTrail (for logging)
4. **SSH Key Pair** for EC2 instance access (update `aws_key_pair` resource)
5. **Network Connectivity** (VPN or Direct Connect) if enabling on-premises trust relationships

## Required Permissions

Your AWS credentials must have permissions for:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ds:*",
                "workspaces:*",
                "rds:*",
                "ec2:*",
                "iam:*",
                "logs:*",
                "cloudtrail:*",
                "s3:*"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository and navigate to the terraform directory
cd aws/hybrid-identity-management-aws-directory-service/code/terraform/

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars
```

### 2. Customize Variables

Edit `terraform.tfvars` to match your requirements:

```hcl
# Basic Configuration
aws_region     = "us-east-1"
environment    = "dev"
project_name   = "hybrid-identity"

# Directory Configuration
directory_name     = "corp.local"
directory_password = "YourSecurePassword123!"
directory_edition  = "Standard"

# Feature Toggles
enable_workspaces        = true
enable_rds              = true
enable_cloudtrail       = true
enable_on_premises_trust = false

# Test Users
create_test_users = true

# Network Configuration
vpc_cidr              = "10.0.0.0/16"
public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs  = ["10.0.10.0/24", "10.0.20.0/24"]
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Deploy the infrastructure
terraform apply
```

The deployment typically takes 45-60 minutes due to Directory Service provisioning time.

### 4. Verify Deployment

After deployment completes, verify the infrastructure:

```bash
# Check directory status
aws ds describe-directories

# Verify WorkSpaces registration (if enabled)
aws workspaces describe-workspace-directories

# Check RDS domain membership (if enabled)
aws rds describe-db-instances --query 'DBInstances[?DomainMemberships!=null]'
```

## Configuration Options

### Core Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `project_name` | Project name for resource naming | `hybrid-identity` | No |

### Directory Service

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `directory_name` | FQDN for the directory | `corp.local` | No |
| `directory_password` | Admin password (generated if empty) | `""` | No |
| `directory_edition` | Standard or Enterprise | `Standard` | No |

### WorkSpaces Integration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_workspaces` | Enable WorkSpaces integration | `true` | No |
| `workspaces_bundle_id` | WorkSpaces bundle ID | `wsb-bh8rsxt14` | No |
| `enable_workdocs` | Enable WorkDocs integration | `true` | No |

### RDS Integration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_rds` | Enable RDS SQL Server | `true` | No |
| `rds_instance_class` | RDS instance type | `db.t3.medium` | No |
| `rds_allocated_storage` | Storage size in GB | `200` | No |

### Trust Relationships

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_on_premises_trust` | Enable on-premises trust | `false` | No |
| `on_premises_domain_name` | On-premises domain FQDN | `""` | If trust enabled |
| `on_premises_dns_ips` | On-premises DNS servers | `[]` | If trust enabled |

## Post-Deployment Steps

### 1. Access Domain Admin Instance

```bash
# Get instance ID from Terraform output
INSTANCE_ID=$(terraform output -raw domain_admin_instance_id)

# Connect via Session Manager (recommended)
aws ssm start-session --target $INSTANCE_ID

# Or use RDP (requires VPN/bastion host for private instance)
# RDP to the private IP shown in outputs
```

### 2. Create Active Directory Users

Connect to the domain admin instance and create users:

```powershell
# Import Active Directory module
Import-Module ActiveDirectory

# Create organizational unit for users
New-ADOrganizationalUnit -Name "CloudUsers" -Path "DC=corp,DC=local"

# Create test user
New-ADUser -Name "TestUser1" -GivenName "Test" -Surname "User1" -SamAccountName "testuser1" -UserPrincipalName "testuser1@corp.local" -Path "OU=CloudUsers,DC=corp,DC=local" -AccountPassword (ConvertTo-SecureString "TempPassword123!" -AsPlainText -Force) -Enabled $true

# Create WorkSpaces user
New-ADUser -Name "WorkSpacesUser" -GivenName "WorkSpaces" -Surname "User" -SamAccountName "workspacesuser" -UserPrincipalName "workspacesuser@corp.local" -Path "OU=CloudUsers,DC=corp,DC=local" -AccountPassword (ConvertTo-SecureString "TempPassword123!" -AsPlainText -Force) -Enabled $true
```

### 3. Create WorkSpaces for Users

```bash
# Create WorkSpace for user
aws workspaces create-workspaces --workspaces '{
    "DirectoryId": "'$(terraform output -raw directory_id)'",
    "UserName": "testuser1",
    "BundleId": "wsb-bh8rsxt14",
    "WorkspaceProperties": {
        "RunningMode": "AUTO_STOP",
        "RunningModeAutoStopTimeoutInMinutes": 60,
        "ComputeTypeName": "STANDARD"
    }
}'
```

### 4. Configure RDS Windows Authentication

```sql
-- Connect to RDS instance as admin user
-- Enable Windows Authentication for domain users

-- Create Windows login for domain users
CREATE LOGIN [CORP\testuser1] FROM WINDOWS;

-- Grant database access
USE [master]
CREATE USER [CORP\testuser1] FOR LOGIN [CORP\testuser1];

-- Add to database roles as needed
ALTER ROLE [db_datareader] ADD MEMBER [CORP\testuser1];
```

### 5. Configure Trust Relationship (Optional)

If enabling on-premises trust, configure on both sides:

**AWS Side (already configured by Terraform):**
- Trust relationship created with specified parameters

**On-Premises Side:**
```powershell
# On on-premises domain controller
# Create trust relationship pointing to AWS domain
netdom trust aws.corp.local /domain:onprem.corp.local /add /twoway /userD:Administrator /passwordD:TrustPassword123!
```

## Monitoring and Maintenance

### CloudWatch Monitoring

Monitor directory service health:

```bash
# View directory service logs
aws logs describe-log-groups --log-group-name-prefix "/aws/directoryservice"

# Monitor WorkSpaces usage
aws workspaces describe-workspace-connection-status

# Check RDS performance
aws rds describe-db-instances --query 'DBInstances[0].DomainMemberships'
```

### Regular Maintenance Tasks

1. **Password Policy**: Configure and enforce strong password policies
2. **User Management**: Regularly review and manage user accounts
3. **Security Groups**: Audit and update security group rules
4. **Backup Verification**: Ensure RDS backups are functioning
5. **Trust Relationship**: Monitor trust relationship health if configured

## Troubleshooting

### Common Issues

**Directory Service not accessible:**
```bash
# Check directory status
aws ds describe-directories --directory-ids $(terraform output -raw directory_id)

# Verify DNS configuration
nslookup $(terraform output -raw directory_name)
```

**WorkSpaces registration failed:**
```bash
# Check WorkSpaces directory registration
aws workspaces describe-workspace-directories --directory-ids $(terraform output -raw directory_id)

# Verify subnet configuration
aws ec2 describe-subnets --subnet-ids $(terraform output -json private_subnet_ids | jq -r '.[]')
```

**RDS domain join failed:**
```bash
# Check RDS domain membership
aws rds describe-db-instances --db-instance-identifier $(terraform output -raw rds_instance_id) --query 'DBInstances[0].DomainMemberships'

# Verify IAM role
aws iam get-role --role-name $(terraform output -raw rds_directory_service_role_arn | cut -d'/' -f2)
```

### Log Analysis

**Directory Service Logs:**
```bash
# View directory service events
aws logs filter-log-events --log-group-name $(terraform output -raw cloudwatch_log_group_name)
```

**CloudTrail Analysis:**
```bash
# Search for directory service API calls
aws logs filter-log-events --log-group-name "CloudTrail/DirectoryService" --filter-pattern "DirectoryService"
```

## Security Considerations

### Network Security
- All directory services are deployed in private subnets
- Security groups enforce least privilege access
- NAT gateways provide controlled internet access

### Identity Security
- Strong password policies enforced
- Multi-factor authentication recommended
- Regular access reviews required

### Data Security
- Encryption at rest enabled for RDS
- CloudTrail logging for compliance
- VPC Flow Logs for network monitoring

## Cost Optimization

### Estimated Monthly Costs

- **AWS Managed Microsoft AD (Standard)**: ~$292/month
- **WorkSpaces (per user)**: ~$25-35/month
- **RDS SQL Server**: ~$150-300/month
- **EC2 Management Instance**: ~$30-50/month
- **NAT Gateways**: ~$45-90/month
- **Total**: ~$522-985/month

### Cost Reduction Strategies

1. **Use AUTO_STOP for WorkSpaces** to reduce costs during non-business hours
2. **Right-size RDS instances** based on actual usage
3. **Consider reserved instances** for predictable workloads
4. **Monitor and optimize** data transfer costs

## Backup and Disaster Recovery

### Automated Backups
- **Directory Service**: Automatic snapshots
- **RDS**: Point-in-time recovery enabled
- **CloudTrail**: S3 versioning enabled

### Disaster Recovery
- Multi-AZ deployment ensures high availability
- Cross-region snapshots for critical data
- Documented recovery procedures

## Cleanup

To destroy all created resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

**Warning**: This will permanently delete all resources and data. Ensure you have backups of any important data before running destroy.

## Support and Documentation

### AWS Documentation
- [AWS Directory Service](https://docs.aws.amazon.com/directoryservice/)
- [Amazon WorkSpaces](https://docs.aws.amazon.com/workspaces/)
- [Amazon RDS](https://docs.aws.amazon.com/rds/)

### Terraform Documentation
- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Configuration Language](https://www.terraform.io/language)

### Support Channels
- AWS Support (if you have a support plan)
- AWS Community Forums
- Stack Overflow (terraform + aws tags)

## Contributing

To contribute improvements to this Terraform configuration:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This Terraform configuration is provided under the MIT License. See LICENSE file for details.