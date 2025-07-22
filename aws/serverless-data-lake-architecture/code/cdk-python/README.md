# Advanced Serverless Data Lake Architecture - CDK Python

This CDK Python application implements an enterprise-grade serverless data lake architecture using AWS Lambda layers, AWS Glue, and Amazon EventBridge for scalable, event-driven data processing.

## Architecture Overview

The solution implements a comprehensive data processing pipeline with the following components:

### Core Infrastructure
- **S3 Buckets**: Separate buckets for raw, processed, and quarantine data with lifecycle policies
- **DynamoDB Table**: Metadata storage for tracking processing history and data lineage
- **Lambda Layer**: Shared utilities and dependencies for code reusability
- **EventBridge**: Custom event bus for loosely coupled, event-driven orchestration

### Processing Pipeline
- **Data Ingestion**: Lambda function triggered by S3 events for automated data intake
- **Data Validation**: Event-driven Lambda function for comprehensive data quality checking
- **Quality Monitoring**: Real-time metrics collection and alerting system
- **ETL Processing**: AWS Glue crawler and jobs for schema discovery and batch processing

### Observability
- **CloudWatch Metrics**: Custom metrics for pipeline health and data quality
- **X-Ray Tracing**: Distributed tracing for performance monitoring
- **CloudWatch Logs**: Centralized logging with configurable retention

## Features

### Enterprise-Grade Capabilities
- **Code Reusability**: Lambda layers eliminate code duplication across functions
- **Event-Driven Architecture**: Loose coupling through EventBridge enables scalable workflows
- **Data Quality Gates**: Multi-layer validation with automatic quarantine for failed data
- **Comprehensive Monitoring**: Real-time quality metrics and alerting
- **Cost Optimization**: Intelligent S3 lifecycle policies and serverless scaling

### Data Processing Features
- **Multi-Format Support**: JSON, CSV, and text file processing
- **Schema Validation**: Configurable validation rules for data structure
- **Quality Scoring**: Automated data quality assessment with scoring
- **Error Handling**: Robust error handling with detailed logging and metadata tracking
- **Data Lineage**: Complete audit trail from ingestion to processing

## Prerequisites

- AWS CLI v2 installed and configured
- AWS CDK v2.121.1 or later
- Python 3.9 or later
- Node.js 18.x or later (for CDK CLI)
- Appropriate AWS permissions for:
  - Lambda functions and layers
  - S3 buckets and objects
  - DynamoDB tables
  - EventBridge custom buses
  - AWS Glue databases and crawlers
  - IAM roles and policies
  - CloudWatch logs and metrics

## Installation

1. **Clone the repository and navigate to the CDK directory**:
   ```bash
   cd aws/advanced-serverless-data-lake-architecture-lambda-layers-glue-eventbridge/code/cdk-python/
   ```

2. **Create and activate a Python virtual environment**:
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install Python dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Install CDK CLI** (if not already installed):
   ```bash
   npm install -g aws-cdk@latest
   ```

5. **Bootstrap CDK** (first time only):
   ```bash
   cdk bootstrap
   ```

## Configuration

### Environment Variables

The application supports customization through CDK context variables:

```bash
# Set project name (default: advanced-serverless-datalake)
cdk deploy -c project_name=my-data-lake

# Set environment (default: dev)
cdk deploy -c environment=prod

# Set AWS account and region
cdk deploy -c account=123456789012 -c region=us-east-1
```

### Context Configuration in cdk.json

```json
{
  "customizations": {
    "data-lake": {
      "project_name": "advanced-serverless-datalake",
      "environment": "dev",
      "enable_monitoring": true,
      "enable_tracing": true,
      "log_retention_days": 7,
      "glue_crawler_schedule": "cron(0 */6 * * ? *)"
    }
  }
}
```

## Deployment

### Development Environment

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy with confirmation prompts
cdk deploy

# Deploy without confirmation prompts
cdk deploy --require-approval never
```

### Production Environment

```bash
# Deploy to production with custom configuration
cdk deploy -c environment=prod -c project_name=company-data-lake
```

### Multi-Account Deployment

```bash
# Deploy to specific account and region
cdk deploy -c account=123456789012 -c region=us-west-2
```

## Usage

### Data Ingestion

1. **Upload files to the raw data bucket** with the `input/` prefix:
   ```bash
   aws s3 cp sample-data.json s3://[raw-bucket-name]/input/
   ```

2. **Monitor processing** through CloudWatch logs:
   ```bash
   aws logs tail /aws/lambda/[project-name]-data-ingestion --follow
   ```

### Monitoring Quality Metrics

View quality metrics in CloudWatch:

```bash
# Get validation success rate
aws cloudwatch get-metric-statistics \
    --namespace "DataLake/Quality" \
    --metric-name "ValidationSuccessRate" \
    --dimensions Name=Pipeline,Value=[project-name] \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 3600 \
    --statistics Average
```

### Querying Metadata

Query processing metadata from DynamoDB:

```bash
# Scan for recent processing records
aws dynamodb scan \
    --table-name [metadata-table-name] \
    --filter-expression "ProcessingStage = :stage" \
    --expression-attribute-values '{":stage":{"S":"validation"}}'
```

### Glue Catalog Integration

Access processed data through Athena using the Glue catalog:

```sql
-- Query processed data using Athena
SELECT * FROM [glue-database-name].[table-name] 
WHERE partition_date >= '2024-01-01'
LIMIT 100;
```

## Project Structure

```
├── app.py                          # Main CDK application entry point
├── serverless_datalake_stack.py    # Primary CDK stack definition
├── requirements.txt                # Python dependencies
├── setup.py                       # Package configuration
├── cdk.json                       # CDK configuration
├── lambda_layers/
│   └── shared_utilities/
│       └── data_utils.py          # Shared utilities for Lambda functions
├── lambda_functions/
│   ├── data_ingestion/
│   │   └── lambda_function.py     # Data ingestion Lambda function
│   ├── data_validation/
│   │   └── lambda_function.py     # Data validation Lambda function
│   └── quality_monitoring/
│       └── lambda_function.py     # Quality monitoring Lambda function
└── README.md                      # This file
```

## Testing

### Unit Tests

```bash
# Install development dependencies
pip install -r requirements.txt[dev]

# Run unit tests
python -m pytest tests/ -v

# Run tests with coverage
python -m pytest tests/ --cov=. --cov-report=html
```

### Integration Tests

```bash
# Deploy to test environment
cdk deploy -c environment=test

# Run integration tests
python -m pytest integration_tests/ -v

# Clean up test resources
cdk destroy -c environment=test
```

### Load Testing

```bash
# Generate test data
python scripts/generate_test_data.py --count 1000 --output test-data/

# Upload test data
aws s3 sync test-data/ s3://[raw-bucket-name]/input/

# Monitor processing metrics
aws cloudwatch get-metric-statistics \
    --namespace "DataLake/Quality" \
    --metric-name "ProcessedRecords" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Monitoring and Observability

### CloudWatch Dashboards

The solution publishes custom metrics to CloudWatch:

- **ValidationSuccessRate**: Percentage of records passing validation
- **AverageQualityScore**: Average data quality score across all records
- **ProcessedRecords**: Total number of processed records
- **QualityDistribution**: Distribution of quality scores across ranges

### X-Ray Tracing

Enable detailed tracing to monitor performance and identify bottlenecks:

```bash
# View X-Ray trace map
aws xray get-trace-summaries \
    --time-range-type TimeRangeByStartTime \
    --start-time 2024-01-01T00:00:00 \
    --end-time 2024-01-01T23:59:59
```

### Log Analysis

Query CloudWatch logs for debugging and analysis:

```bash
# Query logs with CloudWatch Insights
aws logs start-query \
    --log-group-name "/aws/lambda/[function-name]" \
    --start-time $(date -d '1 hour ago' +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, @message | filter @message like /ERROR/'
```

## Security Considerations

### IAM Best Practices

- **Least Privilege**: Each Lambda function has minimal required permissions
- **Resource-Specific Access**: S3 and DynamoDB permissions are scoped to specific resources
- **Cross-Service Security**: EventBridge permissions limited to custom bus operations

### Data Protection

- **Encryption at Rest**: All S3 buckets use server-side encryption
- **Encryption in Transit**: All AWS service communications use TLS
- **Access Logging**: S3 access logging can be enabled for audit trails

### Network Security

- **VPC Integration**: Lambda functions can be deployed in VPC for network isolation
- **Security Groups**: Configurable security groups for VPC-deployed functions
- **Private Endpoints**: Support for VPC endpoints to keep traffic private

## Cost Optimization

### Resource Optimization

- **ARM64 Architecture**: Lambda functions use ARM64 for better price/performance
- **Rightsized Memory**: Memory allocation optimized for each function's workload
- **S3 Lifecycle Policies**: Automatic transition to lower-cost storage classes

### Monitoring Costs

```bash
# Monitor Lambda costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Troubleshooting

### Common Issues

1. **Lambda Function Timeouts**:
   ```bash
   # Check function configuration
   aws lambda get-function-configuration --function-name [function-name]
   
   # Increase timeout if needed
   aws lambda update-function-configuration \
       --function-name [function-name] \
       --timeout 300
   ```

2. **S3 Event Notification Issues**:
   ```bash
   # Verify S3 event configuration
   aws s3api get-bucket-notification-configuration --bucket [bucket-name]
   
   # Check Lambda function permissions
   aws lambda get-policy --function-name [function-name]
   ```

3. **DynamoDB Throttling**:
   ```bash
   # Check table metrics
   aws cloudwatch get-metric-statistics \
       --namespace "AWS/DynamoDB" \
       --metric-name "ThrottledRequests" \
       --dimensions Name=TableName,Value=[table-name]
   ```

### Debug Mode

Enable debug logging:

```bash
# Deploy with debug logging
cdk deploy -c debug=true
```

## Cleanup

### Remove All Resources

```bash
# Destroy the CDK stack
cdk destroy

# Confirm resource deletion
aws cloudformation describe-stacks --stack-name [stack-name]
```

### Selective Cleanup

```bash
# Empty S3 buckets before destruction
aws s3 rm s3://[bucket-name] --recursive

# Delete specific resources
aws lambda delete-function --function-name [function-name]
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Make changes and test thoroughly
4. Commit changes: `git commit -am 'Add new feature'`
5. Push to branch: `git push origin feature/new-feature`
6. Submit a pull request

## Support

For issues and questions:

1. Check the troubleshooting section above
2. Review CloudWatch logs for error details
3. Consult AWS documentation for service-specific guidance
4. Open an issue in the repository for bugs or feature requests

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.

## Additional Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/)
- [Data Lake Architecture on AWS](https://aws.amazon.com/big-data/datalakes-and-analytics/)