# Infrastructure as Code for Database Security with Encryption and IAM Authentication

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Security with Encryption and IAM".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - RDS instance creation and management
  - KMS key creation and management
  - IAM role and policy creation
  - VPC and security group management
  - CloudWatch logs and alarms
  - RDS Proxy creation
- PostgreSQL client (`psql`) for database testing
- Estimated cost: $50-100/month for db.r5.large instance with associated resources

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name database-security-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DBInstanceClass,ParameterValue=db.r5.large \
                 ParameterKey=DBAllocatedStorage,ParameterValue=100

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name database-security-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name database-security-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls --long
```

### Using Terraform
```bash
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
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/deploy.sh --status
```

## Architecture Overview

The infrastructure creates a comprehensive database security solution including:

- **RDS PostgreSQL Instance**: Encrypted with customer-managed KMS key
- **KMS Customer-Managed Key**: For encryption at rest and Performance Insights
- **IAM Authentication**: Eliminates password-based authentication
- **RDS Proxy**: Connection pooling with TLS enforcement
- **Security Groups**: Restrictive network access controls
- **CloudWatch Monitoring**: Performance and security alerting
- **Enhanced Monitoring**: Detailed database metrics
- **Performance Insights**: Query-level performance analysis

## Testing the Deployment

After deployment, test the security features:

### 1. Verify Encryption Status
```bash
# Get RDS instance details
aws rds describe-db-instances \
    --db-instance-identifier $(terraform output -raw db_instance_id) \
    --query 'DBInstances[0].{Encrypted:StorageEncrypted,KmsKeyId:KmsKeyId,IAMAuth:IAMDatabaseAuthenticationEnabled}'
```

### 2. Test IAM Authentication
```bash
# Get database endpoint
DB_ENDPOINT=$(terraform output -raw db_endpoint)
DB_USER=$(terraform output -raw db_user_name)

# Generate authentication token
AUTH_TOKEN=$(aws rds generate-db-auth-token \
    --hostname "$DB_ENDPOINT" \
    --port 5432 \
    --region $(aws configure get region) \
    --username "$DB_USER")

# Test connection
PGPASSWORD="$AUTH_TOKEN" psql \
    -h "$DB_ENDPOINT" \
    -U "$DB_USER" \
    -d "secure_app_db" \
    -c "SELECT 'IAM Authentication successful' AS status;"
```

### 3. Verify SSL/TLS Connection
```bash
# Test SSL connection
PGPASSWORD="$AUTH_TOKEN" psql \
    -h "$DB_ENDPOINT" \
    -U "$DB_USER" \
    -d "secure_app_db" \
    -c "SELECT ssl_is_used() AS ssl_enabled;"
```

### 4. Test RDS Proxy Connection
```bash
# Get proxy endpoint
PROXY_ENDPOINT=$(terraform output -raw proxy_endpoint)

# Test connection through proxy
PGPASSWORD="$AUTH_TOKEN" psql \
    -h "$PROXY_ENDPOINT" \
    -U "$DB_USER" \
    -d "secure_app_db" \
    -c "SELECT 'Proxy connection successful' AS status;"
```

## Security Features

### Encryption
- **At Rest**: Customer-managed KMS key encryption
- **In Transit**: TLS/SSL enforcement with `rds.force_ssl=1`
- **Backups**: Encrypted using the same KMS key
- **Performance Insights**: Encrypted with customer-managed key

### Authentication
- **IAM Database Authentication**: Eliminates password-based access
- **Temporary Tokens**: 15-minute authentication tokens
- **Centralized Access Control**: IAM policies control database access
- **Audit Trail**: CloudTrail logs all authentication events

### Network Security
- **Security Groups**: Restrictive inbound rules
- **VPC Isolation**: Database deployed in private subnets
- **RDS Proxy**: Additional security layer with connection pooling

### Monitoring
- **CloudWatch Alarms**: CPU usage and authentication failure alerts
- **Enhanced Monitoring**: Detailed OS-level metrics
- **Performance Insights**: Query-level performance analysis
- **CloudWatch Logs**: Database logs for security analysis

## Customization

### Variables/Parameters

Each implementation supports customization through variables:

- `db_instance_class`: Database instance type (default: db.r5.large)
- `db_allocated_storage`: Storage size in GB (default: 100)
- `db_engine_version`: PostgreSQL version (default: 15.7)
- `backup_retention_period`: Backup retention days (default: 7)
- `monitoring_interval`: Enhanced monitoring interval (default: 60)
- `performance_insights_retention`: PI retention days (default: 7)

### Environment-Specific Configurations

For production environments, consider:

```bash
# Higher performance instance
export DB_INSTANCE_CLASS="db.r5.xlarge"

# Increased storage
export DB_ALLOCATED_STORAGE="500"

# Longer backup retention
export BACKUP_RETENTION_PERIOD="30"

# Extended Performance Insights retention
export PI_RETENTION_PERIOD="31"
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name database-security-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name database-security-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Cost Optimization

### Resource Costs
- **RDS Instance**: Primary cost component (~$150-300/month for db.r5.large)
- **Storage**: ~$0.115/GB/month for gp3 storage
- **Backup Storage**: First 100GB free, then $0.095/GB/month
- **RDS Proxy**: $0.015/hour per proxy (~$11/month)
- **KMS**: $1/month per key + $0.03 per 10,000 requests
- **Enhanced Monitoring**: $0.50/month per instance

### Cost Reduction Strategies
1. **Instance Sizing**: Use appropriate instance class for workload
2. **Storage Optimization**: Use gp3 storage for better price/performance
3. **Backup Management**: Adjust retention period based on requirements
4. **Monitoring**: Disable enhanced monitoring in development environments

## Troubleshooting

### Common Issues

1. **IAM Authentication Failures**
   ```bash
   # Check IAM role permissions
   aws iam get-role-policy \
       --role-name $(terraform output -raw iam_role_name) \
       --policy-name DatabaseAccessPolicy
   ```

2. **SSL Connection Issues**
   ```bash
   # Verify SSL parameter setting
   aws rds describe-db-parameters \
       --db-parameter-group-name $(terraform output -raw parameter_group_name) \
       --query 'Parameters[?ParameterName==`rds.force_ssl`]'
   ```

3. **Network Connectivity**
   ```bash
   # Check security group rules
   aws ec2 describe-security-groups \
       --group-ids $(terraform output -raw security_group_id)
   ```

### Debugging Steps

1. **Check CloudWatch Logs**
   ```bash
   # View database logs
   aws logs describe-log-streams \
       --log-group-name "/aws/rds/instance/$(terraform output -raw db_instance_id)/postgresql"
   ```

2. **Monitor CloudWatch Alarms**
   ```bash
   # Check alarm status
   aws cloudwatch describe-alarms \
       --alarm-name-prefix "RDS-"
   ```

3. **Verify Resource Status**
   ```bash
   # Check RDS instance status
   aws rds describe-db-instances \
       --db-instance-identifier $(terraform output -raw db_instance_id) \
       --query 'DBInstances[0].DBInstanceStatus'
   ```

## Compliance and Best Practices

### Security Compliance
- **SOC 2**: Encryption at rest and in transit
- **PCI-DSS**: Secure authentication and network isolation
- **HIPAA**: Comprehensive audit logging and encryption
- **ISO 27001**: Access controls and monitoring

### Operational Best Practices
- **Backup Strategy**: Regular automated backups with encryption
- **Monitoring**: Comprehensive CloudWatch alarms and logging
- **Access Control**: Least privilege IAM policies
- **Network Security**: VPC isolation and security groups
- **Patch Management**: Automated maintenance windows

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS RDS documentation for service-specific guidance
3. Consult AWS CloudFormation/CDK/Terraform documentation
4. Review AWS security best practices documentation

## Additional Resources

- [AWS RDS Security Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.Security.html)
- [IAM Database Authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
- [RDS Proxy Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)
- [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html)