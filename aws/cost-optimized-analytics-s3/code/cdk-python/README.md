# Cost-Optimized Analytics S3 Intelligent-Tiering - CDK Python

This AWS CDK Python application deploys a complete cost-optimized analytics solution using S3 Intelligent-Tiering, AWS Glue, Amazon Athena, and CloudWatch monitoring. The solution automatically optimizes storage costs by moving data between access tiers based on usage patterns while maintaining full analytical capabilities.

## 🏗️ Architecture Overview

The CDK application creates the following infrastructure:

- **S3 Bucket** with Intelligent-Tiering configuration and lifecycle policies
- **AWS Glue Database** and table for analytics metadata
- **Amazon Athena Workgroup** with cost controls and query limits
- **CloudWatch Dashboard** for monitoring storage distribution and costs
- **Cost Anomaly Detection** for proactive cost management
- **IAM Roles and Policies** with least privilege access

## 📋 Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS Account** with appropriate permissions for:
   - S3 (bucket creation, configuration)
   - AWS Glue (database and table management)
   - Amazon Athena (workgroup management)
   - CloudWatch (dashboard and metrics)
   - AWS Cost Explorer (anomaly detection)
   - IAM (role and policy management)

2. **Development Environment**:
   - Python 3.8 or later
   - AWS CLI v2 installed and configured
   - AWS CDK v2.114.1 or later
   - Node.js 14.x or later (for CDK CLI)

3. **CDK Bootstrap** (if not already done):
   ```bash
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

## 🚀 Quick Start

### 1. Clone and Setup

```bash
# Navigate to the CDK Python directory
cd aws/cost-optimized-analytics-s3-intelligent-tiering/code/cdk-python/

# Create a Python virtual environment
python -m venv .venv

# Activate the virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure CDK Context (Optional)

You can customize the deployment by modifying the `unique_suffix` in `cdk.json` or by passing context parameters:

```bash
# Deploy with custom suffix
cdk deploy --context unique_suffix=prod123

# Deploy with different region context
cdk deploy --context unique_suffix=dev456
```

### 3. Deploy the Infrastructure

```bash
# Synthesize CloudFormation template (optional)
cdk synth

# Deploy the stack
cdk deploy

# Deploy with approval for security changes
cdk deploy --require-approval never
```

### 4. Verify Deployment

After successful deployment, the CDK will output important resource information:

```bash
# Example outputs:
✅  CostOptimizedAnalyticsStack

Outputs:
CostOptimizedAnalyticsStack.BucketName = cost-optimized-analytics-demo123
CostOptimizedAnalyticsStack.GlueDatabaseName = analytics_database_demo123
CostOptimizedAnalyticsStack.AthenaWorkgroupName = cost-optimized-workgroup-demo123
CostOptimizedAnalyticsStack.CloudWatchDashboardUrl = https://console.aws.amazon.com/cloudwatch/...
CostOptimizedAnalyticsStack.AthenaQueryLocation = s3://cost-optimized-analytics-demo123/athena-results/
```

## 📊 Using the Deployed Infrastructure

### Upload Sample Data

```bash
# Set environment variables from CDK outputs
export BUCKET_NAME="cost-optimized-analytics-demo123"
export DATABASE_NAME="analytics_database_demo123"
export WORKGROUP_NAME="cost-optimized-workgroup-demo123"

# Create sample transaction data
mkdir -p /tmp/analytics-data
echo "2024-01-15 10:30:00,user_001,txn_12345,150.00" > /tmp/analytics-data/sample-transaction.csv

# Upload to S3 with Intelligent-Tiering
aws s3 cp /tmp/analytics-data/sample-transaction.csv \
    s3://$BUCKET_NAME/analytics-data/ \
    --storage-class INTELLIGENT_TIERING
```

### Run Athena Queries

```bash
# Execute analytical query
aws athena start-query-execution \
    --query-string "SELECT COUNT(*) FROM $DATABASE_NAME.transaction_logs" \
    --work-group $WORKGROUP_NAME \
    --result-configuration OutputLocation=s3://$BUCKET_NAME/athena-results/
```

### Monitor Cost Optimization

1. **CloudWatch Dashboard**: Visit the dashboard URL from CDK outputs
2. **S3 Metrics**: Monitor storage tier distribution
3. **Athena Costs**: Track data scanning costs
4. **Cost Anomaly Detection**: Receive alerts for unusual spending

## 🛠️ Customization Options

### Modifying Intelligent-Tiering Configuration

Edit the `_create_s3_bucket()` method in `app.py`:

```python
intelligent_tiering_configurations=[
    s3.IntelligentTieringConfiguration(
        id="custom-config",
        status=s3.IntelligentTieringStatus.ENABLED,
        prefix="analytics-data/",
        archive_access_tier_time=Duration.days(30),  # Custom: 30 days
        deep_archive_access_tier_time=Duration.days(90),  # Custom: 90 days
    )
]
```

### Adjusting Athena Cost Controls

Modify the `_create_athena_workgroup()` method:

```python
bytes_scanned_cutoff_per_query=2147483648,  # 2GB limit instead of 1GB
```

### Adding Custom CloudWatch Metrics

Extend the `_create_cloudwatch_dashboard()` method to include additional metrics:

```python
# Add custom widget for error monitoring
error_widget = cloudwatch.GraphWidget(
    title="S3 Error Rates",
    left=[
        cloudwatch.Metric(
            namespace="AWS/S3",
            metric_name="4xxErrors",
            dimensions_map={"BucketName": self.analytics_bucket.bucket_name},
            statistic="Sum"
        )
    ]
)
dashboard.add_widgets(error_widget)
```

## 🔧 Development and Testing

### Running Tests

```bash
# Install development dependencies
pip install -r requirements.txt[dev]

# Run unit tests
pytest tests/ -v

# Run tests with coverage
pytest tests/ --cov=app --cov-report=html

# Type checking
mypy app.py

# Code formatting
black app.py
isort app.py

# Security scanning
bandit -r .
safety check
```

### Local Development

```bash
# Watch for changes and auto-redeploy
cdk deploy --hotswap

# Compare deployed stack with current code
cdk diff

# Validate CloudFormation template
cdk synth --validate
```

## 📚 Advanced Features

### Multi-Environment Deployment

Create environment-specific configuration files:

```bash
# Deploy to development
cdk deploy --context environment=dev --context unique_suffix=dev001

# Deploy to production  
cdk deploy --context environment=prod --context unique_suffix=prod001
```

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy CDK Stack
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.9'
      - run: |
          pip install -r requirements.txt
          cdk deploy --require-approval never
```

### Cost Optimization Best Practices

1. **Enable S3 Storage Class Analysis** before implementing Intelligent-Tiering
2. **Use Athena query result caching** to reduce repeated data scanning
3. **Implement data partitioning** for time-series analytics
4. **Monitor CloudWatch metrics** regularly for cost trends
5. **Set up billing alerts** for budget management

## 🧹 Cleanup

To avoid ongoing costs, clean up the deployed resources:

```bash
# Delete the CDK stack
cdk destroy

# Confirm deletion when prompted
# This will remove all created resources including:
# - S3 bucket and all objects
# - Glue database and table
# - Athena workgroup
# - CloudWatch dashboard
# - Cost anomaly detector
```

## 📖 Additional Resources

- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [S3 Intelligent-Tiering Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering.html)
- [Amazon Athena Cost Control](https://docs.aws.amazon.com/athena/latest/ug/workgroups-manage-queries-control-costs.html)
- [AWS Glue Data Catalog](https://docs.aws.amazon.com/glue/latest/dg/components-overview.html)
- [CloudWatch S3 Metrics](https://docs.aws.amazon.com/AmazonS3/latest/userguide/cloudwatch-monitoring.html)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Important Notes

- **Cost Monitoring**: S3 Intelligent-Tiering has a monthly monitoring fee of $0.0025 per 1,000 objects
- **Data Size**: Objects smaller than 128KB are not eligible for automatic tiering
- **Transition Time**: Allow 30+ days to see full cost optimization benefits
- **Testing**: Use small datasets initially to understand cost implications
- **Cleanup**: Always run `cdk destroy` after testing to avoid unnecessary charges

## 🔍 Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Resource Conflicts**: Use unique suffixes to avoid naming conflicts
3. **Region Restrictions**: Some regions may not support all features
4. **CDK Version**: Ensure you're using CDK v2.114.1 or later

### Getting Help

- Check AWS CloudFormation events for detailed error messages
- Review CloudWatch logs for runtime issues
- Consult AWS documentation for service-specific guidance
- Open GitHub issues for CDK-related problems