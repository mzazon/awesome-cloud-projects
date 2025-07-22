# Amazon Redshift Serverless Data Warehouse - CDK TypeScript

This AWS CDK TypeScript application deploys a complete Amazon Redshift Serverless data warehousing solution with S3 integration, monitoring, and security best practices.

## Architecture

The CDK application creates:

- **Amazon Redshift Serverless**: Fully managed, auto-scaling data warehouse
  - Namespace for storage layer configuration
  - Workgroup for compute resources (128 RPU base capacity)
  - Automatic scaling based on workload demands
- **Amazon S3**: Secure data storage with lifecycle policies
  - Versioning enabled
  - Server-side encryption (SSE-S3)
  - Automatic lifecycle transitions to IA and Glacier
- **IAM Role**: Least privilege access for Redshift to S3 and CloudWatch
- **CloudWatch**: Comprehensive monitoring and dashboards
  - Query performance metrics
  - Compute utilization tracking
  - Data scanning analytics
- **Security**: Best practices implementation
  - Encrypted storage and transit
  - Private access controls
  - Audit logging enabled

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm
- AWS CDK v2 CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for Redshift, S3, IAM, and CloudWatch

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

4. **Review the outputs** which include:
   - S3 bucket name for data files
   - Redshift Serverless endpoint
   - CloudWatch dashboard URL
   - Query Editor v2 URL

## Configuration

The stack accepts several configuration options through CDK context or constructor props:

### CDK Context Variables

Set these in `cdk.json` or pass via `--context` flag:

```json
{
  "context": {
    "environment": "development",
    "baseCapacity": 128,
    "publiclyAccessible": true,
    "databaseName": "sampledb",
    "adminUsername": "awsuser"
  }
}
```

### Environment-Specific Deployment

For production environments:

```bash
cdk deploy --context environment=production
```

This enables:
- Resource retention policies
- Termination protection
- Enhanced security configurations

## Post-Deployment Setup

After successful deployment:

1. **Upload sample data to S3**:
   ```bash
   # Get bucket name from stack outputs
   export BUCKET_NAME=$(aws cloudformation describe-stacks \
     --stack-name RedshiftDataWarehouseStack \
     --query 'Stacks[0].Outputs[?OutputKey==`DataBucketName`].OutputValue' \
     --output text)
   
   # Create sample data files (optional)
   echo "order_id,customer_id,product_id,quantity,price,order_date
   1001,501,2001,2,29.99,2024-01-15" > sales_data.csv
   
   # Upload to S3
   aws s3 cp sales_data.csv s3://${BUCKET_NAME}/data/
   ```

2. **Connect to Redshift using Query Editor v2**:
   - Navigate to the Query Editor v2 URL from stack outputs
   - Connect to your workgroup using the admin credentials
   - Create tables and load data using COPY commands

3. **Monitor performance**:
   - Access the CloudWatch Dashboard from stack outputs
   - Monitor query performance and compute utilization
   - Set up alarms for cost optimization

## Sample SQL Operations

After connecting to your Redshift Serverless workgroup:

### Create Tables
```sql
CREATE TABLE sales (
    order_id INTEGER,
    customer_id INTEGER,
    product_id INTEGER,
    quantity INTEGER,
    price DECIMAL(10,2),
    order_date DATE
);
```

### Load Data from S3
```sql
COPY sales FROM 's3://your-bucket-name/data/sales_data.csv'
IAM_ROLE 'arn:aws:iam::account:role/RedshiftServerlessRole-xxxxxxxx'
CSV
IGNOREHEADER 1;
```

### Analytics Query
```sql
SELECT 
    product_id,
    SUM(quantity) as total_quantity,
    SUM(quantity * price) as total_revenue
FROM sales
GROUP BY product_id
ORDER BY total_revenue DESC;
```

## Monitoring and Observability

The stack includes comprehensive monitoring:

### CloudWatch Metrics
- `ComputeCapacity`: RPU usage over time
- `QueryDuration`: Query execution times
- `DataScannedInBytes`: Data processing volume
- `QueryCount`: Number of active queries

### Log Groups
- User activity logs
- Connection logs
- User logs

Access logs through CloudWatch Logs console or CLI:
```bash
aws logs describe-log-groups --log-group-name-prefix "/aws/redshift"
```

## Security Features

### Encryption
- S3 bucket with server-side encryption (SSE-S3)
- Redshift data encrypted at rest using AWS managed KMS
- Enforced SSL for all connections

### Access Control
- IAM role with least privilege principles
- S3 bucket blocks all public access
- Redshift workgroup access controls

### Audit Logging
- Comprehensive query and connection logging
- CloudTrail integration for API calls
- CloudWatch Logs for centralized log management

## Cost Optimization

### Serverless Benefits
- Pay only for compute resources during query execution
- Automatic scaling based on workload
- No idle capacity charges

### Storage Optimization
- S3 lifecycle policies for automatic cost reduction
- Intelligent tiering for frequently accessed data
- Glacier storage for long-term archival

### Monitoring Costs
```bash
# View current month costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Customization

### Modifying Base Capacity
```typescript
new RedshiftDataWarehouseStack(app, 'MyStack', {
  baseCapacity: 256, // Higher capacity for demanding workloads
});
```

### Adding VPC Configuration
For private networking, modify the workgroup configuration:
```typescript
this.workgroup = new redshift.CfnWorkgroup(this, 'Workgroup', {
  // ... other props
  subnetGroupName: 'your-subnet-group',
  securityGroupIds: ['sg-xxxxxxxxx'],
  publiclyAccessible: false,
  enhancedVpcRouting: true,
});
```

### Custom IAM Policies
Add specific permissions for your use case:
```typescript
this.redshiftRole.addToPolicy(
  new iam.PolicyStatement({
    effect: iam.Effect.ALLOW,
    actions: ['glue:GetTable', 'glue:GetPartitions'],
    resources: ['arn:aws:glue:region:account:*'],
  })
);
```

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Verify AWS credentials and permissions
   - Check region availability for Redshift Serverless
   - Ensure unique resource names

2. **Connection Issues**:
   - Verify workgroup is in `AVAILABLE` status
   - Check security group rules if using VPC
   - Confirm admin credentials

3. **Data Loading Errors**:
   - Verify IAM role permissions for S3 access
   - Check S3 bucket path and file format
   - Review COPY command syntax

### Getting Help

- Check CloudWatch Logs for detailed error messages
- Use AWS Support for service-specific issues
- Review the [Amazon Redshift documentation](https://docs.aws.amazon.com/redshift/)

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
# Delete all resources
cdk destroy

# Confirm deletion
```

**Note**: For production environments with retention policies, some resources may require manual deletion.

## Development

### Local Development
```bash
# Compile TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm test

# View synthesized CloudFormation
cdk synth
```

### Project Structure
```
├── app.ts                 # CDK app entry point
├── lib/
│   └── redshift-data-warehouse-stack.ts  # Main stack definition
├── package.json           # Node.js dependencies
├── tsconfig.json         # TypeScript configuration
├── cdk.json              # CDK configuration
└── README.md             # This file
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This code is licensed under the MIT-0 License. See the LICENSE file for details.