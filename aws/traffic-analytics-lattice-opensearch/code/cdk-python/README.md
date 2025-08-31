# Traffic Analytics with VPC Lattice and OpenSearch - CDK Python

This directory contains the AWS CDK Python implementation for the Traffic Analytics with VPC Lattice and OpenSearch recipe. This solution creates a comprehensive traffic analytics pipeline that captures VPC Lattice access logs, transforms them through Lambda, and delivers them to OpenSearch Service for real-time analytics and visualization.

## Architecture Overview

The CDK application deploys the following AWS services:

- **VPC Lattice Service Network**: Provides application-level networking with detailed access logging
- **Kinesis Data Firehose**: Streams access logs in real-time to OpenSearch Service
- **Lambda Function**: Transforms and enriches log data for optimal analytics performance
- **OpenSearch Service**: Provides analytics platform with built-in visualization capabilities
- **S3 Bucket**: Stores backup data and handles error records with lifecycle management
- **IAM Roles**: Implements least privilege access controls across all services

## Prerequisites

- AWS CLI v2 installed and configured
- Python 3.8 or higher
- Node.js 18.x or higher (for CDK CLI)
- AWS CDK CLI v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for creating the listed resources

## Installation and Setup

1. **Clone or navigate to this directory**:
   ```bash
   cd aws/traffic-analytics-lattice-opensearch/code/cdk-python/
   ```

2. **Create and activate a Python virtual environment** (recommended):
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install Python dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK in your AWS account** (if not done previously):
   ```bash
   cdk bootstrap
   ```

## Deployment

1. **Synthesize the CloudFormation template** (recommended for validation):
   ```bash
   cdk synth
   ```

2. **Review the generated CloudFormation template**:
   The synthesized template will be in the `cdk.out/` directory. Review it to understand what resources will be created.

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

   The deployment will take approximately 10-15 minutes due to OpenSearch domain creation.

4. **Confirm deployment**:
   Type `y` when prompted to confirm the deployment of security-related changes.

## Post-Deployment Configuration

After successful deployment, you can:

1. **Access OpenSearch Dashboards**:
   - Use the `OpenSearchDashboardsURL` output from the stack
   - Configure index patterns for `vpc-lattice-traffic*`
   - Create visualizations and dashboards for traffic analytics

2. **Generate test traffic**:
   - Use the deployed demo VPC Lattice service to generate test traffic
   - Monitor logs flowing into OpenSearch through the Firehose delivery stream

3. **Monitor the pipeline**:
   - Check Lambda function logs in CloudWatch for transformation status
   - Monitor Firehose delivery metrics in CloudWatch
   - Verify data ingestion in OpenSearch Service

## CDK Commands

- `cdk ls` - List all stacks in the application
- `cdk synth` - Synthesize CloudFormation template
- `cdk deploy` - Deploy the stack to AWS
- `cdk diff` - Compare deployed stack with current state
- `cdk destroy` - Remove all resources (be careful!)

## Customization

### Environment Variables

You can customize the deployment by setting these environment variables:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012  # Your AWS account ID
export CDK_DEFAULT_REGION=us-east-1      # Your preferred region
```

### Code Modifications

To customize the infrastructure:

1. **Modify OpenSearch instance type**:
   Edit the `data_node_instance_type` in the `_create_opensearch_domain` method.

2. **Adjust Firehose buffering**:
   Modify the `buffering_hints` configuration in the `_create_firehose_delivery_stream` method.

3. **Update Lambda transformation logic**:
   Enhance the Lambda function code in the `_create_transform_function` method.

4. **Add additional services**:
   Extend the VPC Lattice configuration in the `_create_demo_service` method.

## Security Considerations

This CDK application implements several security best practices:

- **Encryption**: Enables encryption at rest for OpenSearch and S3
- **HTTPS**: Enforces HTTPS for all OpenSearch communications
- **IAM**: Uses least privilege access policies for all service roles
- **Network Security**: Configures appropriate security groups and access controls
- **Data Protection**: Implements backup strategies and error handling

## Cost Optimization

To minimize costs during testing:

- **OpenSearch Instance**: Uses `t3.small.search` instance type (can be downgraded to `t3.micro.search` for minimal testing)
- **Single AZ**: Deploys OpenSearch in a single availability zone
- **Lifecycle Policies**: Automatically archives old backup data to cheaper storage tiers
- **Auto-Delete**: Configures S3 bucket for automatic cleanup when stack is destroyed

## Troubleshooting

### Common Issues

1. **OpenSearch domain creation timeout**:
   - OpenSearch domains take 10-15 minutes to create
   - Ensure your region supports the selected instance type

2. **Lambda permission errors**:
   - Verify the Lambda execution role has proper permissions
   - Check CloudWatch logs for detailed error messages

3. **Firehose delivery failures**:
   - Check the S3 error prefix for failed records
   - Verify OpenSearch domain is accessible from Firehose

4. **VPC Lattice access denied**:
   - Ensure your IAM user/role has VPC Lattice permissions
   - Check that the service network is properly configured

### Debugging

1. **Check CloudFormation events**:
   ```bash
   aws cloudformation describe-stack-events --stack-name TrafficAnalyticsStack
   ```

2. **View Lambda logs**:
   ```bash
   aws logs tail /aws/lambda/TrafficAnalyticsStack-TrafficTransformFunction --follow
   ```

3. **Monitor Firehose metrics**:
   ```bash
   aws firehose describe-delivery-stream --delivery-stream-name vpc-lattice-traffic-stream
   ```

## Cleanup

To avoid ongoing charges, destroy the stack when testing is complete:

```bash
cdk destroy
```

**Warning**: This will permanently delete all resources including the OpenSearch domain and any indexed data.

## Stack Outputs

After deployment, the stack provides these outputs:

- `OpenSearchDomainEndpoint`: Direct endpoint for OpenSearch API access
- `OpenSearchDashboardsURL`: URL for accessing OpenSearch Dashboards
- `FirehoseDeliveryStreamName`: Name of the Kinesis Data Firehose delivery stream
- `ServiceNetworkId`: VPC Lattice service network identifier
- `ServiceNetworkArn`: VPC Lattice service network ARN
- `DemoServiceId`: Demo service identifier for testing
- `DemoServiceArn`: Demo service ARN for testing

## Learn More

- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [VPC Lattice Documentation](https://docs.aws.amazon.com/vpc-lattice/)
- [OpenSearch Service Documentation](https://docs.aws.amazon.com/opensearch-service/)
- [Kinesis Data Firehose Documentation](https://docs.aws.amazon.com/firehose/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)

## Support

For issues with this CDK implementation:
1. Check the troubleshooting section above
2. Review AWS CDK and service-specific documentation
3. Check AWS CloudFormation events for deployment issues
4. Refer to the original recipe documentation for architecture details