# AWS Glue Workflows Data Pipeline Orchestration - CDK TypeScript

This CDK TypeScript application implements a complete data pipeline orchestration solution using AWS Glue Workflows, demonstrating automated ETL processes with crawlers, jobs, and triggers.

## Architecture Overview

The solution creates:
- **S3 Buckets**: Raw and processed data storage with lifecycle policies
- **IAM Role**: Glue service role with appropriate permissions
- **Glue Database**: Data catalog container for metadata
- **Glue Crawlers**: Automatic schema discovery for source and target data
- **Glue ETL Job**: Data transformation and processing logic
- **Glue Workflow**: Orchestration framework with conditional triggers
- **CloudWatch Logs**: Centralized logging for monitoring

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18.x or later
- TypeScript 5.x or later
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)
- Appropriate AWS permissions for Glue, S3, IAM, and CloudWatch

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### 3. Build and Deploy

```bash
npm run build
cdk deploy
```

### 4. Start Workflow

After deployment, use the AWS CLI to start the workflow:

```bash
# Replace with your actual workflow name from the outputs
aws glue start-workflow-run --name data-pipeline-workflow-{suffix}
```

## Key Features

### Automated Data Pipeline
- **Schedule Trigger**: Automatically starts the workflow daily at 2 AM UTC
- **Conditional Triggers**: Ensure proper sequencing of crawlers and jobs
- **Error Handling**: Built-in retry logic and failure notifications

### Data Processing
- **Schema Discovery**: Crawlers automatically detect and catalog data schemas
- **Data Transformation**: ETL job performs data cleaning and type conversion
- **Parquet Output**: Optimized columnar storage format for analytics

### Monitoring & Logging
- **CloudWatch Integration**: Comprehensive logging and metrics
- **Workflow Visualization**: AWS Glue console provides execution graphs
- **Output Validation**: Automated verification of processing results

## Configuration

### Environment Variables
The application uses CDK environment variables:
- `CDK_DEFAULT_ACCOUNT`: AWS account ID
- `CDK_DEFAULT_REGION`: AWS region

### Customization
Key parameters can be modified in the CDK code:
- **Schedule**: Modify the cron expression in `scheduleTrigger`
- **Timeout**: Adjust job timeout values
- **Retry**: Configure retry attempts for failed jobs
- **Bucket Names**: Customize S3 bucket naming patterns

## Workflow Components

### 1. Source Data Crawler
- **Purpose**: Discovers schema of raw CSV data
- **Target**: S3 raw data bucket input folder
- **Output**: Creates 'input' table in Glue catalog

### 2. ETL Job
- **Purpose**: Transforms data with type conversions
- **Input**: Reads from cataloged 'input' table
- **Output**: Writes Parquet files to processed bucket
- **Transformations**: Maps columns and converts data types

### 3. Target Data Crawler
- **Purpose**: Catalogs transformed Parquet data
- **Target**: S3 processed data bucket output folder
- **Output**: Creates 'output' table in Glue catalog

### 4. Triggers
- **Schedule Trigger**: Starts source crawler daily
- **Crawler Success Trigger**: Starts ETL job after crawler succeeds
- **Job Success Trigger**: Starts target crawler after job completes

## Monitoring

### CloudWatch Logs
- **Job Logs**: `/aws-glue/jobs/{job-name}`
- **Crawler Logs**: `/aws-glue/crawlers/{crawler-name}`

### Workflow Status
```bash
# Check workflow runs
aws glue get-workflow-runs --name {workflow-name}

# Check individual job status
aws glue get-job-runs --job-name {job-name}

# Check crawler status
aws glue get-crawler --name {crawler-name}
```

## Testing

### Sample Data
The deployment includes sample customer purchase data for testing:
- Customer ID, name, email, purchase amount, and date
- CSV format in the raw data bucket

### Validation Steps
1. **Verify Data Catalog**: Check that tables are created
2. **Check Processed Data**: Confirm Parquet files are generated
3. **Review Logs**: Monitor CloudWatch logs for errors
4. **Test Queries**: Use Athena to query cataloged data

## Security

### IAM Permissions
- **Glue Service Role**: Minimal permissions for Glue operations
- **S3 Access**: Read/write permissions for designated buckets only
- **CloudWatch Logs**: Write permissions for logging

### Data Encryption
- **S3 Buckets**: Server-side encryption enabled
- **Data in Transit**: HTTPS for all API calls
- **Logs**: CloudWatch encryption at rest

## Cost Optimization

### Resource Management
- **Auto-scaling**: Glue jobs scale automatically
- **Lifecycle Policies**: S3 objects expire after 30 days
- **Log Retention**: CloudWatch logs retained for 1 week
- **Removal Policy**: Resources destroyed with stack deletion

### Monitoring Costs
- **S3 Storage**: Monitor bucket sizes and lifecycle rules
- **Glue DPU Hours**: Track job execution time and resource usage
- **CloudWatch**: Monitor log volume and retention settings

## Troubleshooting

### Common Issues

1. **Job Failures**:
   - Check CloudWatch logs for detailed error messages
   - Verify IAM permissions for S3 access
   - Ensure input data format matches expected schema

2. **Crawler Issues**:
   - Verify S3 bucket permissions
   - Check data format compatibility
   - Review crawler configuration settings

3. **Workflow Execution**:
   - Ensure triggers are properly configured
   - Check dependency conditions
   - Verify resource availability

### Debugging Commands

```bash
# Get workflow run details
aws glue get-workflow-run --name {workflow-name} --run-id {run-id}

# Check job execution details
aws glue get-job-run --job-name {job-name} --run-id {run-id}

# Review crawler metrics
aws glue get-crawler-metrics --crawler-name-list {crawler-name}
```

## Cleanup

To remove all resources:

```bash
cdk destroy
```

**Note**: This will permanently delete all data and resources. Ensure you have backups if needed.

## Development

### Building
```bash
npm run build
```

### Testing
```bash
npm test
```

### Synthesizing Templates
```bash
cdk synth
```

### Differences
```bash
cdk diff
```

## Extension Ideas

1. **Data Quality Checks**: Add validation steps in the ETL process
2. **Error Notifications**: Integrate SNS for failure alerts
3. **Multi-environment**: Support dev/staging/prod configurations
4. **Advanced Transformations**: Add more complex data processing logic
5. **Real-time Processing**: Integrate with Kinesis for streaming data

## Resources

- [AWS Glue Documentation](https://docs.aws.amazon.com/glue/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Glue Best Practices](https://docs.aws.amazon.com/glue/latest/dg/best-practices.html)
- [CDK TypeScript Guide](https://docs.aws.amazon.com/cdk/latest/guide/work-with-cdk-typescript.html)

## Support

For issues with this CDK application, please refer to:
- AWS Glue service documentation
- CDK troubleshooting guides
- AWS support channels