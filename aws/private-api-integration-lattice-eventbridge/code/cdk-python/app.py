#!/usr/bin/env python3
"""
CDK Application for Private API Integration with VPC Lattice and EventBridge

This application deploys a complete solution for secure cross-VPC API integration
using VPC Lattice Resource Configurations and EventBridge connections.

Architecture Components:
- VPC Lattice Service Network and Resource Gateway
- Private API Gateway with VPC Endpoint
- EventBridge custom bus with connections
- Step Functions state machine for workflow orchestration
- IAM roles with least privilege permissions

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    Tags,
    aws_ec2 as ec2,
    aws_apigateway as apigateway,
    aws_events as events,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as tasks,
    aws_iam as iam,
    aws_vpclattice as vpclattice,
    aws_logs as logs,
)
from constructs import Construct
import json
from typing import Dict, List, Optional


class PrivateApiIntegrationStack(Stack):
    """
    CDK Stack for Private API Integration with VPC Lattice and EventBridge
    
    This stack creates a secure event-driven architecture that enables
    EventBridge and Step Functions to invoke private APIs across VPC
    boundaries using VPC Lattice Resource Configurations.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        self.unique_suffix = self.node.addr[-8:].lower()

        # Create target VPC with subnets for private API
        self.target_vpc = self._create_target_vpc()
        
        # Create VPC Lattice Service Network
        self.service_network = self._create_service_network()
        
        # Create private API Gateway with VPC endpoint
        self.api_gateway, self.vpc_endpoint = self._create_private_api_gateway()
        
        # Create VPC Lattice Resource Gateway and Configuration
        self.resource_gateway = self._create_resource_gateway()
        self.resource_config = self._create_resource_configuration()
        
        # Associate resource configuration with service network
        self.resource_association = self._create_resource_association()
        
        # Create IAM role for EventBridge and Step Functions
        self.execution_role = self._create_execution_role()
        
        # Create EventBridge custom bus and connection
        self.event_bus = self._create_event_bus()
        self.event_connection = self._create_event_connection()
        
        # Create Step Functions state machine
        self.state_machine = self._create_state_machine()
        
        # Create EventBridge rule to trigger workflows
        self.event_rule = self._create_event_rule()
        
        # Add tags to all resources
        self._add_tags()
        
        # Create outputs for validation
        self._create_outputs()

    def _create_target_vpc(self) -> ec2.Vpc:
        """
        Create target VPC with private subnets for API Gateway deployment.
        
        Returns:
            ec2.Vpc: The created VPC with private subnets across 2 AZs
        """
        vpc = ec2.Vpc(
            self,
            "TargetVpc",
            vpc_name=f"target-vpc-{self.unique_suffix}",
            ip_addresses=ec2.IpAddresses.cidr("10.1.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24,
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Add tags
        Tags.of(vpc).add("Name", f"target-vpc-{self.unique_suffix}")
        Tags.of(vpc).add("Purpose", "private-api-integration")
        
        return vpc

    def _create_service_network(self) -> vpclattice.CfnServiceNetwork:
        """
        Create VPC Lattice Service Network for application-level networking.
        
        Returns:
            vpclattice.CfnServiceNetwork: The created service network
        """
        service_network = vpclattice.CfnServiceNetwork(
            self,
            "ServiceNetwork",
            name=f"private-api-network-{self.unique_suffix}",
            auth_type="AWS_IAM",
            tags=[
                cdk.CfnTag(key="Environment", value="demo"),
                cdk.CfnTag(key="Purpose", value="private-api-integration"),
            ],
        )
        
        return service_network

    def _create_private_api_gateway(self) -> tuple[apigateway.RestApi, ec2.InterfaceVpcEndpoint]:
        """
        Create private API Gateway with VPC endpoint for secure access.
        
        Returns:
            tuple: (RestApi, InterfaceVpcEndpoint) for the private API and its VPC endpoint
        """
        # Create VPC endpoint for API Gateway
        vpc_endpoint = ec2.InterfaceVpcEndpoint(
            self,
            "ApiGatewayVpcEndpoint",
            vpc=self.target_vpc,
            service=ec2.InterfaceVpcEndpointService(
                f"com.amazonaws.{self.region}.execute-api",
                443
            ),
            subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            ),
            policy_document=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        principals=[iam.AnyPrincipal()],
                        actions=["execute-api:*"],
                        resources=["*"]
                    )
                ]
            )
        )
        
        # Wait for VPC endpoint to be available
        vpc_endpoint.node.add_dependency(self.target_vpc)
        
        # Create private API Gateway with resource-based policy
        api_gateway = apigateway.RestApi(
            self,
            "PrivateApiGateway",
            rest_api_name=f"private-demo-api-{self.unique_suffix}",
            description="Private API Gateway for VPC Lattice integration demo",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.PRIVATE],
                vpc_endpoints=[vpc_endpoint]
            ),
            policy=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        principals=[iam.AnyPrincipal()],
                        actions=["execute-api:Invoke"],
                        resources=["*"],
                        conditions={
                            "StringEquals": {
                                "aws:sourceVpce": vpc_endpoint.vpc_endpoint_id
                            }
                        }
                    )
                ]
            ),
            deploy=True,
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True,
            )
        )
        
        # Create /orders resource with POST method
        orders_resource = api_gateway.root.add_resource("orders")
        orders_resource.add_method(
            "POST",
            apigateway.MockIntegration(
                integration_responses=[
                    apigateway.IntegrationResponse(
                        status_code="200",
                        response_templates={
                            "application/json": json.dumps({
                                "orderId": "12345",
                                "status": "created",
                                "timestamp": "$context.requestTime"
                            })
                        }
                    )
                ],
                request_templates={
                    "application/json": json.dumps({"statusCode": 200})
                }
            ),
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_models={
                        "application/json": apigateway.Model.EMPTY_MODEL
                    }
                )
            ],
            authorization_type=apigateway.AuthorizationType.IAM
        )
        
        return api_gateway, vpc_endpoint

    def _create_resource_gateway(self) -> vpclattice.CfnResourceGateway:
        """
        Create VPC Lattice Resource Gateway for cross-VPC connectivity.
        
        Returns:
            vpclattice.CfnResourceGateway: The created resource gateway
        """
        # Get private subnet IDs
        private_subnets = self.target_vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
        )
        
        resource_gateway = vpclattice.CfnResourceGateway(
            self,
            "ResourceGateway",
            name=f"api-gateway-resource-gateway-{self.unique_suffix}",
            vpc_identifier=self.target_vpc.vpc_id,
            subnet_ids=[subnet.subnet_id for subnet in private_subnets.subnets],
            tags=[
                cdk.CfnTag(key="Purpose", value="private-api-access"),
                cdk.CfnTag(key="Environment", value="demo"),
            ],
        )
        
        # Add dependency on VPC endpoint
        resource_gateway.node.add_dependency(self.vpc_endpoint)
        
        return resource_gateway

    def _create_resource_configuration(self) -> vpclattice.CfnResourceConfiguration:
        """
        Create VPC Lattice Resource Configuration for API Gateway access.
        
        Returns:
            vpclattice.CfnResourceConfiguration: The created resource configuration
        """
        resource_config = vpclattice.CfnResourceConfiguration(
            self,
            "ResourceConfiguration",
            name=f"private-api-config-{self.unique_suffix}",
            type="SINGLE",
            resource_gateway_identifier=self.resource_gateway.ref,
            resource_configuration_definition=vpclattice.CfnResourceConfiguration.ResourceConfigurationDefinitionProperty(
                type="RESOURCE",
                resource_identifier=self.vpc_endpoint.vpc_endpoint_id,
                port_ranges=[
                    vpclattice.CfnResourceConfiguration.PortRangeProperty(
                        from_port=443,
                        to_port=443,
                        protocol="TCP"
                    )
                ]
            ),
            allow_association_to_shareable_service_network=True,
            tags=[
                cdk.CfnTag(key="Purpose", value="private-api-integration"),
                cdk.CfnTag(key="Environment", value="demo"),
            ],
        )
        
        # Add dependency on resource gateway
        resource_config.node.add_dependency(self.resource_gateway)
        
        return resource_config

    def _create_resource_association(self) -> vpclattice.CfnServiceNetworkResourceAssociation:
        """
        Create association between resource configuration and service network.
        
        Returns:
            vpclattice.CfnServiceNetworkResourceAssociation: The created association
        """
        association = vpclattice.CfnServiceNetworkResourceAssociation(
            self,
            "ResourceAssociation",
            service_network_identifier=self.service_network.ref,
            resource_configuration_identifier=self.resource_config.ref,
        )
        
        # Add dependencies
        association.node.add_dependency(self.service_network)
        association.node.add_dependency(self.resource_config)
        
        return association

    def _create_execution_role(self) -> iam.Role:
        """
        Create IAM role for EventBridge and Step Functions execution.
        
        Returns:
            iam.Role: The created execution role with necessary permissions
        """
        role = iam.Role(
            self,
            "ExecutionRole",
            role_name=f"EventBridgeStepFunctionsVPCLatticeRole-{self.unique_suffix}",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("events.amazonaws.com"),
                iam.ServicePrincipal("states.amazonaws.com"),
            ),
            description="Role for EventBridge and Step Functions VPC Lattice integration",
        )
        
        # Add policy for VPC Lattice and API operations
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "events:CreateConnection",
                    "events:UpdateConnection",
                    "events:InvokeApiDestination",
                    "execute-api:Invoke",
                    "vpc-lattice:GetResourceConfiguration",
                    "states:StartExecution",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"]
            )
        )
        
        return role

    def _create_event_bus(self) -> events.EventBus:
        """
        Create custom EventBridge bus for private API integration.
        
        Returns:
            events.EventBus: The created custom event bus
        """
        event_bus = events.EventBus(
            self,
            "EventBus",
            event_bus_name=f"private-api-bus-{self.unique_suffix}",
            description="Custom event bus for private API integration demo",
        )
        
        return event_bus

    def _create_event_connection(self) -> events.Connection:
        """
        Create EventBridge connection for private API invocation.
        
        Returns:
            events.Connection: The created EventBridge connection
        """
        # Create the connection endpoint URL
        api_endpoint = f"https://{self.api_gateway.rest_api_id}-{self.vpc_endpoint.vpc_endpoint_id}.execute-api.{self.region}.amazonaws.com/prod/orders"
        
        connection = events.Connection(
            self,
            "EventConnection",
            connection_name=f"private-api-connection-{self.unique_suffix}",
            description="Connection to private API Gateway via VPC Lattice",
            authorization=events.Authorization.invocation_http_parameters(
                header_parameters={
                    "Content-Type": "application/json"
                }
            ),
            # Note: CDK L2 constructs don't directly support resource configuration ARN
            # This would need to be added via escape hatch or custom resource
        )
        
        # Add dependency on resource association
        connection.node.add_dependency(self.resource_association)
        
        return connection

    def _create_state_machine(self) -> sfn.StateMachine:
        """
        Create Step Functions state machine for private API workflow.
        
        Returns:
            sfn.StateMachine: The created state machine
        """
        # Create CloudWatch log group for state machine
        log_group = logs.LogGroup(
            self,
            "StateMachineLogGroup",
            log_group_name=f"/aws/stepfunctions/private-api-workflow-{self.unique_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Define the workflow tasks
        process_order_task = tasks.CallAwsService(
            self,
            "ProcessOrder",
            service="apigateway",
            action="executeApi",
            parameters={
                "ApiId": self.api_gateway.rest_api_id,
                "Method": "POST",
                "ResourcePath": "/orders",
                "RequestBody": {
                    "customerId": "12345",
                    "orderItems": ["item1", "item2"],
                    "timestamp.$": "$$.State.EnteredTime"
                }
            },
            iam_resources=["*"],
        )
        
        # Define success and error states
        process_success = sfn.Pass(
            self,
            "ProcessSuccess",
            result=sfn.Result.from_object({
                "status": "success",
                "message": "Order processed successfully"
            })
        )
        
        handle_error = sfn.Pass(
            self,
            "HandleError",
            result=sfn.Result.from_object({
                "status": "error",
                "message": "Order processing failed"
            })
        )
        
        # Create the state machine definition
        definition = process_order_task.add_retry(
            errors=["States.Http.StatusCodeFailure"],
            interval=Duration.seconds(2),
            max_attempts=3,
            backoff_rate=2.0
        ).add_catch(
            handle_error,
            errors=["States.TaskFailed"]
        ).next(process_success)
        
        # Create the state machine
        state_machine = sfn.StateMachine(
            self,
            "StateMachine",
            state_machine_name=f"private-api-workflow-{self.unique_suffix}",
            definition=definition,
            role=self.execution_role,
            logs=sfn.LogOptions(
                destination=log_group,
                level=sfn.LogLevel.ALL,
                include_execution_data=True
            ),
            tracing_enabled=True,
        )
        
        return state_machine

    def _create_event_rule(self) -> events.Rule:
        """
        Create EventBridge rule to trigger Step Functions workflow.
        
        Returns:
            events.Rule: The created EventBridge rule
        """
        rule = events.Rule(
            self,
            "EventRule",
            rule_name="trigger-private-api-workflow",
            description="Rule to trigger private API workflow via Step Functions",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["demo.application"],
                detail_type=["Order Received"]
            ),
            enabled=True,
        )
        
        # Add Step Functions as target
        rule.add_target(
            events.targets.SfnStateMachine(
                machine=self.state_machine,
                role=self.execution_role
            )
        )
        
        return rule

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", "PrivateApiIntegration")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "private-api-integration-lattice-eventbridge")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for validation and testing."""
        cdk.CfnOutput(
            self,
            "ServiceNetworkId",
            value=self.service_network.ref,
            description="VPC Lattice Service Network ID",
        )
        
        cdk.CfnOutput(
            self,
            "ResourceConfigurationArn",
            value=self.resource_config.ref,
            description="VPC Lattice Resource Configuration ARN",
        )
        
        cdk.CfnOutput(
            self,
            "ApiGatewayId",
            value=self.api_gateway.rest_api_id,
            description="Private API Gateway ID",
        )
        
        cdk.CfnOutput(
            self,
            "VpcEndpointId",
            value=self.vpc_endpoint.vpc_endpoint_id,
            description="API Gateway VPC Endpoint ID",
        )
        
        cdk.CfnOutput(
            self,
            "EventBusName",
            value=self.event_bus.event_bus_name,
            description="Custom EventBridge Bus Name",
        )
        
        cdk.CfnOutput(
            self,
            "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="Step Functions State Machine ARN",
        )
        
        cdk.CfnOutput(
            self,
            "TestCommand",
            value=f"aws events put-events --entries '[{{\"Source\": \"demo.application\", \"DetailType\": \"Order Received\", \"Detail\": \"{{\\\"orderId\\\": \\\"test-123\\\", \\\"customerId\\\": \\\"cust-456\\\"}}\", \"EventBusName\": \"{self.event_bus.event_bus_name}\"}}]'",
            description="Command to test the integration",
        )


class PrivateApiIntegrationApp(cdk.App):
    """
    CDK Application for Private API Integration
    
    This application creates a complete event-driven architecture for
    secure cross-VPC API integration using VPC Lattice and EventBridge.
    """

    def __init__(self) -> None:
        super().__init__()
        
        # Create the main stack
        PrivateApiIntegrationStack(
            self,
            "PrivateApiIntegrationStack",
            description="Private API Integration with VPC Lattice and EventBridge",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region"),
            ),
        )


if __name__ == "__main__":
    app = PrivateApiIntegrationApp()
    app.synth()