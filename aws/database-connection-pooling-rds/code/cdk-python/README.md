# Database Connection Pooling with RDS Proxy - CDK Python

This AWS CDK Python application implements database connection pooling using Amazon RDS Proxy, demonstrating best practices for serverless database connectivity and connection management.

## Architecture Overview

This solution creates:

- **VPC**: Multi-AZ VPC with public and private subnets
- **RDS MySQL Instance**: Encrypted database with automated backups
- **RDS Proxy**: Connection pooling proxy for efficient connection management
- **Secrets Manager**: Secure credential storage with automatic rotation capability
- **Lambda Function**: Test function demonstrating proxy connectivity
- **Security Groups**: Layered security with least privilege access
- **IAM Roles**: Properly scoped permissions for each service

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate permissions
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Docker (for bundling Lambda functions with dependencies)

## Installation

1. **Clone and navigate to the project**:
   ```bash
   cd aws/database-connection-pooling-rds-proxy/code/cdk-python/
   ```

2. **Create and activate a virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap your AWS environment** (if not done previously):
   ```bash
   cdk bootstrap
   ```

## Deployment

### Quick Deploy

```bash
# Deploy the entire stack
cdk deploy

# Deploy with automatic approval (skip confirmation prompts)
cdk deploy --require-approval never

# Deploy to a specific AWS profile
cdk deploy --profile my-aws-profile
```

### Step-by-Step Deployment

1. **Synthesize CloudFormation template**:
   ```bash
   cdk synth
   ```

2. **Review the generated template**:
   ```bash
   ls cdk.out/
   cat cdk.out/DatabaseConnectionPoolingStack.template.json
   ```

3. **Deploy with confirmation**:
   ```bash
   cdk deploy
   ```

4. **View stack outputs**:
   ```bash
   # Outputs are displayed after successful deployment
   # Or view them later with:
   aws cloudformation describe-stacks \
     --stack-name DatabaseConnectionPoolingStack \
     --query 'Stacks[0].Outputs'
   ```

## Configuration

### Environment Variables

You can customize the deployment using CDK context:

```bash
# Deploy to specific account/region
cdk deploy -c account=123456789012 -c region=us-east-1

# Deploy with custom database name
cdk deploy -c dbName=myapp-db

# Deploy with custom instance type
cdk deploy -c instanceType=db.t3.small
```

### Customization Options

Modify `app.py` to customize:

- **Database Configuration**: Instance type, storage, engine version
- **Network Settings**: VPC CIDR, subnet configuration, AZ count
- **Security Settings**: Security group rules, encryption settings
- **Connection Pooling**: Max connections, idle timeout, TLS requirements
- **Lambda Settings**: Runtime, timeout, memory allocation

## Testing

### Test RDS Proxy Connectivity

After deployment, test the connection using the provided Lambda function:

```bash
# Get the Lambda function name from stack outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name DatabaseConnectionPoolingStack \
  --query 'Stacks[0].Outputs[?OutputKey==`TestLambdaFunction`].OutputValue' \
  --output text)

# Test the connection
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{}' \
  /tmp/test-response.json

# View the response
cat /tmp/test-response.json | jq '.'
```

Expected successful response:
```json
{
  "statusCode": 200,
  "body": "{\"message\": \"Successfully connected through RDS Proxy\", \"connection_test\": {\"connection_test\": 1, \"connection_id\": 12345, \"timestamp\": \"2024-01-01 12:00:00\"}, \"connection_info\": {\"user_info\": \"admin@%\", \"database_info\": \"testdb\"}, \"proxy_endpoint\": \"rds-proxy-demo-xxxxx.proxy-xxxxxxxxx.us-east-1.rds.amazonaws.com\"}"
}
```

### Test Connection Pooling Behavior

```bash
# Test multiple concurrent connections to verify pooling
for i in {1..5}; do
  echo "Testing connection $i:"
  aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    /tmp/test-$i.json &
done

# Wait for all tests to complete
wait

# View all responses
for i in {1..5}; do
  echo "Response $i:"
  cat /tmp/test-$i.json | jq '.body | fromjson | .connection_test.connection_id'
done
```

### Monitor Connection Metrics

```bash
# View RDS Proxy CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=ProxyName,Value=DatabaseConnectionPoolingStack-DatabaseProxy \
  --statistics Average,Maximum \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300
```

## Security Considerations

### Production Recommendations

1. **Enable TLS**: Set `require_tls=True` in the RDS Proxy configuration
2. **Deletion Protection**: Set `deletion_protection=True` for the RDS instance
3. **Backup Retention**: Increase backup retention period for production
4. **VPC Endpoints**: Add VPC endpoints for Secrets Manager and other services
5. **Parameter Groups**: Create custom parameter groups for database optimization
6. **Monitoring**: Enable Performance Insights and Enhanced Monitoring

### Security Features Implemented

- **Encryption at Rest**: RDS instance uses encryption
- **Secrets Management**: Database credentials stored in Secrets Manager
- **Network Isolation**: Resources deployed in private subnets
- **Least Privilege IAM**: Minimal required permissions for each role
- **Security Groups**: Restrictive inbound/outbound rules

## Troubleshooting

### Common Issues

1. **VPC Endpoint Errors**: Ensure your account has VPC endpoints enabled
2. **Lambda Timeout**: Increase timeout if connection establishment is slow
3. **Security Group Issues**: Verify port 3306 is allowed between security groups
4. **IAM Permissions**: Ensure CDK has sufficient permissions for deployment

### Debug Mode

Enable debug logging for RDS Proxy:

```bash
# The CDK template already enables debug logging
# View logs in CloudWatch Logs group: /aws/rds/proxy/DatabaseProxy
aws logs describe-log-groups --log-group-name-prefix "/aws/rds/proxy"
```

### Useful Commands

```bash
# View stack events
aws cloudformation describe-stack-events \
  --stack-name DatabaseConnectionPoolingStack

# Check RDS instance status
aws rds describe-db-instances \
  --query 'DBInstances[?DBInstanceIdentifier==`databaseconnectionpoolingstack-databaseinstance`]'

# Check proxy status
aws rds describe-db-proxies \
  --query 'DBProxies[?DBProxyName==`DatabaseConnectionPoolingStack-DatabaseProxy`]'
```

## Cleanup

### Remove All Resources

```bash
# Destroy the CDK stack
cdk destroy

# Confirm deletion when prompted
# Type 'y' and press Enter
```

### Verify Cleanup

```bash
# Verify stack deletion
aws cloudformation describe-stacks \
  --stack-name DatabaseConnectionPoolingStack

# Should return: "Stack with id DatabaseConnectionPoolingStack does not exist"
```

### Manual Cleanup (if needed)

If automatic cleanup fails, manually delete resources:

```bash
# Delete RDS Proxy
aws rds delete-db-proxy --db-proxy-name <proxy-name>

# Delete RDS instance (after proxy is deleted)
aws rds delete-db-instance \
  --db-instance-identifier <instance-id> \
  --skip-final-snapshot

# Delete VPC (after all resources are deleted)
aws ec2 delete-vpc --vpc-id <vpc-id>
```

## Cost Estimation

### Resource Costs (US East 1, as of 2024)

- **RDS t3.micro instance**: ~$13/month
- **RDS Proxy**: ~$11/month (0.015/hour)
- **Secrets Manager**: ~$0.40/month
- **Lambda**: Minimal (pay per invocation)
- **VPC**: No additional cost
- **CloudWatch Logs**: Minimal (first 5GB free)

**Total estimated cost**: ~$25-30/month

### Cost Optimization Tips

1. Use Reserved Instances for production RDS instances
2. Enable automatic pause for Aurora Serverless
3. Implement lifecycle policies for CloudWatch Logs
4. Monitor and adjust RDS Proxy connection settings
5. Use Spot instances for development environments

## Best Practices

### Performance Optimization

1. **Connection Pool Sizing**: Tune max_connections_percent based on workload
2. **Idle Timeout**: Adjust based on application connection patterns
3. **Instance Type**: Right-size RDS instance based on connection needs
4. **Monitoring**: Use CloudWatch metrics to optimize settings

### Operational Excellence

1. **Automated Backups**: Enabled with 7-day retention
2. **Multi-AZ**: Consider enabling for production high availability
3. **Parameter Groups**: Create custom parameter groups for optimization
4. **Maintenance Windows**: Schedule during low-traffic periods

### Security Best Practices

1. **Credential Rotation**: Enable automatic rotation for Secrets Manager
2. **Network ACLs**: Implement additional network layer security
3. **VPC Flow Logs**: Enable for network traffic monitoring
4. **Access Logging**: Enable RDS and proxy access logging

## Additional Resources

- [AWS RDS Proxy Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)
- [AWS CDK Python Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)
- [RDS Proxy Best Practices](https://aws.amazon.com/blogs/database/best-practices-for-amazon-rds-proxy/)
- [Connection Pooling Patterns](https://docs.aws.amazon.com/lambda/latest/dg/configuration-database.html)

## Support

For issues with this CDK application:

1. Check AWS CloudFormation events for deployment errors
2. Review CloudWatch Logs for runtime issues
3. Consult AWS documentation for service-specific guidance
4. Use AWS Support for account-specific issues