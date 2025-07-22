# Terraform Infrastructure for Real-Time WebSocket APIs

This Terraform configuration deploys a complete WebSocket API infrastructure on AWS, including API Gateway WebSocket API, Lambda functions for connection handling, DynamoDB tables for state management, and comprehensive monitoring and security features.

## Architecture Overview

The infrastructure includes:

- **API Gateway WebSocket API**: Manages WebSocket connections and route handling
- **Lambda Functions**: Handle connection lifecycle and message processing
- **DynamoDB Tables**: Store connection state, room information, and message history
- **IAM Roles and Policies**: Secure access control for all components
- **CloudWatch Logs**: Centralized logging for monitoring and debugging
- **KMS Encryption**: Optional encryption for data at rest

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for resource creation
- Understanding of WebSocket protocols and real-time applications

## Quick Start

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```

2. **Review and customize variables** (optional):
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your desired values
   ```

3. **Plan the deployment**:
   ```bash
   terraform plan
   ```

4. **Apply the configuration**:
   ```bash
   terraform apply
   ```

5. **Test the WebSocket API**:
   ```bash
   # Get the WebSocket endpoint from outputs
   terraform output websocket_api_endpoint
   
   # Test connection using wscat (install with: npm install -g wscat)
   wscat -c "$(terraform output -raw test_connection_url)"
   ```

## Configuration Variables

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment name (dev, staging, prod) | `dev` | No |
| `project_name` | Name of the project | `websocket-api` | No |

### WebSocket API Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `api_name` | Name for the WebSocket API | `websocket-api` | No |
| `stage_name` | Stage name for API deployment | `staging` | No |
| `route_selection_expression` | Route selection expression | `$request.body.type` | No |
| `custom_routes` | Custom routes to create | `["chat", "join_room", ...]` | No |

### DynamoDB Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `dynamodb_billing_mode` | DynamoDB billing mode | `PROVISIONED` | No |
| `dynamodb_read_capacity` | Read capacity units | `5` | No |
| `dynamodb_write_capacity` | Write capacity units | `5` | No |
| `enable_dynamodb_point_in_time_recovery` | Enable point-in-time recovery | `true` | No |

### Lambda Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `lambda_runtime` | Lambda runtime version | `python3.11` | No |
| `lambda_memory_size` | Lambda memory size in MB | `256` | No |
| `lambda_timeout` | Lambda timeout in seconds | `30` | No |
| `lambda_message_memory_size` | Message handler memory size | `512` | No |
| `lambda_message_timeout` | Message handler timeout | `60` | No |

### Security Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_encryption` | Enable KMS encryption | `true` | No |
| `enable_xray_tracing` | Enable X-Ray tracing | `true` | No |
| `log_retention_days` | Log retention period | `14` | No |

### Monitoring Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_detailed_metrics` | Enable detailed metrics | `true` | No |
| `enable_data_trace` | Enable data trace | `true` | No |
| `logging_level` | API Gateway logging level | `INFO` | No |
| `throttling_burst_limit` | Throttling burst limit | `500` | No |
| `throttling_rate_limit` | Throttling rate limit | `1000` | No |

## Example terraform.tfvars

```hcl
# Core configuration
aws_region   = "us-west-2"
environment  = "production"
project_name = "chat-app"

# WebSocket API configuration
api_name    = "chat-websocket-api"
stage_name  = "prod"

# DynamoDB configuration
dynamodb_billing_mode = "PAY_PER_REQUEST"
enable_dynamodb_point_in_time_recovery = true

# Lambda configuration
lambda_runtime = "python3.11"
lambda_memory_size = 512
lambda_message_memory_size = 1024

# Security configuration
enable_encryption = true
enable_xray_tracing = true
log_retention_days = 30

# Monitoring configuration
enable_detailed_metrics = true
logging_level = "INFO"
throttling_burst_limit = 1000
throttling_rate_limit = 2000

# Custom routes
custom_routes = [
  "chat",
  "join_room",
  "leave_room",
  "private_message",
  "room_list",
  "typing_indicator"
]

# Additional tags
additional_tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Application = "chat-service"
}
```

## Testing the WebSocket API

### Using wscat

```bash
# Install wscat
npm install -g wscat

# Connect to WebSocket API
wscat -c "$(terraform output -raw websocket_api_endpoint)?userId=testuser&username=TestUser&roomId=general&token=valid_test_token"

# Send messages
{"type": "chat", "message": "Hello World!"}
{"type": "join_room", "roomId": "developers"}
{"type": "private_message", "targetUserId": "user2", "message": "Private hello"}
{"type": "room_list"}
```

### Using Python WebSocket Client

```python
import asyncio
import websockets
import json

async def test_websocket():
    uri = "ws://your-websocket-endpoint"
    async with websockets.connect(uri) as websocket:
        # Send a chat message
        await websocket.send(json.dumps({
            "type": "chat",
            "message": "Hello from Python!"
        }))
        
        # Listen for messages
        async for message in websocket:
            data = json.loads(message)
            print(f"Received: {data}")

# Run the test
asyncio.run(test_websocket())
```

## Monitoring and Debugging

### CloudWatch Logs

Monitor Lambda function logs:

```bash
# View connect handler logs
aws logs tail /aws/lambda/$(terraform output -raw connect_function_name) --follow

# View message handler logs
aws logs tail /aws/lambda/$(terraform output -raw message_function_name) --follow

# View disconnect handler logs
aws logs tail /aws/lambda/$(terraform output -raw disconnect_function_name) --follow
```

### API Gateway Metrics

Monitor API Gateway metrics in CloudWatch:

- `ConnectCount`: Number of connections
- `MessageCount`: Number of messages
- `ExecutionError`: Number of execution errors
- `ClientError`: Number of client errors
- `IntegrationLatency`: Integration latency

### DynamoDB Monitoring

Monitor table metrics:

```bash
# Check table status
aws dynamodb describe-table --table-name $(terraform output -raw connections_table_name)

# View table items
aws dynamodb scan --table-name $(terraform output -raw connections_table_name) --max-items 10
```

## Security Best Practices

### Authentication

The current implementation includes basic token validation. For production use:

1. Integrate with Amazon Cognito User Pools
2. Implement JWT token validation
3. Add role-based access control
4. Enable API Gateway authorizers

### Network Security

1. Use VPC endpoints for DynamoDB access
2. Implement API Gateway resource policies
3. Enable AWS WAF for DDoS protection
4. Use security groups and NACLs appropriately

### Data Protection

1. Enable encryption at rest with KMS
2. Use TLS 1.2+ for data in transit
3. Implement field-level encryption for sensitive data
4. Regular security audits and penetration testing

## Scaling Considerations

### Auto Scaling

- Lambda functions automatically scale based on concurrent executions
- DynamoDB can use on-demand billing or auto-scaling
- API Gateway automatically handles connection scaling

### Performance Optimization

1. Use DynamoDB Global Secondary Indexes efficiently
2. Implement connection pooling for database operations
3. Use Lambda provisioned concurrency for consistent performance
4. Monitor and optimize Lambda memory allocation

### Cost Optimization

1. Use DynamoDB on-demand billing for variable workloads
2. Implement TTL for automatic data cleanup
3. Monitor and optimize Lambda execution time
4. Use CloudWatch cost monitoring and alerts

## Troubleshooting

### Common Issues

1. **Connection Timeout**: Check security groups and network ACLs
2. **Lambda Timeout**: Increase timeout values or optimize code
3. **DynamoDB Throttling**: Increase provisioned capacity or use on-demand
4. **Permission Errors**: Verify IAM roles and policies

### Debug Steps

```bash
# Check API Gateway logs
aws logs filter-log-events --log-group-name /aws/apigateway/$(terraform output -raw websocket_api_id)

# Check Lambda function configuration
aws lambda get-function --function-name $(terraform output -raw message_function_name)

# Check DynamoDB table metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ConsumedReadCapacityUnits \
    --dimensions Name=TableName,Value=$(terraform output -raw connections_table_name) \
    --start-time 2023-01-01T00:00:00Z \
    --end-time 2023-01-01T23:59:59Z \
    --period 3600 \
    --statistics Average
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources including data stored in DynamoDB tables. Make sure to backup any important data before running this command.

## Support

For issues with this infrastructure:

1. Check the CloudWatch logs for error messages
2. Review the Terraform state for resource configuration
3. Consult the AWS documentation for specific services
4. Refer to the original recipe documentation for implementation details

## License

This infrastructure code is provided as-is under the terms specified in the recipe documentation.