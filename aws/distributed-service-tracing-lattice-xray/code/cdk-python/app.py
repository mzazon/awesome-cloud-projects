#!/usr/bin/env python3
"""
AWS CDK Python Application for Distributed Service Tracing with VPC Lattice and X-Ray

This application demonstrates comprehensive distributed tracing by combining VPC Lattice 
service mesh capabilities with AWS X-Ray application-level tracing. It creates a complete
observability solution for microservices architectures.

Architecture Components:
- VPC with subnets for Lambda functions
- VPC Lattice service network for service mesh
- Lambda functions with X-Ray tracing enabled
- CloudWatch dashboards for monitoring
- IAM roles with least privilege access
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    Tags,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_iam as iam
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_logs as logs
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_vpclattice as lattice
from constructs import Construct
import json
from typing import Dict, List


class DistributedServiceTracingStack(Stack):
    """
    Main CDK Stack for Distributed Service Tracing with VPC Lattice and X-Ray
    
    This stack creates a complete microservices observability solution including:
    - VPC Lattice service network for inter-service communication
    - Lambda functions with comprehensive X-Ray instrumentation
    - CloudWatch monitoring and alerting
    - IAM roles following least privilege principles
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Add tags to all resources in this stack
        Tags.of(self).add("Project", "DistributedServiceTracing")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("ManagedBy", "CDK")

        # Create VPC for Lambda functions
        self.vpc = self._create_vpc()
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda layer with X-Ray SDK
        self.xray_layer = self._create_xray_layer()
        
        # Create Lambda functions for microservices
        self.lambda_functions = self._create_lambda_functions()
        
        # Create VPC Lattice service network
        self.service_network = self._create_vpc_lattice_network()
        
        # Create VPC Lattice services and target groups
        self.lattice_services = self._create_lattice_services()
        
        # Create CloudWatch resources for observability
        self._create_observability_resources()
        
        # Create outputs for important resource identifiers
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets for Lambda functions
        
        Returns:
            ec2.Vpc: The created VPC with appropriate subnet configuration
        """
        vpc = ec2.Vpc(
            self, "TracingVPC",
            vpc_name="distributed-tracing-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Add VPC Flow Logs for network observability
        vpc.add_flow_log(
            "VPCFlowLogs",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                logs.LogGroup(
                    self, "VPCFlowLogsGroup",
                    log_group_name="/aws/vpc/flowlogs",
                    retention=logs.RetentionDays.ONE_WEEK,
                    removal_policy=RemovalPolicy.DESTROY,
                )
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )
        
        return vpc

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda functions with X-Ray and VPC permissions
        
        Returns:
            iam.Role: IAM role with appropriate permissions for Lambda execution
        """
        role = iam.Role(
            self, "LambdaExecutionRole",
            role_name="lattice-lambda-xray-execution-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Lambda functions with X-Ray tracing",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaVPCAccessExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSXRayDaemonWriteAccess"
                ),
            ],
        )
        
        # Add custom policy for Lambda invocation (for inter-service calls)
        lambda_invoke_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "lambda:InvokeFunction",
            ],
            resources=[
                f"arn:aws:lambda:{self.region}:{self.account}:function:*service*"
            ],
        )
        
        role.add_to_policy(lambda_invoke_policy)
        
        return role

    def _create_xray_layer(self) -> lambda_.LayerVersion:
        """
        Create Lambda layer containing AWS X-Ray SDK for Python
        
        Returns:
            lambda_.LayerVersion: Lambda layer with X-Ray SDK dependencies
        """
        # Create layer from inline code that includes X-Ray SDK installation
        layer_code = '''
import subprocess
import sys
import os

def install_packages():
    """Install X-Ray SDK packages for Lambda layer"""
    target_dir = "/opt/python"
    os.makedirs(target_dir, exist_ok=True)
    
    packages = [
        "aws-xray-sdk==2.12.1",
        "requests==2.31.0"
    ]
    
    for package in packages:
        subprocess.check_call([
            sys.executable, "-m", "pip", "install", 
            package, "-t", target_dir, "--no-deps"
        ])

if __name__ == "__main__":
    install_packages()
'''
        
        # For demonstration, we'll create a layer that users need to build separately
        # In production, you would pre-build this layer or use a pre-built one
        return lambda_.LayerVersion(
            self, "XRaySDKLayer",
            layer_version_name="xray-sdk-python",
            description="AWS X-Ray SDK for Python with dependencies",
            compatible_runtimes=[
                lambda_.Runtime.PYTHON_3_12,
                lambda_.Runtime.PYTHON_3_11,
                lambda_.Runtime.PYTHON_3_10,
            ],
            # Note: In real deployment, you would provide the actual layer code
            # code=lambda_.Code.from_asset("path/to/layer/zip"),
            code=lambda_.Code.from_inline(layer_code),
        )

    def _create_lambda_functions(self) -> Dict[str, lambda_.Function]:
        """
        Create Lambda functions for each microservice with X-Ray tracing
        
        Returns:
            Dict[str, lambda_.Function]: Dictionary of Lambda functions by service name
        """
        functions = {}
        
        # Order Service - Main orchestrator service
        order_service_code = '''
import json
import boto3
import os
import time
import random
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch all AWS SDK calls for X-Ray tracing
patch_all()

# Initialize Lambda client for downstream service calls
lambda_client = boto3.client('lambda')

@xray_recorder.capture('process_order')
def lambda_handler(event, context):
    """
    Main order processing function with comprehensive X-Ray tracing
    
    Args:
        event: Lambda event containing order information
        context: Lambda context object
        
    Returns:
        dict: Order processing response with status and details
    """
    try:
        # Extract order information from event
        order_id = event.get('order_id', f'order-{int(time.time())}')
        customer_id = event.get('customer_id', 'unknown-customer')
        items = event.get('items', [])
        
        # Add annotations for filtering and searching traces
        xray_recorder.current_segment().put_annotation('order_id', order_id)
        xray_recorder.current_segment().put_annotation('customer_id', customer_id)
        xray_recorder.current_segment().put_annotation('item_count', len(items))
        xray_recorder.current_segment().put_annotation('service_name', 'order-service')
        
        # Process payment through payment service
        with xray_recorder.in_subsegment('call_payment_service'):
            payment_response = call_payment_service(order_id, items)
        
        # Check inventory through inventory service  
        with xray_recorder.in_subsegment('call_inventory_service'):
            inventory_response = call_inventory_service(order_id, items)
        
        # Add comprehensive metadata for debugging
        xray_recorder.current_segment().put_metadata('order_details', {
            'order_id': order_id,
            'customer_id': customer_id,
            'items': items,
            'payment_response': payment_response,
            'inventory_response': inventory_response,
            'processing_timestamp': time.time()
        })
        
        # Determine overall order status
        order_status = 'completed' if (
            payment_response.get('status') == 'approved' and 
            inventory_response.get('status') == 'available'
        ) else 'failed'
        
        xray_recorder.current_segment().put_annotation('order_status', order_status)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'order_id': order_id,
                'customer_id': customer_id,
                'status': order_status,
                'payment': payment_response,
                'inventory': inventory_response,
                'message': f'Order {order_status} successfully'
            }),
            'headers': {
                'Content-Type': 'application/json',
                'X-Trace-Id': os.environ.get('_X_AMZN_TRACE_ID', 'unknown')
            }
        }
        
    except Exception as e:
        # Add exception to X-Ray trace
        xray_recorder.current_segment().add_exception(e)
        xray_recorder.current_segment().put_annotation('error', True)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Order processing failed',
                'message': str(e)
            })
        }

@xray_recorder.capture('payment_service_call')
def call_payment_service(order_id: str, items: list) -> dict:
    """Call payment service with X-Ray tracing"""
    try:
        # Calculate total amount
        total_amount = sum(item.get('price', 0) * item.get('quantity', 1) for item in items)
        
        # Add subsegment annotations
        xray_recorder.current_subsegment().put_annotation('service', 'payment')
        xray_recorder.current_subsegment().put_annotation('total_amount', total_amount)
        xray_recorder.current_subsegment().put_metadata('payment_request', {
            'order_id': order_id,
            'amount': total_amount,
            'currency': 'USD',
            'items_count': len(items)
        })
        
        # Simulate payment service call via Lambda invoke
        payment_function_name = os.environ.get('PAYMENT_FUNCTION_NAME', 'payment-service')
        
        response = lambda_client.invoke(
            FunctionName=payment_function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'order_id': order_id,
                'amount': total_amount,
                'customer_payment_method': 'credit_card'
            })
        )
        
        payload = json.loads(response['Payload'].read())
        payment_result = json.loads(payload.get('body', '{}'))
        
        xray_recorder.current_subsegment().put_annotation('payment_status', 
                                                        payment_result.get('status', 'unknown'))
        
        return payment_result
        
    except Exception as e:
        xray_recorder.current_subsegment().add_exception(e)
        return {'status': 'failed', 'error': str(e)}

@xray_recorder.capture('inventory_service_call')
def call_inventory_service(order_id: str, items: list) -> dict:
    """Call inventory service with X-Ray tracing"""
    try:
        # Add subsegment annotations
        xray_recorder.current_subsegment().put_annotation('service', 'inventory')
        xray_recorder.current_subsegment().put_metadata('inventory_request', {
            'order_id': order_id,
            'items': items,
            'total_items': len(items)
        })
        
        # Simulate inventory service call via Lambda invoke
        inventory_function_name = os.environ.get('INVENTORY_FUNCTION_NAME', 'inventory-service')
        
        response = lambda_client.invoke(
            FunctionName=inventory_function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'order_id': order_id,
                'items': items
            })
        )
        
        payload = json.loads(response['Payload'].read())
        inventory_result = json.loads(payload.get('body', '{}'))
        
        xray_recorder.current_subsegment().put_annotation('inventory_status', 
                                                        inventory_result.get('status', 'unknown'))
        
        return inventory_result
        
    except Exception as e:
        xray_recorder.current_subsegment().add_exception(e)
        return {'status': 'failed', 'error': str(e)}
'''
        
        functions['order'] = lambda_.Function(
            self, "OrderService",
            function_name="order-service",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(order_service_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            tracing=lambda_.Tracing.ACTIVE,
            layers=[self.xray_layer],
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            environment={
                "PAYMENT_FUNCTION_NAME": "payment-service",
                "INVENTORY_FUNCTION_NAME": "inventory-service",
                "AWS_XRAY_TRACING_NAME": "order-service",
                "AWS_XRAY_CONTEXT_MISSING": "LOG_ERROR"
            },
            description="Order processing service with X-Ray distributed tracing",
        )
        
        # Payment Service
        payment_service_code = '''
import json
import time
import random
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

patch_all()

@xray_recorder.capture('process_payment')
def lambda_handler(event, context):
    """
    Payment processing service with comprehensive X-Ray instrumentation
    
    Args:
        event: Payment request with order details
        context: Lambda context
        
    Returns:
        dict: Payment processing response
    """
    try:
        order_id = event.get('order_id', 'unknown')
        amount = event.get('amount', 100.00)
        payment_method = event.get('customer_payment_method', 'credit_card')
        
        # Simulate varying payment processing times
        processing_time = random.uniform(0.1, 0.5)
        time.sleep(processing_time)
        
        # Add comprehensive annotations for trace analysis
        xray_recorder.current_segment().put_annotation('service_name', 'payment-service')
        xray_recorder.current_segment().put_annotation('payment_amount', amount)
        xray_recorder.current_segment().put_annotation('processing_time', processing_time)
        xray_recorder.current_segment().put_annotation('payment_method', payment_method)
        xray_recorder.current_segment().put_annotation('payment_gateway', 'stripe_demo')
        
        # Add detailed metadata for debugging
        xray_recorder.current_segment().put_metadata('payment_processing', {
            'order_id': order_id,
            'amount': amount,
            'currency': 'USD',
            'payment_method': payment_method,
            'processing_time_ms': processing_time * 1000,
            'gateway_endpoint': 'api.stripe.com/v1/charges',
            'timestamp': time.time()
        })
        
        # Simulate payment gateway interaction with subsegment
        with xray_recorder.in_subsegment('payment_gateway_call'):
            xray_recorder.current_subsegment().put_annotation('gateway', 'stripe')
            xray_recorder.current_subsegment().put_metadata('gateway_request', {
                'amount_cents': int(amount * 100),
                'currency': 'usd',
                'description': f'Order {order_id}'
            })
            
            # Simulate network call delay
            time.sleep(random.uniform(0.05, 0.15))
        
        # Simulate occasional payment failures for realistic testing
        failure_rate = 0.1  # 10% failure rate
        if random.random() < failure_rate:
            error = Exception(f"Payment gateway declined transaction for amount ${amount}")
            xray_recorder.current_segment().add_exception(error)
            xray_recorder.current_segment().put_annotation('payment_status', 'declined')
            
            return {
                'statusCode': 402,  # Payment Required
                'body': json.dumps({
                    'status': 'declined',
                    'order_id': order_id,
                    'amount': amount,
                    'error': 'Payment declined by gateway',
                    'retry_allowed': True
                })
            }
        
        # Successful payment processing
        payment_id = f'pay_{order_id}_{int(time.time())}'
        xray_recorder.current_segment().put_annotation('payment_status', 'approved')
        xray_recorder.current_segment().put_annotation('payment_id', payment_id)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'approved',
                'payment_id': payment_id,
                'order_id': order_id,
                'amount': amount,
                'processing_time': processing_time,
                'gateway_reference': f'ch_{random.randint(100000, 999999)}'
            })
        }
        
    except Exception as e:
        xray_recorder.current_segment().add_exception(e)
        xray_recorder.current_segment().put_annotation('payment_status', 'error')
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'error': str(e),
                'order_id': event.get('order_id', 'unknown')
            })
        }
'''
        
        functions['payment'] = lambda_.Function(
            self, "PaymentService", 
            function_name="payment-service",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(payment_service_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            tracing=lambda_.Tracing.ACTIVE,
            layers=[self.xray_layer],
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            environment={
                "AWS_XRAY_TRACING_NAME": "payment-service",
                "AWS_XRAY_CONTEXT_MISSING": "LOG_ERROR"
            },
            description="Payment processing service with failure simulation and X-Ray tracing",
        )
        
        # Inventory Service
        inventory_service_code = '''
import json
import time
import random
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

patch_all()

@xray_recorder.capture('check_inventory')
def lambda_handler(event, context):
    """
    Inventory checking service with comprehensive X-Ray instrumentation
    
    Args:
        event: Inventory check request with items
        context: Lambda context
        
    Returns:
        dict: Inventory availability response
    """
    try:
        order_id = event.get('order_id', 'unknown')
        items = event.get('items', [])
        
        # Simulate database lookup time with realistic variance
        lookup_time = random.uniform(0.05, 0.3)
        time.sleep(lookup_time)
        
        # Add comprehensive annotations for trace filtering
        xray_recorder.current_segment().put_annotation('service_name', 'inventory-service')
        xray_recorder.current_segment().put_annotation('items_count', len(items))
        xray_recorder.current_segment().put_annotation('lookup_time', lookup_time)
        xray_recorder.current_segment().put_annotation('database_type', 'dynamodb')
        
        # Process each item and check availability
        inventory_results = []
        total_requested = 0
        total_available = 0
        
        for item in items:
            product_id = item.get('product_id', f'product-{random.randint(1, 1000)}')
            quantity_requested = item.get('quantity', 1)
            total_requested += quantity_requested
            
            # Simulate per-item database lookup with subsegment
            with xray_recorder.in_subsegment(f'lookup_{product_id}'):
                xray_recorder.current_subsegment().put_annotation('product_id', product_id)
                xray_recorder.current_subsegment().put_annotation('quantity_requested', quantity_requested)
                
                # Simulate varying stock levels
                available_stock = random.randint(0, 20)
                total_available += min(available_stock, quantity_requested)
                
                xray_recorder.current_subsegment().put_metadata('inventory_lookup', {
                    'product_id': product_id,
                    'available_stock': available_stock,
                    'requested_quantity': quantity_requested,
                    'can_fulfill': available_stock >= quantity_requested
                })
                
                inventory_results.append({
                    'product_id': product_id,
                    'requested': quantity_requested,
                    'available': available_stock,
                    'reserved': min(available_stock, quantity_requested),
                    'status': 'available' if available_stock >= quantity_requested else 'partial'
                })
                
                # Simulate individual item lookup time
                time.sleep(random.uniform(0.01, 0.05))
        
        # Determine overall availability status
        all_available = all(item['status'] == 'available' for item in inventory_results)
        overall_status = 'available' if all_available else 'partial' if total_available > 0 else 'unavailable'
        
        # Add final annotations and metadata
        xray_recorder.current_segment().put_annotation('inventory_status', overall_status)
        xray_recorder.current_segment().put_annotation('total_items_requested', total_requested)
        xray_recorder.current_segment().put_annotation('total_items_available', total_available)
        
        xray_recorder.current_segment().put_metadata('inventory_summary', {
            'order_id': order_id,
            'total_items_requested': total_requested,
            'total_items_available': total_available,
            'fulfillment_rate': total_available / total_requested if total_requested > 0 else 0,
            'lookup_time_ms': lookup_time * 1000,
            'items_processed': len(items),
            'timestamp': time.time()
        })
        
        status_code = 200 if overall_status != 'unavailable' else 409
        
        return {
            'statusCode': status_code,
            'body': json.dumps({
                'status': overall_status,
                'order_id': order_id,
                'items': inventory_results,
                'summary': {
                    'total_requested': total_requested,
                    'total_available': total_available,
                    'fulfillment_rate': round(total_available / total_requested, 2) if total_requested > 0 else 0
                },
                'lookup_time': lookup_time
            })
        }
        
    except Exception as e:
        xray_recorder.current_segment().add_exception(e)
        xray_recorder.current_segment().put_annotation('inventory_status', 'error')
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'error': str(e),
                'order_id': event.get('order_id', 'unknown')
            })
        }
'''
        
        functions['inventory'] = lambda_.Function(
            self, "InventoryService",
            function_name="inventory-service", 
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(inventory_service_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            tracing=lambda_.Tracing.ACTIVE,
            layers=[self.xray_layer],
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            environment={
                "AWS_XRAY_TRACING_NAME": "inventory-service",
                "AWS_XRAY_CONTEXT_MISSING": "LOG_ERROR"
            },
            description="Inventory management service with stock simulation and X-Ray tracing",
        )
        
        return functions

    def _create_vpc_lattice_network(self) -> lattice.CfnServiceNetwork:
        """
        Create VPC Lattice service network for microservices communication
        
        Returns:
            lattice.CfnServiceNetwork: The created service network
        """
        # Create service network
        service_network = lattice.CfnServiceNetwork(
            self, "TracingServiceNetwork",
            name="distributed-tracing-network",
            auth_type="AWS_IAM",
            tags=[
                {"key": "Name", "value": "distributed-tracing-network"},
                {"key": "Purpose", "value": "Microservices mesh with observability"}
            ]
        )
        
        # Associate VPC with service network
        vpc_association = lattice.CfnServiceNetworkVpcAssociation(
            self, "VPCAssociation",
            service_network_identifier=service_network.attr_id,
            vpc_identifier=self.vpc.vpc_id,
            tags=[
                {"key": "Name", "value": "tracing-vpc-association"}
            ]
        )
        
        # Create access log subscription for detailed request logging
        access_log_group = logs.LogGroup(
            self, "LatticeAccessLogs",
            log_group_name="/aws/vpclattice/servicenetwork",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Note: Access log subscription is created via custom resource or AWS CLI
        # as it's not yet supported in CDK constructs
        
        return service_network

    def _create_lattice_services(self) -> Dict[str, lattice.CfnService]:
        """
        Create VPC Lattice services and target groups for Lambda functions
        
        Returns:
            Dict[str, lattice.CfnService]: Dictionary of Lattice services
        """
        services = {}
        
        # Create target group for order service
        order_target_group = lattice.CfnTargetGroup(
            self, "OrderTargetGroup",
            name="order-service-tg",
            type="LAMBDA",
            config=lattice.CfnTargetGroup.TargetGroupConfigProperty(
                health_check=lattice.CfnTargetGroup.HealthCheckConfigProperty(
                    enabled=True,
                    protocol="HTTPS",
                    health_check_interval_seconds=30,
                    health_check_timeout_seconds=5,
                    healthy_threshold_count=2,
                    unhealthy_threshold_count=2,
                    path="/health"
                )
            ),
            targets=[
                lattice.CfnTargetGroup.TargetProperty(
                    id=self.lambda_functions['order'].function_arn
                )
            ],
            tags=[
                {"key": "Name", "value": "order-service-target-group"},
                {"key": "Service", "value": "order"}
            ]
        )
        
        # Create VPC Lattice service for order processing
        order_service = lattice.CfnService(
            self, "OrderLatticeService",
            name="order-service",
            auth_type="AWS_IAM",
            tags=[
                {"key": "Name", "value": "order-service"},
                {"key": "Type", "value": "microservice"}
            ]
        )
        
        # Create listener for the order service
        order_listener = lattice.CfnListener(
            self, "OrderListener",
            service_identifier=order_service.attr_id,
            name="order-listener",
            protocol="HTTPS",
            port=443,
            default_action=lattice.CfnListener.DefaultActionProperty(
                forward=lattice.CfnListener.ForwardProperty(
                    target_groups=[
                        lattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=order_target_group.attr_id,
                            weight=100
                        )
                    ]
                )
            ),
            tags=[
                {"key": "Name", "value": "order-service-listener"}
            ]
        )
        
        # Associate service with service network
        order_service_association = lattice.CfnServiceNetworkServiceAssociation(
            self, "OrderServiceAssociation",
            service_network_identifier=self.service_network.attr_id,
            service_identifier=order_service.attr_id,
            tags=[
                {"key": "Name", "value": "order-service-association"}
            ]
        )
        
        services['order'] = order_service
        
        return services

    def _create_observability_resources(self) -> None:
        """
        Create CloudWatch dashboards and monitoring resources for comprehensive observability
        """
        # Create log groups for Lambda functions
        for service_name, function in self.lambda_functions.items():
            logs.LogGroup(
                self, f"{service_name.title()}ServiceLogs",
                log_group_name=f"/aws/lambda/{function.function_name}",
                retention=logs.RetentionDays.ONE_WEEK,
                removal_policy=RemovalPolicy.DESTROY,
            )
        
        # Create comprehensive CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self, "TracingObservabilityDashboard",
            dashboard_name="Distributed-Service-Tracing-Dashboard",
            widgets=[
                [
                    # VPC Lattice metrics row
                    cloudwatch.GraphWidget(
                        title="VPC Lattice Request Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/VPC-Lattice",
                                metric_name="RequestCount",
                                dimensions_map={
                                    "ServiceNetwork": self.service_network.attr_id
                                },
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/VPC-Lattice", 
                                metric_name="ResponseTime",
                                dimensions_map={
                                    "ServiceNetwork": self.service_network.attr_id
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    # Lambda performance metrics
                    cloudwatch.GraphWidget(
                        title="Lambda Function Performance",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Duration",
                                dimensions_map={
                                    "FunctionName": self.lambda_functions['order'].function_name
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Order Service Duration"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Duration", 
                                dimensions_map={
                                    "FunctionName": self.lambda_functions['payment'].function_name
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                                label="Payment Service Duration"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Duration",
                                dimensions_map={
                                    "FunctionName": self.lambda_functions['inventory'].function_name
                                },
                                statistic="Average", 
                                period=Duration.minutes(5),
                                label="Inventory Service Duration"
                            )
                        ],
                        width=8,
                        height=6
                    ),
                    cloudwatch.GraphWidget(
                        title="Lambda Invocations & Errors",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Invocations",
                                dimensions_map={
                                    "FunctionName": self.lambda_functions['order'].function_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                                label="Order Service Invocations"
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Errors",
                                dimensions_map={
                                    "FunctionName": self.lambda_functions['order'].function_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                                label="Order Service Errors",
                                color=cloudwatch.Color.RED
                            )
                        ],
                        width=4,
                        height=6
                    )
                ],
                [
                    # X-Ray metrics
                    cloudwatch.GraphWidget(
                        title="X-Ray Tracing Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/X-Ray",
                                metric_name="TracesReceived",
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/X-Ray",
                                metric_name="LatencyHigh",
                                dimensions_map={
                                    "ServiceName": "order-service"
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=6,
                        height=6
                    ),
                    cloudwatch.SingleValueWidget(
                        title="Active Traces",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/X-Ray",
                                metric_name="TracesReceived",
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=3,
                        height=6
                    ),
                    cloudwatch.SingleValueWidget(
                        title="Service Error Rate",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/X-Ray",
                                metric_name="ErrorRate",
                                dimensions_map={
                                    "ServiceName": "order-service"
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=3,
                        height=6
                    )
                ]
            ]
        )
        
        # Create CloudWatch alarms for critical metrics
        high_error_rate_alarm = cloudwatch.Alarm(
            self, "HighErrorRateAlarm",
            alarm_name="DistributedTracing-HighErrorRate",
            alarm_description="Alert when Lambda error rate exceeds threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Errors",
                dimensions_map={
                    "FunctionName": self.lambda_functions['order'].function_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        high_latency_alarm = cloudwatch.Alarm(
            self, "HighLatencyAlarm",
            alarm_name="DistributedTracing-HighLatency",
            alarm_description="Alert when service latency is too high",
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Duration",
                dimensions_map={
                    "FunctionName": self.lambda_functions['order'].function_name
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=10000,  # 10 seconds in milliseconds
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource identifiers
        """
        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for the distributed tracing environment",
            export_name="DistributedTracing-VPC-ID"
        )
        
        CfnOutput(
            self, "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="VPC Lattice Service Network ID",
            export_name="DistributedTracing-ServiceNetwork-ID"
        )
        
        CfnOutput(
            self, "OrderServiceArn",
            value=self.lambda_functions['order'].function_arn,
            description="Order Service Lambda Function ARN",
            export_name="DistributedTracing-OrderService-ARN"
        )
        
        CfnOutput(
            self, "PaymentServiceArn", 
            value=self.lambda_functions['payment'].function_arn,
            description="Payment Service Lambda Function ARN",
            export_name="DistributedTracing-PaymentService-ARN"
        )
        
        CfnOutput(
            self, "InventoryServiceArn",
            value=self.lambda_functions['inventory'].function_arn,
            description="Inventory Service Lambda Function ARN",
            export_name="DistributedTracing-InventoryService-ARN"
        )
        
        CfnOutput(
            self, "XRayConsoleURL",
            value=f"https://{self.region}.console.aws.amazon.com/xray/home?region={self.region}#/service-map",
            description="URL to X-Ray Service Map Console",
            export_name="DistributedTracing-XRay-Console-URL"
        )
        
        CfnOutput(
            self, "CloudWatchDashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=Distributed-Service-Tracing-Dashboard",
            description="URL to CloudWatch Observability Dashboard",
            export_name="DistributedTracing-CloudWatch-Dashboard-URL"
        )


def main():
    """
    Main application entry point for CDK deployment
    
    This function creates the CDK app and stack, then synthesizes the CloudFormation template.
    The app can be deployed to any AWS region and account with appropriate permissions.
    """
    app = App()
    
    # Get deployment environment from context or use defaults
    env = Environment(
        account=app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    )
    
    # Create the main stack
    DistributedServiceTracingStack(
        app, "DistributedServiceTracingStack",
        env=env,
        description="Complete distributed service tracing solution with VPC Lattice and X-Ray"
    )
    
    app.synth()


if __name__ == "__main__":
    import os
    main()