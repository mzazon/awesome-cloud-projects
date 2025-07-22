# Infrastructure as Code for Automated Carbon Footprint Optimization

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Carbon Footprint Optimization".

## Solution Overview

This infrastructure automatically analyzes carbon footprint data from AWS Customer Carbon Footprint Tool alongside Cost Explorer insights to identify optimization opportunities that reduce both environmental impact and operational costs. The solution uses EventBridge scheduling, Lambda functions, and DynamoDB storage to provide continuous monitoring and actionable sustainability recommendations.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

- **Lambda Function**: Core analysis engine for carbon footprint optimization
- **DynamoDB Table**: Storage for carbon metrics and optimization data
- **EventBridge Schedules**: Automated triggers for monthly and weekly analysis
- **SNS Topic**: Notifications for optimization opportunities
- **S3 Bucket**: Storage for Cost and Usage Reports and templates
- **IAM Roles**: Secure access permissions for automation
- **Cost and Usage Reports**: Enhanced data for detailed carbon analysis

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with billing and cost management permissions
- IAM permissions for Lambda, EventBridge, Cost Explorer, S3, DynamoDB, and SNS
- At least one month of AWS usage history for Customer Carbon Footprint Tool
- Basic understanding of carbon accounting principles and AWS sustainability practices
- Estimated cost: $15-25/month for Lambda executions, storage, and data transfer

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name carbon-footprint-optimizer \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
export NOTIFICATION_EMAIL=your-email@example.com
cdk deploy --require-approval never
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
export NOTIFICATION_EMAIL=your-email@example.com
cdk deploy --require-approval never
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan -var="notification_email=your-email@example.com"
terraform apply -auto-approve
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
export NOTIFICATION_EMAIL=your-email@example.com
./scripts/deploy.sh
```

## Configuration Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| NotificationEmail | Email address for optimization notifications | - | Yes |
| ProjectName | Unique project identifier | carbon-optimizer-{random} | No |
| AnalysisFrequency | How often to run analysis (days) | 30 | No |
| CarbonThreshold | Minimum carbon impact for high-priority alerts | 10.0 | No |
| CostThreshold | Minimum cost for optimization recommendations | 100.0 | No |

## Deployment Validation

After deployment, verify the solution is working:

1. **Check Lambda Function**:
   ```bash
   aws lambda invoke \
       --function-name carbon-optimizer-analyzer \
       --payload '{}' \
       response.json && cat response.json
   ```

2. **Verify DynamoDB Table**:
   ```bash
   aws dynamodb describe-table \
       --table-name carbon-optimizer-metrics
   ```

3. **Test SNS Notifications**:
   ```bash
   aws sns list-subscriptions-by-topic \
       --topic-arn arn:aws:sns:us-east-1:ACCOUNT:carbon-optimizer-notifications
   ```

4. **Check EventBridge Schedules**:
   ```bash
   aws scheduler list-schedules \
       --name-prefix carbon-optimizer
   ```

## Expected Outcomes

- Automated monthly carbon footprint analysis reports
- Email notifications for high-impact optimization opportunities
- DynamoDB storage of historical carbon and cost correlation data
- Actionable recommendations for sustainable resource optimization
- Integration with AWS Cost and Usage Reports for enhanced accuracy

## Monitoring and Maintenance

### CloudWatch Metrics

Monitor these key metrics:
- Lambda function execution duration and errors
- DynamoDB read/write capacity utilization
- SNS notification delivery success rates
- EventBridge schedule execution status

### Cost Optimization

The solution includes automatic cost monitoring and will:
- Track its own operational costs
- Recommend optimizations when cost threshold is exceeded
- Provide regular cost impact reports via email notifications

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name carbon-footprint-optimizer
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Customization

### Adding Custom Carbon Factors

Modify the Lambda function code to include industry-specific carbon intensity factors:

```python
# In the Lambda function
carbon_factors = {
    'Amazon Elastic Compute Cloud': 0.5,  # Customize based on your workload
    'Amazon Simple Storage Service': 0.1,
    'Your Custom Service': 0.3  # Add your specific factors
}
```

### Extending Analysis Frequency

Update EventBridge schedules for different monitoring intervals:
- Daily analysis for production environments
- Weekly analysis for development environments
- Monthly analysis for cost optimization focus

### Custom Notification Channels

Extend SNS integration to support:
- Slack webhook notifications
- Microsoft Teams integration
- Custom API endpoints for enterprise systems

## Troubleshooting

### Common Issues

1. **Lambda Function Timeouts**:
   - Increase timeout in function configuration
   - Optimize Cost Explorer API calls with pagination

2. **DynamoDB Throttling**:
   - Monitor read/write capacity metrics
   - Consider on-demand billing mode for variable workloads

3. **Missing Carbon Footprint Data**:
   - Verify AWS account has sufficient usage history
   - Check Customer Carbon Footprint Tool availability in your region

4. **SNS Delivery Failures**:
   - Confirm email subscription is confirmed
   - Check SNS topic policies and permissions

### Debug Mode

Enable debug logging by setting environment variable:
```bash
export DEBUG_MODE=true
```

## Security Considerations

- All IAM roles follow least privilege principles
- S3 bucket encryption enabled by default
- DynamoDB encryption at rest enabled
- SNS topics use server-side encryption
- Cost and Usage Reports stored securely with appropriate access controls

## Support and Documentation

- [AWS Customer Carbon Footprint Tool](https://aws.amazon.com/aws-cost-management/aws-customer-carbon-footprint-tool/)
- [AWS Cost Explorer API Reference](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/ce-api.html)
- [AWS Well-Architected Sustainability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/sustainability-pillar/)
- [AWS Sustainability Scanner](https://github.com/awslabs/sustainability-scanner)

For issues with this infrastructure code, refer to the original recipe documentation or contact your AWS solutions architect.

## Contributing

To extend this solution:

1. Fork the infrastructure code
2. Add your enhancements following AWS best practices
3. Test thoroughly in a non-production environment
4. Submit pull requests with detailed documentation

## License

This infrastructure code is provided under the MIT License. See the original recipe for full licensing details.