# Analytics-Ready Data Storage with S3 Tables - CDK TypeScript

This CDK TypeScript application deploys a complete analytics-ready data storage solution using Amazon S3 Tables with Apache Iceberg format, Amazon Athena for querying, and AWS Glue for catalog integration.

## Architecture

The solution creates:

- **S3 Table Bucket**: Purpose-built storage for Apache Iceberg tables with automatic optimization
- **Namespace**: Logical organization for related tables (similar to databases)
- **Sample Table**: Customer events table with optimized schema for analytics
- **Athena Workgroup**: Configured for querying S3 Tables with performance optimization
- **S3 Results Bucket**: Encrypted storage for Athena query results
- **AWS Glue Database**: Catalog integration for seamless analytics service discovery
- **IAM Policies**: Secure integration between S3 Tables and AWS analytics services

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18.x or later
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- Appropriate AWS permissions for S3, S3 Tables, Athena, and AWS Glue

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (if not done previously)**:
   ```bash
   cdk bootstrap
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

4. **View outputs**:
   The deployment will output important resource names and sample SQL commands.

## Configuration

You can customize the deployment using CDK context variables:

```bash
# Deploy with custom table bucket name
cdk deploy -c tableBucketName=my-analytics-bucket

# Deploy with custom namespace name
cdk deploy -c namespaceName=my_namespace

# Deploy without sample data setup
cdk deploy -c enableSampleData=false

# Deploy with custom sample table name
cdk deploy -c sampleTableName=my_events_table
```

## Post-Deployment Steps

After successful deployment, you'll receive output values including:

1. **Table Bucket ARN**: Use this for CLI operations
2. **Athena Workgroup Name**: Use this for running queries
3. **Sample DDL Command**: Copy and run in Athena to create table schema
4. **Sample Insert Command**: Copy and run in Athena to insert demo data

### Creating Table Schema

Use the provided DDL command in Athena:

```sql
CREATE TABLE IF NOT EXISTS s3tablescatalog.analytics_data.customer_events (
  event_id STRING,
  customer_id STRING,
  event_type STRING,
  event_timestamp TIMESTAMP,
  product_category STRING,
  amount DECIMAL(10,2),
  session_id STRING,
  user_agent STRING,
  event_date DATE
)
USING ICEBERG
PARTITIONED BY (event_date)
TBLPROPERTIES (
  'table_type'='ICEBERG',
  'format'='PARQUET',
  'write_compression'='SNAPPY'
);
```

### Inserting Sample Data

Use the provided INSERT command in Athena to add demo data:

```sql
INSERT INTO s3tablescatalog.analytics_data.customer_events VALUES
('evt_001', 'cust_12345', 'page_view', TIMESTAMP '2025-01-15 10:30:00', 'electronics', 0.00, 'sess_abc123', 'Mozilla/5.0', DATE '2025-01-15'),
-- Additional sample records...
```

### Running Analytics Queries

Example analytics query:

```sql
SELECT 
  event_type,
  COUNT(*) as event_count,
  AVG(amount) as avg_amount
FROM s3tablescatalog.analytics_data.customer_events
WHERE event_date = DATE '2025-01-15'
GROUP BY event_type;
```

## Development

### Available Scripts

- `npm run build` - Compile TypeScript to JavaScript
- `npm run watch` - Watch for changes and recompile
- `npm run test` - Run Jest tests
- `npm run lint` - Run ESLint
- `npm run cdk` - Run CDK commands
- `cdk diff` - Compare deployed stack with current state
- `cdk synth` - Emit the synthesized CloudFormation template

### Testing

```bash
# Run tests
npm test

# Run tests in watch mode
npm run test:watch
```

### Linting

```bash
# Check for linting issues
npm run lint

# Fix auto-fixable linting issues
npm run lint:fix
```

## Key Features

### S3 Tables Benefits

- **3x Faster Queries**: Optimized for analytics workloads
- **10x More Transactions**: Higher concurrent operations support
- **Automatic Maintenance**: No manual compaction or optimization needed
- **Apache Iceberg Format**: ACID transactions, schema evolution, time travel

### Security Features

- **Encryption**: All data encrypted at rest and in transit
- **IAM Integration**: Least privilege access policies
- **VPC Endpoints**: Optional private connectivity (not included in basic setup)
- **Access Logging**: Comprehensive audit trails

### Cost Optimization

- **Lifecycle Policies**: Automatic cleanup of old query results
- **Intelligent Tiering**: Automatic storage class optimization
- **Query Limits**: Configurable data scanning limits
- **Resource Tagging**: Cost allocation and management

## Troubleshooting

### Common Issues

1. **S3 Tables Not Available**: Ensure you're deploying in a supported region
2. **Permission Errors**: Verify your AWS credentials have necessary permissions
3. **CDK Bootstrap**: Ensure CDK is bootstrapped in your target region
4. **Node Version**: Ensure you're using Node.js 18.x or later

### Useful Commands

```bash
# Check stack status
cdk list

# View stack resources
aws cloudformation describe-stack-resources --stack-name AnalyticsDataStorageStack

# View S3 Tables
aws s3tables list-table-buckets

# View Athena workgroups
aws athena list-work-groups
```

## Cleanup

To remove all resources:

```bash
cdk destroy
```

This will delete all resources including:
- S3 Table Bucket and all tables
- Athena workgroup
- S3 results bucket (with auto-delete enabled)
- IAM roles and policies
- AWS Glue database

## Security Considerations

- Review IAM policies before production deployment
- Enable CloudTrail for audit logging
- Consider VPC endpoints for private connectivity
- Implement data classification and encryption policies
- Regular security assessments and updates

## Additional Resources

- [Amazon S3 Tables Documentation](https://docs.aws.amazon.com/s3tables/)
- [Apache Iceberg Documentation](https://iceberg.apache.org/)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)

## Support

For issues with this CDK application:
1. Check the troubleshooting section above
2. Review AWS CloudFormation events in the AWS Console
3. Check CDK documentation for updates
4. Refer to the original recipe documentation