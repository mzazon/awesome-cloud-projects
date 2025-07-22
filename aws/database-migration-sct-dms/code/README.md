# Infrastructure as Code for Database Migration Strategies with AWS DMS and Schema Conversion Tool

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Migration with Schema Conversion Tool".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deployment creates a comprehensive database migration infrastructure including:

- VPC with public subnets across multiple availability zones
- AWS DMS replication instance for data migration
- DMS subnet group for network isolation
- Source and target database endpoints
- Target RDS PostgreSQL database
- CloudWatch monitoring and dashboards
- Security groups and IAM roles
- Migration task configurations

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - DMS (Database Migration Service)
  - RDS (Relational Database Service)
  - EC2 (VPC, subnets, security groups)
  - CloudWatch (logs, metrics, dashboards)
  - IAM (roles and policies)
- Access to source database with connection credentials
- AWS Schema Conversion Tool (SCT) installed locally for schema analysis
- Estimated cost: $150-300 for complete migration environment

> **Note**: Ensure your source database allows network connectivity from AWS DMS replication instance.

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete migration infrastructure
aws cloudformation create-stack \
    --stack-name dms-migration-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=SourceDatabaseHost,ParameterValue=your-source-host \
                 ParameterKey=SourceDatabasePort,ParameterValue=1521 \
                 ParameterKey=SourceDatabaseName,ParameterValue=your-database \
                 ParameterKey=SourceDatabaseUsername,ParameterValue=your-username \
                 ParameterKey=SourceDatabasePassword,ParameterValue=your-password \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name dms-migration-stack

# Get outputs with connection information
aws cloudformation describe-stacks \
    --stack-name dms-migration-stack \
    --query 'Stacks[0].Outputs' \
    --output table
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure source database parameters
export SOURCE_DATABASE_HOST="your-source-host"
export SOURCE_DATABASE_PORT="1521"
export SOURCE_DATABASE_NAME="your-database"
export SOURCE_DATABASE_USERNAME="your-username"
export SOURCE_DATABASE_PASSWORD="your-password"

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View deployment outputs
cdk list --long
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

# Configure source database parameters
export SOURCE_DATABASE_HOST="your-source-host"
export SOURCE_DATABASE_PORT="1521"
export SOURCE_DATABASE_NAME="your-database"
export SOURCE_DATABASE_USERNAME="your-username"
export SOURCE_DATABASE_PASSWORD="your-password"

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View deployment outputs
cdk list --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your configuration
cat > terraform.tfvars << EOF
source_database_host = "your-source-host"
source_database_port = 1521
source_database_name = "your-database"
source_database_username = "your-username"
source_database_password = "your-password"
project_name = "dms-migration"
environment = "dev"
EOF

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

# Set required environment variables
export SOURCE_DATABASE_HOST="your-source-host"
export SOURCE_DATABASE_PORT="1521"
export SOURCE_DATABASE_NAME="your-database"
export SOURCE_DATABASE_USERNAME="your-username"
export SOURCE_DATABASE_PASSWORD="your-password"

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor deployment progress
./scripts/monitor-deployment.sh
```

## Configuration Parameters

### Required Parameters

- **Source Database Host**: Hostname or IP address of source database
- **Source Database Port**: Port number for source database connection
- **Source Database Name**: Name of source database/service
- **Source Database Username**: Username for source database access
- **Source Database Password**: Password for source database access

### Optional Parameters

- **Replication Instance Class**: DMS replication instance size (default: dms.t3.medium)
- **Target Database Class**: RDS instance class (default: db.t3.medium)
- **VPC CIDR Block**: VPC CIDR range (default: 10.0.0.0/16)
- **Environment**: Environment tag (default: dev)
- **Project Name**: Project identifier for resource naming

## Post-Deployment Steps

### 1. Schema Conversion with SCT

```bash
# Download and install AWS Schema Conversion Tool locally
# Create SCT project using the generated configuration

# Connect to source database
# Connect to target database (use outputs from deployment)
# Run assessment report
# Convert and apply schema changes
```

### 2. Configure Migration Tasks

```bash
# Test database connectivity
aws dms test-connection \
    --replication-instance-identifier <replication-instance-id> \
    --endpoint-identifier <source-endpoint-id>

aws dms test-connection \
    --replication-instance-identifier <replication-instance-id> \
    --endpoint-identifier <target-endpoint-id>

# Create and start migration task
aws dms create-replication-task \
    --replication-task-identifier migration-task-001 \
    --source-endpoint-identifier <source-endpoint-id> \
    --target-endpoint-identifier <target-endpoint-id> \
    --replication-instance-identifier <replication-instance-id> \
    --migration-type full-load-and-cdc \
    --table-mappings file://table-mappings.json
```

### 3. Monitor Migration Progress

```bash
# Check migration task status
aws dms describe-replication-tasks \
    --replication-task-identifier migration-task-001 \
    --query 'ReplicationTasks[0].Status'

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/DMS \
    --metric-name CPUUtilization \
    --dimensions Name=ReplicationInstanceIdentifier,Value=<replication-instance-id> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

## Validation and Testing

### 1. Infrastructure Validation

```bash
# Verify DMS replication instance
aws dms describe-replication-instances \
    --replication-instance-identifier <replication-instance-id>

# Verify RDS target database
aws rds describe-db-instances \
    --db-instance-identifier <target-db-instance-id>

# Verify endpoints
aws dms describe-endpoints \
    --endpoint-identifier <source-endpoint-id>
```

### 2. Data Validation

```bash
# Check table statistics
aws dms describe-table-statistics \
    --replication-task-identifier migration-task-001

# Validate data integrity
# (Use provided validation scripts in scripts/ directory)
./scripts/validate-data.sh
```

### 3. Performance Testing

```bash
# Monitor replication performance
aws dms describe-replication-tasks \
    --replication-task-identifier migration-task-001 \
    --query 'ReplicationTasks[0].ReplicationTaskStats'

# Check CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name DMS-Migration-Dashboard
```

## Security Considerations

### Network Security

- VPC with properly configured subnets and security groups
- DMS replication instance in private subnets (production recommendation)
- Security group rules limiting access to required ports only
- VPC endpoints for AWS service communication (optional)

### Access Control

- IAM roles with least privilege permissions for DMS operations
- Secrets Manager integration for database credentials (recommended)
- CloudTrail logging for API activity monitoring
- Encryption in transit and at rest for all database connections

### Data Protection

- SSL/TLS encryption for all database connections
- RDS encryption at rest with KMS keys
- VPC Flow Logs for network traffic monitoring
- CloudWatch Logs encryption for migration logs

## Troubleshooting

### Common Issues

1. **Connection Test Failures**
   - Verify security group rules allow traffic on database ports
   - Check source database network ACLs and firewall settings
   - Validate database credentials and permissions

2. **Migration Task Errors**
   - Review CloudWatch logs for detailed error messages
   - Check table mappings and task settings configuration
   - Verify source database has sufficient privileges for CDC

3. **Performance Issues**
   - Monitor replication instance CPU and memory usage
   - Consider increasing replication instance size
   - Optimize table mappings to reduce unnecessary data transfer

### Monitoring and Alerting

```bash
# Set up CloudWatch alarms for key metrics
aws cloudwatch put-metric-alarm \
    --alarm-name "DMS-CPU-High" \
    --alarm-description "DMS Replication Instance CPU Usage" \
    --metric-name CPUUtilization \
    --namespace AWS/DMS \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name dms-migration-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name dms-migration-stack
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the infrastructure
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts for resource confirmation
```

## Cost Optimization

### Resource Sizing

- Start with smaller instance classes (t3.medium) for testing
- Monitor utilization metrics to optimize instance sizes
- Use Multi-AZ only for production environments
- Consider Reserved Instances for long-term migrations

### Migration Strategy

- Use full-load first, then CDC to minimize replication time
- Optimize table mappings to migrate only necessary data
- Schedule migrations during low-traffic periods
- Clean up test resources promptly to avoid unnecessary charges

## Advanced Configuration

### Multi-Region Deployment

```bash
# Deploy to multiple regions for disaster recovery
aws cloudformation create-stack \
    --stack-name dms-migration-dr \
    --template-body file://cloudformation.yaml \
    --region us-west-2 \
    --parameters ParameterKey=Environment,ParameterValue=dr
```

### Custom Networking

```bash
# Deploy with existing VPC
aws cloudformation create-stack \
    --stack-name dms-migration-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=UseExistingVPC,ParameterValue=true \
                 ParameterKey=VpcId,ParameterValue=vpc-12345678
```

## Support and Documentation

- [AWS DMS User Guide](https://docs.aws.amazon.com/dms/latest/userguide/)
- [AWS Schema Conversion Tool Documentation](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/)
- [DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html)
- [Migration Planning Guide](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_GettingStarted.html)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.