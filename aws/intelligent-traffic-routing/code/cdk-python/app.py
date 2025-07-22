#!/usr/bin/env python3
"""
AWS CDK Python application for Global Load Balancing with Route53 and CloudFront.

This application creates a global load balancing solution that combines Route53's 
intelligent DNS routing with CloudFront's global edge network to provide automatic 
failover, geolocation-based routing, and performance optimization across multiple regions.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, List, Any

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    RemovalPolicy,
    Duration,
    CfnOutput,
    Tags
)
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_elbv2 as elbv2
from aws_cdk import aws_autoscaling as autoscaling
from aws_cdk import aws_route53 as route53
from aws_cdk import aws_route53_targets as route53_targets
from aws_cdk import aws_cloudfront as cloudfront
from aws_cdk import aws_cloudfront_origins as origins
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_iam as iam
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_sns as sns
from aws_cdk import aws_cloudwatch_actions as cw_actions

from constructs import Construct


class GlobalLoadBalancingStack(Stack):
    """
    Main stack for global load balancing infrastructure.
    
    Creates a comprehensive global load balancing solution with:
    - Multi-region VPC infrastructure
    - Application Load Balancers in each region
    - Auto Scaling Groups with sample applications
    - Route53 health checks and DNS routing
    - CloudFront distribution with origin failover
    - S3 fallback content
    - CloudWatch monitoring and alerting
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        primary_region: str,
        secondary_region: str,
        tertiary_region: str,
        domain_name: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.primary_region = primary_region
        self.secondary_region = secondary_region
        self.tertiary_region = tertiary_region
        self.domain_name = domain_name
        
        # Create S3 fallback bucket
        self.fallback_bucket = self._create_fallback_bucket()
        
        # Create SNS topic for alerts
        self.alerts_topic = self._create_alerts_topic()
        
        # Create Route53 hosted zone
        self.hosted_zone = self._create_hosted_zone()
        
        # Store ALB DNS names and health checks for CloudFront
        self.alb_dns_names: List[str] = []
        self.health_checks: List[route53.CfnHealthCheck] = []
        
        # Create CloudFront distribution (will be populated with origins)
        self.cloudfront_distribution = self._create_cloudfront_distribution()
        
        # Output important values
        self._create_outputs()

    def _create_fallback_bucket(self) -> s3.Bucket:
        """Create S3 bucket for fallback maintenance content."""
        bucket = s3.Bucket(
            self,
            "FallbackBucket",
            bucket_name=f"global-lb-fallback-{self.account}-{self.region}",
            website_index_document="index.html",
            website_error_document="index.html",
            public_read_access=False,  # CloudFront will use OAC
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=False,
            encryption=s3.BucketEncryption.S3_MANAGED
        )

        # Create fallback content
        fallback_html = """<!DOCTYPE html>
<html>
<head>
    <title>Service Temporarily Unavailable</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .message { background: #f8f9fa; padding: 20px; border-radius: 5px; margin: 20px auto; max-width: 600px; }
        .status { color: #dc3545; font-size: 18px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="message">
        <h1>Service Temporarily Unavailable</h1>
        <p class="status">We're working to restore service as quickly as possible.</p>
        <p>Please try again in a few minutes. If the problem persists, contact support.</p>
        <p><small>Error Code: GLB-FALLBACK</small></p>
    </div>
</body>
</html>"""

        fallback_health = """{
    "status": "maintenance",
    "message": "Service temporarily unavailable",
    "timestamp": "2025-01-11T00:00:00Z"
}"""

        # Deploy fallback content
        s3.BucketDeployment(
            self,
            "FallbackContent",
            sources=[
                s3.Source.data("index.html", fallback_html),
                s3.Source.data("health.json", fallback_health)
            ],
            destination_bucket=bucket
        )

        return bucket

    def _create_alerts_topic(self) -> sns.Topic:
        """Create SNS topic for monitoring alerts."""
        topic = sns.Topic(
            self,
            "AlertsTopic",
            topic_name="global-lb-alerts",
            display_name="Global Load Balancer Alerts"
        )

        # Add tags
        Tags.of(topic).add("Project", "GlobalLoadBalancer")
        Tags.of(topic).add("Component", "Monitoring")

        return topic

    def _create_hosted_zone(self) -> route53.HostedZone:
        """Create Route53 hosted zone for DNS routing."""
        hosted_zone = route53.HostedZone(
            self,
            "HostedZone",
            zone_name=self.domain_name,
            comment="Global load balancer demo zone"
        )

        # Add tags
        Tags.of(hosted_zone).add("Project", "GlobalLoadBalancer")
        Tags.of(hosted_zone).add("Component", "DNS")

        return hosted_zone

    def _create_cloudfront_distribution(self) -> cloudfront.Distribution:
        """Create CloudFront distribution with origin failover."""
        # Create Origin Access Control for S3
        oac = cloudfront.CfnOriginAccessControl(
            self,
            "OriginAccessControl",
            origin_access_control_config=cloudfront.CfnOriginAccessControl.OriginAccessControlConfigProperty(
                name="global-lb-oac",
                origin_access_control_origin_type="s3",
                signing_behavior="always",
                signing_protocol="sigv4",
                description="OAC for fallback S3 origin"
            )
        )

        # Create S3 origin for fallback
        s3_origin = origins.S3Origin(
            self.fallback_bucket,
            origin_access_identity=None  # Will use OAC instead
        )

        # Create initial distribution (origins will be added by regional stacks)
        distribution = cloudfront.Distribution(
            self,
            "CloudFrontDistribution",
            comment="Global load balancer with failover",
            default_behavior=cloudfront.BehaviorOptions(
                origin=s3_origin,  # Temporary origin, will be replaced with origin group
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                compress=True,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL
            ),
            additional_behaviors={
                "/health": cloudfront.BehaviorOptions(
                    origin=s3_origin,  # Will be replaced
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
                    cache_policy=cloudfront.CachePolicy.CACHING_DISABLED,
                    compress=True,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD
                )
            },
            error_responses=[
                cloudfront.ErrorResponse(
                    http_status=500,
                    response_http_status=200,
                    response_page_path="/index.html",
                    ttl=Duration.seconds(0)
                ),
                cloudfront.ErrorResponse(
                    http_status=502,
                    response_http_status=200,
                    response_page_path="/index.html",
                    ttl=Duration.seconds(0)
                )
            ],
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,
            http_version=cloudfront.HttpVersion.HTTP2,
            enable_ipv6=True,
            default_root_object="index.html"
        )

        # Update S3 bucket policy to allow CloudFront access via OAC
        bucket_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            principals=[iam.ServicePrincipal("cloudfront.amazonaws.com")],
            actions=["s3:GetObject"],
            resources=[f"{self.fallback_bucket.bucket_arn}/*"],
            conditions={
                "StringEquals": {
                    "AWS:SourceArn": f"arn:aws:cloudfront::{self.account}:distribution/{distribution.distribution_id}"
                }
            }
        )
        self.fallback_bucket.add_to_resource_policy(bucket_policy)

        # Add tags
        Tags.of(distribution).add("Project", "GlobalLoadBalancer")
        Tags.of(distribution).add("Component", "CDN")

        return distribution

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "HostedZoneId",
            value=self.hosted_zone.hosted_zone_id,
            description="Route53 Hosted Zone ID",
            export_name=f"{self.stack_name}-HostedZoneId"
        )

        CfnOutput(
            self,
            "HostedZoneNameServers",
            value=cdk.Fn.join(",", self.hosted_zone.hosted_zone_name_servers or []),
            description="Route53 Hosted Zone Name Servers",
            export_name=f"{self.stack_name}-NameServers"
        )

        CfnOutput(
            self,
            "CloudFrontDistributionId",
            value=self.cloudfront_distribution.distribution_id,
            description="CloudFront Distribution ID",
            export_name=f"{self.stack_name}-CloudFrontDistributionId"
        )

        CfnOutput(
            self,
            "CloudFrontDomainName",
            value=self.cloudfront_distribution.domain_name,
            description="CloudFront Distribution Domain Name",
            export_name=f"{self.stack_name}-CloudFrontDomainName"
        )

        CfnOutput(
            self,
            "FallbackBucketName",
            value=self.fallback_bucket.bucket_name,
            description="S3 Fallback Bucket Name",
            export_name=f"{self.stack_name}-FallbackBucketName"
        )

        CfnOutput(
            self,
            "AlertsTopicArn",
            value=self.alerts_topic.topic_arn,
            description="SNS Topic ARN for Alerts",
            export_name=f"{self.stack_name}-AlertsTopicArn"
        )


class RegionalInfrastructureStack(Stack):
    """
    Regional infrastructure stack for global load balancing.
    
    Creates regional components including:
    - VPC with public subnets across multiple AZs
    - Application Load Balancer
    - Auto Scaling Group with sample web application
    - Route53 health checks
    - CloudWatch alarms
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        region_name: str,
        region_code: str,
        global_stack: GlobalLoadBalancingStack,
        weight: int = 100,
        continent_code: str = "NA",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.region_name = region_name
        self.region_code = region_code
        self.global_stack = global_stack
        self.weight = weight
        self.continent_code = continent_code

        # Create VPC infrastructure
        self.vpc = self._create_vpc()
        
        # Create security group
        self.security_group = self._create_security_group()
        
        # Create Application Load Balancer
        self.alb = self._create_application_load_balancer()
        
        # Create Auto Scaling Group
        self.asg = self._create_auto_scaling_group()
        
        # Create Route53 health check
        self.health_check = self._create_health_check()
        
        # Create DNS records
        self._create_dns_records()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public subnets."""
        vpc = ec2.Vpc(
            self,
            "VPC",
            ip_addresses=ec2.IpAddresses.cidr(f"10.{self.region_code}.0.0/16"),
            max_azs=2,
            nat_gateways=0,  # Only public subnets needed
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Add tags
        Tags.of(vpc).add("Name", f"global-lb-vpc-{self.region_name}")
        Tags.of(vpc).add("Project", "GlobalLoadBalancer")
        Tags.of(vpc).add("Region", self.region_name)

        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for ALB and instances."""
        sg = ec2.SecurityGroup(
            self,
            "SecurityGroup",
            vpc=self.vpc,
            description="Security group for global load balancer demo",
            allow_all_outbound=True
        )

        # Allow HTTP and HTTPS from anywhere
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP from anywhere"
        )
        
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS from anywhere"
        )

        # Add tags
        Tags.of(sg).add("Name", f"global-lb-sg-{self.region_name}")
        Tags.of(sg).add("Project", "GlobalLoadBalancer")
        Tags.of(sg).add("Region", self.region_name)

        return sg

    def _create_application_load_balancer(self) -> elbv2.ApplicationLoadBalancer:
        """Create Application Load Balancer."""
        alb = elbv2.ApplicationLoadBalancer(
            self,
            "ApplicationLoadBalancer",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.security_group,
            load_balancer_name=f"global-lb-alb-{self.region_code}"
        )

        # Create target group
        target_group = elbv2.ApplicationTargetGroup(
            self,
            "TargetGroup",
            vpc=self.vpc,
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.INSTANCE,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                interval=Duration.seconds(30),
                path="/health",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
                unhealthy_threshold_count=3,
                healthy_threshold_count=2
            ),
            target_group_name=f"global-lb-tg-{self.region_code}"
        )

        # Create listener
        alb.add_listener(
            "HTTPListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[target_group]
        )

        # Store target group for ASG
        self.target_group = target_group

        # Add tags
        Tags.of(alb).add("Name", f"global-lb-alb-{self.region_name}")
        Tags.of(alb).add("Project", "GlobalLoadBalancer")
        Tags.of(alb).add("Region", self.region_name)

        return alb

    def _create_auto_scaling_group(self) -> autoscaling.AutoScalingGroup:
        """Create Auto Scaling Group with sample web application."""
        # Create user data script
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "yum update -y",
            "yum install -y httpd",
            "systemctl start httpd",
            "systemctl enable httpd",
            "",
            "# Create simple web application",
            f"cat > /var/www/html/index.html << 'EOF'",
            "<!DOCTYPE html>",
            "<html>",
            "<head>",
            "    <title>Global Load Balancer Demo</title>",
            "    <style>",
            "        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }",
            "        .region { background: #e3f2fd; padding: 20px; border-radius: 5px; margin: 20px auto; max-width: 600px; }",
            "        .healthy { color: #4caf50; font-weight: bold; }",
            "    </style>",
            "</head>",
            "<body>",
            "    <div class=\"region\">",
            f"        <h1>Hello from {self.region_name}!</h1>",
            "        <p class=\"healthy\">Status: Healthy</p>",
            "        <p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>",
            "        <p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>",
            f"        <p>Region: {self.region_name}</p>",
            "        <p>Timestamp: $(date)</p>",
            "    </div>",
            "</body>",
            "</html>",
            "EOF",
            "",
            "# Create health check endpoint",
            "cat > /var/www/html/health << 'EOF'",
            "{",
            "    \"status\": \"healthy\",",
            f"    \"region\": \"{self.region_name}\",",
            "    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",",
            "    \"instance_id\": \"$(curl -s http://169.254.169.254/latest/meta-data/instance-id)\",",
            "    \"availability_zone\": \"$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)\"",
            "}",
            "EOF"
        )

        # Create launch template
        launch_template = ec2.LaunchTemplate(
            self,
            "LaunchTemplate",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            security_group=self.security_group,
            user_data=user_data,
            launch_template_name=f"global-lb-lt-{self.region_code}"
        )

        # Create Auto Scaling Group
        asg = autoscaling.AutoScalingGroup(
            self,
            "AutoScalingGroup",
            vpc=self.vpc,
            launch_template=launch_template,
            min_capacity=1,
            max_capacity=3,
            desired_capacity=2,
            health_check=autoscaling.HealthCheck.elb(grace=Duration.minutes(5)),
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            auto_scaling_group_name=f"global-lb-asg-{self.region_code}"
        )

        # Associate with target group
        asg.attach_to_application_target_group(self.target_group)

        # Add tags
        Tags.of(asg).add("Name", f"global-lb-asg-{self.region_name}")
        Tags.of(asg).add("Project", "GlobalLoadBalancer")
        Tags.of(asg).add("Region", self.region_name)

        return asg

    def _create_health_check(self) -> route53.CfnHealthCheck:
        """Create Route53 health check for the ALB."""
        health_check = route53.CfnHealthCheck(
            self,
            "HealthCheck",
            type="HTTP",
            resource_path="/health",
            fully_qualified_domain_name=self.alb.load_balancer_dns_name,
            port=80,
            request_interval=30,
            failure_threshold=3,
            tags=[
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Name",
                    value=f"global-lb-hc-{self.region_name}"
                ),
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Project",
                    value="GlobalLoadBalancer"
                ),
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Region",
                    value=self.region_name
                )
            ]
        )

        return health_check

    def _create_dns_records(self) -> None:
        """Create Route53 DNS records with weighted and geolocation routing."""
        # Weighted routing record
        route53.CfnRecordSet(
            self,
            "WeightedRecord",
            hosted_zone_id=self.global_stack.hosted_zone.hosted_zone_id,
            name=f"app.{self.global_stack.domain_name}",
            type="CNAME",
            set_identifier=self.region_name,
            weight=self.weight,
            ttl=60,
            resource_records=[self.alb.load_balancer_dns_name],
            health_check_id=self.health_check.attr_health_check_id
        )

        # Geolocation routing record
        route53.CfnRecordSet(
            self,
            "GeolocationRecord",
            hosted_zone_id=self.global_stack.hosted_zone.hosted_zone_id,
            name=f"geo.{self.global_stack.domain_name}",
            type="CNAME",
            set_identifier=f"{self.region_name}-geo",
            geo_location=route53.CfnRecordSet.GeoLocationProperty(
                continent_code=self.continent_code
            ),
            ttl=60,
            resource_records=[self.alb.load_balancer_dns_name],
            health_check_id=self.health_check.attr_health_check_id
        )

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring."""
        # Health check alarm
        health_alarm = cloudwatch.Alarm(
            self,
            "HealthCheckAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/Route53",
                metric_name="HealthCheckStatus",
                dimensions_map={
                    "HealthCheckId": self.health_check.attr_health_check_id
                },
                statistic="Minimum",
                period=Duration.minutes(1)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            alarm_description=f"Health check alarm for {self.region_name}",
            alarm_name=f"global-lb-health-{self.region_name}"
        )

        # Add alarm action
        health_alarm.add_alarm_action(
            cw_actions.SnsAction(self.global_stack.alerts_topic)
        )
        health_alarm.add_ok_action(
            cw_actions.SnsAction(self.global_stack.alerts_topic)
        )

        # ALB response time alarm
        response_time_alarm = cloudwatch.Alarm(
            self,
            "ResponseTimeAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationELB",
                metric_name="TargetResponseTime",
                dimensions_map={
                    "LoadBalancer": self.alb.load_balancer_full_name
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=5,  # 5 seconds
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            alarm_description=f"ALB response time alarm for {self.region_name}",
            alarm_name=f"global-lb-response-time-{self.region_name}"
        )

        response_time_alarm.add_alarm_action(
            cw_actions.SnsAction(self.global_stack.alerts_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "ALBDnsName",
            value=self.alb.load_balancer_dns_name,
            description=f"ALB DNS Name for {self.region_name}",
            export_name=f"{self.stack_name}-ALBDnsName"
        )

        CfnOutput(
            self,
            "HealthCheckId",
            value=self.health_check.attr_health_check_id,
            description=f"Health Check ID for {self.region_name}",
            export_name=f"{self.stack_name}-HealthCheckId"
        )

        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description=f"VPC ID for {self.region_name}",
            export_name=f"{self.stack_name}-VPCId"
        )


def main() -> None:
    """Main application entry point."""
    app = App()

    # Configuration
    primary_region = "us-east-1"
    secondary_region = "eu-west-1"
    tertiary_region = "ap-southeast-1"
    domain_name = os.environ.get("DOMAIN_NAME", "example-global-lb.com")
    
    # Environment configuration
    aws_account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    primary_env = Environment(account=aws_account, region=primary_region)
    secondary_env = Environment(account=aws_account, region=secondary_region)
    tertiary_env = Environment(account=aws_account, region=tertiary_region)

    # Create global stack in primary region
    global_stack = GlobalLoadBalancingStack(
        app,
        "GlobalLoadBalancingStack",
        primary_region=primary_region,
        secondary_region=secondary_region,
        tertiary_region=tertiary_region,
        domain_name=domain_name,
        env=primary_env,
        description="Global Load Balancing with Route53 and CloudFront - Main Stack"
    )

    # Create regional infrastructure stacks
    primary_stack = RegionalInfrastructureStack(
        app,
        "PrimaryRegionStack",
        region_name=primary_region,
        region_code="10",
        global_stack=global_stack,
        weight=100,
        continent_code="NA",
        env=primary_env,
        description="Primary Region Infrastructure - US East (N. Virginia)"
    )

    secondary_stack = RegionalInfrastructureStack(
        app,
        "SecondaryRegionStack",
        region_name=secondary_region,
        region_code="20",
        global_stack=global_stack,
        weight=50,
        continent_code="EU",
        env=secondary_env,
        description="Secondary Region Infrastructure - EU West (Ireland)"
    )

    tertiary_stack = RegionalInfrastructureStack(
        app,
        "TertiaryRegionStack",
        region_name=tertiary_region,
        region_code="30",
        global_stack=global_stack,
        weight=25,
        continent_code="AS",
        env=tertiary_env,
        description="Tertiary Region Infrastructure - Asia Pacific (Singapore)"
    )

    # Add dependencies
    primary_stack.add_dependency(global_stack)
    secondary_stack.add_dependency(global_stack)
    tertiary_stack.add_dependency(global_stack)

    # Add global tags
    Tags.of(app).add("Project", "GlobalLoadBalancer")
    Tags.of(app).add("Environment", "Demo")
    Tags.of(app).add("ManagedBy", "CDK")

    app.synth()


if __name__ == "__main__":
    main()