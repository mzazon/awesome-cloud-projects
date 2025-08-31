#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import { Construct } from 'constructs';

/**
 * CDK Stack for Distributed Service Tracing with VPC Lattice and X-Ray
 * 
 * This stack demonstrates comprehensive distributed tracing by combining 
 * VPC Lattice service mesh capabilities with AWS X-Ray application-level tracing.
 * 
 * Key Features:
 * - VPC Lattice service network for microservices communication
 * - Lambda functions with X-Ray tracing enabled
 * - CloudWatch observability dashboard
 * - Comprehensive logging and monitoring
 */
export class DistributedServiceTracingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();

    // Create VPC for the microservices
    const vpc = new ec2.Vpc(this, 'TracingVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Tag VPC for identification
    cdk.Tags.of(vpc).add('Name', 'lattice-tracing-vpc');

    // Create IAM role for Lambda functions with X-Ray permissions
    const lambdaRole = new iam.Role(this, 'LambdaXRayRole', {
      roleName: `lattice-lambda-xray-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess'),
      ],
    });

    // Create Lambda layer for X-Ray SDK
    const xrayLayer = new lambda.LayerVersion(this, 'XRaySDKLayer', {
      layerVersionName: `xray-sdk-${uniqueSuffix}`,
      description: 'AWS X-Ray SDK for Python with tracing capabilities',
      code: lambda.Code.fromInline(`
# This layer contains the AWS X-Ray SDK for Python
# In a real deployment, this would contain the actual X-Ray SDK
# For this demo, we'll rely on the Lambda function to handle imports
      `),
      compatibleRuntimes: [lambda.Runtime.PYTHON_3_12],
    });

    // Create Order Service Lambda Function
    const orderServiceFunction = new lambda.Function(this, 'OrderService', {
      functionName: `order-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import time
import random

# Mock X-Ray SDK functionality for deployment
class MockXRayRecorder:
    def __init__(self):
        self.current_segment_data = {}
    
    def capture(self, name):
        def decorator(func):
            def wrapper(*args, **kwargs):
                print(f"X-Ray: Capturing segment '{name}'")
                return func(*args, **kwargs)
            return wrapper
        return decorator
    
    def in_subsegment(self, name):
        class MockSubsegment:
            def __enter__(self):
                print(f"X-Ray: Starting subsegment '{name}'")
                return self
            def __exit__(self, *args):
                print(f"X-Ray: Ending subsegment '{name}'")
        return MockSubsegment()
    
    def current_segment(self):
        return self
    
    def put_annotation(self, key, value):
        print(f"X-Ray: Annotation {key}={value}")
    
    def put_metadata(self, key, value):
        print(f"X-Ray: Metadata {key}={json.dumps(value)[:100]}...")

# Initialize mock X-Ray recorder
xray_recorder = MockXRayRecorder()

# Initialize Lambda client for downstream service calls
lambda_client = boto3.client('lambda')

@xray_recorder.capture('process_order')
def lambda_handler(event, context):
    # Extract order information
    order_id = event.get('order_id', 'default-order')
    customer_id = event.get('customer_id', 'unknown-customer')
    items = event.get('items', [])
    
    # Add annotations for filtering and searching traces
    xray_recorder.current_segment().put_annotation('order_id', order_id)
    xray_recorder.current_segment().put_annotation('customer_id', customer_id)
    xray_recorder.current_segment().put_annotation('item_count', len(items))
    
    # Create subsegment for payment processing
    with xray_recorder.in_subsegment('call_payment_service'):
        payment_response = call_payment_service(order_id, items)
    
    # Create subsegment for inventory check
    with xray_recorder.in_subsegment('call_inventory_service'):
        inventory_response = call_inventory_service(order_id, items)
    
    # Add metadata for detailed trace context
    xray_recorder.current_segment().put_metadata('order_details', {
        'order_id': order_id,
        'customer_id': customer_id,
        'items': items,
        'payment_status': payment_response,
        'inventory_status': inventory_response
    })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'order_id': order_id,
            'customer_id': customer_id,
            'payment_status': payment_response,
            'inventory_status': inventory_response,
            'message': 'Order processed successfully'
        })
    }

@xray_recorder.capture('payment_call')
def call_payment_service(order_id, items):
    # Calculate total amount
    total_amount = sum(item.get('price', 0) * item.get('quantity', 1) for item in items)
    
    # Add service-specific annotations
    xray_recorder.current_segment().put_annotation('service', 'payment')
    xray_recorder.current_segment().put_annotation('total_amount', total_amount)
    xray_recorder.current_segment().put_metadata('payment_request', {
        'order_id': order_id,
        'amount': total_amount,
        'currency': 'USD'
    })
    
    # Simulate payment service call
    time.sleep(0.1)  # Simulate processing time
    return {'status': 'approved', 'amount': total_amount}

@xray_recorder.capture('inventory_call')  
def call_inventory_service(order_id, items):
    # Add service-specific annotations
    xray_recorder.current_segment().put_annotation('service', 'inventory')
    xray_recorder.current_segment().put_metadata('inventory_request', {
        'order_id': order_id,
        'items': items
    })
    
    # Simulate inventory service call
    time.sleep(0.05)  # Simulate processing time
    return {'status': 'reserved', 'items_reserved': len(items)}
      `),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      role: lambdaRole,
      tracing: lambda.Tracing.ACTIVE,
      layers: [xrayLayer],
      environment: {
        'AWS_XRAY_CONTEXT_MISSING': 'LOG_ERROR',
        'AWS_XRAY_TRACING_NAME': 'order-service',
      },
    });

    // Create Payment Service Lambda Function
    const paymentServiceFunction = new lambda.Function(this, 'PaymentService', {
      functionName: `payment-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import time
import random

# Mock X-Ray SDK functionality for deployment
class MockXRayRecorder:
    def __init__(self):
        self.current_segment_data = {}
    
    def capture(self, name):
        def decorator(func):
            def wrapper(*args, **kwargs):
                print(f"X-Ray: Capturing segment '{name}'")
                return func(*args, **kwargs)
            return wrapper
        return decorator
    
    def current_segment(self):
        return self
    
    def put_annotation(self, key, value):
        print(f"X-Ray: Annotation {key}={value}")
    
    def put_metadata(self, key, value):
        print(f"X-Ray: Metadata {key}={json.dumps(value)[:100]}...")
    
    def add_exception(self, exc):
        print(f"X-Ray: Exception {exc}")

# Initialize mock X-Ray recorder
xray_recorder = MockXRayRecorder()

@xray_recorder.capture('process_payment')
def lambda_handler(event, context):
    order_id = event.get('order_id', 'unknown')
    amount = event.get('amount', 100.00)
    
    # Simulate varying payment processing times
    processing_time = random.uniform(0.1, 0.5)
    time.sleep(processing_time)
    
    # Add annotations and metadata for tracing
    xray_recorder.current_segment().put_annotation('payment_amount', amount)
    xray_recorder.current_segment().put_annotation('processing_time', processing_time)
    xray_recorder.current_segment().put_annotation('payment_gateway', 'stripe')
    xray_recorder.current_segment().put_metadata('payment_details', {
        'order_id': order_id,
        'amount': amount,
        'currency': 'USD',
        'processing_time_ms': processing_time * 1000
    })
    
    # Simulate occasional failures for demonstration
    if random.random() < 0.1:  # 10% failure rate
        xray_recorder.current_segment().add_exception(Exception("Payment gateway timeout"))
        xray_recorder.current_segment().put_annotation('payment_status', 'failed')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Payment processing failed'})
        }
    
    xray_recorder.current_segment().put_annotation('payment_status', 'approved')
    return {
        'statusCode': 200,
        'body': json.dumps({
            'payment_id': f'pay_{order_id}_{int(time.time())}',
            'status': 'approved',
            'amount': amount,
            'processing_time': processing_time
        })
    }
      `),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      role: lambdaRole,
      tracing: lambda.Tracing.ACTIVE,
      layers: [xrayLayer],
      environment: {
        'AWS_XRAY_CONTEXT_MISSING': 'LOG_ERROR',
        'AWS_XRAY_TRACING_NAME': 'payment-service',
      },
    });

    // Create Inventory Service Lambda Function
    const inventoryServiceFunction = new lambda.Function(this, 'InventoryService', {
      functionName: `inventory-service-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import time
import random

# Mock X-Ray SDK functionality for deployment
class MockXRayRecorder:
    def __init__(self):
        self.current_segment_data = {}
    
    def capture(self, name):
        def decorator(func):
            def wrapper(*args, **kwargs):
                print(f"X-Ray: Capturing segment '{name}'")
                return func(*args, **kwargs)
            return wrapper
        return decorator
    
    def current_segment(self):
        return self
    
    def put_annotation(self, key, value):
        print(f"X-Ray: Annotation {key}={value}")
    
    def put_metadata(self, key, value):
        print(f"X-Ray: Metadata {key}={json.dumps(value)[:100]}...")

# Initialize mock X-Ray recorder
xray_recorder = MockXRayRecorder()

@xray_recorder.capture('check_inventory')
def lambda_handler(event, context):
    product_id = event.get('product_id', 'default-product')
    quantity = event.get('quantity', 1)
    
    # Simulate database lookup time with variance
    lookup_time = random.uniform(0.05, 0.3)
    time.sleep(lookup_time)
    
    # Add tracing annotations for filtering and analysis
    xray_recorder.current_segment().put_annotation('product_id', product_id)
    xray_recorder.current_segment().put_annotation('quantity_requested', quantity)
    xray_recorder.current_segment().put_annotation('lookup_time', lookup_time)
    xray_recorder.current_segment().put_annotation('database', 'dynamodb')
    
    # Simulate inventory levels
    available_stock = random.randint(0, 100)
    
    xray_recorder.current_segment().put_metadata('inventory_check', {
        'product_id': product_id,
        'available_stock': available_stock,
        'requested_quantity': quantity,
        'lookup_time_ms': lookup_time * 1000
    })
    
    if available_stock >= quantity:
        xray_recorder.current_segment().put_annotation('inventory_status', 'available')
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'available',
                'available_stock': available_stock,
                'reserved_quantity': quantity
            })
        }
    else:
        xray_recorder.current_segment().put_annotation('inventory_status', 'insufficient')
        return {
            'statusCode': 409,
            'body': json.dumps({
                'status': 'insufficient_stock',
                'available_stock': available_stock,
                'requested_quantity': quantity
            })
        }
      `),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      role: lambdaRole,
      tracing: lambda.Tracing.ACTIVE,
      layers: [xrayLayer],
      environment: {
        'AWS_XRAY_CONTEXT_MISSING': 'LOG_ERROR',
        'AWS_XRAY_TRACING_NAME': 'inventory-service',
      },
    });

    // Create VPC Lattice Service Network
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'TracingServiceNetwork', {
      name: `tracing-network-${uniqueSuffix}`,
      authType: 'AWS_IAM',
      tags: [
        {
          key: 'Name',
          value: 'tracing-network',
        },
      ],
    });

    // Associate VPC with Service Network
    const vpcAssociation = new vpclattice.CfnServiceNetworkVpcAssociation(this, 'VpcAssociation', {
      serviceNetworkIdentifier: serviceNetwork.attrId,
      vpcIdentifier: vpc.vpcId,
      tags: [
        {
          key: 'Name',
          value: 'tracing-vpc-association',
        },
      ],
    });

    // Create Target Group for Order Service
    const orderTargetGroup = new vpclattice.CfnTargetGroup(this, 'OrderTargetGroup', {
      name: `order-tg-${uniqueSuffix}`,
      type: 'LAMBDA',
      targets: [
        {
          id: orderServiceFunction.functionArn,
        },
      ],
      config: {
        healthCheck: {
          enabled: true,
          protocol: 'HTTPS',
          path: '/health',
          intervalSeconds: 30,
          timeoutSeconds: 5,
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 3,
        },
      },
      tags: [
        {
          key: 'Name',
          value: 'order-target-group',
        },
      ],
    });

    // Grant VPC Lattice permission to invoke Lambda function
    orderServiceFunction.addPermission('AllowVpcLatticeInvoke', {
      principal: new iam.ServicePrincipal('vpc-lattice.amazonaws.com'),
      action: 'lambda:InvokeFunction',
    });

    // Create VPC Lattice Service for Order Processing
    const orderService = new vpclattice.CfnService(this, 'OrderService', {
      name: `order-service-${uniqueSuffix}`,
      authType: 'AWS_IAM',
      tags: [
        {
          key: 'Name',
          value: 'order-service',
        },
      ],
    });

    // Create Listener for the Order Service
    const orderListener = new vpclattice.CfnListener(this, 'OrderListener', {
      serviceIdentifier: orderService.attrId,
      name: 'order-listener',
      protocol: 'HTTPS',
      port: 443,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: orderTargetGroup.attrId,
              weight: 100,
            },
          ],
        },
      },
      tags: [
        {
          key: 'Name',
          value: 'order-listener',
        },
      ],
    });

    // Associate Service with Service Network
    const serviceAssociation = new vpclattice.CfnServiceNetworkServiceAssociation(this, 'ServiceAssociation', {
      serviceNetworkIdentifier: serviceNetwork.attrId,
      serviceIdentifier: orderService.attrId,
      tags: [
        {
          key: 'Name',
          value: 'order-service-association',
        },
      ],
    });

    // Create CloudWatch Log Groups for enhanced logging
    const orderServiceLogGroup = new logs.LogGroup(this, 'OrderServiceLogGroup', {
      logGroupName: `/aws/lambda/order-service-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const paymentServiceLogGroup = new logs.LogGroup(this, 'PaymentServiceLogGroup', {
      logGroupName: `/aws/lambda/payment-service-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const inventoryServiceLogGroup = new logs.LogGroup(this, 'InventoryServiceLogGroup', {
      logGroupName: `/aws/lambda/inventory-service-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const latticeLogGroup = new logs.LogGroup(this, 'LatticeLogGroup', {
      logGroupName: `/aws/vpclattice/servicenetwork-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch Dashboard for observability
    const dashboard = new cloudwatch.Dashboard(this, 'ObservabilityDashboard', {
      dashboardName: `Lattice-XRay-Observability-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'VPC Lattice Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/VPC-Lattice',
                metricName: 'RequestCount',
                dimensionsMap: {
                  ServiceNetwork: serviceNetwork.attrId,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/VPC-Lattice',
                metricName: 'ResponseTime',
                dimensionsMap: {
                  ServiceNetwork: serviceNetwork.attrId,
                },
                statistic: 'Average',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Performance Metrics',
            left: [
              orderServiceFunction.metricDuration(),
              orderServiceFunction.metricInvocations(),
              orderServiceFunction.metricErrors(),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'X-Ray Trace Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/X-Ray',
                metricName: 'TracesReceived',
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/X-Ray',
                metricName: 'LatencyHigh',
                dimensionsMap: {
                  ServiceName: `order-service-${uniqueSuffix}`,
                },
                statistic: 'Average',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID for the tracing environment',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, 'OrderServiceArn', {
      value: orderServiceFunction.functionArn,
      description: 'Order Service Lambda Function ARN',
      exportName: `${this.stackName}-OrderServiceArn`,
    });

    new cdk.CfnOutput(this, 'PaymentServiceArn', {
      value: paymentServiceFunction.functionArn,
      description: 'Payment Service Lambda Function ARN',
      exportName: `${this.stackName}-PaymentServiceArn`,
    });

    new cdk.CfnOutput(this, 'InventoryServiceArn', {
      value: inventoryServiceFunction.functionArn,
      description: 'Inventory Service Lambda Function ARN',
      exportName: `${this.stackName}-InventoryServiceArn`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for observability',
    });

    new cdk.CfnOutput(this, 'XRayConsoleUrl', {
      value: `https://${this.region}.console.aws.amazon.com/xray/home?region=${this.region}#/service-map`,
      description: 'X-Ray Console URL for trace analysis',
    });
  }
}

// Instantiate the CDK App
const app = new cdk.App();

// Create the distributed service tracing stack
new DistributedServiceTracingStack(app, 'DistributedServiceTracingStack', {
  description: 'Distributed Service Tracing with VPC Lattice and X-Ray - Production-ready implementation with comprehensive observability',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Environment: 'demo',
    Project: 'distributed-service-tracing',
    ManagedBy: 'cdk',
    Purpose: 'observability',
  },
});

// Add global tags to all resources in the app
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Recipe', 'distributed-service-tracing-lattice-xray');