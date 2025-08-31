# Multi-Tenant Resource Sharing with VPC Lattice and AWS RAM - CDK Python

This directory contains the AWS Cloud Development Kit (CDK) Python implementation for the **Multi-Tenant Resource Sharing with VPC Lattice and AWS RAM** recipe. This CDK application deploys a comprehensive multi-tenant architecture that enables secure resource sharing across AWS accounts while maintaining strict access controls and audit capabilities.

## Architecture Overview

The CDK application creates:

- **VPC Lattice Service Network** with IAM authentication for application networking
- **Amazon RDS Database** as a shared resource with encryption and security best practices
- **VPC Lattice Resource Configuration** to represent the database within the service mesh
- **AWS RAM Resource Share** for cross-account resource sharing
- **IAM Roles** with team-based tags for multi-tenant access control
- **Authentication Policies** with attribute-based access control (ABAC)
- **CloudTrail** for comprehensive audit logging and compliance

## Prerequisites

- **Python 3.8+** installed and configured
- **AWS CLI v2** installed and configured with appropriate permissions
- **AWS CDK v2** installed (`npm install -g aws-cdk`)
- **Node.js 18+** (required for CDK CLI)
- **IAM permissions** for VPC Lattice, AWS RAM, RDS, IAM, CloudTrail, and S3 operations
- **Multiple AWS accounts** or cross-account access for testing multi-tenant scenarios

### Required AWS Permissions

Your AWS credentials should have the following permissions:
- `VPCLatticeFullAccess` or equivalent custom policy
- `AWSResourceAccessManagerFullAccess`
- `AmazonRDSFullAccess`
- `IAMFullAccess`
- `CloudTrailFullAccess`
- `AmazonS3FullAccess`
- `CloudWatchLogsFullAccess`

## Quick Start

### 1. Environment Setup

```bash
# Clone or navigate to the project directory
cd aws/multi-tenant-resource-sharing-lattice-ram/code/cdk-python

# Create and activate Python virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap
```

### 2. Deploy the Application

```bash
# Synthesize CloudFormation template (optional, for validation)
cdk synth

# Deploy the stack
cdk deploy

# Deploy with approval for security changes
cdk deploy --require-approval never
```

### 3. Verify Deployment

```bash
# List deployed stacks
cdk list

# View stack outputs
aws cloudformation describe-stacks \
    --stack-name MultiTenantLatticeRAMStack \
    --query "Stacks[0].Outputs"
```

## Configuration Options

### Environment Variables

Set these environment variables before deployment:

```bash
export CDK_DEFAULT_ACCOUNT="123456789012"
export CDK_DEFAULT_REGION="us-east-1"
```

### Context Parameters

Configure the deployment using CDK context parameters in `cdk.json` or command line:

```bash
# Enable cross-account sharing
cdk deploy -c enableCrossAccountSharing=true

# Specify accounts to share with
cdk deploy -c sharedPrincipals='["123456789012","987654321098"]'

# Set custom region
cdk deploy -c region="us-west-2"
```

### Application Configuration

The CDK application supports several configuration options:

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `enableCrossAccountSharing` | Enable AWS RAM sharing | `false` | `true` |
| `sharedPrincipals` | AWS account IDs to share with | `[]` | `["123456789012"]` |
| `account` | Target AWS account ID | Current account | `"123456789012"` |
| `region` | Target AWS region | Current region | `"us-east-1"` |

## Stack Components

### 1. VPC and Networking

```python
# Creates VPC with public, private, and database subnets
vpc = ec2.Vpc(
    self, "MultiTenantVpc",
    ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
    max_azs=3,
    subnet_configuration=[
        # Public subnets for NAT gateways
        ec2.SubnetConfiguration(
            name="Public",
            subnet_type=ec2.SubnetType.PUBLIC,
            cidr_mask=24
        ),
        # Private subnets for application resources
        ec2.SubnetConfiguration(
            name="Private", 
            subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
            cidr_mask=24
        ),
        # Isolated subnets for database
        ec2.SubnetConfiguration(
            name="Database",
            subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
            cidr_mask=28
        )
    ]
)
```

### 2. VPC Lattice Service Network

```python
# Service network with IAM authentication
service_network = lattice.CfnServiceNetwork(
    self, "MultiTenantServiceNetwork",
    name=f"multitenant-network-{cdk.Aws.STACK_NAME}",
    auth_type="AWS_IAM"
)
```

### 3. RDS Database with Security

```python
# MySQL database with encryption and monitoring
database = rds.DatabaseInstance(
    self, "SharedDatabase",
    engine=rds.DatabaseInstanceEngine.mysql(
        version=rds.MysqlEngineVersion.VER_8_0
    ),
    instance_type=ec2.InstanceType.of(
        ec2.InstanceClass.BURSTABLE3,
        ec2.InstanceSize.MICRO
    ),
    storage_encrypted=True,
    backup_retention=cdk.Duration.days(7),
    enable_performance_insights=True,
    cloudwatch_logs_exports=["error", "general", "slowquery"]
)
```

### 4. Authentication Policy

The stack creates a comprehensive authentication policy with:

- **Team-based access control** using IAM principal tags
- **Time-based conditions** for access windows
- **IP address restrictions** for network-level security
- **Resource-level permissions** for fine-grained control

### 5. Audit and Compliance

```python
# CloudTrail with S3 storage and CloudWatch Logs
trail = cloudtrail.Trail(
    self, "VPCLatticeAuditTrail",
    bucket=trail_bucket,
    cloud_watch_log_group=log_group,
    include_global_service_events=True,
    is_multi_region_trail=True,
    enable_file_validation=True
)
```

## Testing and Validation

### 1. Verify Service Network

```bash
# Get service network information
aws vpc-lattice list-service-networks \
    --query "items[?name=='multitenant-network-MultiTenantLatticeRAMStack']"

# Check VPC association
aws vpc-lattice list-service-network-vpc-associations \
    --service-network-identifier <service-network-id>
```

### 2. Test Database Access

```bash
# Get database endpoint from stack outputs
DB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name MultiTenantLatticeRAMStack \
    --query "Stacks[0].Outputs[?OutputKey=='DatabaseEndpoint'].OutputValue" \
    --output text)

# Test database connectivity (requires VPC access)
mysql -h $DB_ENDPOINT -u admin -p
```

### 3. Validate IAM Roles

```bash
# Assume team role for testing
aws sts assume-role \
    --role-arn "arn:aws:iam::ACCOUNT:role/TeamA-DatabaseAccess-MultiTenantLatticeRAMStack" \
    --role-session-name "TestSession" \
    --external-id "TeamA-Access"
```

### 4. Check CloudTrail Logs

```bash
# View recent CloudTrail events
aws logs filter-log-events \
    --log-group-name "/aws/cloudtrail/vpc-lattice-audit-MultiTenantLatticeRAMStack" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Customization

### Adding New Teams

To add additional teams, modify the `_create_team_roles` method:

```python
def _create_team_roles(self) -> Dict[str, iam.Role]:
    teams = ["TeamA", "TeamB", "TeamC", "TeamD"]  # Add new teams
    roles = {}
    
    for team in teams:
        # Role creation logic...
```

### Custom Authentication Policies

Modify the `_create_auth_policy` method to implement custom access controls:

```python
auth_policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": "vpc-lattice-svcs:Invoke",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:PrincipalTag/Department": ["Engineering", "Sales"]
                },
                "DateBetween": {
                    "aws:CurrentTime": {
                        "aws:TokenIssueTime": "9:00Z",
                        "aws:TokenExpirationTime": "17:00Z"
                    }
                }
            }
        }
    ]
}
```

### Database Configuration

Customize database settings in the `_create_database` method:

```python
database = rds.DatabaseInstance(
    self, "SharedDatabase",
    engine=rds.DatabaseInstanceEngine.postgres(  # Change to PostgreSQL
        version=rds.PostgresEngineVersion.VER_15
    ),
    instance_type=ec2.InstanceType.of(
        ec2.InstanceClass.BURSTABLE4G,  # Use newer instance class
        ec2.InstanceSize.LARGE          # Scale up for production
    ),
    allocated_storage=100,              # Increase storage
    max_allocated_storage=1000,         # Enable storage autoscaling
    deletion_protection=True            # Enable for production
)
```

## Security Best Practices

### 1. Least Privilege Access

- IAM roles use minimal required permissions
- Security groups restrict database access to VPC CIDR
- Authentication policies enforce team-based access

### 2. Encryption

- RDS database encryption at rest enabled
- CloudTrail log file validation enabled
- S3 bucket encryption for audit logs

### 3. Monitoring and Alerting

- CloudTrail logs all API calls
- RDS Performance Insights enabled
- CloudWatch metrics for all resources

### 4. Network Security

- Database in isolated subnets
- VPC Lattice auth policies restrict access
- IP address-based conditions in policies

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**
   ```bash
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

2. **Insufficient Permissions**
   ```bash
   # Check your AWS credentials
   aws sts get-caller-identity
   
   # Verify IAM permissions
   aws iam simulate-principal-policy \
       --policy-source-arn arn:aws:iam::ACCOUNT:user/USERNAME \
       --action-names vpc-lattice:CreateServiceNetwork
   ```

3. **VPC Lattice Quota Limits**
   ```bash
   # Check service quotas
   aws service-quotas get-service-quota \
       --service-code vpc-lattice \
       --quota-code L-123456789
   ```

4. **Database Connection Issues**
   ```bash
   # Check security group rules
   aws ec2 describe-security-groups \
       --group-ids sg-xxxxxxxxx \
       --query "SecurityGroups[0].IpPermissions"
   ```

### Debug Mode

Enable debug logging:

```bash
export CDK_DEBUG=true
cdk deploy --verbose
```

### Rollback on Failure

```bash
# Destroy stack if deployment fails
cdk destroy

# Or rollback to previous version
aws cloudformation cancel-update-stack \
    --stack-name MultiTenantLatticeRAMStack
```

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
# Destroy the CDK stack
cdk destroy

# Confirm deletion
cdk destroy --force

# Clean up CDK staging resources (optional)
aws s3 rm s3://cdk-hnb659fds-assets-ACCOUNT-REGION --recursive
aws cloudformation delete-stack --stack-name CDKToolkit
```

### Manual Cleanup

If automatic cleanup fails, manually delete:

1. **VPC Lattice resources** (service networks, associations)
2. **RDS database** (if deletion protection enabled)
3. **CloudTrail** (if created outside CDK)
4. **S3 buckets** (if versioning enabled)

## Cost Optimization

### Development Environment

For development and testing, use cost-optimized settings:

```python
# Use smaller instance types
instance_type=ec2.InstanceType.of(
    ec2.InstanceClass.BURSTABLE3,
    ec2.InstanceSize.MICRO
)

# Reduce backup retention
backup_retention=cdk.Duration.days(1)

# Disable Performance Insights
enable_performance_insights=False
```

### Production Environment

For production, enable additional features:

```python
# Use production-grade instances
instance_type=ec2.InstanceType.of(
    ec2.InstanceClass.MEMORY6I,
    ec2.InstanceSize.LARGE
)

# Enable Multi-AZ deployment
multi_az=True

# Extended backup retention
backup_retention=cdk.Duration.days(30)

# Enable deletion protection
deletion_protection=True
```

## Support and Documentation

- **AWS CDK Documentation**: [CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- **VPC Lattice Documentation**: [VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
- **AWS RAM Documentation**: [RAM User Guide](https://docs.aws.amazon.com/ram/latest/userguide/)
- **CloudTrail Documentation**: [CloudTrail User Guide](https://docs.aws.amazon.com/cloudtrail/latest/userguide/)

For issues specific to this implementation:
1. Check the [AWS CDK GitHub Issues](https://github.com/aws/aws-cdk/issues)
2. Review the original recipe documentation
3. Consult AWS Support for production issues

## License

This code is provided under the MIT-0 License. See the LICENSE file for details.