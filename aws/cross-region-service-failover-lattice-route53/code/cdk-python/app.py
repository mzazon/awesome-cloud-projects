#!/usr/bin/env python3
"""
CDK Application for Cross-Region Service Failover with VPC Lattice and Route53

This application creates a resilient multi-region microservices architecture using 
VPC Lattice service networks and Route53 health checks for DNS-based failover.

The solution includes:
- VPC Lattice service networks in primary and secondary regions
- Lambda functions as health check endpoints
- Route53 health checks and DNS failover configuration
- CloudWatch monitoring and alarms
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_route53 as route53,
    aws_route53_resolver as route53resolver,
    aws_cloudwatch as cloudwatch,
    aws_ec2 as ec2,
    aws_vpclattice as vpclattice,
    aws_logs as logs,
)
from constructs import Construct


class CrossRegionFailoverStack(Stack):
    """
    CDK Stack for Cross-Region Service Failover with VPC Lattice and Route53
    
    This stack creates the infrastructure for a cross-region failover solution
    including VPC Lattice services, Lambda health check endpoints, and Route53
    DNS failover configuration.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        region_type: str,
        domain_name: str,
        random_suffix: str,
        vpc_cidr: str = None,
        **kwargs
    ) -> None:
        """
        Initialize the Cross-Region Failover Stack
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            region_type: Either "primary" or "secondary" to indicate region role
            domain_name: Domain name for DNS failover configuration
            random_suffix: Random suffix for unique resource naming
            vpc_cidr: CIDR block for VPC (optional, defaults based on region type)
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.region_type = region_type
        self.domain_name = domain_name
        self.random_suffix = random_suffix
        
        # Set default VPC CIDR based on region type
        if vpc_cidr is None:
            vpc_cidr = "10.0.0.0/16" if region_type == "primary" else "10.1.0.0/16"
        
        # Create foundational VPC infrastructure
        self.vpc = self._create_vpc(vpc_cidr)
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda health check function
        self.health_check_function = self._create_health_check_function()
        
        # Create VPC Lattice infrastructure
        self.service_network = self._create_service_network()
        self.target_group = self._create_target_group()
        self.lattice_service = self._create_lattice_service()
        self.service_association = self._create_service_network_association()
        
        # Create Route53 health check
        self.health_check = self._create_route53_health_check()
        
        # Create CloudWatch monitoring
        self._create_cloudwatch_monitoring()
        
        # Add tags to all resources
        self._add_tags()
        
        # Create outputs for cross-stack references
        self._create_outputs()

    def _create_vpc(self, vpc_cidr: str) -> ec2.Vpc:
        """Create VPC with appropriate configuration for VPC Lattice"""
        vpc = ec2.Vpc(
            self,
            "VPC",
            ip_addresses=ec2.IpAddresses.cidr(vpc_cidr),
            max_azs=2,
            nat_gateways=0,  # No NAT gateways needed for this use case
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Add VPC endpoint for Lambda (required for VPC Lattice integration)
        vpc.add_interface_endpoint(
            "LambdaEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.LAMBDA,
            subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            ),
        )
        
        return vpc

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda health check functions"""
        role = iam.Role(
            self,
            "LambdaHealthCheckRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description=f"IAM role for Lambda health check functions in {self.region_type} region",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaVPCAccessExecutionRole"
                ),
            ],
        )
        
        # Add permissions for CloudWatch metrics
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"],
            )
        )
        
        return role

    def _create_health_check_function(self) -> lambda_.Function:
        """Create Lambda function for health check endpoint"""
        
        # Lambda function code
        function_code = '''
import json
import os
import time
from datetime import datetime

def lambda_handler(event, context):
    """
    Health check endpoint that validates service availability
    Returns HTTP 200 for healthy, 503 for unhealthy
    """
    region = os.environ.get('AWS_REGION', 'unknown')
    region_type = os.environ.get('REGION_TYPE', 'unknown')
    simulate_failure = os.environ.get('SIMULATE_FAILURE', 'false').lower()
    
    try:
        current_time = datetime.utcnow().isoformat()
        
        # Check for simulated failure from environment variable
        if simulate_failure == 'true':
            health_status = False
        else:
            # Add actual health validation logic here
            # Example: Check database connectivity, external APIs, etc.
            health_status = check_service_health()
        
        if health_status:
            response = {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'X-Health-Check': 'pass',
                    'X-Region-Type': region_type
                },
                'body': json.dumps({
                    'status': 'healthy',
                    'region': region,
                    'region_type': region_type,
                    'timestamp': current_time,
                    'version': '1.0'
                })
            }
        else:
            response = {
                'statusCode': 503,
                'headers': {
                    'Content-Type': 'application/json',
                    'X-Health-Check': 'fail',
                    'X-Region-Type': region_type
                },
                'body': json.dumps({
                    'status': 'unhealthy',
                    'region': region,
                    'region_type': region_type,
                    'timestamp': current_time
                })
            }
            
        return response
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'status': 'error',
                'message': str(e),
                'region': region,
                'region_type': region_type
            })
        }

def check_service_health():
    """
    Implement actual health check logic
    Returns True if healthy, False otherwise
    """
    # Example health checks:
    # - Database connectivity
    # - External API availability
    # - Cache service status
    # - Disk space checks
    # - Custom business logic validation
    
    # For demonstration, always return healthy
    # In production, implement actual health validation
    return True
'''
        
        function = lambda_.Function(
            self,
            "HealthCheckFunction",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            timeout=cdk.Duration.seconds(30),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "REGION_TYPE": self.region_type,
                "SIMULATE_FAILURE": "false",
            },
            description=f"Health check endpoint for {self.region_type} region",
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        return function

    def _create_service_network(self) -> vpclattice.CfnServiceNetwork:
        """Create VPC Lattice service network"""
        service_network = vpclattice.CfnServiceNetwork(
            self,
            "ServiceNetwork",
            name=f"microservices-network-{self.random_suffix}",
            tags=[
                cdk.CfnTag(key="Environment", value="production"),
                cdk.CfnTag(key="Region", value=self.region_type),
                cdk.CfnTag(key="Purpose", value="CrossRegionFailover"),
            ],
        )
        
        return service_network

    def _create_target_group(self) -> vpclattice.CfnTargetGroup:
        """Create VPC Lattice target group for Lambda function"""
        target_group = vpclattice.CfnTargetGroup(
            self,
            "TargetGroup",
            name=f"health-check-targets-{self.region_type}-{self.random_suffix}",
            type="LAMBDA",
            targets=[
                vpclattice.CfnTargetGroup.TargetProperty(
                    id=self.health_check_function.function_arn
                )
            ],
            config=vpclattice.CfnTargetGroup.TargetGroupConfigProperty(
                health_check=vpclattice.CfnTargetGroup.HealthCheckConfigProperty(
                    enabled=True,
                    health_check_interval_seconds=30,
                    health_check_timeout_seconds=5,
                    healthy_threshold_count=2,
                    unhealthy_threshold_count=3,
                    path="/",
                    protocol="HTTPS",
                    protocol_version="HTTP1",
                )
            ),
            tags=[
                cdk.CfnTag(key="Environment", value="production"),
                cdk.CfnTag(key="Region", value=self.region_type),
            ],
        )
        
        return target_group

    def _create_lattice_service(self) -> vpclattice.CfnService:
        """Create VPC Lattice service with listener"""
        # Create the service
        service = vpclattice.CfnService(
            self,
            "LatticeService",
            name=f"api-service-{self.region_type}-{self.random_suffix}",
            tags=[
                cdk.CfnTag(key="Environment", value="production"),
                cdk.CfnTag(key="Region", value=self.region_type),
            ],
        )
        
        # Create listener for the service
        listener = vpclattice.CfnListener(
            self,
            "ServiceListener",
            name="health-check-listener",
            protocol="HTTPS",
            port=443,
            service_identifier=service.ref,
            default_action=vpclattice.CfnListener.DefaultActionProperty(
                forward=vpclattice.CfnListener.ForwardProperty(
                    target_groups=[
                        vpclattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=self.target_group.ref,
                            weight=100,
                        )
                    ]
                )
            ),
            tags=[
                cdk.CfnTag(key="Environment", value="production"),
                cdk.CfnTag(key="Region", value=self.region_type),
            ],
        )
        
        # Add dependency to ensure target group is created first
        listener.add_dependency(self.target_group)
        
        return service

    def _create_service_network_association(self) -> vpclattice.CfnServiceNetworkServiceAssociation:
        """Associate service with service network"""
        association = vpclattice.CfnServiceNetworkServiceAssociation(
            self,
            "ServiceNetworkAssociation",
            service_identifier=self.lattice_service.ref,
            service_network_identifier=self.service_network.ref,
            tags=[
                cdk.CfnTag(key="Environment", value="production"),
                cdk.CfnTag(key="Region", value=self.region_type),
            ],
        )
        
        return association

    def _create_route53_health_check(self) -> route53.CfnHealthCheck:
        """Create Route53 health check for the VPC Lattice service"""
        health_check = route53.CfnHealthCheck(
            self,
            "HealthCheck",
            type="HTTPS",
            resource_path="/",
            fully_qualified_domain_name=self.lattice_service.attr_dns_entry_domain_name,
            port=443,
            request_interval=30,
            failure_threshold=3,
            tags=[
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Name",
                    value=f"{self.region_type}-service-health",
                ),
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Region",
                    value=self.region_type,
                ),
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Environment",
                    value="production",
                ),
            ],
        )
        
        return health_check

    def _create_cloudwatch_monitoring(self) -> None:
        """Create CloudWatch alarms for health check monitoring"""
        alarm = cloudwatch.Alarm(
            self,
            "ServiceHealthAlarm",
            alarm_name=f"{self.region_type.title()}-Service-Health-{self.random_suffix}",
            alarm_description=f"Monitor {self.region_type} region service health",
            metric=cloudwatch.Metric(
                namespace="AWS/Route53",
                metric_name="HealthCheckStatus",
                dimensions_map={
                    "HealthCheckId": self.health_check.ref,
                },
                statistic="Minimum",
                period=cdk.Duration.minutes(1),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING,
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack"""
        Tags.of(self).add("Project", "CrossRegionFailover")
        Tags.of(self).add("Environment", "production")
        Tags.of(self).add("Region", self.region_type)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "cross-region-service-failover-lattice-route53")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for cross-stack references"""
        cdk.CfnOutput(
            self,
            "ServiceNetworkId",
            value=self.service_network.ref,
            description=f"VPC Lattice Service Network ID for {self.region_type} region",
            export_name=f"ServiceNetwork-{self.region_type}-{self.random_suffix}",
        )
        
        cdk.CfnOutput(
            self,
            "ServiceId",
            value=self.lattice_service.ref,
            description=f"VPC Lattice Service ID for {self.region_type} region",
            export_name=f"LatticeService-{self.region_type}-{self.random_suffix}",
        )
        
        cdk.CfnOutput(
            self,
            "ServiceDNS",
            value=self.lattice_service.attr_dns_entry_domain_name,
            description=f"VPC Lattice Service DNS name for {self.region_type} region",
            export_name=f"ServiceDNS-{self.region_type}-{self.random_suffix}",
        )
        
        cdk.CfnOutput(
            self,
            "HealthCheckId",
            value=self.health_check.ref,
            description=f"Route53 Health Check ID for {self.region_type} region",
            export_name=f"HealthCheck-{self.region_type}-{self.random_suffix}",
        )
        
        cdk.CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.health_check_function.function_arn,
            description=f"Lambda function ARN for {self.region_type} region",
            export_name=f"HealthCheckFunction-{self.region_type}-{self.random_suffix}",
        )


class Route53FailoverStack(Stack):
    """
    Stack for Route53 DNS failover configuration
    
    This stack creates the Route53 hosted zone and DNS records
    with failover routing policy. It depends on the CrossRegionFailoverStack
    outputs from both regions.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        domain_name: str,
        random_suffix: str,
        primary_service_dns: str,
        secondary_service_dns: str,
        primary_health_check_id: str,
        **kwargs
    ) -> None:
        """
        Initialize the Route53 Failover Stack
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            domain_name: Domain name for DNS configuration
            random_suffix: Random suffix for unique resource naming
            primary_service_dns: DNS name of primary region service
            secondary_service_dns: DNS name of secondary region service
            primary_health_check_id: Health check ID for primary region
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.domain_name = domain_name
        self.random_suffix = random_suffix
        
        # Create hosted zone
        self.hosted_zone = self._create_hosted_zone()
        
        # Create DNS records with failover routing
        self._create_failover_records(
            primary_service_dns,
            secondary_service_dns,
            primary_health_check_id,
        )
        
        # Add tags
        self._add_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_hosted_zone(self) -> route53.HostedZone:
        """Create Route53 hosted zone"""
        hosted_zone = route53.HostedZone(
            self,
            "HostedZone",
            zone_name=self.domain_name,
            comment=f"Hosted zone for cross-region failover demo - {self.random_suffix}",
        )
        
        return hosted_zone

    def _create_failover_records(
        self,
        primary_service_dns: str,
        secondary_service_dns: str,
        primary_health_check_id: str,
    ) -> None:
        """Create DNS records with failover routing policy"""
        
        # Primary record with health check
        route53.CfnRecordSet(
            self,
            "PrimaryFailoverRecord",
            hosted_zone_id=self.hosted_zone.hosted_zone_id,
            name=self.domain_name,
            type="CNAME",
            set_identifier="primary",
            failover="PRIMARY",
            ttl=60,
            resource_records=[primary_service_dns],
            health_check_id=primary_health_check_id,
        )
        
        # Secondary record (no health check needed for secondary)
        route53.CfnRecordSet(
            self,
            "SecondaryFailoverRecord",
            hosted_zone_id=self.hosted_zone.hosted_zone_id,
            name=self.domain_name,
            type="CNAME",
            set_identifier="secondary",
            failover="SECONDARY",
            ttl=60,
            resource_records=[secondary_service_dns],
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack"""
        Tags.of(self).add("Project", "CrossRegionFailover")
        Tags.of(self).add("Environment", "production")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "cross-region-service-failover-lattice-route53")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        cdk.CfnOutput(
            self,
            "HostedZoneId",
            value=self.hosted_zone.hosted_zone_id,
            description="Route53 Hosted Zone ID",
        )
        
        cdk.CfnOutput(
            self,
            "DomainName",
            value=self.domain_name,
            description="Domain name for failover testing",
        )
        
        cdk.CfnOutput(
            self,
            "NameServers",
            value=cdk.Fn.join(",", self.hosted_zone.hosted_zone_name_servers or []),
            description="Route53 name servers (update your domain registrar)",
        )


class CrossRegionFailoverApp(cdk.App):
    """
    CDK Application for Cross-Region Service Failover
    
    This application orchestrates the deployment of cross-region failover
    infrastructure across multiple AWS regions with Route53 DNS failover.
    """

    def __init__(self) -> None:
        super().__init__()
        
        # Configuration parameters
        domain_name = self.node.try_get_context("domain_name") or "api-demo.example.com"
        random_suffix = self.node.try_get_context("random_suffix") or "abc123"
        primary_region = self.node.try_get_context("primary_region") or "us-east-1"
        secondary_region = self.node.try_get_context("secondary_region") or "us-west-2"
        account_id = self.node.try_get_context("account_id") or os.environ.get("CDK_DEFAULT_ACCOUNT")
        
        if not account_id:
            raise ValueError("Account ID must be provided via context or CDK_DEFAULT_ACCOUNT environment variable")
        
        # Create environments for each region
        primary_env = Environment(account=account_id, region=primary_region)
        secondary_env = Environment(account=account_id, region=secondary_region)
        
        # Deploy primary region stack
        primary_stack = CrossRegionFailoverStack(
            self,
            "CrossRegionFailover-Primary",
            env=primary_env,
            region_type="primary",
            domain_name=domain_name,
            random_suffix=random_suffix,
            vpc_cidr="10.0.0.0/16",
            description="Cross-region failover infrastructure - Primary region",
        )
        
        # Deploy secondary region stack
        secondary_stack = CrossRegionFailoverStack(
            self,
            "CrossRegionFailover-Secondary",
            env=secondary_env,
            region_type="secondary",
            domain_name=domain_name,
            random_suffix=random_suffix,
            vpc_cidr="10.1.0.0/16",
            description="Cross-region failover infrastructure - Secondary region",
        )
        
        # Note: Route53 stack would need to be deployed separately after
        # the regional stacks are complete, or use cross-stack references
        # For simplicity in this example, we're not including the Route53 stack
        # as it would require complex cross-region dependencies


if __name__ == "__main__":
    app = CrossRegionFailoverApp()
    app.synth()