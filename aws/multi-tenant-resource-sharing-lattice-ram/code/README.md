# Infrastructure as Code for Multi-Tenant Resource Sharing with VPC Lattice and RAM

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Tenant Resource Sharing with VPC Lattice and RAM".

## Overview

This solution demonstrates how to create a multi-tenant architecture using Amazon VPC Lattice as the application networking layer combined with AWS Resource Access Manager (RAM) for secure cross-account resource sharing. The infrastructure includes:

- Amazon VPC Lattice Service Network with IAM authentication
- RDS MySQL database instance as a shared resource
- VPC Lattice Resource Configuration for database integration
- AWS RAM Resource Share for cross-account access
- IAM roles with team-based access control
- CloudTrail audit logging for compliance
- Authentication policies with attribute-based access control

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- IAM permissions for VPC Lattice, AWS RAM, RDS, IAM, CloudTrail, and S3 operations
- Understanding of AWS networking concepts and IAM policies
- Multiple AWS accounts or cross-account access for testing (minimum 2 accounts recommended)
- Estimated cost: $12-18 for RDS instance and associated resources during testing period

### Required IAM Permissions

Your deployment user/role needs the following permissions:
- `vpc-lattice:*`
- `ram:*`
- `rds:*`
- `iam:CreateRole`, `iam:DeleteRole`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`
- `ec2:CreateSecurityGroup`, `ec2:DeleteSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress`
- `cloudtrail:*`
- `s3:CreateBucket`, `s3:DeleteBucket`, `s3:PutBucketPolicy`
- `organizations:DescribeOrganization` (optional, for RAM sharing)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name multi-tenant-lattice-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=TeamAName,ParameterValue=TeamA \
                 ParameterKey=TeamBName,ParameterValue=TeamB \
                 ParameterKey=DBMasterUsername,ParameterValue=admin \
                 ParameterKey=DBMasterPassword,ParameterValue=TempPassword123!

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name multi-tenant-lattice-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name multi-tenant-lattice-stack \
    --query "Stacks[0].Outputs" \
    --output table
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
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

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for configuration values
# and deploy all resources step by step
```

## Configuration Options

### CloudFormation Parameters

- `TeamAName`: Name for the first tenant team (default: TeamA)
- `TeamBName`: Name for the second tenant team (default: TeamB)
- `DBMasterUsername`: RDS master username (default: admin)
- `DBMasterPassword`: RDS master password (must meet complexity requirements)
- `DBInstanceClass`: RDS instance type (default: db.t3.micro)
- `EnableMultiAZ`: Enable Multi-AZ deployment (default: false)
- `BackupRetentionPeriod`: Backup retention days (default: 7)

### CDK Configuration

Modify the configuration in the CDK app files:

```typescript
// cdk-typescript/app.ts
const config = {
  teamAName: 'TeamA',
  teamBName: 'TeamB',
  dbInstanceClass: 'db.t3.micro',
  enableMultiAZ: false,
  backupRetentionPeriod: 7
};
```

```python
# cdk-python/app.py
config = {
    "team_a_name": "TeamA",
    "team_b_name": "TeamB",
    "db_instance_class": "db.t3.micro",
    "enable_multi_az": False,
    "backup_retention_period": 7
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
team_a_name              = "TeamA"
team_b_name              = "TeamB"
db_instance_class        = "db.t3.micro"
db_master_username       = "admin"
db_master_password       = "TempPassword123!"
enable_multi_az          = false
backup_retention_period  = 7
```

## Validation and Testing

After deployment, validate the infrastructure:

### Test Service Network

```bash
# Get service network details
aws vpc-lattice list-service-networks \
    --query "items[?contains(name, 'multitenant')].{Name:name,Status:status,AuthType:authType}"

# Verify VPC association
aws vpc-lattice list-service-network-vpc-associations \
    --query "items[?status=='ACTIVE'].{ServiceNetwork:serviceNetworkName,VPC:vpcId,Status:status}"
```

### Test Resource Configuration

```bash
# List resource configurations
aws vpc-lattice list-resource-configurations \
    --query "items[?contains(name, 'shared-database')].{Name:name,Type:type,Status:status}"
```

### Test IAM Roles

```bash
# List created roles
aws iam list-roles \
    --query "Roles[?contains(RoleName, 'DatabaseAccess')].{RoleName:RoleName,CreateDate:CreateDate}"

# Test role assumption (replace with actual role ARN)
aws sts assume-role \
    --role-arn arn:aws:iam::ACCOUNT-ID:role/TeamA-DatabaseAccess-SUFFIX \
    --role-session-name TestSession \
    --external-id TeamA-Access
```

### Test AWS RAM Share

```bash
# List resource shares
aws ram get-resource-shares \
    --resource-owner SELF \
    --query "resourceShares[?contains(name, 'database-share')].{Name:name,Status:status}"
```

## Security Considerations

This implementation includes several security best practices:

1. **Encryption at Rest**: RDS instance uses AWS managed encryption
2. **Network Isolation**: Database is not publicly accessible
3. **Least Privilege IAM**: Role policies follow least privilege principles
4. **Attribute-Based Access Control**: VPC Lattice auth policies use principal tags
5. **Audit Logging**: CloudTrail captures all API calls
6. **Time-Based Access**: Authentication policies include time restrictions
7. **IP-Based Restrictions**: Access limited to private IP ranges

## Monitoring and Observability

The deployed infrastructure includes:

- **CloudTrail**: Comprehensive API call logging
- **VPC Flow Logs**: Network traffic monitoring (can be enabled post-deployment)
- **CloudWatch**: Service metrics and alarms
- **AWS Config**: Configuration compliance monitoring (can be integrated)

### Enable Additional Monitoring

```bash
# Enable VPC Flow Logs for the default VPC
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids vpc-xxxxxxxxx \
    --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name VPCFlowLogs
```

## Troubleshooting

### Common Issues

1. **CloudFormation Stack Fails**: Check IAM permissions and parameter values
2. **RDS Creation Timeout**: Instance creation can take 10-15 minutes
3. **VPC Lattice Association Fails**: Ensure VPC exists and has proper subnets
4. **RAM Share Not Visible**: Verify organizational settings and account relationships
5. **Role Assumption Fails**: Check trust policies and external ID requirements

### Debug Commands

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name multi-tenant-lattice-stack

# View CloudTrail logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/cloudtrail

# Check VPC Lattice service health
aws vpc-lattice list-services \
    --query "items[].{Name:name,Status:status}"
```

## Cost Optimization

To minimize costs during testing:

1. **Use Spot Instances**: For non-production workloads
2. **Schedule Shutdowns**: Use AWS Instance Scheduler
3. **Right-size Resources**: Start with t3.micro instances
4. **Clean Up Regularly**: Use the destroy scripts when not needed
5. **Monitor Usage**: Set up billing alerts

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this will remove all resources)
aws cloudformation delete-stack \
    --stack-name multi-tenant-lattice-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name multi-tenant-lattice-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/
terraform destroy

# Type 'yes' when prompted to confirm destruction
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Multi-Account Setup

For true multi-tenant testing across accounts:

1. **Accept RAM Invitations**: In target accounts, accept resource share invitations
2. **Associate VPCs**: Associate target account VPCs with the shared service network
3. **Configure IAM**: Set up cross-account IAM roles and trust relationships
4. **Test Connectivity**: Verify applications can access shared resources

### Cross-Account IAM Setup

```bash
# In the resource sharing account, create cross-account trust
aws iam create-role \
    --role-name CrossAccountLatticeAccess \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"AWS": "arn:aws:iam::TARGET-ACCOUNT:root"},
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "MultiTenantAccess"
                }
            }
        }]
    }'
```

## Extensions and Enhancements

Consider these enhancements for production use:

1. **Add Application Load Balancer**: For HTTP/HTTPS services
2. **Implement Service Mesh**: Add AWS App Mesh for advanced traffic management
3. **Add Container Services**: Deploy applications using ECS or EKS
4. **Enhance Monitoring**: Add custom CloudWatch dashboards
5. **Implement GitOps**: Use AWS CodePipeline for infrastructure automation
6. **Add Secrets Management**: Use AWS Secrets Manager for database credentials

## Support and Documentation

- [Amazon VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- [AWS Resource Access Manager User Guide](https://docs.aws.amazon.com/ram/latest/userguide/)
- [Amazon RDS User Guide](https://docs.aws.amazon.com/rds/latest/userguide/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's policies before deploying in production environments.