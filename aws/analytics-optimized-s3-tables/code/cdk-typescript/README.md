# Analytics-Optimized Data Storage with S3 Tables - CDK TypeScript

This directory contains the AWS CDK TypeScript implementation for building analytics-optimized data storage using Amazon S3 Tables with Apache Iceberg format.

## Architecture Overview

This CDK application deploys a complete analytics solution featuring:

- **S3 Table Bucket**: Purpose-built storage optimized for analytics workloads
- **Table Namespace**: Logical organization for related tables
- **Apache Iceberg Table**: High-performance table format with ACID transactions
- **AWS Glue Data Catalog**: Centralized metadata management
- **Amazon Athena Workgroup**: Interactive SQL query engine
- **Sample Dataset**: Transaction data for testing and validation
- **Security Controls**: CDK Nag validation and AWS best practices

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- Permissions for S3 Tables, Athena, Glue, and supporting services

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Synthesize CloudFormation template (recommended first)
cdk synth

# Deploy the infrastructure
cdk deploy
```

### 4. Verify Deployment

After deployment, the stack outputs will provide:
- Data bucket name for sample datasets
- Athena results bucket name
- Glue database name for metadata
- Athena workgroup name for queries
- QuickSight setup instructions

## Key Features

### S3 Tables Integration

The stack creates S3 Tables resources using custom resources, as S3 Tables is a new service with evolving CDK support. The implementation includes:

- Table bucket with automatic maintenance operations
- Namespace for logical data organization
- Apache Iceberg table configuration
- Integration with AWS analytics services

### Security Best Practices

- **Encryption**: S3 buckets use server-side encryption
- **Access Control**: Least privilege IAM policies
- **CDK Nag**: Automated security validation
- **VPC**: Can be extended for private networking

### Cost Optimization

- **Lifecycle Policies**: Automatic data tiering to reduce costs
- **Query Results Cleanup**: Automatic cleanup of Athena results
- **Resource Tagging**: Comprehensive tagging for cost allocation

## Configuration

### Environment Variables

```bash
# Set AWS account and region (optional)
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-east-1

# Set environment type
export NODE_ENV=development
```

### Customization

Modify the stack parameters in `app.ts` or create context values in `cdk.json`:

```json
{
  "context": {
    "tableBucketName": "custom-analytics-tables",
    "namespaceName": "custom_namespace",
    "tableName": "custom_table"
  }
}
```

## Usage Examples

### Querying Data with Athena

After deployment, you can query the sample data:

```sql
-- Connect to the deployed Athena workgroup
SELECT 
    region,
    COUNT(*) as transaction_count,
    SUM(price * quantity) as total_revenue
FROM "s3-tables-analytics"."transaction_data"
GROUP BY region
ORDER BY total_revenue DESC;
```

### Adding New Data

Upload additional CSV files to the data bucket:

```bash
aws s3 cp new_data.csv s3://[DATA-BUCKET-NAME]/input/
```

### Connecting QuickSight

1. Sign up for Amazon QuickSight (if not already done)
2. Create a new data source connecting to Athena
3. Select the deployed workgroup: `s3-tables-workgroup`
4. Choose the Glue database: `s3-tables-analytics`
5. Create visualizations using the transaction data

## Development

### Project Structure

```
├── app.ts                              # CDK application entry point
├── lib/
│   └── analytics-optimized-s3-tables-stack.ts  # Main stack implementation
├── package.json                        # Dependencies and scripts
├── tsconfig.json                      # TypeScript configuration
├── cdk.json                           # CDK configuration
└── README.md                          # This file
```

### Available Scripts

```bash
# Compile TypeScript
npm run build

# Watch for changes and compile
npm run watch

# Run tests
npm run test

# Synthesize CloudFormation
npm run synth

# Deploy to AWS
npm run deploy

# Destroy stack
npm run destroy
```

### Testing

The project includes CDK Nag for security validation. Run synthesis to validate:

```bash
cdk synth
```

Address any CDK Nag findings or add suppressions with proper justification in the stack code.

## Troubleshooting

### Common Issues

1. **S3 Tables Region Availability**
   - Ensure your deployment region supports S3 Tables
   - Check AWS documentation for current regional availability

2. **Permissions Errors**
   - Verify AWS CLI credentials have necessary permissions
   - Check IAM policies for S3 Tables operations

3. **CDK Bootstrap**
   - Ensure CDK is bootstrapped in your target account/region
   - Run `cdk bootstrap` if needed

### Debug Mode

Enable detailed logging:

```bash
export CDK_DEBUG=true
cdk deploy --verbose
```

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
cdk destroy
```

This will remove all created resources including:
- S3 buckets and their contents
- Glue database and tables
- Athena workgroup
- IAM roles and policies
- Custom resources

## Cost Estimation

Expected costs for this implementation:
- S3 Tables storage: ~$35.37/TB/month
- Athena queries: $5.00/TB scanned
- Glue operations: Minimal for this demo
- Lambda executions: Minimal for custom resources

## Extensions

Consider these enhancements:

1. **Real-time Ingestion**: Add Kinesis Data Firehose integration
2. **Multi-Region**: Implement cross-region replication
3. **Data Governance**: Add Lake Formation fine-grained access control
4. **Monitoring**: Enhanced CloudWatch dashboards and alerts
5. **Automation**: EventBridge-triggered ETL pipelines

## Support

For issues with this CDK implementation:
1. Check the AWS CDK documentation
2. Review S3 Tables service documentation
3. Consult the original recipe documentation
4. Check AWS support forums

## License

This code is provided under the MIT-0 license. See the LICENSE file for details.