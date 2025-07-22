# Infrastructure as Code for Database Migration Strategies with DMS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Migration Strategies with DMS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a complete AWS Database Migration Service (DMS) infrastructure including:

- DMS Replication Instance with Multi-AZ deployment
- DMS Subnet Group for network isolation
- Source and Target Endpoints for database connectivity
- Migration Tasks for full-load and CDC replication
- CloudWatch monitoring and logging
- S3 bucket for migration logs
- IAM roles and security configurations

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured
- Appropriate AWS permissions for DMS, RDS, VPC, S3, CloudWatch, and IAM services
- Existing source database (MySQL, PostgreSQL, Oracle, etc.)
- Target RDS database or S3 destination
- Network connectivity between DMS and databases

### Cost Considerations
- DMS replication instances: $50-200/month depending on size
- Data transfer charges for cross-AZ and cross-region traffic
- CloudWatch logs retention costs
- S3 storage costs for migration logs

### CloudFormation Specific
- AWS CLI configured with appropriate permissions
- CloudFormation stack creation permissions

### CDK Specific
- Node.js 16+ (for TypeScript)
- Python 3.8+ (for Python)
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- CDK bootstrapped in target account/region

### Terraform Specific
- Terraform 1.5+ installed
- AWS provider 5.0+ compatible

## Quick Start

### Using CloudFormation
```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name dms-migration-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=SourceDBHostname,ParameterValue=your-source-db-hostname \
                 ParameterKey=SourceDBUsername,ParameterValue=your-source-username \
                 ParameterKey=SourceDBPassword,ParameterValue=your-source-password \
                 ParameterKey=TargetDBHostname,ParameterValue=your-target-db-hostname \
                 ParameterKey=TargetDBUsername,ParameterValue=your-target-username \
                 ParameterKey=TargetDBPassword,ParameterValue=your-target-password \
    --capabilities CAPABILITY_IAM

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name dms-migration-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name dms-migration-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Set database connection parameters
export SOURCE_DB_HOSTNAME=your-source-db-hostname
export SOURCE_DB_USERNAME=your-source-username
export SOURCE_DB_PASSWORD=your-source-password
export TARGET_DB_HOSTNAME=your-target-db-hostname
export TARGET_DB_USERNAME=your-target-username
export TARGET_DB_PASSWORD=your-target-password

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Set database connection parameters
export SOURCE_DB_HOSTNAME=your-source-db-hostname
export SOURCE_DB_USERNAME=your-source-username
export SOURCE_DB_PASSWORD=your-source-password
export TARGET_DB_HOSTNAME=your-target-db-hostname
export TARGET_DB_USERNAME=your-target-username
export TARGET_DB_PASSWORD=your-target-password

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the plan
terraform plan \
    -var="source_db_hostname=your-source-db-hostname" \
    -var="source_db_username=your-source-username" \
    -var="source_db_password=your-source-password" \
    -var="target_db_hostname=your-target-db-hostname" \
    -var="target_db_username=your-target-username" \
    -var="target_db_password=your-target-password"

# Apply the configuration
terraform apply \
    -var="source_db_hostname=your-source-db-hostname" \
    -var="source_db_username=your-source-username" \
    -var="source_db_password=your-source-password" \
    -var="target_db_hostname=your-target-db-hostname" \
    -var="target_db_username=your-target-username" \
    -var="target_db_password=your-target-password"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export AWS_REGION=$(aws configure get region)
export SOURCE_DB_HOSTNAME=your-source-db-hostname
export SOURCE_DB_USERNAME=your-source-username
export SOURCE_DB_PASSWORD=your-source-password
export TARGET_DB_HOSTNAME=your-target-db-hostname
export TARGET_DB_USERNAME=your-target-username
export TARGET_DB_PASSWORD=your-target-password

# Deploy infrastructure
./scripts/deploy.sh

# Monitor migration progress
./scripts/monitor.sh
```

## Configuration Parameters

### Required Parameters
- **Source Database Configuration**:
  - `source_db_hostname`: Source database hostname or IP address
  - `source_db_username`: Source database username
  - `source_db_password`: Source database password
  - `source_db_port`: Source database port (default: 3306 for MySQL)
  - `source_database_name`: Source database name

- **Target Database Configuration**:
  - `target_db_hostname`: Target database hostname or RDS endpoint
  - `target_db_username`: Target database username
  - `target_db_password`: Target database password
  - `target_db_port`: Target database port (default: 3306 for MySQL)
  - `target_database_name`: Target database name

### Optional Parameters
- **Infrastructure Configuration**:
  - `replication_instance_class`: DMS replication instance size (default: dms.t3.medium)
  - `allocated_storage`: Storage size in GB (default: 100)
  - `multi_az`: Enable Multi-AZ deployment (default: true)
  - `publicly_accessible`: Enable public access (default: true)
  - `auto_minor_version_upgrade`: Enable automatic minor version upgrades (default: true)

- **Migration Configuration**:
  - `migration_type`: Migration type (default: full-load-and-cdc)
  - `target_table_prep_mode`: Table preparation mode (default: DROP_AND_CREATE)
  - `include_op_for_full_load`: Include operation for full load (default: true)
  - `enable_validation`: Enable data validation (default: true)
  - `enable_cloudwatch_logs`: Enable CloudWatch logging (default: true)

## Post-Deployment Steps

1. **Verify Infrastructure**:
   ```bash
   # Check replication instance status
   aws dms describe-replication-instances \
       --query 'ReplicationInstances[*].{ID:ReplicationInstanceIdentifier,Status:ReplicationInstanceStatus}'
   
   # Check endpoint connectivity
   aws dms describe-connections \
       --query 'Connections[*].{EndpointIdentifier:EndpointIdentifier,Status:Status}'
   ```

2. **Start Migration Tasks**:
   ```bash
   # Start full load and CDC task
   aws dms start-replication-task \
       --replication-task-arn <migration-task-arn> \
       --start-replication-task-type start-replication
   ```

3. **Monitor Migration Progress**:
   ```bash
   # Check task status
   aws dms describe-replication-tasks \
       --query 'ReplicationTasks[*].{TaskID:ReplicationTaskIdentifier,Status:Status,Progress:ReplicationTaskStats}'
   
   # Check table statistics
   aws dms describe-table-statistics \
       --replication-task-arn <migration-task-arn> \
       --query 'TableStatistics[*].{Table:TableName,State:TableState,Rows:FullLoadRows}'
   ```

## Monitoring and Troubleshooting

### CloudWatch Integration
- Migration metrics available in CloudWatch DMS namespace
- Custom alarms for task failures and high latency
- Detailed logs in CloudWatch Logs for debugging

### Key Metrics to Monitor
- `FreeableMemory`: Available memory on replication instance
- `SwapUsage`: Swap usage indicating memory pressure
- `NetworkReceiveThroughput`/`NetworkTransmitThroughput`: Network utilization
- `CDCLatencySource`/`CDCLatencyTarget`: Change data capture latency

### Common Issues and Solutions
1. **Connection Failures**: Verify security groups, NACLs, and database permissions
2. **Performance Issues**: Consider larger replication instance or parallel loading
3. **Data Validation Errors**: Review character sets, collations, and data types
4. **High Memory Usage**: Tune batch apply settings or increase instance size

## Security Considerations

### Network Security
- DMS replication instance deployed in private subnets when possible
- Security groups restrict access to necessary ports only
- VPC endpoints for S3 access to avoid internet routing

### Data Security
- Database passwords stored in AWS Secrets Manager
- Encryption in transit using SSL/TLS
- CloudWatch logs encrypted at rest
- S3 bucket with encryption and versioning enabled

### IAM Security
- Least privilege IAM roles for DMS service
- Resource-based policies for S3 bucket access
- CloudTrail logging for API calls

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name dms-migration-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name dms-migration-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Clean up CDK context
cdk context --clear
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="source_db_hostname=your-source-db-hostname" \
    -var="source_db_username=your-source-username" \
    -var="source_db_password=your-source-password" \
    -var="target_db_hostname=your-target-db-hostname" \
    -var="target_db_username=your-target-username" \
    -var="target_db_password=your-target-password"

# Clean up state files
rm -f terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
aws dms describe-replication-instances
aws dms describe-endpoints
aws s3 ls | grep dms-migration
```

## Customization

### Modifying Migration Settings
Edit the table mapping and task settings JSON configurations in your chosen IaC implementation:

- **Table Mapping**: Control which tables and schemas to migrate
- **Task Settings**: Configure performance, logging, and error handling
- **Transformation Rules**: Apply data transformations during migration

### Adding Additional Endpoints
To support multiple source databases or targets, extend the endpoint configurations:

```bash
# Example: Add Oracle source endpoint
aws dms create-endpoint \
    --endpoint-identifier oracle-source \
    --endpoint-type source \
    --engine-name oracle \
    --server-name oracle-host \
    --port 1521 \
    --database-name ORCL
```

### Scaling for Performance
For large migrations, consider:

- Larger replication instance classes (dms.r5.xlarge, dms.r5.2xlarge)
- Multiple parallel tasks for different table sets
- Optimized task settings for your workload
- Source database tuning for CDC performance

## Best Practices

1. **Pre-Migration Assessment**:
   - Use AWS Schema Conversion Tool (SCT) for heterogeneous migrations
   - Analyze source database performance and resource utilization
   - Plan for peak load and CDC lag requirements

2. **Testing Strategy**:
   - Test migration in non-production environment first
   - Validate data consistency using DMS validation features
   - Test application cutover procedures

3. **Production Migration**:
   - Schedule migration during low-activity periods
   - Monitor CDC lag and adjust as needed
   - Have rollback procedures ready

4. **Cost Optimization**:
   - Right-size replication instances based on workload
   - Use S3 storage classes for log retention
   - Monitor data transfer costs for cross-region migrations

## Support and Documentation

- [AWS DMS User Guide](https://docs.aws.amazon.com/dms/latest/userguide/)
- [AWS DMS Best Practices](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_BestPractices.html)
- [DMS Migration Planning](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_GettingStarted.html)
- [Schema Conversion Tool](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.