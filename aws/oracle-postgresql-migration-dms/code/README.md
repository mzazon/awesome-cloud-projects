# Infrastructure as Code for Oracle to PostgreSQL Migration with DMS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Oracle to PostgreSQL Migration with DMS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a comprehensive Oracle to PostgreSQL migration solution including:

- Aurora PostgreSQL cluster with Multi-AZ deployment
- AWS DMS replication instance with enhanced monitoring
- DMS source and target endpoints with optimized configurations
- VPC networking with proper security groups and subnets
- IAM roles and policies following least privilege principles
- CloudWatch monitoring and alerting for migration tracking
- S3 bucket for DMS logs and SCT assessment reports

## Prerequisites

### AWS Account Setup
- AWS CLI v2 installed and configured
- AWS account with appropriate permissions:
  - DMS Full Access
  - RDS Full Access
  - VPC Management
  - IAM Role Management
  - CloudWatch Management
  - S3 Management
- Estimated cost: $150-300 for Aurora PostgreSQL instance during migration period

### Source Database Requirements
- Oracle database (version 10.2.0.3 or later) with:
  - Appropriate privileges (DBA or equivalent access)
  - Network connectivity to AWS
  - Archived logging enabled for CDC
  - Supplemental logging configured

### Tools and Software
- Java 8 or later for AWS Schema Conversion Tool (SCT)
- Oracle client libraries for DMS connectivity
- Understanding of Oracle PL/SQL and PostgreSQL procedures

> **Warning**: This migration process involves schema conversion and data transformation that may require application code modifications. Test thoroughly in a non-production environment first.

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name oracle-postgresql-migration \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProjectName,ParameterValue=my-migration \
                 ParameterKey=SourceOracleHost,ParameterValue=oracle.example.com \
                 ParameterKey=SourceOraclePort,ParameterValue=1521 \
                 ParameterKey=SourceOracleDatabase,ParameterValue=ORCL \
                 ParameterKey=SourceOracleUsername,ParameterValue=oracle_user \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name oracle-postgresql-migration

# Get outputs
aws cloudformation describe-stacks \
    --stack-name oracle-postgresql-migration \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment parameters
cp cdk.json.example cdk.json
# Edit cdk.json with your specific values

# Deploy the stack
cdk bootstrap  # First time only
cdk deploy OraclePostgreSQLMigrationStack

# Get outputs
cdk list
cdk output OraclePostgreSQLMigrationStack
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

# Configure deployment parameters
cp cdk.json.example cdk.json
# Edit cdk.json with your specific values

# Deploy the stack
cdk bootstrap  # First time only
cdk deploy OraclePostgreSQLMigrationStack

# Get outputs
cdk output OraclePostgreSQLMigrationStack
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values:
# project_name = "my-migration"
# source_oracle_host = "oracle.example.com"
# source_oracle_port = 1521
# source_oracle_database = "ORCL"
# source_oracle_username = "oracle_user"

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export PROJECT_NAME="my-migration"
export SOURCE_ORACLE_HOST="oracle.example.com"
export SOURCE_ORACLE_PORT="1521"
export SOURCE_ORACLE_DATABASE="ORCL"
export SOURCE_ORACLE_USERNAME="oracle_user"
export AWS_REGION="us-east-1"

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for sensitive values like passwords
# and provide progress updates throughout deployment
```

## Configuration Parameters

### Required Parameters

| Parameter | Description | Example Value |
|-----------|-------------|---------------|
| ProjectName | Unique identifier for resources | `my-migration` |
| SourceOracleHost | Oracle database hostname | `oracle.example.com` |
| SourceOraclePort | Oracle database port | `1521` |
| SourceOracleDatabase | Oracle database name/SID | `ORCL` |
| SourceOracleUsername | Oracle username for migration | `oracle_user` |

### Optional Parameters

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| VpcCidr | VPC CIDR block | `10.0.0.0/16` |
| AuroraInstanceClass | Aurora instance class | `db.r6g.large` |
| DmsInstanceClass | DMS replication instance class | `dms.c5.large` |
| BackupRetentionPeriod | Aurora backup retention | `7` days |
| MultiAz | Enable Multi-AZ deployment | `true` |

## Post-Deployment Steps

### 1. Download and Configure AWS SCT

```bash
# Download AWS Schema Conversion Tool
curl -O https://s3.amazonaws.com/publicsctdownload/AWS+SCT/1.0.668/aws-schema-conversion-tool-1.0.668.zip
unzip aws-schema-conversion-tool-1.0.668.zip
cd aws-schema-conversion-tool-1.0.668
chmod +x aws-schema-conversion-tool
```

### 2. Run Schema Assessment

```bash
# Create SCT project and run assessment
# Use the Aurora PostgreSQL endpoint from deployment outputs
# Follow the recipe documentation for detailed SCT configuration
```

### 3. Create and Start Migration Task

```bash
# Get endpoint ARNs from deployment outputs
SOURCE_ENDPOINT_ARN=$(aws cloudformation describe-stacks \
    --stack-name oracle-postgresql-migration \
    --query 'Stacks[0].Outputs[?OutputKey==`SourceEndpointArn`].OutputValue' \
    --output text)

TARGET_ENDPOINT_ARN=$(aws cloudformation describe-stacks \
    --stack-name oracle-postgresql-migration \
    --query 'Stacks[0].Outputs[?OutputKey==`TargetEndpointArn`].OutputValue' \
    --output text)

# Create migration task using the recipe's table mapping configuration
# Start the migration task and monitor progress
```

### 4. Monitor Migration Progress

```bash
# View CloudWatch dashboards created by the infrastructure
# Monitor DMS task statistics and replication lag
# Check CloudWatch alarms for any migration issues
```

## Outputs

The infrastructure deployment provides the following outputs:

| Output | Description |
|--------|-------------|
| VpcId | VPC ID for the migration environment |
| AuroraClusterEndpoint | Aurora PostgreSQL cluster endpoint |
| AuroraClusterPort | Aurora PostgreSQL port (5432) |
| DmsReplicationInstanceArn | DMS replication instance ARN |
| SourceEndpointArn | Oracle source endpoint ARN |
| TargetEndpointArn | PostgreSQL target endpoint ARN |
| CloudWatchDashboardUrl | Migration monitoring dashboard URL |
| S3BucketName | S3 bucket for logs and reports |

## Monitoring and Troubleshooting

### CloudWatch Metrics

The infrastructure includes comprehensive monitoring:

- **DMS Replication Lag**: Monitors lag between source and target
- **DMS Task Failures**: Alerts on migration task failures
- **Aurora Performance Insights**: Database performance monitoring
- **VPC Flow Logs**: Network traffic analysis

### Common Issues

1. **Network Connectivity**: Ensure Oracle source is accessible from AWS
2. **Authentication**: Verify Oracle credentials and PostgreSQL passwords
3. **Schema Conversion**: Review SCT assessment for manual conversion needs
4. **Performance**: Monitor replication lag and adjust instance sizes if needed

### Log Locations

- **DMS Logs**: CloudWatch Logs groups created per task
- **Aurora Logs**: Available in RDS console and CloudWatch
- **SCT Reports**: Stored in the created S3 bucket

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (will prompt for confirmation on destructive operations)
aws cloudformation delete-stack \
    --stack-name oracle-postgresql-migration

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name oracle-postgresql-migration
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy OraclePostgreSQLMigrationStack
```

### Using CDK Python

```bash
cd cdk-python/
source .venv/bin/activate
cdk destroy OraclePostgreSQLMigrationStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
# and provide progress updates throughout the cleanup process
```

## Customization

### Security Enhancements

- **Secrets Manager**: Store database passwords in AWS Secrets Manager
- **KMS Encryption**: Enable encryption for Aurora, DMS, and S3 resources
- **VPC Endpoints**: Add VPC endpoints for AWS services to avoid internet traffic
- **Security Groups**: Customize security group rules for your network requirements

### Performance Optimization

- **Instance Sizing**: Adjust Aurora and DMS instance classes based on workload
- **Storage**: Configure Aurora storage and DMS allocated storage
- **Parallel Processing**: Tune DMS parallel load settings for large tables
- **Compression**: Enable compression for data transfer optimization

### High Availability

- **Multi-Region**: Deploy Aurora Global Database for cross-region replication
- **Backup Strategy**: Configure automated backups and point-in-time recovery
- **Monitoring**: Add additional CloudWatch alarms and SNS notifications
- **Disaster Recovery**: Implement backup replication instance in different AZ

## Cost Optimization

### Resource Recommendations

- **Right-sizing**: Start with smaller instances and scale based on performance
- **Reserved Instances**: Consider Reserved Instances for long-term migrations
- **Storage Classes**: Use appropriate S3 storage classes for logs and reports
- **Cleanup**: Remove temporary resources after migration completion

### Cost Monitoring

- **Budgets**: Set up AWS Budgets to monitor migration costs
- **Cost Explorer**: Use Cost Explorer to track resource expenses
- **Tagging**: All resources are tagged for cost allocation tracking

## Security Considerations

### Data Protection

- **Encryption in Transit**: All data transfers use SSL/TLS encryption
- **Encryption at Rest**: Aurora and S3 resources support encryption at rest
- **Network Isolation**: Resources deployed in private subnets with controlled access
- **Audit Logging**: Comprehensive logging for compliance requirements

### Access Control

- **IAM Roles**: Least privilege access for all service roles
- **Security Groups**: Restricted network access between components
- **VPC**: Isolated network environment for migration resources
- **Password Policies**: Strong password requirements for database access

## Support

### Troubleshooting Resources

- [AWS DMS Troubleshooting Guide](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Troubleshooting.html)
- [Aurora PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.AuroraPostgreSQL.html)
- [AWS Schema Conversion Tool User Guide](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html)

### Additional Resources

- Original recipe documentation for step-by-step migration process
- AWS DMS Oracle to PostgreSQL migration playbook
- PostgreSQL migration best practices documentation
- Enterprise migration planning guides

For issues with this infrastructure code, refer to the original recipe documentation or the AWS service documentation for specific troubleshooting guidance.