# gRPC Microservices with VPC Lattice and CloudWatch - CDK Python

This CDK Python application deploys a complete gRPC microservices architecture using AWS VPC Lattice's native HTTP/2 support and CloudWatch monitoring. The solution provides intelligent routing, health monitoring, and comprehensive observability for production gRPC workloads.

## Architecture Overview

The application creates:

- **VPC Lattice Service Network**: Application-layer service mesh for gRPC communication
- **Three gRPC Microservices**: User, Order, and Inventory services with HTTP/2 optimization
- **EC2 Instances**: Hosting gRPC services with health check endpoints
- **CloudWatch Monitoring**: Metrics, alarms, and dashboards for observability
- **Advanced Routing**: API versioning and method-based traffic management

## Prerequisites

- AWS CLI v2 installed and configured
- Python 3.8 or higher
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for VPC Lattice, EC2, CloudWatch, and IAM

## Installation

1. **Clone and navigate to the directory**:
   ```bash
   cd aws/grpc-microservices-lattice-cloudwatch/code/cdk-python/
   ```

2. **Create a virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

The application supports customization through CDK context parameters:

### Context Parameters

- `environment`: Environment name (default: "development")
- `instance_type`: EC2 instance type (default: "t3.micro")
- `enable_detailed_monitoring`: Enable detailed CloudWatch monitoring (default: true)

### Setting Context Parameters

```bash
# Set environment to production
cdk deploy -c environment=production

# Use larger instances
cdk deploy -c instance_type=t3.small

# Disable detailed monitoring
cdk deploy -c enable_detailed_monitoring=false
```

### Environment Variables

You can also set AWS environment variables:

```bash
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-east-1
```

## Deployment

### Deploy the Stack

```bash
# Preview changes
cdk diff

# Deploy the application
cdk deploy

# Deploy with specific configuration
cdk deploy -c environment=production -c instance_type=t3.small
```

### Deployment Output

The deployment provides several important outputs:

- `ServiceNetworkId`: VPC Lattice Service Network identifier
- `ServiceNetworkDns`: Service network DNS endpoint
- `UserServiceEndpoint`: User service gRPC endpoint
- `OrderServiceEndpoint`: Order service gRPC endpoint
- `InventoryServiceEndpoint`: Inventory service gRPC endpoint
- `DashboardUrl`: CloudWatch dashboard URL
- `LogGroupName`: Access logs CloudWatch Log Group

## Usage

### Service Endpoints

After deployment, your gRPC services are available at:

```
https://{service-name}-service-{environment}.{service-network-dns}/
```

### Health Check Endpoints

Each service also provides an HTTP health check endpoint on port 8080:

```
http://{instance-private-ip}:8080/health
```

### CloudWatch Monitoring

Access the CloudWatch dashboard using the provided URL to monitor:

- Request count and throughput
- Request latency and response times
- Error rates and connection failures
- Target group health status

### gRPC Communication

Services support:

- **HTTP/2 Protocol**: Optimized for gRPC communication
- **API Versioning**: Header-based routing with `grpc-version` header
- **Method Routing**: Path-based routing for specific gRPC methods
- **Load Balancing**: Automatic distribution across healthy instances

## Advanced Features

### API Versioning

Route traffic based on gRPC version headers:

```bash
# Route to v2 API
grpcurl -H "grpc-version: v2" {user-service-endpoint} user.UserService/GetUser
```

### Method-Based Routing

The Order service includes path-based routing for processing methods:

```bash
# Routes to optimized processing targets
grpcurl {order-service-endpoint} order.OrderService/ProcessOrder
```

### Health Monitoring

Services include comprehensive health checks:

- HTTP health endpoints for VPC Lattice health checks
- CloudWatch metrics for performance monitoring
- Automatic alarming for error rates and latency

## Customization

### Adding New Services

1. Update the `services` list in `grpc_microservices_stack.py`
2. Add corresponding port mappings
3. Deploy the updated stack

### Modifying Instance Configuration

```python
# In grpc_microservices_stack.py
instance_type = "t3.medium"  # Change instance size
enable_detailed_monitoring = True  # Enable detailed monitoring
```

### Custom Routing Rules

Add new routing rules in the `_create_routing_rules()` method:

```python
# Example: Weight-based routing for canary deployments
vpclattice.CfnRule(
    self,
    "CanaryRoutingRule",
    # ... configuration
)
```

## Testing

### Validate Deployment

```bash
# Check service network status
aws vpc-lattice get-service-network --service-network-identifier {service-network-id}

# Check target group health
aws vpc-lattice list-targets --target-group-identifier {target-group-id}

# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/VpcLattice \
    --metric-name TotalRequestCount \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T01:00:00Z \
    --period 300 \
    --statistics Sum
```

### Load Testing

Use tools like `ghz` or `grpcurl` for gRPC load testing:

```bash
# Install ghz for load testing
go install github.com/bojand/ghz/cmd/ghz@latest

# Run load test
ghz --insecure --total=1000 --concurrency=10 \
    --call user.UserService.GetUser \
    {user-service-endpoint}
```

## Troubleshooting

### Common Issues

1. **Service Not Healthy**:
   - Check EC2 instance logs: `sudo journalctl -u cloud-init`
   - Verify health endpoint: `curl http://localhost:8080/health`

2. **Connection Failures**:
   - Verify security group rules
   - Check VPC Lattice service associations
   - Review CloudWatch logs

3. **High Latency**:
   - Monitor CloudWatch metrics
   - Check target group health
   - Review instance performance

### Debugging Commands

```bash
# Check CloudWatch logs
aws logs tail /aws/vpc-lattice/grpc-services-{environment} --follow

# Describe VPC Lattice services
aws vpc-lattice list-services

# Check target health
aws vpc-lattice list-targets --target-group-identifier {tg-id}
```

## Cleanup

### Destroy the Stack

```bash
# Destroy all resources
cdk destroy

# Confirm destruction
cdk destroy --force
```

### Manual Cleanup (if needed)

If CDK destroy fails, manually clean up:

```bash
# Delete VPC Lattice resources
aws vpc-lattice delete-service-network --service-network-identifier {id}

# Terminate EC2 instances
aws ec2 terminate-instances --instance-ids {instance-ids}

# Delete CloudWatch resources
aws cloudwatch delete-dashboard --dashboard-name {dashboard-name}
aws logs delete-log-group --log-group-name {log-group-name}
```

## Cost Optimization

### Cost Considerations

- **EC2 Instances**: Primary cost driver - consider Spot instances for development
- **VPC Lattice**: Pay-per-use pricing for requests and data transfer
- **CloudWatch**: Metrics, logs, and dashboard costs
- **Data Transfer**: Cross-AZ traffic charges

### Optimization Strategies

```bash
# Deploy with cost-optimized configuration
cdk deploy -c instance_type=t3.nano -c environment=development

# Use Spot instances (requires code modification)
# Disable detailed monitoring for development
cdk deploy -c enable_detailed_monitoring=false
```

## Security

### Security Features

- **IAM Authentication**: VPC Lattice services use AWS IAM for authentication
- **VPC Isolation**: Services isolated within VPC boundaries
- **TLS Encryption**: All VPC Lattice traffic encrypted in transit
- **Security Groups**: Least privilege network access
- **CloudTrail Integration**: Comprehensive audit logging

### Security Best Practices

1. **Least Privilege IAM**: Grant minimal required permissions
2. **Network Segmentation**: Use private subnets for backend services
3. **Encryption**: Enable encryption for CloudWatch logs
4. **Monitoring**: Set up CloudWatch alarms for security events
5. **Regular Updates**: Keep EC2 instances updated with latest patches

## Support

For issues and questions:

1. Check the [VPC Lattice documentation](https://docs.aws.amazon.com/vpc-lattice/)
2. Review [CloudWatch best practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html)
3. Consult [CDK Python documentation](https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html)
4. Review the original recipe documentation

## License

This code is provided under the MIT License. See LICENSE file for details.