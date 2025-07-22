# Infrastructure as Code for Enabling Operational Analytics with Amazon Redshift Spectrum

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enabling Operational Analytics with Amazon Redshift Spectrum".

## Solution Overview

This implementation creates a comprehensive operational analytics platform that combines Amazon Redshift's powerful data warehouse capabilities with Redshift Spectrum's ability to query data directly from S3. The solution enables hybrid analytics across structured warehouse data and unstructured data lake storage, providing cost-effective operational insights without data movement overhead.

## Architecture Components

- **Amazon Redshift Cluster**: Managed data warehouse for analytical queries
- **Amazon S3 Data Lake**: Scalable storage for operational data with partitioning
- **AWS Glue Data Catalog**: Centralized metadata repository for schema management
- **Redshift Spectrum**: Query engine for direct S3 data access
- **IAM Roles**: Secure access management for cross-service operations
- **Sample Datasets**: Operational data including sales transactions, customers, and products

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions for Redshift, S3, Glue, and IAM services
- Understanding of SQL and data warehousing concepts
- Basic knowledge of data lake architectures and file formats
- Estimated cost: $200-500/month depending on cluster size and query frequency

> **Note**: Redshift Spectrum charges separately for data scanned from S3. Use columnar formats like Parquet and partitioning to minimize costs and improve performance.

## Quick Start

### Using CloudFormation (AWS)
```bash
# Deploy the complete operational analytics infrastructure
aws cloudformation create-stack \
    --stack-name operational-analytics-spectrum \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=MasterUsername,ParameterValue=admin \
                 ParameterKey=MasterPassword,ParameterValue=TempPassword123!

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name operational-analytics-spectrum

# Get cluster endpoint and connection details
aws cloudformation describe-stacks \
    --stack-name operational-analytics-spectrum \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)
```bash
# Install dependencies and deploy
cd cdk-typescript/
npm install

# Configure context parameters (optional)
npx cdk context --set masterUsername=admin
npx cdk context --set masterPassword=TempPassword123!

# Deploy with confirmation
npx cdk deploy --require-approval never

# View deployed resources
npx cdk list
```

### Using CDK Python (AWS)
```bash
# Set up Python environment and deploy
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Deploy the infrastructure
cdk deploy --require-approval never

# Get deployment outputs
cdk output
```

### Using Terraform
```bash
# Initialize and deploy with Terraform
cd terraform/

# Initialize Terraform with AWS provider
terraform init

# Review the deployment plan
terraform plan -var="master_username=admin" \
                -var="master_password=TempPassword123!"

# Apply the infrastructure changes
terraform apply -var="master_username=admin" \
                 -var="master_password=TempPassword123!" \
                 -auto-approve

# View important outputs
terraform output
```

### Using Bash Scripts
```bash
# Deploy using automated bash scripts
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment with parameter prompts
./scripts/deploy.sh

# Or with environment variables
export MASTER_USERNAME=admin
export MASTER_PASSWORD=TempPassword123!
./scripts/deploy.sh
```

## Post-Deployment Configuration

After successful deployment, complete these additional setup steps:

### 1. Configure External Schema
```sql
-- Connect to Redshift and create external schema
CREATE EXTERNAL SCHEMA spectrum_schema
FROM DATA CATALOG
DATABASE 'spectrum_db_[random_suffix]'
IAM_ROLE 'arn:aws:iam::[account]:role/RedshiftSpectrumRole-[suffix]'
CREATE EXTERNAL DATABASE IF NOT EXISTS;
```

### 2. Load Sample Data
```sql
-- Create internal tables for frequently accessed data
CREATE TABLE internal_customers (
    customer_id VARCHAR(20),
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    tier VARCHAR(20),
    city VARCHAR(50),
    state VARCHAR(10)
);

-- Load sample data for hybrid queries
INSERT INTO internal_customers VALUES
('CUST001', 'John', 'Doe', 'john.doe@email.com', 'premium', 'New York', 'NY'),
('CUST002', 'Jane', 'Smith', 'jane.smith@email.com', 'standard', 'Los Angeles', 'CA'),
('CUST003', 'Bob', 'Johnson', 'bob.johnson@email.com', 'standard', 'Chicago', 'IL');
```

### 3. Run Sample Analytics Queries
```sql
-- Query operational data across warehouse and data lake
SELECT 
    region,
    COUNT(*) as transaction_count,
    SUM(quantity * unit_price) as total_revenue,
    AVG(quantity * unit_price) as avg_transaction_value
FROM spectrum_schema.sales
GROUP BY region
ORDER BY total_revenue DESC;

-- Hybrid analysis combining internal and external data
SELECT 
    c.tier,
    COUNT(DISTINCT s.customer_id) as active_customers,
    SUM(s.quantity * s.unit_price) as total_spent
FROM spectrum_schema.sales s
JOIN internal_customers c ON s.customer_id = c.customer_id
GROUP BY c.tier;
```

## Validation & Testing

### 1. Verify Infrastructure Deployment
```bash
# Check Redshift cluster status
aws redshift describe-clusters \
    --cluster-identifier [cluster-name] \
    --query 'Clusters[0].ClusterStatus'

# Verify S3 data lake structure
aws s3 ls s3://[bucket-name]/operational-data/ --recursive

# Check Glue catalog tables
aws glue get-tables --database-name [database-name] \
    --query 'TableList[*].[Name,StorageDescriptor.Location]'
```

### 2. Test Spectrum Connectivity
```bash
# Connect to Redshift using Query Editor v2 or psql
psql -h [cluster-endpoint] -p 5439 -U [username] -d analytics

# Run connectivity test
\dt spectrum_schema.*
```

### 3. Performance Monitoring
```sql
-- Monitor Spectrum query performance
SELECT 
    query,
    starttime,
    endtime,
    DATEDIFF(seconds, starttime, endtime) as duration_seconds,
    rows,
    bytes
FROM stl_query
WHERE querytxt LIKE '%spectrum_schema%'
ORDER BY starttime DESC;
```

## Cost Optimization

### Data Format Recommendations
- **Use Parquet**: Convert CSV data to Parquet format for 50-80% cost savings
- **Implement Partitioning**: Partition by date/region to scan only relevant data
- **Compress Data**: Use GZIP or Snappy compression to reduce storage costs

### Query Optimization
- **Predicate Pushdown**: Use WHERE clauses to filter data at the source
- **Projection Pushdown**: Select only necessary columns in queries
- **Join Optimization**: Place frequently accessed data in Redshift tables

### Monitoring Costs
```sql
-- Track data scanned by Spectrum queries
SELECT 
    query,
    segment,
    step,
    ROUND(bytes/1024/1024, 2) as mb_scanned,
    ROUND((bytes/1024/1024) * 0.005, 4) as estimated_cost_usd
FROM svl_s3query
ORDER BY query DESC;
```

## Cleanup

### Using CloudFormation (AWS)
```bash
# Delete the complete stack
aws cloudformation delete-stack \
    --stack-name operational-analytics-spectrum

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name operational-analytics-spectrum
```

### Using CDK (AWS)
```bash
# Destroy infrastructure for both TypeScript and Python
cd cdk-typescript/  # or cdk-python/
npx cdk destroy --force  # or: cdk destroy --force
```

### Using Terraform
```bash
# Destroy all managed infrastructure
cd terraform/
terraform destroy -var="master_username=admin" \
                  -var="master_password=TempPassword123!" \
                  -auto-approve
```

### Using Bash Scripts
```bash
# Run automated cleanup
./scripts/destroy.sh
```

## Customization

### Key Configuration Parameters

| Parameter | Description | Default | CloudFormation | CDK | Terraform |
|-----------|-------------|---------|----------------|-----|-----------|
| ClusterName | Redshift cluster identifier | `spectrum-cluster-[random]` | ✅ | ✅ | ✅ |
| NodeType | Redshift instance type | `dc2.large` | ✅ | ✅ | ✅ |
| MasterUsername | Database admin username | `admin` | ✅ | ✅ | ✅ |
| MasterPassword | Database admin password | User-defined | ✅ | ✅ | ✅ |
| DataLakeBucket | S3 bucket for data lake | `spectrum-data-lake-[random]` | ✅ | ✅ | ✅ |
| GlueDatabase | Glue catalog database name | `spectrum_db_[random]` | ✅ | ✅ | ✅ |

### Advanced Customization Options

1. **Multi-Node Clusters**: Modify node count and type for production workloads
2. **VPC Configuration**: Deploy within existing VPC for network isolation
3. **Encryption**: Enable encryption at rest and in transit
4. **Backup Retention**: Configure automated backup and snapshot policies
5. **Parameter Groups**: Customize Redshift configuration parameters

### Security Enhancements

```yaml
# Example: Enhanced security configuration
SecurityGroups:
  - GroupDescription: "Redshift cluster access"
    SecurityGroupIngress:
      - IpProtocol: tcp
        FromPort: 5439
        ToPort: 5439
        CidrIp: "10.0.0.0/8"  # Restrict to internal networks only

Encryption:
  Encrypted: true
  KmsKeyId: !Ref RedshiftKMSKey
```

## Troubleshooting

### Common Issues

1. **Cluster Creation Failures**:
   - Verify sufficient IAM permissions
   - Check VPC and subnet configuration
   - Ensure unique cluster identifier

2. **Spectrum Query Errors**:
   - Verify external schema creation
   - Check IAM role permissions for S3 and Glue
   - Confirm Glue crawler completion

3. **Performance Issues**:
   - Review data partitioning strategy
   - Optimize query patterns for Spectrum
   - Consider data format conversion to Parquet

### Debug Commands

```bash
# Check IAM role permissions
aws iam get-role-policy \
    --role-name [redshift-role-name] \
    --policy-name [policy-name]

# Verify Glue catalog access
aws glue get-database --name [database-name]

# Test S3 access from Redshift
SELECT * FROM spectrum_schema.sales LIMIT 5;
```

## Performance Tuning

### Best Practices
- **Data Distribution**: Use appropriate distribution keys for Redshift tables
- **Sort Keys**: Implement sort keys for commonly filtered columns
- **Vacuum Operations**: Regular maintenance for optimal performance
- **Workload Management**: Configure query queues for different workload types

### Monitoring Queries
```sql
-- Identify slow-running queries
SELECT query, elapsed, rows
FROM stv_recents 
WHERE status = 'Done' 
ORDER BY elapsed DESC;

-- Check table statistics
SELECT schemaname, tablename, size_in_mb 
FROM svv_table_info 
ORDER BY size_in_mb DESC;
```

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../operational-analytics-amazon-redshift-spectrum.md)
- [AWS Redshift Documentation](https://docs.aws.amazon.com/redshift/)
- [AWS Redshift Spectrum Documentation](https://docs.aws.amazon.com/redshift/latest/dg/c-using-spectrum.html)
- [AWS Glue Documentation](https://docs.aws.amazon.com/glue/)

## Additional Resources

- [Redshift Spectrum Best Practices](https://docs.aws.amazon.com/redshift/latest/dg/c-spectrum-external-tables.html)
- [Data Lake Analytics Patterns](https://aws.amazon.com/big-data/datalakes-and-analytics/)
- [Cost Optimization Guide](https://docs.aws.amazon.com/redshift/latest/mgmt/managing-cluster-costs.html)
- [Security Best Practices](https://docs.aws.amazon.com/redshift/latest/mgmt/security-best-practices.html)