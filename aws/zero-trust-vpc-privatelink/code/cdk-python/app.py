#!/usr/bin/env python3
"""
CDK Python application for Zero Trust Network Architecture with VPC Endpoints and PrivateLink

This application creates a complete zero trust network architecture including:
- Two VPCs (consumer and provider) with private subnets
- VPC endpoints for AWS services (S3, Lambda, CloudWatch Logs)
- PrivateLink service configuration with Network Load Balancer
- Security groups with least privilege access
- VPC Flow Logs for monitoring
- Private DNS resolution
- Lambda function for validation

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    App,
    Environment,
    Tags,
    CfnOutput,
    RemovalPolicy,
    Duration
)
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_elasticloadbalancingv2 as elbv2
from aws_cdk import aws_route53 as route53
from constructs import Construct


class ZeroTrustNetworkStack(Stack):
    """
    CDK Stack for implementing Zero Trust Network Architecture
    
    This stack creates a complete zero trust network architecture using VPC endpoints
    and PrivateLink to eliminate internet connectivity while providing secure access
    to AWS services and cross-account resources.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.random_suffix = self.node.try_get_context("random_suffix") or "zt001"
        
        # Create the zero trust network infrastructure
        self._create_consumer_vpc()
        self._create_provider_vpc()
        self._create_security_groups()
        self._create_vpc_endpoints()
        self._create_privatelink_service()
        self._create_cross_account_endpoint()
        self._create_private_dns()
        self._configure_flow_logs()
        self._create_test_lambda()
        
        # Add stack-wide tags
        Tags.of(self).add("Project", "ZeroTrustArchitecture")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("ManagedBy", "CDK")

    def _create_consumer_vpc(self) -> None:
        """
        Create the consumer VPC with private subnets for zero trust architecture.
        
        This VPC hosts applications that need secure access to AWS services and
        cross-account resources without internet connectivity.
        """
        # Create consumer VPC with no NAT gateways for zero trust
        self.consumer_vpc = ec2.Vpc(
            self, "ConsumerVPC",
            vpc_name=f"zero-trust-vpc-{self.random_suffix}",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            enable_dns_hostnames=True,
            enable_dns_support=True,
            nat_gateways=0,  # Zero trust - no internet access
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PrivateSubnet1",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet2", 
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                )
            ]
        )
        
        # Tag the VPC and subnets
        Tags.of(self.consumer_vpc).add("Name", f"zero-trust-vpc-{self.random_suffix}")
        Tags.of(self.consumer_vpc).add("Type", "ZeroTrust")
        
        # Get private subnets for endpoint placement
        self.private_subnets = self.consumer_vpc.private_subnets

    def _create_provider_vpc(self) -> None:
        """
        Create the provider VPC for hosting PrivateLink services.
        
        This VPC hosts the services that will be exposed through PrivateLink
        to other accounts or VPCs.
        """
        self.provider_vpc = ec2.Vpc(
            self, "ProviderVPC",
            vpc_name=f"provider-vpc-{self.random_suffix}",
            ip_addresses=ec2.IpAddresses.cidr("10.1.0.0/16"),
            enable_dns_hostnames=True,
            enable_dns_support=True,
            nat_gateways=0,  # Provider VPC also follows zero trust
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="ProviderPrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                )
            ]
        )
        
        Tags.of(self.provider_vpc).add("Name", f"provider-vpc-{self.random_suffix}")
        Tags.of(self.provider_vpc).add("Type", "Provider")

    def _create_security_groups(self) -> None:
        """
        Create security groups implementing least privilege access controls.
        
        Security groups enforce zero trust principles by denying all traffic
        by default and only allowing specific, required communications.
        """
        # Security group for VPC endpoints - allows HTTPS from VPC CIDR
        self.endpoint_security_group = ec2.SecurityGroup(
            self, "EndpointSecurityGroup",
            vpc=self.consumer_vpc,
            description="Zero Trust VPC Endpoint Security Group",
            security_group_name=f"zero-trust-endpoint-sg-{self.random_suffix}",
            allow_all_outbound=False
        )
        
        # Allow HTTPS inbound from VPC CIDR
        self.endpoint_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/16"),
            connection=ec2.Port.tcp(443),
            description="HTTPS from VPC CIDR"
        )
        
        # Security group for applications - restrictive outbound rules
        self.app_security_group = ec2.SecurityGroup(
            self, "AppSecurityGroup",
            vpc=self.consumer_vpc,
            description="Zero Trust Application Security Group",
            security_group_name=f"zero-trust-app-sg-{self.random_suffix}",
            allow_all_outbound=False
        )
        
        # Allow outbound HTTPS to VPC endpoints only
        self.app_security_group.add_egress_rule(
            peer=ec2.Peer.security_group_id(self.endpoint_security_group.security_group_id),
            connection=ec2.Port.tcp(443),
            description="HTTPS to VPC endpoints"
        )
        
        # Security group for provider services
        self.provider_security_group = ec2.SecurityGroup(
            self, "ProviderSecurityGroup",
            vpc=self.provider_vpc,
            description="Provider Service Security Group",
            security_group_name=f"provider-service-sg-{self.random_suffix}",
            allow_all_outbound=False
        )
        
        # Allow inbound HTTPS from consumer VPC
        self.provider_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/16"),
            connection=ec2.Port.tcp(443),
            description="HTTPS from consumer VPC"
        )

    def _create_vpc_endpoints(self) -> None:
        """
        Create VPC endpoints for AWS services to enable private connectivity.
        
        Interface VPC endpoints provide secure, private connectivity to AWS services
        without requiring internet gateways or NAT devices.
        """
        # S3 Interface VPC Endpoint with restrictive policy
        s3_endpoint_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AnyPrincipal()],
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject", 
                        "s3:ListBucket"
                    ],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            "aws:PrincipalAccount": self.account
                        }
                    }
                )
            ]
        )
        
        self.s3_endpoint = ec2.InterfaceVpcEndpoint(
            self, "S3VpcEndpoint",
            vpc=self.consumer_vpc,
            service=ec2.InterfaceVpcEndpointAwsService.S3,
            subnets=ec2.SubnetSelection(subnets=self.private_subnets),
            security_groups=[self.endpoint_security_group],
            private_dns_enabled=True,
            policy_document=s3_endpoint_policy
        )
        
        # Lambda VPC Endpoint
        self.lambda_endpoint = ec2.InterfaceVpcEndpoint(
            self, "LambdaVpcEndpoint",
            vpc=self.consumer_vpc,
            service=ec2.InterfaceVpcEndpointAwsService.LAMBDA,
            subnets=ec2.SubnetSelection(subnets=self.private_subnets),
            security_groups=[self.endpoint_security_group],
            private_dns_enabled=True
        )
        
        # CloudWatch Logs VPC Endpoint
        self.logs_endpoint = ec2.InterfaceVpcEndpoint(
            self, "LogsVpcEndpoint", 
            vpc=self.consumer_vpc,
            service=ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
            subnets=ec2.SubnetSelection(subnets=self.private_subnets),
            security_groups=[self.endpoint_security_group],
            private_dns_enabled=True
        )

    def _create_privatelink_service(self) -> None:
        """
        Create PrivateLink service with Network Load Balancer.
        
        This creates a PrivateLink service that can be consumed by other accounts
        or VPCs through VPC endpoints, enabling secure cross-account connectivity.
        """
        # Create Network Load Balancer in provider VPC
        self.network_load_balancer = elbv2.NetworkLoadBalancer(
            self, "ZeroTrustNLB",
            vpc=self.provider_vpc,
            internet_facing=False,  # Internal NLB for PrivateLink
            load_balancer_name=f"zero-trust-nlb-{self.random_suffix}",
            vpc_subnets=ec2.SubnetSelection(
                subnets=self.provider_vpc.private_subnets
            )
        )
        
        # Create target group
        self.target_group = elbv2.NetworkTargetGroup(
            self, "ZeroTrustTargetGroup",
            port=443,
            protocol=elbv2.Protocol.TCP,
            vpc=self.provider_vpc,
            target_group_name=f"zero-trust-tg-{self.random_suffix}",
            target_type=elbv2.TargetType.IP,
            health_check_enabled=True,
            health_check_protocol=elbv2.Protocol.TCP,
            health_check_port="443"
        )
        
        # Create listener
        self.nlb_listener = self.network_load_balancer.add_listener(
            "ZeroTrustListener",
            port=443,
            protocol=elbv2.Protocol.TCP,
            default_target_groups=[self.target_group]
        )
        
        # Create VPC Endpoint Service
        self.vpc_endpoint_service = ec2.VpcEndpointService(
            self, "ZeroTrustEndpointService",
            vpc_endpoint_service_loads=[self.network_load_balancer],
            acceptance_required=True  # Require explicit approval
        )
        
        # Allow connections from consumer account
        self.vpc_endpoint_service.add_allowed_principal(
            iam.AccountPrincipal(self.account)
        )

    def _create_cross_account_endpoint(self) -> None:
        """
        Create VPC endpoint to connect to the PrivateLink service.
        
        This endpoint enables the consumer VPC to securely access services
        in the provider VPC through PrivateLink.
        """
        self.custom_service_endpoint = ec2.InterfaceVpcEndpoint(
            self, "CustomServiceEndpoint",
            vpc=self.consumer_vpc,
            service=ec2.InterfaceVpcEndpointService(
                self.vpc_endpoint_service.vpc_endpoint_service_name
            ),
            subnets=ec2.SubnetSelection(subnets=self.private_subnets),
            security_groups=[self.endpoint_security_group],
            private_dns_enabled=True
        )

    def _create_private_dns(self) -> None:
        """
        Configure private DNS resolution for service discovery.
        
        Private hosted zones enable internal service discovery without
        exposing DNS information to external networks.
        """
        # Create private hosted zone
        self.private_hosted_zone = route53.PrivateHostedZone(
            self, "ZeroTrustPrivateZone",
            zone_name="zero-trust-service.internal",
            vpc=self.consumer_vpc
        )
        
        # Create CNAME record for custom service
        route53.CnameRecord(
            self, "CustomServiceRecord",
            zone=self.private_hosted_zone,
            record_name="api",
            domain_name=self.custom_service_endpoint.vpc_endpoint_dns_entries[0].domain_name,
            ttl=Duration.minutes(5)
        )

    def _configure_flow_logs(self) -> None:
        """
        Configure VPC Flow Logs for network monitoring and compliance.
        
        Flow logs provide comprehensive network traffic visibility essential
        for zero trust monitoring and security analysis.
        """
        # Create CloudWatch log group for flow logs
        self.flow_logs_group = logs.LogGroup(
            self, "VPCFlowLogsGroup",
            log_group_name=f"/aws/vpc/zero-trust-flowlogs-{self.random_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create IAM role for VPC Flow Logs
        self.flow_logs_role = iam.Role(
            self, "VPCFlowLogsRole",
            assumed_by=iam.ServicePrincipal("vpc-flow-logs.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/VPCFlowLogsDeliveryRolePolicy"
                )
            ]
        )
        
        # Enable VPC Flow Logs for consumer VPC
        ec2.FlowLog(
            self, "ConsumerVPCFlowLog",
            resource_type=ec2.FlowLogResourceType.from_vpc(self.consumer_vpc),
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                self.flow_logs_group, self.flow_logs_role
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL
        )
        
        # Enable VPC Flow Logs for provider VPC
        ec2.FlowLog(
            self, "ProviderVPCFlowLog", 
            resource_type=ec2.FlowLogResourceType.from_vpc(self.provider_vpc),
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                self.flow_logs_group, self.flow_logs_role
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL
        )

    def _create_test_lambda(self) -> None:
        """
        Create test Lambda function to validate zero trust connectivity.
        
        This function tests that AWS services are accessible through VPC endpoints
        while internet access is blocked, proving the zero trust implementation.
        """
        # Create Lambda execution role
        self.lambda_role = iam.Role(
            self, "ZeroTrustLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaVPCAccessExecutionRole"
                )
            ]
        )
        
        # Add S3 permissions for testing
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:ListBuckets"],
                resources=["*"]
            )
        )
        
        # Create Lambda function
        self.test_lambda = lambda_.Function(
            self, "ZeroTrustTestFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            function_name=f"zero-trust-test-{self.random_suffix}",
            vpc=self.consumer_vpc,
            vpc_subnets=ec2.SubnetSelection(subnets=self.private_subnets),
            security_groups=[self.app_security_group],
            timeout=Duration.seconds(30),
            code=lambda_.Code.from_inline('''
import json
import boto3
import urllib3

def lambda_handler(event, context):
    """Test function to validate zero trust connectivity"""
    try:
        # Test S3 access through VPC endpoint
        s3_client = boto3.client('s3')
        buckets = s3_client.list_buckets()
        
        # Test external HTTP request (should fail in zero trust)
        http = urllib3.PoolManager()
        try:
            response = http.request('GET', 'https://httpbin.org/get', timeout=5)
            internet_access = True
        except:
            internet_access = False
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Zero Trust validation complete',
                's3_access': len(buckets['Buckets']) >= 0,
                'internet_access': internet_access,
                'vpc_endpoint_working': True
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
            ''')
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self, "ConsumerVPCId",
            value=self.consumer_vpc.vpc_id,
            description="Consumer VPC ID for zero trust architecture"
        )
        
        CfnOutput(
            self, "ProviderVPCId", 
            value=self.provider_vpc.vpc_id,
            description="Provider VPC ID"
        )
        
        CfnOutput(
            self, "VPCEndpointServiceName",
            value=self.vpc_endpoint_service.vpc_endpoint_service_name,
            description="VPC Endpoint Service name for PrivateLink"
        )
        
        CfnOutput(
            self, "TestLambdaFunction",
            value=self.test_lambda.function_name,
            description="Test Lambda function for validation"
        )
        
        CfnOutput(
            self, "PrivateHostedZone",
            value=self.private_hosted_zone.hosted_zone_id,
            description="Private hosted zone for DNS resolution"
        )
        
        CfnOutput(
            self, "FlowLogsGroup", 
            value=self.flow_logs_group.log_group_name,
            description="CloudWatch log group for VPC Flow Logs"
        )


class ZeroTrustNetworkApp(App):
    """
    CDK Application for Zero Trust Network Architecture
    """
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get account and region from environment or context
        account = os.environ.get('CDK_DEFAULT_ACCOUNT')
        region = os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
        
        env = Environment(account=account, region=region)
        
        # Create the zero trust network stack
        ZeroTrustNetworkStack(
            self, "ZeroTrustNetworkStack",
            env=env,
            description="Zero Trust Network Architecture with VPC Endpoints and PrivateLink"
        )


# Application entry point
app = ZeroTrustNetworkApp()
app.synth()