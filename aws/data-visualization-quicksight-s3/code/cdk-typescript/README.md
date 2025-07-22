# Data Visualization Pipeline CDK TypeScript

This CDK TypeScript application deploys a complete data visualization pipeline using AWS services including S3, AWS Glue, Amazon Athena, and Amazon QuickSight integration capabilities.

## Architecture

The solution creates:

- **S3 Buckets**: Raw data storage, processed data storage, and Athena query results
- **AWS Glue**: Data catalog, crawlers for schema discovery, and ETL jobs for data transformation
- **Amazon Athena**: Serverless query engine with dedicated workgroup
- **AWS Lambda**: Automation function for pipeline triggers
- **IAM Roles**: Least-privilege access for all services
- **CloudWatch Logs**: Centralized logging for monitoring

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm installed
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for resource creation
- QuickSight activated in your AWS account (for visualization)

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not done previously)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Deploy with default configuration
cdk deploy

# Or deploy with custom project name and environment
cdk deploy --context projectName=my-data-pipeline --context environment=prod
```

### 4. Upload Sample Data

After deployment, upload your data files to the raw data bucket:

```bash
# Get the bucket name from stack outputs
RAW_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name DataVisualizationPipelineStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`RawDataBucketName`].OutputValue' \
    --output text)

# Upload sample sales data
aws s3 cp sales_data.csv s3://${RAW_BUCKET}/sales-data/
```

### 5. Set Up QuickSight

1. **Enable QuickSight** in your AWS account if not already done
2. **Create Data Source**:
   - Go to QuickSight console
   - Create new data source → Athena
   - Use the Athena workgroup from stack outputs
   - Select the Glue database created by the stack
3. **Create Datasets** from the available tables
4. **Build Dashboards** using QuickSight's visual interface

## Configuration Options

You can customize the deployment using CDK context:

```bash
# Custom project name and environment
cdk deploy --context projectName=analytics-pipeline --context environment=staging

# Deploy to specific region
cdk deploy --context projectName=data-viz --context environment=prod
```

## Sample Data Format

The pipeline expects data in the following formats:

### Sales Data (CSV)
```csv
order_id,customer_id,product_category,product_name,quantity,unit_price,order_date,region,sales_rep
1001,C001,Electronics,Laptop,1,1200.00,2024-01-15,North,John Smith
```

### Customer Data (CSV)
```csv
customer_id,customer_name,email,registration_date,customer_tier,city,state
C001,Michael Johnson,mjohnson@email.com,2023-06-15,Gold,New York,NY
```

### Product Data (JSON)
```json
[
  {
    "product_id": "P001",
    "product_name": "Laptop",
    "category": "Electronics",
    "cost": 800.00,
    "margin": 0.50
  }
]
```

## Pipeline Automation

The solution includes automatic triggers:

1. **Data Upload**: When new files are uploaded to the raw data bucket
2. **Schema Discovery**: Glue crawler automatically updates table schemas
3. **ETL Processing**: Glue job processes new data into analytics-ready format
4. **Catalog Update**: Processed data is cataloged for Athena queries

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor the following log groups:

- `/aws-glue/jobs/{etl-job-name}` - ETL job execution logs
- `/aws/lambda/{automation-function-name}` - Pipeline automation logs

### Manual Operations

```bash
# Manually trigger crawler
aws glue start-crawler --name {crawler-name}

# Check crawler status
aws glue get-crawler --name {crawler-name}

# Manually start ETL job
aws glue start-job-run --job-name {etl-job-name}

# Check job run status
aws glue get-job-runs --job-name {etl-job-name}
```

### Common Issues

1. **Crawler not finding data**: Ensure data is uploaded to the correct S3 path
2. **ETL job failing**: Check CloudWatch logs for specific error messages
3. **Athena queries failing**: Verify table schemas in Glue Data Catalog
4. **QuickSight connection issues**: Ensure proper IAM permissions for QuickSight service

## Cost Optimization

The solution includes several cost optimization features:

- **S3 Lifecycle Policies**: Automatically transition older data to cheaper storage classes
- **Athena Result Expiration**: Query results are automatically deleted after 30 days
- **Glue Job Configuration**: Uses appropriate worker types and counts for cost efficiency
- **CloudWatch Log Retention**: Logs are retained for appropriate periods

## Security Features

- **Bucket Encryption**: All S3 buckets use server-side encryption
- **Block Public Access**: All buckets block public access by default
- **Least Privilege IAM**: Roles have minimal required permissions
- **VPC Support**: Can be deployed in VPC for additional network isolation (modify as needed)

## Customization

### Adding New Data Sources

1. Update the Glue crawler S3 targets
2. Modify ETL script to handle new data formats
3. Update IAM permissions for new S3 locations

### Modifying ETL Logic

Edit the ETL script in the Glue job definition to:
- Add new transformations
- Create additional aggregated views
- Handle different data formats

### Scaling Configuration

Adjust these parameters based on your data volume:

```typescript
// In the Glue job configuration
workerType: 'G.2X',  // Increase for larger datasets
numberOfWorkers: 10, // Scale based on data volume
```

## Cleanup

To remove all resources:

```bash
cdk destroy
```

**Warning**: This will delete all data in the S3 buckets. Ensure you have backups if needed.

## Support

For issues with this CDK application:

1. Check CloudWatch logs for error details
2. Verify IAM permissions
3. Ensure all prerequisites are met
4. Refer to AWS service documentation for specific service issues

## Additional Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/)
- [Amazon Athena User Guide](https://docs.aws.amazon.com/athena/latest/ug/)
- [Amazon QuickSight User Guide](https://docs.aws.amazon.com/quicksight/latest/user/)
- [AWS Data Analytics Best Practices](https://aws.amazon.com/big-data/datalakes-and-analytics/)