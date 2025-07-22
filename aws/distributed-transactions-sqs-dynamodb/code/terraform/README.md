# Distributed Transaction Processing with SQS - Terraform Implementation

This Terraform implementation deploys a complete distributed transaction processing system using AWS services, implementing the Saga pattern for managing distributed transactions across multiple microservices.

## Architecture Overview

The solution creates:

- **DynamoDB Tables**: Saga state tracking and business data storage
- **SQS FIFO Queues**: Event-driven message processing with ordering guarantees
- **Lambda Functions**: Microservices for transaction orchestration and business logic
- **API Gateway**: REST API for transaction initiation
- **CloudWatch**: Monitoring, logging, and alerting
- **IAM Roles**: Secure access control for all services

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for creating:
  - DynamoDB tables
  - SQS queues
  - Lambda functions
  - API Gateway
  - IAM roles and policies
  - CloudWatch resources

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Review Configuration

```bash
terraform plan
```

### 3. Deploy Infrastructure

```bash
terraform apply
```

### 4. Test the System

After deployment, use the provided API endpoint to test transactions:

```bash
# Get the API endpoint from Terraform outputs
API_ENDPOINT=$(terraform output -raw transactions_endpoint)

# Test a successful transaction
curl -X POST -H "Content-Type: application/json" \
  -d '{"customerId": "CUST-001", "productId": "PROD-001", "quantity": 2, "amount": 2599.98}' \
  "$API_ENDPOINT"

# Test a transaction that will likely fail due to high quantity
curl -X POST -H "Content-Type: application/json" \
  -d '{"customerId": "CUST-002", "productId": "PROD-003", "quantity": 100, "amount": 79999.00}' \
  "$API_ENDPOINT"
```

## Configuration Variables

### Required Variables

None - all variables have sensible defaults.

### Optional Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `aws_region` | AWS region for deployment | `us-east-1` | `us-west-2` |
| `environment` | Environment name | `dev` | `prod` |
| `project_name` | Project name for resource naming | `distributed-tx` | `my-project` |
| `lambda_timeout` | Lambda function timeout (seconds) | `300` | `180` |
| `lambda_memory_size` | Lambda memory size (MB) | `256` | `512` |
| `enable_monitoring` | Enable CloudWatch monitoring | `true` | `false` |
| `enable_cloudwatch_logs` | Enable CloudWatch logs | `true` | `false` |

### Example terraform.tfvars

```hcl
aws_region = "us-west-2"
environment = "production"
project_name = "ecommerce-tx"
lambda_timeout = 180
lambda_memory_size = 512
enable_monitoring = true
```

## Outputs

After successful deployment, Terraform provides several useful outputs:

- `transactions_endpoint`: Full URL for the transactions API
- `api_gateway_url`: Base API Gateway URL
- `dynamodb_tables`: Information about all DynamoDB tables
- `sqs_queues`: Information about all SQS queues
- `lambda_functions`: Information about all Lambda functions
- `sample_curl_command`: Ready-to-use curl command for testing

## Monitoring and Debugging

### CloudWatch Dashboard

If monitoring is enabled, a CloudWatch dashboard is created with:

- Lambda function metrics (invocations, errors, duration)
- SQS queue metrics (messages sent/received, queue depth)

Access the dashboard URL from the Terraform output:

```bash
terraform output cloudwatch_dashboard_url
```

### Useful Commands

```bash
# Check saga state for all transactions
aws dynamodb scan --table-name $(terraform output -raw saga_state_table_name) \
  --projection-expression 'TransactionId, #status, CurrentStep' \
  --expression-attribute-names '{"#status": "Status"}'

# Check current inventory levels
aws dynamodb scan --table-name $(terraform output -raw inventory_table_name) \
  --projection-expression 'ProductId, QuantityAvailable'

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/'
```

## Testing Scenarios

### 1. Successful Transaction

```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"customerId": "CUST-001", "productId": "PROD-001", "quantity": 1, "amount": 1299.99}' \
  "$(terraform output -raw transactions_endpoint)"
```

### 2. Payment Failure (10% chance)

The payment service has a built-in 10% failure rate for testing:

```bash
# Run multiple times to trigger payment failures
for i in {1..5}; do
  curl -X POST -H "Content-Type: application/json" \
    -d '{"customerId": "CUST-'$i'", "productId": "PROD-001", "quantity": 1, "amount": 1299.99}' \
    "$(terraform output -raw transactions_endpoint)"
  echo ""
done
```

### 3. Inventory Failure

```bash
# Request high quantity to trigger inventory failure
curl -X POST -H "Content-Type: application/json" \
  -d '{"customerId": "CUST-003", "productId": "PROD-003", "quantity": 100, "amount": 79999.00}' \
  "$(terraform output -raw transactions_endpoint)"
```

### 4. Validation Errors

```bash
# Missing required fields
curl -X POST -H "Content-Type: application/json" \
  -d '{"customerId": "CUST-004", "productId": "PROD-001"}' \
  "$(terraform output -raw transactions_endpoint)"

# Invalid quantity
curl -X POST -H "Content-Type: application/json" \
  -d '{"customerId": "CUST-005", "productId": "PROD-001", "quantity": -1, "amount": 1299.99}' \
  "$(terraform output -raw transactions_endpoint)"
```

## Security Considerations

The implementation includes several security best practices:

- **IAM Least Privilege**: Lambda functions have minimal required permissions
- **Resource Isolation**: Each service has its own DynamoDB tables and SQS queues
- **Encryption**: All data is encrypted at rest and in transit
- **VPC Integration**: Can be deployed in private subnets (modify configuration)
- **CORS**: API Gateway includes CORS headers for web integration

## Cost Optimization

The infrastructure is designed to be cost-effective:

- **Pay-per-request DynamoDB**: Only pay for actual usage
- **SQS FIFO**: Minimal costs for message processing
- **Lambda**: Serverless billing based on actual execution time
- **CloudWatch**: Optional monitoring can be disabled to reduce costs

Estimated monthly costs for low-volume testing: $5-15/month

## Customization

### Adding New Services

To add a new service to the saga:

1. Create a new Lambda function in `lambda_functions/`
2. Add corresponding SQS queue in `main.tf`
3. Update saga state steps in the orchestrator
4. Add event source mapping for the new queue

### Modifying Failure Rates

Edit the Lambda function code to adjust failure simulation:

```python
# In payment_service.py or inventory_service.py
if random.random() < 0.1:  # Change 0.1 to desired failure rate
    raise Exception("Simulated failure")
```

### Adding External Integrations

Replace simulation code with actual service calls:

```python
# Example: Replace payment simulation with actual payment gateway
response = payment_gateway.process_payment(
    customer_id=payment_data['customerId'],
    amount=payment_data['amount']
)
```

## Troubleshooting

### Common Issues

1. **Lambda Function Timeouts**
   - Increase `lambda_timeout` variable
   - Check CloudWatch logs for specific errors

2. **SQS Message Processing Delays**
   - Check dead letter queue for failed messages
   - Verify event source mapping configuration

3. **DynamoDB Throttling**
   - Consider switching to provisioned capacity
   - Implement exponential backoff in Lambda functions

4. **API Gateway Errors**
   - Verify Lambda permissions for API Gateway
   - Check CloudWatch logs for detailed error messages

### Debugging Steps

1. **Check Terraform State**
   ```bash
   terraform state list
   terraform show
   ```

2. **Verify Resource Creation**
   ```bash
   aws dynamodb list-tables --query "TableNames[?contains(@, 'distributed-tx')]"
   aws sqs list-queues --query "QueueUrls[?contains(@, 'distributed-tx')]"
   aws lambda list-functions --query "Functions[?contains(FunctionName, 'distributed-tx')]"
   ```

3. **Monitor Transaction Flow**
   ```bash
   # Watch saga state changes
   aws dynamodb scan --table-name $(terraform output -raw saga_state_table_name) \
     --projection-expression 'TransactionId, #status, CurrentStep, CompletedSteps' \
     --expression-attribute-names '{"#status": "Status"}'
   ```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Note**: This will permanently delete all data and cannot be undone.

## Support

For issues with this Terraform implementation:

1. Check the original recipe documentation
2. Review AWS service documentation
3. Verify Terraform provider documentation
4. Check CloudWatch logs for detailed error messages

## License

This infrastructure code is provided as-is for educational and demonstration purposes.