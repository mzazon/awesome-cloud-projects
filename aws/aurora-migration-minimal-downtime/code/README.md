# Infrastructure as Code for Aurora Migration with Minimal Downtime

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Aurora Migration with Minimal Downtime".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- AWS CLI installed and configured with appropriate credentials
- AWS account with necessary permissions for the following services:
  - Amazon Aurora (RDS)
  - Database Migration Service (DMS)
  - Route 53
  - VPC, EC2, and IAM
  - S3 (for DMS logging)
- Source database with network connectivity to AWS
- Database administrator access to source database

### Estimated Costs
- Aurora cluster: $150-400/month (depending on instance sizes)
- DMS replication instance: $50-200/month (during migration)
- VPC and networking: $10-30/month
- Route 53 hosted zone: $0.50/month + query charges

### Source Database Requirements
- **MySQL**: Binary logging enabled (`log-bin` parameter)
- **PostgreSQL**: Logical replication enabled (`wal_level = logical`)
- **Oracle**: Supplemental logging enabled
- **SQL Server**: Transaction log backups configured
- Network connectivity to AWS (VPN, Direct Connect, or internet)

## Infrastructure Components

This IaC deploys the following AWS resources:

### Networking
- VPC with public/private subnets across multiple AZs
- Security groups for Aurora and DMS access
- Internet gateway and route tables

### Database Infrastructure
- Aurora MySQL cluster with primary and reader instances
- Database subnet group for multi-AZ deployment
- Database cluster parameter group with migration optimizations

### Migration Infrastructure
- DMS replication instance with multi-AZ support
- DMS subnet group for replication instance placement
- IAM roles for DMS service operations

### DNS and Routing
- Route 53 private hosted zone for DNS-based cutover
- Initial DNS records for source database

### Monitoring and Logging
- CloudWatch log groups for Aurora and DMS
- S3 bucket for DMS task logs (optional)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name aurora-migration-stack \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=SourceDatabaseHost,ParameterValue=your-source-server.example.com \
        ParameterKey=SourceDatabasePort,ParameterValue=3306 \
        ParameterKey=SourceDatabaseName,ParameterValue=your-source-database \
        ParameterKey=SourceDatabaseUsername,ParameterValue=your-source-username \
        ParameterKey=SourceDatabasePassword,ParameterValue=your-source-password \
    --capabilities CAPABILITY_IAM

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name aurora-migration-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name aurora-migration-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure source database parameters
cp .env.example .env
# Edit .env with your source database details

# Deploy the infrastructure
cdk bootstrap  # If first time using CDK in this account/region
cdk deploy

# View outputs
cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Linux/Mac
# .venv\Scripts\activate.bat  # Windows

# Install dependencies
pip install -r requirements.txt

# Configure source database parameters
cp .env.example .env
# Edit .env with your source database details

# Deploy the infrastructure
cdk bootstrap  # If first time using CDK in this account/region
cdk deploy

# View outputs
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your source database details

# Plan deployment
terraform plan

# Deploy infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export SOURCE_DB_HOST="your-source-server.example.com"
export SOURCE_DB_PORT="3306"
export SOURCE_DB_NAME="your-source-database"
export SOURCE_DB_USERNAME="your-source-username"
export SOURCE_DB_PASSWORD="your-source-password"

# Deploy infrastructure
./scripts/deploy.sh

# Follow the migration process
# The script will output next steps for starting the migration
```

## Post-Deployment Steps

After deploying the infrastructure, follow these steps to complete the migration:

### 1. Start Migration Task

```bash
# Get the migration task ARN from outputs
MIGRATION_TASK_ARN=$(aws cloudformation describe-stacks \
    --stack-name aurora-migration-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`MigrationTaskArn`].OutputValue' \
    --output text)

# Start the migration
aws dms start-replication-task \
    --replication-task-arn $MIGRATION_TASK_ARN \
    --start-replication-task-type start-replication
```

### 2. Monitor Migration Progress

```bash
# Check task status
aws dms describe-replication-tasks \
    --replication-task-arn $MIGRATION_TASK_ARN \
    --query 'ReplicationTasks[0].[ReplicationTaskIdentifier,Status,ReplicationTaskStats]'

# Monitor table statistics
aws dms describe-table-statistics \
    --replication-task-arn $MIGRATION_TASK_ARN \
    --query 'TableStatistics[*].[SchemaName,TableName,TableState,FullLoadRows,ValidationState]'
```

### 3. Validate Data Migration

```bash
# Get Aurora endpoint from outputs
AURORA_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name aurora-migration-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`AuroraClusterEndpoint`].OutputValue' \
    --output text)

# Connect and verify data
mysql -h $AURORA_ENDPOINT -u admin -p \
    -e "SELECT COUNT(*) FROM migrationdb.your_table_name;"
```

### 4. Perform Cutover

When ready to switch traffic to Aurora:

```bash
# Update DNS to point to Aurora (minimal downtime cutover)
HOSTED_ZONE_ID=$(aws cloudformation describe-stacks \
    --stack-name aurora-migration-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`HostedZoneId`].OutputValue' \
    --output text)

# Apply DNS change (this completes the cutover)
aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch file://dns-cutover.json
```

## Configuration Options

### Aurora Configuration

- **Instance Classes**: Modify `AuroraInstanceClass` parameter for different performance levels
- **Engine Versions**: Update `AuroraEngineVersion` for specific Aurora versions
- **Backup Settings**: Configure backup retention and maintenance windows
- **Encryption**: Enable encryption at rest for production workloads

### DMS Configuration

- **Replication Instance Size**: Adjust `ReplicationInstanceClass` based on database size
- **Migration Settings**: Customize table mappings and task settings
- **Validation**: Enable/disable data validation based on requirements
- **CDC Settings**: Configure change data capture parameters

### Security Configuration

- **VPC CIDR**: Modify VPC and subnet CIDR blocks as needed
- **Security Groups**: Restrict access to specific IP ranges
- **IAM Roles**: Apply principle of least privilege
- **Encryption**: Enable encryption in transit and at rest

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor these key metrics during migration:

- **DMS Metrics**: `CDCLatencySource`, `CDCLatencyTarget`, `FreeableMemory`
- **Aurora Metrics**: `CPUUtilization`, `DatabaseConnections`, `ReadLatency`
- **Network Metrics**: `NetworkThroughput`, `NetworkLatency`

### Common Issues

1. **Connection Failures**: Verify security group rules and network connectivity
2. **CDC Lag**: Monitor replication lag and adjust instance sizes if needed
3. **Validation Errors**: Check data types and constraints between source and target
4. **Performance Issues**: Review Aurora parameter groups and instance classes

### Logs and Diagnostics

- **Aurora Logs**: Available in CloudWatch Logs
- **DMS Logs**: Task logs stored in CloudWatch and optionally S3
- **VPC Flow Logs**: Enable for network troubleshooting

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this removes all resources)
aws cloudformation delete-stack --stack-name aurora-migration-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name aurora-migration-stack
```

### Using CDK

```bash
# From the appropriate CDK directory
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
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletions when prompted
```

## Security Considerations

### Database Security

- Use AWS Secrets Manager for database credentials
- Enable encryption at rest for Aurora
- Use SSL/TLS for all database connections
- Implement database activity monitoring

### Network Security

- Use private subnets for database resources
- Implement VPC flow logs for audit trails
- Restrict security group access to minimum required
- Consider AWS PrivateLink for source connectivity

### Access Control

- Apply IAM policies with least privilege
- Use IAM database authentication where possible
- Enable CloudTrail for API audit logging
- Implement resource tagging for governance

## Migration Best Practices

### Pre-Migration

1. **Assessment**: Use AWS SCT (Schema Conversion Tool) for compatibility analysis
2. **Testing**: Perform trial migrations in non-production environment
3. **Monitoring**: Establish baseline performance metrics
4. **Backup**: Ensure source database backups are current

### During Migration

1. **Monitoring**: Continuously monitor CDC lag and validation status
2. **Performance**: Adjust replication instance size based on workload
3. **Testing**: Validate data integrity throughout the process
4. **Communication**: Keep stakeholders informed of progress

### Post-Migration

1. **Optimization**: Tune Aurora parameters for your workload
2. **Monitoring**: Establish ongoing monitoring and alerting
3. **Backup**: Verify Aurora backup and recovery procedures
4. **Documentation**: Update connection strings and procedures

## Support and Resources

- [AWS Database Migration Service User Guide](https://docs.aws.amazon.com/dms/latest/userguide/)
- [Amazon Aurora User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/)
- [AWS Database Migration Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/migration-sql-server-to-aurora-mysql/)
- [AWS Database Blog](https://aws.amazon.com/blogs/database/)

For technical support with this infrastructure code, refer to the original recipe documentation or AWS documentation for specific services.

## Cost Optimization

### During Migration

- Use spot instances for non-critical testing environments
- Size DMS replication instances appropriately
- Monitor data transfer costs for large databases
- Use compression for data in transit

### Post-Migration

- Implement Aurora auto-scaling for variable workloads
- Use Aurora Serverless for intermittent workloads
- Configure appropriate backup retention periods
- Monitor and optimize instance classes based on usage

## Compliance and Governance

- Tag all resources for cost allocation and governance
- Implement backup and retention policies per compliance requirements
- Enable encryption for data subject to regulatory requirements
- Document change management procedures for production migrations