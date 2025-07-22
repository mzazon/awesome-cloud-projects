#!/usr/bin/env python3
"""
CDK Python application for DNS-Based Load Balancing with Route 53

This application creates a comprehensive DNS-based load balancing solution using
Amazon Route 53's advanced routing policies across multiple AWS regions.
It implements weighted, latency-based, geolocation, failover, and multivalue
answer routing policies with health checks.

Architecture:
- Route 53 hosted zone with multiple routing policies
- Application Load Balancers across 3 regions (us-east-1, eu-west-1, ap-southeast-1)
- VPC infrastructure in each region
- Health checks for automated failover
- SNS notifications for health check alerts
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    Tags,
    aws_ec2 as ec2,
    aws_elasticloadbalancingv2 as elbv2,
    aws_route53 as route53,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
)
from constructs import Construct
from typing import List, Dict
import random
import string


class NetworkStack(Stack):
    """
    Creates VPC infrastructure in a specific region for hosting load balancers.
    
    This stack creates:
    - VPC with DNS resolution enabled
    - Public subnets across multiple AZs
    - Internet Gateway and routing
    - Security groups for load balancer traffic
    - Application Load Balancer with target group
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        region: str,
        environment_name: str = "production",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create VPC with DNS resolution enabled
        self.vpc = ec2.Vpc(
            self,
            "VPC",
            max_azs=2,  # Use 2 AZs for high availability
            cidr="10.0.0.0/16",
            enable_dns_hostnames=True,
            enable_dns_support=True,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="Public",
                    cidr_mask=24,
                )
            ],
            nat_gateways=0,  # No NAT gateways needed for this use case
        )

        # Create security group for Application Load Balancer
        self.alb_security_group = ec2.SecurityGroup(
            self,
            "ALBSecurityGroup",
            vpc=self.vpc,
            description=f"Security group for ALB in {region}",
            allow_all_outbound=True,
        )

        # Allow HTTP traffic from internet
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from internet",
        )

        # Allow HTTPS traffic from internet
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from internet",
        )

        # Create Application Load Balancer
        self.load_balancer = elbv2.ApplicationLoadBalancer(
            self,
            "ApplicationLoadBalancer",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.alb_security_group,
            load_balancer_name=f"alb-{region}-{environment_name}",
        )

        # Create target group with health check configuration
        self.target_group = elbv2.ApplicationTargetGroup(
            self,
            "TargetGroup",
            vpc=self.vpc,
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.INSTANCE,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                healthy_threshold_count=2,
                interval=Duration.seconds(30),
                path="/health",
                port="80",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
                unhealthy_threshold_count=3,
            ),
            target_group_name=f"tg-{region}-{environment_name}",
        )

        # Create listener for the load balancer
        self.listener = self.load_balancer.add_listener(
            "Listener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[self.target_group],
        )

        # Tag resources for better organization
        Tags.of(self).add("Environment", environment_name)
        Tags.of(self).add("Region", region)
        Tags.of(self).add("Application", "DNS-Load-Balancing")
        Tags.of(self).add("Recipe", "route53-dns-load-balancing")

        # Outputs
        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description=f"VPC ID for {region}",
        )

        CfnOutput(
            self,
            "LoadBalancerDNS",
            value=self.load_balancer.load_balancer_dns_name,
            description=f"DNS name of the load balancer in {region}",
        )

        CfnOutput(
            self,
            "LoadBalancerArn",
            value=self.load_balancer.load_balancer_arn,
            description=f"ARN of the load balancer in {region}",
        )


class Route53Stack(Stack):
    """
    Creates Route 53 hosted zone and implements comprehensive DNS-based load balancing.
    
    This stack creates:
    - Route 53 hosted zone
    - Health checks for each regional endpoint
    - Multiple routing policies: weighted, latency-based, geolocation, failover, multivalue
    - SNS topic for health check notifications
    - CloudWatch alarms for health check monitoring
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        domain_name: str,
        load_balancer_configs: List[Dict[str, str]],
        environment_name: str = "production",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.domain_name = domain_name
        self.subdomain = f"api.{domain_name}"
        
        # Create hosted zone
        self.hosted_zone = route53.HostedZone(
            self,
            "HostedZone",
            zone_name=domain_name,
            comment=f"Hosted zone for {domain_name} - DNS load balancing recipe",
        )

        # Create SNS topic for health check notifications
        self.health_check_topic = sns.Topic(
            self,
            "HealthCheckTopic",
            topic_name=f"route53-health-alerts-{environment_name}",
            display_name="Route 53 Health Check Alerts",
        )

        # Store health checks and their configurations
        self.health_checks: List[route53.CfnHealthCheck] = []
        self.health_check_configs = []

        # Create health checks for each load balancer
        for i, config in enumerate(load_balancer_configs):
            region = config["region"]
            dns_name = config["dns_name"]
            
            # Create health check
            health_check = route53.CfnHealthCheck(
                self,
                f"HealthCheck{region.replace('-', '').title()}",
                type="HTTP",
                resource_path="/health",
                fully_qualified_domain_name=dns_name,
                port=80,
                request_interval=30,
                failure_threshold=3,
                tags=[
                    cdk.CfnTag(key="Environment", value=environment_name),
                    cdk.CfnTag(key="Region", value=region),
                    cdk.CfnTag(key="Application", value="API"),
                    cdk.CfnTag(key="Recipe", value="route53-dns-load-balancing"),
                ],
            )
            
            self.health_checks.append(health_check)
            self.health_check_configs.append({
                "health_check": health_check,
                "region": region,
                "dns_name": dns_name,
                "config": config,
            })

        # Create routing policies after health checks are configured
        self._create_weighted_routing()
        self._create_latency_routing()
        self._create_geolocation_routing()
        self._create_failover_routing()
        self._create_multivalue_routing()

        # Set up CloudWatch monitoring for health checks
        self._setup_health_check_monitoring()

        # Tag resources
        Tags.of(self).add("Environment", environment_name)
        Tags.of(self).add("Application", "DNS-Load-Balancing")
        Tags.of(self).add("Recipe", "route53-dns-load-balancing")

        # Outputs
        CfnOutput(
            self,
            "HostedZoneId",
            value=self.hosted_zone.hosted_zone_id,
            description="Route 53 hosted zone ID",
        )

        CfnOutput(
            self,
            "DomainName",
            value=self.domain_name,
            description="Domain name for the hosted zone",
        )

        CfnOutput(
            self,
            "NameServers",
            value=cdk.Fn.join(",", self.hosted_zone.hosted_zone_name_servers or []),
            description="Name servers for the hosted zone",
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.health_check_topic.topic_arn,
            description="SNS topic ARN for health check notifications",
        )

        # Output test URLs for different routing policies
        CfnOutput(
            self,
            "WeightedRoutingURL",
            value=f"http://{self.subdomain}",
            description="URL for testing weighted routing",
        )

        CfnOutput(
            self,
            "LatencyRoutingURL",
            value=f"http://latency.{self.subdomain}",
            description="URL for testing latency-based routing",
        )

        CfnOutput(
            self,
            "GeolocationRoutingURL",
            value=f"http://geo.{self.subdomain}",
            description="URL for testing geolocation routing",
        )

        CfnOutput(
            self,
            "FailoverRoutingURL",
            value=f"http://failover.{self.subdomain}",
            description="URL for testing failover routing",
        )

        CfnOutput(
            self,
            "MultivalueRoutingURL",
            value=f"http://multivalue.{self.subdomain}",
            description="URL for testing multivalue routing",
        )

    def _create_weighted_routing(self) -> None:
        """Create weighted routing records with different weights per region."""
        weights = [50, 30, 20]  # Primary: 50%, Secondary: 30%, Tertiary: 20%
        
        for i, hc_config in enumerate(self.health_check_configs):
            route53.CfnRecordSet(
                self,
                f"WeightedRecord{hc_config['region'].replace('-', '').title()}",
                hosted_zone_id=self.hosted_zone.hosted_zone_id,
                name=self.subdomain,
                type="A",
                set_identifier=f"{hc_config['region']}-Weighted",
                weight=weights[i] if i < len(weights) else 10,
                ttl=60,
                resource_records=["1.2.3.4"],  # Placeholder IP - in production use actual IPs
                health_check_id=hc_config["health_check"].attr_health_check_id,
            )

    def _create_latency_routing(self) -> None:
        """Create latency-based routing records for optimal performance."""
        for i, hc_config in enumerate(self.health_check_configs):
            route53.CfnRecordSet(
                self,
                f"LatencyRecord{hc_config['region'].replace('-', '').title()}",
                hosted_zone_id=self.hosted_zone.hosted_zone_id,
                name=f"latency.{self.subdomain}",
                type="A",
                set_identifier=f"{hc_config['region']}-Latency",
                region=hc_config["region"],
                ttl=60,
                resource_records=["1.2.3.4"],  # Placeholder IP
                health_check_id=hc_config["health_check"].attr_health_check_id,
            )

    def _create_geolocation_routing(self) -> None:
        """Create geolocation routing records for regional compliance."""
        geo_mappings = [
            {"continent": "NA", "region": "us-east-1"},  # North America
            {"continent": "EU", "region": "eu-west-1"},  # Europe
            {"continent": "AS", "region": "ap-southeast-1"},  # Asia Pacific
        ]
        
        for geo_mapping in geo_mappings:
            # Find matching health check config
            hc_config = next(
                (hc for hc in self.health_check_configs if hc["region"] == geo_mapping["region"]),
                None
            )
            
            if hc_config:
                route53.CfnRecordSet(
                    self,
                    f"GeoRecord{geo_mapping['continent']}",
                    hosted_zone_id=self.hosted_zone.hosted_zone_id,
                    name=f"geo.{self.subdomain}",
                    type="A",
                    set_identifier=f"{geo_mapping['continent']}-Geo",
                    geo_location=route53.CfnRecordSet.GeoLocationProperty(
                        continent_code=geo_mapping["continent"]
                    ),
                    ttl=60,
                    resource_records=["1.2.3.4"],  # Placeholder IP
                    health_check_id=hc_config["health_check"].attr_health_check_id,
                )
        
        # Create default geolocation record (fallback)
        primary_hc = self.health_check_configs[0] if self.health_check_configs else None
        if primary_hc:
            route53.CfnRecordSet(
                self,
                "GeoRecordDefault",
                hosted_zone_id=self.hosted_zone.hosted_zone_id,
                name=f"geo.{self.subdomain}",
                type="A",
                set_identifier="Default-Geo",
                geo_location=route53.CfnRecordSet.GeoLocationProperty(
                    country_code="*"
                ),
                ttl=60,
                resource_records=["1.2.3.4"],  # Placeholder IP
                health_check_id=primary_hc["health_check"].attr_health_check_id,
            )

    def _create_failover_routing(self) -> None:
        """Create failover routing records for active-passive setup."""
        if len(self.health_check_configs) >= 2:
            # Primary failover record
            route53.CfnRecordSet(
                self,
                "FailoverRecordPrimary",
                hosted_zone_id=self.hosted_zone.hosted_zone_id,
                name=f"failover.{self.subdomain}",
                type="A",
                set_identifier="Primary-Failover",
                failover="PRIMARY",
                ttl=60,
                resource_records=["1.2.3.4"],  # Placeholder IP
                health_check_id=self.health_check_configs[0]["health_check"].attr_health_check_id,
            )
            
            # Secondary failover record
            route53.CfnRecordSet(
                self,
                "FailoverRecordSecondary",
                hosted_zone_id=self.hosted_zone.hosted_zone_id,
                name=f"failover.{self.subdomain}",
                type="A",
                set_identifier="Secondary-Failover",
                failover="SECONDARY",
                ttl=60,
                resource_records=["5.6.7.8"],  # Placeholder IP
                health_check_id=self.health_check_configs[1]["health_check"].attr_health_check_id,
            )

    def _create_multivalue_routing(self) -> None:
        """Create multivalue answer routing records for DNS-level load balancing."""
        for i, hc_config in enumerate(self.health_check_configs):
            placeholder_ips = ["1.2.3.4", "5.6.7.8", "9.10.11.12"]
            ip = placeholder_ips[i] if i < len(placeholder_ips) else "192.0.2.1"
            
            route53.CfnRecordSet(
                self,
                f"MultiValueRecord{hc_config['region'].replace('-', '').title()}",
                hosted_zone_id=self.hosted_zone.hosted_zone_id,
                name=f"multivalue.{self.subdomain}",
                type="A",
                set_identifier=f"{hc_config['region']}-Multivalue",
                ttl=60,
                resource_records=[ip],
                health_check_id=hc_config["health_check"].attr_health_check_id,
            )

    def _setup_health_check_monitoring(self) -> None:
        """Set up CloudWatch monitoring and SNS notifications for health checks."""
        for hc_config in self.health_check_configs:
            region = hc_config["region"]
            health_check = hc_config["health_check"]
            
            # Create CloudWatch alarm for health check
            alarm = cloudwatch.Alarm(
                self,
                f"HealthCheckAlarm{region.replace('-', '').title()}",
                alarm_description=f"Health check alarm for {region}",
                metric=cloudwatch.Metric(
                    namespace="AWS/Route53",
                    metric_name="HealthCheckStatus",
                    dimensions_map={
                        "HealthCheckId": health_check.attr_health_check_id,
                    },
                    statistic="Minimum",
                    period=Duration.minutes(1),
                ),
                threshold=1,
                comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
                evaluation_periods=1,
                treat_missing_data=cloudwatch.TreatMissingData.BREACHING,
            )
            
            # Add SNS action to alarm
            alarm.add_alarm_action(
                cloudwatch_actions.SnsAction(self.health_check_topic)
            )


class DnsLoadBalancingApp(cdk.App):
    """
    Main CDK application that orchestrates the DNS-based load balancing solution.
    
    This application creates:
    1. Network stacks in multiple regions with ALBs
    2. Route 53 stack with comprehensive routing policies
    3. Health checks and monitoring
    """

    def __init__(self) -> None:
        super().__init__()
        
        # Configuration
        account = self.node.try_get_context("account") or "123456789012"
        domain_name = self.node.try_get_context("domain_name") or self._generate_domain_name()
        environment_name = self.node.try_get_context("environment") or "production"
        
        # Define regions for multi-region deployment
        regions = [
            "us-east-1",      # Primary region
            "eu-west-1",      # Secondary region
            "ap-southeast-1", # Tertiary region
        ]
        
        # Create network stacks in each region
        network_stacks = []
        load_balancer_configs = []
        
        for region in regions:
            network_stack = NetworkStack(
                self,
                f"NetworkStack{region.replace('-', '').title()}",
                region=region,
                environment_name=environment_name,
                env=Environment(account=account, region=region),
            )
            
            network_stacks.append(network_stack)
            
            # Store load balancer configuration for Route 53
            load_balancer_configs.append({
                "region": region,
                "dns_name": network_stack.load_balancer.load_balancer_dns_name,
                "arn": network_stack.load_balancer.load_balancer_arn,
            })
        
        # Create Route 53 stack (deploy in primary region)
        route53_stack = Route53Stack(
            self,
            "Route53Stack",
            domain_name=domain_name,
            load_balancer_configs=load_balancer_configs,
            environment_name=environment_name,
            env=Environment(account=account, region=regions[0]),  # Deploy in primary region
        )
        
        # Add dependencies - Route 53 stack depends on all network stacks
        for network_stack in network_stacks:
            route53_stack.add_dependency(network_stack)
        
        # Add application-level tags
        Tags.of(self).add("Project", "DNS-Load-Balancing-Recipe")
        Tags.of(self).add("Environment", environment_name)
        Tags.of(self).add("ManagedBy", "CDK")

    def _generate_domain_name(self) -> str:
        """Generate a unique domain name for testing purposes."""
        random_suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
        return f"example-{random_suffix}.com"


# Create and run the application
app = DnsLoadBalancingApp()
app.synth()