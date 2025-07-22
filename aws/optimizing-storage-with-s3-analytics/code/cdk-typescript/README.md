# S3 Inventory and Storage Analytics Reporting - CDK TypeScript

This CDK TypeScript application deploys a comprehensive S3 Inventory and Storage Analytics solution that provides automated reporting and cost optimization insights for your AWS S3 storage.

## Architecture Overview

The solution implements the following architecture:

- **Source S3 Bucket**: Stores your data and generates inventory reports
- **Destination S3 Bucket**: Receives inventory reports and analytics data
- **S3 Inventory Configuration**: Automated daily/weekly inventory generation
- **Storage Class Analysis**: Monitors access patterns for cost optimization
- **AWS Glue Database**: Catalog for Athena queries
- **Athena WorkGroup**: Serverless SQL queries on inventory data
- **Lambda Function**: Automated analytics execution
- **EventBridge Rule**: Daily scheduling for automated reports
- **CloudWatch Dashboard**: Real-time monitoring and visualization

## Prerequisites

Before deploying this solution, ensure you have:

1. **AWS CLI v2** installed and configured
2. **Node.js 18+** and npm installed
3. **AWS CDK v2** installed globally (`npm install -g aws-cdk`)
4. **AWS account** with appropriate permissions for:
   - S3 (bucket creation, inventory configuration)
   - IAM (role and policy creation)
   - Lambda (function creation and execution)
   - Athena (database and query execution)
   - Glue (catalog management)
   - CloudWatch (dashboard and metrics)
   - EventBridge (rule creation)

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not already done)

```bash
npm run bootstrap
```

### 3. Build the Application

```bash
npm run build
```

### 4. Deploy the Stack

```bash
npm run deploy
```

The deployment will create all necessary resources and output important information including:
- Source and destination bucket names
- Glue database name
- Athena WorkGroup name
- Lambda function name
- CloudWatch dashboard URL
- Sample data upload commands

### 5. Upload Sample Data (Optional)

After deployment, you can upload sample data using the commands provided in the stack outputs:

```bash
echo "Sample data for storage analytics" > sample-file.txt
aws s3 cp sample-file.txt s3://[SOURCE-BUCKET-NAME]/data/sample-file.txt
aws s3 cp sample-file.txt s3://[SOURCE-BUCKET-NAME]/logs/access-log.txt
aws s3 cp sample-file.txt s3://[SOURCE-BUCKET-NAME]/archive/old-data.txt
```

## Configuration Options

The CDK application supports several parameters for customization:

### Stack Parameters

You can customize the deployment using CDK context values:

```bash
# Deploy with custom bucket prefix
cdk deploy --parameters BucketPrefix=my-company-storage

# Deploy with weekly inventory instead of daily
cdk deploy --parameters InventorySchedule=Weekly

# Deploy with custom analysis prefix
cdk deploy --parameters AnalysisPrefix=logs/
```

### Environment Variables

Set environment variables before deployment:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-east-1
```

## Usage

### Accessing the Dashboard

1. Navigate to the CloudWatch dashboard URL provided in the stack outputs
2. Monitor storage metrics, request patterns, and Lambda function performance
3. Set up alerts based on the metrics as needed

### Running Analytics Queries

#### Manual Query Execution

1. Open the Amazon Athena console
2. Select the `storage-analytics-workgroup` WorkGroup
3. Use the `s3-inventory-db` database
4. Create a table for your inventory data:

```sql
CREATE EXTERNAL TABLE inventory_table (
  bucket_name string,
  key string,
  version_id string,
  is_latest boolean,
  is_delete_marker boolean,
  size bigint,
  last_modified_date timestamp,
  etag string,
  storage_class string,
  is_multipart_uploaded boolean,
  replication_status string,
  encryption_status string
)
STORED AS INPUTFORMAT 'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://[DESTINATION-BUCKET-NAME]/inventory-reports/[SOURCE-BUCKET-NAME]/daily-inventory-config/'
TBLPROPERTIES (
  'skip.header.line.count'='1'
);
```

#### Sample Analytics Queries

**Storage Class Distribution:**
```sql
SELECT 
    storage_class,
    COUNT(*) as object_count,
    SUM(size) as total_size_bytes,
    ROUND(SUM(size) / 1024.0 / 1024.0 / 1024.0, 2) as total_size_gb
FROM s3_inventory_db.inventory_table
GROUP BY storage_class
ORDER BY total_size_bytes DESC;
```

**Objects Older Than 30 Days:**
```sql
SELECT 
    key,
    size,
    storage_class,
    last_modified_date,
    DATE_DIFF('day', last_modified_date, CURRENT_DATE) as days_old
FROM s3_inventory_db.inventory_table
WHERE DATE_DIFF('day', last_modified_date, CURRENT_DATE) > 30
ORDER BY days_old DESC;
```

#### Automated Analytics

The Lambda function runs daily and executes predefined analytics queries. Results are stored in the destination bucket under the `athena-results/` prefix.

### Monitoring and Troubleshooting

#### CloudWatch Logs

Monitor Lambda function execution:
```bash
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/S3InventoryStorageAnalyticsStack-StorageAnalyticsFunction
```

#### Manual Lambda Invocation

Test the analytics function manually:
```bash
aws lambda invoke \
    --function-name [ANALYTICS-FUNCTION-NAME] \
    --payload '{}' \
    response.json && cat response.json
```

## Cost Optimization

### S3 Storage Costs

- **S3 Inventory**: ~$0.0025 per million objects listed
- **Storage Class Analysis**: No additional charges
- **S3 Storage**: Standard rates apply for source and destination buckets

### Compute Costs

- **Athena**: $5 per TB of data scanned
- **Lambda**: Pay per request and compute time
- **CloudWatch**: Standard monitoring costs

### Cost Control Features

1. **Athena Query Limits**: 1GB scan limit per query in the WorkGroup
2. **Lifecycle Policies**: Automatic transition to cheaper storage classes
3. **S3 Intelligent Tiering**: Can be enabled for automatic optimization

## Security Best Practices

### IAM Roles and Policies

- Lambda function uses least-privilege IAM policies
- S3 bucket policies restrict access to specific services
- All resources follow AWS security best practices

### Encryption

- S3 buckets use SSE-S3 encryption by default
- Athena query results are encrypted
- Lambda environment variables can be encrypted (configure if needed)

### Network Security

- S3 buckets block all public access
- VPC endpoints can be configured for private communication

## Development

### Project Structure

```
├── app.ts                          # CDK application entry point
├── lib/
│   └── s3-inventory-storage-analytics-stack.ts  # Main stack definition
├── test/                           # Unit tests (to be implemented)
├── package.json                    # NPM dependencies and scripts
├── tsconfig.json                   # TypeScript configuration
├── cdk.json                        # CDK configuration
└── README.md                       # This file
```

### Available Scripts

```bash
npm run build        # Compile TypeScript
npm run watch        # Watch for changes and compile
npm run test         # Run unit tests
npm run lint         # Run ESLint
npm run lint:fix     # Fix ESLint issues
npm run cdk          # Run CDK CLI commands
npm run deploy       # Build and deploy
npm run destroy      # Destroy the stack
npm run diff         # Show differences
npm run synth        # Synthesize CloudFormation
```

### Testing

Run unit tests:
```bash
npm test
```

Run in watch mode:
```bash
npm run test:watch
```

## Cleanup

To remove all resources created by this stack:

```bash
npm run destroy
```

**Note**: This will delete all S3 buckets and their contents. Ensure you have backed up any important data before running this command.

## Troubleshooting

### Common Issues

1. **Inventory Reports Not Appearing**
   - S3 Inventory reports take 24-48 hours to generate initially
   - Check the destination bucket for inventory reports

2. **Athena Query Failures**
   - Ensure the Glue table schema matches your inventory data
   - Verify the S3 location in the table definition

3. **Lambda Function Errors**
   - Check CloudWatch Logs for detailed error messages
   - Verify IAM permissions for Athena and S3 access

4. **Permission Errors**
   - Ensure your AWS credentials have sufficient permissions
   - Check IAM policies for all required services

### Getting Help

- Check AWS documentation for each service
- Review CloudWatch Logs for detailed error messages
- Use AWS Support for complex issues

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Additional Resources

- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Amazon S3 Inventory Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-inventory.html)
- [Amazon S3 Storage Class Analysis](https://docs.aws.amazon.com/AmazonS3/latest/userguide/analytics-storage-class.html)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)