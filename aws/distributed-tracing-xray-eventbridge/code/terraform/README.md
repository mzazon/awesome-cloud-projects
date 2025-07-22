# Terraform Infrastructure for Distributed Tracing with X-Ray

This Terraform configuration deploys a complete distributed tracing solution using AWS X-Ray and Amazon EventBridge. The infrastructure implements a microservices architecture with comprehensive observability across event-driven workflows.

## Architecture Overview

The infrastructure creates:

- **4 Lambda Functions**: Order, Payment, Inventory, and Notification services
- **Custom EventBridge Bus**: For isolated event routing
- **3 EventBridge Rules**: For event pattern matching and routing
- **API Gateway**: REST API with X-Ray tracing enabled
- **IAM Roles**: With least-privilege permissions for X-Ray and EventBridge
- **CloudWatch Log Groups**: For centralized logging with configurable retention

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** version 1.0 or later installed
3. **AWS Account** with permissions for:
   - Lambda function creation and management
   - EventBridge custom bus and rule creation
   - API Gateway creation and management
   - IAM role and policy management
   - X-Ray service access
   - CloudWatch Logs access

## Quick Start

### 1. Clone and Navigate

```bash
cd aws/distributed-tracing-x-ray-eventbridge/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
# terraform.tfvars
aws_region                = "us-east-1"
environment              = "dev"
project_name            = "distributed-tracing"
lambda_timeout          = 30
lambda_memory_size      = 128
x_ray_tracing_mode      = "Active"
enable_detailed_monitoring = true
api_gateway_stage_name  = "prod"
lambda_log_retention_days = 14

# Additional tags
tags = {
  Owner       = "your-team"
  CostCenter  = "engineering"
  Application = "distributed-tracing-demo"
}
```

### 4. Plan Deployment

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

Review the planned changes and type `yes` to confirm deployment.

### 6. Test the Implementation

After deployment, use the API endpoint from the outputs:

```bash
# Get the API endpoint
API_ENDPOINT=$(terraform output -raw api_gateway_test_url)

# Send a test request
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"productId": "12345", "quantity": 2, "amount": 149.99}' \
  "$API_ENDPOINT"
```

## Configuration Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `aws_region` | AWS region for resources | string | `us-east-1` | No |
| `environment` | Environment name | string | `dev` | No |
| `project_name` | Project name for resource naming | string | `distributed-tracing` | No |
| `lambda_timeout` | Lambda function timeout (seconds) | number | `30` | No |
| `lambda_memory_size` | Lambda function memory (MB) | number | `128` | No |
| `x_ray_tracing_mode` | X-Ray tracing mode | string | `Active` | No |
| `enable_detailed_monitoring` | Enable CloudWatch detailed monitoring | bool | `true` | No |
| `api_gateway_stage_name` | API Gateway stage name | string | `prod` | No |
| `lambda_log_retention_days` | Log retention period | number | `14` | No |
| `tags` | Additional resource tags | map(string) | `{}` | No |

## Outputs

The Terraform configuration provides comprehensive outputs for testing and integration:

- **API Gateway Endpoint**: Base URL for API requests
- **API Gateway Test URL**: Complete URL for order creation
- **EventBridge Bus Details**: Custom bus name and ARN
- **Lambda Function Information**: Names and ARNs of all functions
- **X-Ray Console URLs**: Direct links to traces and service map
- **Testing Commands**: Ready-to-use CLI commands for validation

## File Structure

```
terraform/
├── main.tf                          # Main infrastructure resources
├── variables.tf                     # Input variable definitions
├── outputs.tf                       # Output value definitions
├── versions.tf                      # Terraform and provider requirements
├── README.md                        # This documentation
└── lambda_functions/                # Lambda function source code
    ├── order_service.py            # Order processing service
    ├── payment_service.py          # Payment processing service
    ├── inventory_service.py        # Inventory management service
    └── notification_service.py     # Customer notification service
```

## Resource Details

### Lambda Functions

Each Lambda function is configured with:

- **Runtime**: Python 3.9
- **X-Ray Tracing**: Active mode enabled
- **Environment Variables**: EventBridge bus name
- **IAM Permissions**: Least-privilege access to required services
- **CloudWatch Logs**: Structured logging with configurable retention

#### Order Service
- **Trigger**: API Gateway POST requests
- **Function**: Processes order creation and publishes events
- **X-Ray Features**: Request tracing, business metadata, error tracking

#### Payment Service
- **Trigger**: EventBridge "Order Created" events
- **Function**: Processes payments and publishes completion events
- **X-Ray Features**: Payment processor tracing, amount annotations

#### Inventory Service
- **Trigger**: EventBridge "Order Created" events
- **Function**: Reserves inventory and publishes status events
- **X-Ray Features**: Warehouse selection tracing, stock level tracking

#### Notification Service
- **Trigger**: EventBridge "Payment Processed" and "Inventory Updated" events
- **Function**: Sends customer notifications via multiple channels
- **X-Ray Features**: Notification delivery tracking, channel performance

### EventBridge Configuration

- **Custom Event Bus**: Isolated event routing for the application
- **Event Rules**: Pattern-based routing with precise source/detail-type matching
- **Event Targets**: Lambda function invocations with automatic retry
- **Dead Letter Queues**: (Can be added for production resilience)

### API Gateway Setup

- **Type**: REST API with regional endpoint
- **X-Ray Tracing**: Enabled for request flow visibility
- **CORS**: Configured for cross-origin requests
- **Stage**: Configurable deployment stage with monitoring
- **Throttling**: Default AWS limits (can be customized)

## Monitoring and Observability

### X-Ray Tracing

The infrastructure provides comprehensive distributed tracing:

- **Service Map**: Visual representation of service dependencies
- **Trace Timeline**: End-to-end request flow analysis
- **Performance Metrics**: Response times and error rates
- **Custom Annotations**: Business context for filtering
- **Metadata**: Detailed request and response information

### CloudWatch Integration

- **Lambda Logs**: Structured application logs
- **API Gateway Logs**: Request/response logging (when enabled)
- **Custom Metrics**: Business and technical metrics
- **Alarms**: (Can be added for production monitoring)

### Key Annotations for Filtering

The implementation adds strategic X-Ray annotations:

- `order_id`: Track specific orders across services
- `customer_id`: Customer-centric trace filtering
- `service_name`: Service-specific trace analysis
- `payment_amount`: Financial transaction tracking
- `warehouse`: Inventory location tracking
- `error`: Error condition identification

## Testing and Validation

### Functional Testing

1. **Order Creation**: Test API Gateway to Lambda integration
2. **Event Processing**: Verify EventBridge routing to services
3. **Payment Processing**: Validate payment service logic
4. **Inventory Management**: Test stock reservation logic
5. **Notifications**: Confirm notification delivery

### Observability Testing

1. **Trace Generation**: Verify X-Ray trace creation
2. **Service Map**: Check service dependency visualization
3. **Performance Analysis**: Analyze response times
4. **Error Tracking**: Test error handling and reporting
5. **Business Analytics**: Validate custom annotations

### Load Testing

Use the provided test commands for load testing:

```bash
# Concurrent requests
for i in {1..10}; do
  curl -X POST \
    -H "Content-Type: application/json" \
    -d "{\"productId\": \"test-$i\", \"quantity\": $i}" \
    "$API_ENDPOINT" &
done
wait

# Monitor traces
aws xray get-trace-summaries \
  --time-range-type TimeRangeByStartTime \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S)
```

## Cost Optimization

### Estimated Monthly Costs (Low Volume)

For 1,000 requests per month:

- **Lambda**: ~$0.20 (execution time and requests)
- **API Gateway**: ~$3.50 (REST API requests)
- **X-Ray**: ~$5.00 (trace recording and retrieval)
- **EventBridge**: ~$1.00 (custom events)
- **CloudWatch Logs**: ~$0.50 (log ingestion and storage)
- **Total**: ~$10.20/month

### Cost Optimization Strategies

1. **X-Ray Sampling**: Configure sampling rules to reduce trace volume
2. **Log Retention**: Adjust retention periods based on compliance needs
3. **Lambda Memory**: Right-size memory allocation based on performance
4. **API Gateway**: Consider HTTP API for lower costs
5. **Reserved Capacity**: Use reserved capacity for predictable workloads

## Security Considerations

### IAM Permissions

The infrastructure implements least-privilege access:

- Lambda functions have minimal required permissions
- Cross-service access is explicitly defined
- EventBridge rules are scoped to specific functions
- No overly broad wildcard permissions

### Data Protection

- X-Ray traces may contain sensitive data - review annotations
- CloudWatch logs are encrypted by default
- EventBridge events should not contain PII
- API Gateway can be secured with API keys or authentication

### Network Security

- All services operate within AWS managed infrastructure
- VPC deployment can be added for additional isolation
- Private endpoints can be configured for enhanced security
- WAF can be added to API Gateway for additional protection

## Troubleshooting

### Common Issues

1. **Permission Errors**: Verify IAM roles and policies
2. **EventBridge Routing**: Check event patterns and rule configuration
3. **Lambda Timeouts**: Increase timeout or optimize function code
4. **X-Ray Missing Traces**: Verify tracing mode and SDK configuration
5. **API Gateway 502**: Check Lambda function errors in CloudWatch

### Debugging Commands

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/distributed-tracing-dev-order-XXXX --follow

# Verify EventBridge rules
aws events list-rules --event-bus-name distributed-tracing-bus-XXXX

# Check X-Ray service map
aws xray get-service-graph \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S)

# Test EventBridge connectivity
aws events put-events \
  --entries Source=test,DetailType="Test Event",Detail='{"test":true}',EventBusName=your-bus-name
```

## Cleanup

To avoid ongoing charges, destroy the infrastructure when testing is complete:

```bash
terraform destroy
```

Review the resources to be destroyed and type `yes` to confirm.

## Production Considerations

Before using this configuration in production:

1. **Add Error Handling**: Implement dead letter queues and retry logic
2. **Enable Monitoring**: Add CloudWatch alarms and notifications
3. **Secure APIs**: Implement authentication and authorization
4. **Add Validation**: Input validation and sanitization
5. **Scale Configuration**: Adjust memory, timeout, and concurrency limits
6. **Backup Strategy**: Configure backup for stateful components
7. **Disaster Recovery**: Multi-region deployment strategy
8. **Compliance**: Review logging and data retention requirements

## Support and Contributions

For issues with this Terraform configuration:

1. Check the troubleshooting section above
2. Review AWS service documentation
3. Validate IAM permissions and resource limits
4. Check CloudWatch logs for detailed error information

## References

- [AWS X-Ray Developer Guide](https://docs.aws.amazon.com/xray/latest/devguide/)
- [Amazon EventBridge User Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)