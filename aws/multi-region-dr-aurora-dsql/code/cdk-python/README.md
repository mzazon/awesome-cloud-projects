# Aurora DSQL Multi-Region Disaster Recovery - CDK Python Implementation

This directory contains a production-ready AWS CDK Python application that implements a comprehensive multi-region disaster recovery solution using Aurora DSQL with active-active architecture, EventBridge-orchestrated monitoring, and Lambda-based health checks.

## Architecture Overview

The CDK application deploys:

- **Aurora DSQL Clusters**: Active-active multi-region clusters with witness region for zero-downtime failover
- **EventBridge Rules**: Automated scheduling for health monitoring every 2 minutes
- **Lambda Functions**: Intelligent health monitoring with exponential backoff and custom metrics
- **SNS Topics**: Multi-region alerting with email subscriptions
- **CloudWatch**: Comprehensive monitoring with alarms, dashboards, and custom metrics
- **IAM Roles**: Least-privilege security for all components

## Prerequisites

### Software Requirements
- Python 3.8 or higher
- AWS CLI v2 installed and configured
- AWS CDK v2.130.0 or higher
- Node.js 18.x or higher (for CDK CLI)

### AWS Requirements
- AWS account with appropriate permissions for Aurora DSQL, EventBridge, Lambda, and CloudWatch
- Administrator permissions or equivalent IAM roles
- Aurora DSQL service availability in target regions

### Estimated Costs
- **Aurora DSQL**: $150-300/month for multi-region clusters
- **Lambda**: $5-15/month for monitoring functions
- **CloudWatch**: $10-25/month for metrics and alarms
- **SNS**: $1-5/month for notifications
- **Total**: $175-350/month (varies by usage and data transfer)

## Quick Start

### 1. Environment Setup

```bash
# Clone the repository and navigate to the CDK Python directory
cd aws/building-multi-region-disaster-recovery-with-aurora-dsql-and-eventbridge/code/cdk-python/

# Create and activate Python virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Install CDK CLI if not already installed
npm install -g aws-cdk@latest
```

### 2. Configure Environment Variables

```bash
# Set required environment variables
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION="us-west-2"
export WITNESS_REGION="us-west-1"
export ENVIRONMENT="production"
export MONITORING_EMAIL="your-ops-team@company.com"
```

### 3. Deploy the Infrastructure

```bash
# Bootstrap CDK in both regions (first time only)
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$PRIMARY_REGION
cdk bootstrap aws://$CDK_DEFAULT_ACCOUNT/$SECONDARY_REGION

# Synthesize the CloudFormation templates
cdk synth

# Deploy both stacks (primary deploys first due to dependencies)
cdk deploy --all --require-approval never

# Or deploy individually
cdk deploy AuroraDsqlDR-Primary-production
cdk deploy AuroraDsqlDR-Secondary-production
```

### 4. Verify Deployment

```bash
# Check stack status
aws cloudformation describe-stacks \
    --region $PRIMARY_REGION \
    --stack-name AuroraDsqlDR-Primary-production

aws cloudformation describe-stacks \
    --region $SECONDARY_REGION \
    --stack-name AuroraDsqlDR-Secondary-production

# Test Lambda function
aws lambda invoke \
    --region $PRIMARY_REGION \
    --function-name aurora-dsql-monitor-* \
    --payload '{}' \
    response.json && cat response.json
```

## Configuration Options

### CDK Context Parameters

You can customize the deployment by modifying `cdk.json` or passing context parameters:

```bash
# Deploy with custom configuration
cdk deploy --context environment=staging \
           --context primaryRegion=us-west-1 \
           --context secondaryRegion=us-east-2 \
           --context monitoringEmail=staging-ops@company.com
```

### Available Context Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `environment` | `production` | Environment name for resource tagging |
| `primaryRegion` | `us-east-1` | Primary AWS region for Aurora DSQL cluster |
| `secondaryRegion` | `us-west-2` | Secondary AWS region for Aurora DSQL cluster |
| `witnessRegion` | `us-west-1` | Witness region for cluster tie-breaking |
| `monitoringEmail` | `ops-team@company.com` | Email address for SNS alert subscriptions |
| `clusterPrefix` | `dr-dsql` | Prefix for Aurora DSQL cluster naming |
| `monitoringFrequencyMinutes` | `2` | Frequency of health checks in minutes |

### Environment Variables

The application supports environment variable configuration:

```bash
export ENVIRONMENT="production"
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION="us-west-2"
export WITNESS_REGION="us-west-1"
export MONITORING_EMAIL="ops-team@company.com"
```

## Stack Architecture

### Primary Region Stack (`AuroraDsqlDisasterRecoveryStack`)

- Aurora DSQL primary cluster with witness region configuration
- Lambda function for health monitoring with custom metrics
- EventBridge rule for automated monitoring (2-minute intervals)
- SNS topic with email subscription for alerting
- CloudWatch dashboard with comprehensive metrics visualization
- CloudWatch alarms for Lambda errors, cluster health, and EventBridge failures

### Secondary Region Stack (`AuroraDsqlSecondaryRegionStack`)

- Aurora DSQL secondary cluster with peering to primary cluster
- Lambda function for secondary region health monitoring
- EventBridge rule for automated monitoring
- SNS topic for secondary region alerting
- CloudWatch alarms for secondary region monitoring

## Monitoring and Alerting

### CloudWatch Dashboard

The deployment creates a comprehensive dashboard with:

- Lambda function invocation and error rates
- Lambda function duration and performance metrics
- EventBridge rule execution statistics and success rates
- Aurora DSQL cluster health status across regions
- Custom disaster recovery metrics

Access the dashboard at:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=Aurora-DSQL-DR-Dashboard-*
```

### CloudWatch Alarms

Automated alarms monitor:

- **Lambda Function Errors**: Triggers on Lambda execution failures
- **Aurora DSQL Cluster Health**: Monitors cluster availability and status
- **EventBridge Rule Failures**: Detects monitoring system issues
- **Custom Health Metrics**: Tracks application-specific health indicators

### SNS Notifications

Email alerts are sent for:

- Aurora DSQL cluster health degradation
- Lambda function execution errors
- EventBridge rule failures
- Custom health check failures

## Security Considerations

### IAM Roles and Permissions

The CDK application implements least-privilege access:

- **Lambda Execution Role**: Minimal permissions for Aurora DSQL access, SNS publishing, and CloudWatch metrics
- **Resource-Specific Policies**: Each service has targeted permissions
- **No Admin Privileges**: All roles follow principle of least privilege

### Encryption and Security

- **SNS Topics**: Encrypted using AWS managed keys
- **CloudWatch Logs**: Encrypted at rest with configurable retention
- **Aurora DSQL**: Built-in encryption at rest and in transit
- **Lambda Functions**: Environment variables encrypted

### Network Security

- **VPC Integration**: Optional VPC deployment for enhanced isolation
- **Security Groups**: Minimal required network access
- **Private Endpoints**: Support for VPC endpoints where applicable

## Operational Procedures

### Health Check Validation

```bash
# Manual Lambda function testing
aws lambda invoke \
    --region us-east-1 \
    --function-name aurora-dsql-monitor-* \
    --payload '{}' \
    response.json

# Check custom CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --region us-east-1 \
    --namespace "Aurora/DSQL/DisasterRecovery" \
    --metric-name "ClusterHealth" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

### Disaster Recovery Testing

```bash
# Simulate regional failure for testing
aws dsql update-cluster \
    --region us-east-1 \
    --identifier dr-dsql-primary-* \
    --multi-region-properties "{\"witnessRegion\":\"us-west-1\",\"clusters\":[]}"

# Monitor failover behavior and alert generation
# Re-establish connection after testing
```

### Scaling and Performance Tuning

- **Lambda Concurrency**: Adjust reserved concurrency based on monitoring frequency
- **CloudWatch Retention**: Modify log retention periods for cost optimization
- **Monitoring Frequency**: Tune EventBridge schedule based on RTO requirements
- **Alert Thresholds**: Adjust alarm sensitivity based on operational experience

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Issues**
   ```bash
   cdk bootstrap --force aws://$CDK_DEFAULT_ACCOUNT/$PRIMARY_REGION
   ```

2. **Aurora DSQL Regional Availability**
   - Verify Aurora DSQL is available in target regions
   - Check service quotas and limits

3. **IAM Permission Errors**
   - Ensure deploying user has administrator access
   - Verify Aurora DSQL service permissions

4. **Lambda Function Errors**
   - Check CloudWatch logs for detailed error messages
   - Verify environment variables and IAM permissions

### Debugging Commands

```bash
# Check CDK diff
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events \
    --region us-east-1 \
    --stack-name AuroraDsqlDR-Primary-production

# Lambda function logs
aws logs describe-log-groups \
    --region us-east-1 \
    --log-group-name-prefix "/aws/lambda/aurora-dsql-monitor"
```

## Cleanup

### Complete Infrastructure Removal

```bash
# Destroy all resources (in reverse dependency order)
cdk destroy AuroraDsqlDR-Secondary-production --force
cdk destroy AuroraDsqlDR-Primary-production --force

# Clean up CDK staging bucket (optional)
aws s3 rm s3://cdktoolkit-stagingbucket-* --recursive
aws s3 rb s3://cdktoolkit-stagingbucket-*
```

### Partial Cleanup (Keep Aurora DSQL clusters)

```bash
# Remove only monitoring components
cdk destroy --exclusively AuroraDsqlDR-Secondary-production/SecondaryMonitoringLambda
cdk destroy --exclusively AuroraDsqlDR-Primary-production/MonitoringLambda
```

## Development and Testing

### Local Development Setup

```bash
# Install development dependencies
pip install -r requirements.txt[dev]

# Run type checking
mypy app.py

# Run code formatting
black app.py

# Run linting
flake8 app.py

# Run tests
pytest tests/ -v --cov=.
```

### Testing Strategy

- **Unit Tests**: Test individual stack components and configurations
- **Integration Tests**: Validate cross-region functionality and dependencies
- **End-to-End Tests**: Complete disaster recovery scenario testing
- **Performance Tests**: Monitor Lambda cold start times and execution duration

## Support and Maintenance

### Updates and Versioning

- **CDK Updates**: Regularly update CDK dependencies for security patches
- **Python Updates**: Keep Python runtime current for Lambda functions
- **AWS Service Updates**: Monitor Aurora DSQL service announcements

### Monitoring Best Practices

1. **Regular Health Checks**: Validate monitoring system functionality monthly
2. **Alert Testing**: Test SNS notification delivery quarterly
3. **Disaster Recovery Drills**: Conduct full DR testing semi-annually
4. **Performance Review**: Analyze CloudWatch metrics monthly for optimization opportunities

### Documentation

- [AWS Aurora DSQL Documentation](https://docs.aws.amazon.com/aurora-dsql/)
- [AWS CDK Python Documentation](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [EventBridge Best Practices](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-best-practices.html)
- [Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)

## Contributing

When contributing to this CDK application:

1. Follow Python PEP 8 style guidelines
2. Add type hints for all function parameters and return values
3. Include comprehensive docstrings for all classes and methods
4. Update tests for any new functionality
5. Ensure all security best practices are maintained

## License

This CDK application is provided under the MIT License. See the repository's main LICENSE file for details.