# Infrastructure as Code for Database Scaling with Aurora Serverless

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Scaling with Aurora Serverless".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for RDS, CloudWatch, IAM, and VPC management
- VPC with at least two subnets in different Availability Zones
- Basic understanding of Aurora architecture and serverless concepts

### Tool-Specific Prerequisites

**For CloudFormation:**
- AWS CLI with CloudFormation permissions

**For CDK TypeScript:**
- Node.js (v18 or later)
- npm or yarn
- AWS CDK CLI (`npm install -g aws-cdk`)

**For CDK Python:**
- Python 3.8 or later
- pip package manager
- AWS CDK CLI (`pip install aws-cdk-lib`)

**For Terraform:**
- Terraform v1.0 or later
- AWS provider v5.0 or later

## Quick Start

### Using CloudFormation
```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name aurora-serverless-scaling-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DatabaseUsername,ParameterValue=admin \
                 ParameterKey=DatabasePassword,ParameterValue=YourSecurePassword123! \
    --capabilities CAPABILITY_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name aurora-serverless-scaling-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name aurora-serverless-scaling-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters DatabasePassword=YourSecurePassword123!

# Get outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters DatabasePassword=YourSecurePassword123!

# Get outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
database_password = "YourSecurePassword123!"
cluster_identifier = "aurora-serverless-$(openssl rand -hex 3)"
EOF

# Plan deployment
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

# Set required environment variables
export DATABASE_PASSWORD="YourSecurePassword123!"

# Deploy infrastructure
./scripts/deploy.sh

# The script will output connection endpoints and resource IDs
```

## Architecture Overview

This implementation creates:

- **Aurora Serverless v2 MySQL Cluster** with automatic scaling (0.5-16 ACUs)
- **Writer Instance** for read-write operations
- **Read Replica** for scaling read workloads
- **Security Group** with appropriate MySQL access rules
- **DB Subnet Group** for multi-AZ deployment
- **Custom Parameter Group** for optimization
- **CloudWatch Alarms** for capacity monitoring
- **Performance Insights** enabled for both instances

## Configuration Options

### Database Configuration
- **Engine**: Aurora MySQL 8.0
- **Scaling Range**: 0.5 to 16 Aurora Capacity Units (ACUs)
- **Backup Retention**: 7 days
- **Multi-AZ**: Enabled via read replica
- **Encryption**: Enabled by default

### Monitoring
- **Performance Insights**: 7-day retention
- **CloudWatch Logs**: Error, general, and slow query logs
- **Alarms**: High and low ACU utilization alerts

### Security
- **Deletion Protection**: Enabled (can be disabled for testing)
- **VPC Security Groups**: Restricts access to VPC network ranges
- **IAM Integration**: Supports IAM database authentication

## Customization

### Key Variables/Parameters

**CloudFormation Parameters:**
- `DatabaseUsername`: Master database username (default: admin)
- `DatabasePassword`: Master database password (required)
- `MinCapacity`: Minimum ACU capacity (default: 0.5)
- `MaxCapacity`: Maximum ACU capacity (default: 16)
- `VpcId`: VPC ID for deployment (uses default VPC if not specified)

**CDK Context Variables:**
- `databasePassword`: Master database password
- `minCapacity`: Minimum scaling capacity
- `maxCapacity`: Maximum scaling capacity
- `enableDeletionProtection`: Enable/disable deletion protection

**Terraform Variables:**
- `database_password`: Master database password (required)
- `cluster_identifier`: Unique cluster identifier
- `min_capacity`: Minimum ACU capacity (default: 0.5)
- `max_capacity`: Maximum ACU capacity (default: 16)
- `vpc_id`: VPC ID for deployment

### Environment-Specific Configurations

For **Development**:
```bash
# Lower minimum capacity for cost optimization
export MIN_CAPACITY=0.5
export MAX_CAPACITY=4
export DELETION_PROTECTION=false
```

For **Production**:
```bash
# Higher minimum capacity for performance
export MIN_CAPACITY=2
export MAX_CAPACITY=32
export DELETION_PROTECTION=true
export BACKUP_RETENTION_PERIOD=30
```

## Cost Optimization

### Aurora Serverless v2 Pricing
- **Minimum billing**: 0.5 ACU when active
- **Scaling granularity**: 0.5 ACU increments
- **Automatic pause**: Not available in Aurora Serverless v2
- **Storage**: Pay for actual usage, scales automatically

### Cost Monitoring
The CloudWatch alarms help monitor:
- **High ACU usage**: Indicates approaching capacity limits
- **Low ACU usage**: Opportunities to reduce minimum capacity
- **Scaling patterns**: Optimization opportunities

## Validation & Testing

### Post-Deployment Verification

1. **Check cluster status**:
```bash
aws rds describe-db-clusters \
    --db-cluster-identifier your-cluster-id \
    --query 'DBClusters[0].Status'
```

2. **Verify scaling configuration**:
```bash
aws rds describe-db-clusters \
    --db-cluster-identifier your-cluster-id \
    --query 'DBClusters[0].ServerlessV2ScalingConfiguration'
```

3. **Test database connectivity**:
```bash
# Use the writer endpoint for read-write operations
mysql -h your-writer-endpoint -u admin -p

# Use the reader endpoint for read-only operations
mysql -h your-reader-endpoint -u admin -p
```

4. **Monitor ACU usage**:
```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ServerlessDatabaseCapacity \
    --dimensions Name=DBClusterIdentifier,Value=your-cluster-id \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name aurora-serverless-scaling-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name aurora-serverless-scaling-stack
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
# Run the destroy script
./scripts/destroy.sh

# Confirm deletion when prompted
# The script will clean up all resources in proper order
```

## Troubleshooting

### Common Issues

1. **Capacity Scaling Delays**
   - Aurora Serverless v2 typically scales within seconds
   - Check CloudWatch metrics for scaling events
   - Verify workload patterns match scaling triggers

2. **Connection Issues**
   - Verify security group rules allow access from your IP/network
   - Check VPC and subnet configuration
   - Ensure endpoints are correctly resolved

3. **Cost Concerns**
   - Monitor ACU usage patterns via CloudWatch
   - Adjust minimum capacity based on actual usage
   - Consider read replica scaling for read-heavy workloads

4. **Performance Issues**
   - Enable Performance Insights for detailed analysis
   - Review slow query logs for optimization opportunities
   - Consider parameter group tuning for specific workloads

### Support Resources

- [Aurora Serverless v2 Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html)
- [Aurora Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [Aurora Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html)

## Support

For issues with this infrastructure code, refer to:
1. The original recipe documentation for architectural guidance
2. AWS documentation for service-specific troubleshooting
3. Provider tool documentation (CloudFormation, CDK, Terraform) for deployment issues
4. CloudWatch logs and metrics for operational insights

## Security Considerations

- Database passwords should be stored in AWS Secrets Manager for production
- Enable VPC Flow Logs for network monitoring
- Consider enabling GuardDuty for threat detection
- Use IAM database authentication for enhanced security
- Regularly review and rotate database credentials
- Enable CloudTrail for API audit logging