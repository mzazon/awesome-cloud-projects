# CDK TypeScript Implementation - Intelligent Sustainability Dashboards

This directory contains the AWS CDK TypeScript implementation for building intelligent sustainability dashboards with AWS Customer Carbon Footprint Tool and Amazon QuickSight.

## Architecture Overview

The solution creates an integrated sustainability intelligence platform that combines:

- **AWS Customer Carbon Footprint Tool** for emissions tracking
- **Amazon QuickSight** for advanced visualization and business intelligence
- **AWS Cost Explorer API** for cost correlation analysis
- **AWS Lambda** for automated data processing and ETL
- **Amazon EventBridge** for scheduled automation
- **Amazon S3** for data lake storage with lifecycle management
- **Amazon CloudWatch** for monitoring and alerting

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured with appropriate permissions
2. **Node.js** (version 18.x or later) and npm installed
3. **AWS CDK** v2 installed globally: `npm install -g aws-cdk`
4. **CDK Bootstrap** completed in your target account/region: `cdk bootstrap`
5. **Cost Management permissions** for accessing Cost Explorer APIs
6. **QuickSight account** (Standard edition recommended - ~$18/month)

### Required AWS Permissions

The deployment requires the following permissions:
- IAM role creation and policy attachment
- Lambda function creation and configuration
- S3 bucket creation with lifecycle policies
- EventBridge rule creation and Lambda targets
- CloudWatch alarms and custom metrics
- SNS topic creation and subscriptions

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment (Optional)

Set environment variables for customization:

```bash
export CDK_DEFAULT_ACCOUNT="123456789012"  # Your AWS account ID
export CDK_DEFAULT_REGION="us-east-1"     # Your preferred region
```

### 3. Synthesize CloudFormation Template

Review the generated CloudFormation template before deployment:

```bash
npm run synth
# or
cdk synth
```

### 4. Deploy the Stack

Deploy the complete sustainability analytics platform:

```bash
npm run deploy
# or
cdk deploy
```

### 5. Configure Email Alerts (Optional)

To receive sustainability alerts via email, deploy with the alert email parameter:

```bash
cdk deploy --parameters alertEmail=your-email@example.com
```

## Post-Deployment Setup

After successful deployment, complete these steps to activate the full solution:

### 1. Set Up QuickSight Integration

1. **Access QuickSight Console**: https://quicksight.aws.amazon.com/
2. **Sign up** for QuickSight Standard edition if not already active
3. **Grant S3 permissions** to QuickSight during setup process
4. **Create Data Source**:
   - Choose "S3" as data source type
   - Upload the manifest file from: `s3://sustainability-analytics-{uniqueId}/manifests/sustainability-manifest.json`
   - Name the dataset: "Sustainability Analytics Dataset"

### 2. Build Sustainability Dashboard

Create comprehensive visualizations including:

- **Time-series charts** for cost trends by service and region
- **Bar charts** for regional cost and optimization comparisons  
- **KPI cards** for cost optimization opportunities and potential savings
- **Heat maps** for service-region carbon intensity visualization
- **Pie charts** for cost distribution across services

### 3. Configure Automated Refresh

- Set up **monthly refresh** schedule to align with AWS carbon footprint data availability
- Configure **incremental refresh** for cost data to optimize performance
- Enable **automated email reports** for stakeholders

### 4. Set Up User Access

- Configure **user permissions** for sustainability stakeholders
- Create **shared dashboards** for executive reporting
- Set up **embedded analytics** integration if needed

## Configuration Options

The CDK stack supports several configuration options through the `SustainabilityDashboardStackProps` interface:

### Stack Properties

```typescript
export interface SustainabilityDashboardStackProps extends cdk.StackProps {
  // Email address for sustainability alerts
  readonly alertEmail?: string;
  
  // CloudWatch logs retention period (default: 30 days)
  readonly logRetentionDays?: logs.RetentionDays;
  
  // Lambda memory allocation in MB (default: 512)
  readonly lambdaMemorySize?: number;
  
  // Lambda timeout in minutes (default: 5)
  readonly lambdaTimeoutMinutes?: number;
}
```

### Custom Deployment Examples

```bash
# Deploy with custom configuration
cdk deploy --parameters alertEmail=sustainability@company.com \
           --parameters lambdaMemorySize=1024 \
           --parameters lambdaTimeoutMinutes=10
```

## Monitoring and Troubleshooting

### CloudWatch Dashboards

The solution automatically creates CloudWatch alarms for:

- **Lambda function errors** - Alerts on any processing failures
- **Data processing success** - Monitors successful monthly data collection
- **S3 data ingestion** - Tracks new data uploads to the data lake

### Log Groups

Monitor application behavior through these log groups:

- `/aws/lambda/SustainabilityDataProcessor-{uniqueId}` - Data processing logs
- `/aws/s3/sustainability-analytics-{uniqueId}` - S3 access logs
- `/aws/events/rule/sustainability-data-collection` - EventBridge execution logs

### Common Troubleshooting Steps

1. **Lambda function timeout**: Increase `lambdaTimeoutMinutes` parameter
2. **Memory issues**: Increase `lambdaMemorySize` parameter  
3. **Cost Explorer API errors**: Verify account permissions for Cost Management
4. **QuickSight connection issues**: Ensure S3 permissions are granted to QuickSight
5. **Missing data**: Check EventBridge rule execution and Lambda function logs

## Cost Optimization

### Expected Monthly Costs

- **QuickSight Standard**: ~$18/month per user
- **Lambda executions**: <$5/month for monthly processing
- **S3 storage**: <$10/month for analytics data with lifecycle policies
- **CloudWatch monitoring**: <$5/month for logs and metrics
- **EventBridge rules**: <$1/month for scheduled triggers

**Total estimated cost**: ~$40/month for a single user implementation

### Cost Reduction Strategies

1. **Use S3 Intelligent Tiering** for automatic cost optimization
2. **Configure appropriate log retention** periods
3. **Optimize Lambda memory** allocation based on processing requirements
4. **Use QuickSight embedded** analytics to reduce per-user costs
5. **Implement data archival** policies for older analytics data

## Security Best Practices

The CDK implementation follows AWS Well-Architected security principles:

### Implemented Security Controls

- **IAM least privilege** - Lambda roles have minimal required permissions
- **S3 bucket encryption** - All data encrypted at rest with AES-256
- **SSL/TLS enforcement** - All data in transit encrypted
- **VPC endpoints** - Private connectivity where applicable
- **Resource-level permissions** - Granular access controls
- **CloudWatch encryption** - Log data encrypted with AWS KMS

### CDK Nag Validation

The stack includes CDK Nag validation to ensure:
- No hardcoded secrets or credentials
- Proper encryption configuration
- Secure networking practices
- Compliant resource configurations

Run security validation:

```bash
npm run synth  # CDK Nag runs automatically during synthesis
```

## Development and Customization

### Project Structure

```
cdk-typescript/
├── app.ts                           # CDK application entry point
├── lib/
│   └── sustainability-dashboard-stack.ts  # Main stack implementation
├── package.json                     # Node.js dependencies
├── tsconfig.json                    # TypeScript configuration
├── cdk.json                         # CDK configuration
└── README.md                        # This documentation
```

### Adding Custom Functionality

To extend the solution with additional features:

1. **Modify the Lambda function** code in `sustainability-dashboard-stack.ts`
2. **Add new AWS resources** using CDK constructs
3. **Update IAM permissions** as needed for new resources
4. **Add CloudWatch alarms** for new monitoring requirements
5. **Update CDK Nag suppressions** if introducing acceptable security exceptions

### Testing Changes

```bash
# Compile TypeScript and validate syntax
npm run build

# Generate CloudFormation template and validate
npm run synth

# Compare changes with deployed infrastructure
npm run diff

# Deploy updates to existing stack
npm run deploy
```

## Cleanup

To remove all resources and avoid ongoing costs:

```bash
npm run destroy
# or
cdk destroy
```

**Important**: The S3 data lake bucket has `RetainPolicy.RETAIN` set to protect against accidental data loss. If you need to delete the bucket completely, you must:

1. Empty the bucket contents manually
2. Remove the retention policy in the CDK code
3. Redeploy and then destroy the stack

## Support and Documentation

### Additional Resources

- [AWS CDK TypeScript Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [AWS Customer Carbon Footprint Tool](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/tracking-carbon-emissions.html)
- [Amazon QuickSight User Guide](https://docs.aws.amazon.com/quicksight/)
- [AWS Cost Explorer API Documentation](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/)
- [AWS Well-Architected Sustainability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/sustainability-pillar/)

### Getting Help

For issues specific to this implementation:
1. Check CloudWatch logs for detailed error information
2. Review CDK synthesis output for configuration issues
3. Validate AWS permissions and service quotas
4. Consult AWS documentation for service-specific guidance

For AWS CDK and service issues:
- AWS Support (if you have a support plan)
- AWS Developer Forums
- AWS CDK GitHub repository
- Stack Overflow with appropriate tags

---

This CDK TypeScript implementation provides a production-ready foundation for intelligent sustainability analytics with AWS services. The modular design enables easy customization and extension while maintaining security best practices and cost optimization.