#!/usr/bin/env python3
"""
AWS CDK Python application for building low-latency edge applications
with AWS Wavelength and CloudFront.

This application creates a complete edge computing solution that combines
AWS Wavelength Zones for ultra-low latency processing with CloudFront
for global content delivery.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    aws_ec2 as ec2,
    aws_elasticloadbalancingv2 as elbv2,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_s3 as s3,
    aws_s3_deployment as s3deploy,
    aws_route53 as route53,
    aws_route53_targets as targets,
    aws_iam as iam,
    CfnOutput,
    RemovalPolicy,
    Duration,
)
from constructs import Construct


class EdgeApplicationStack(Stack):
    """
    CDK Stack for Low-Latency Edge Applications with Wavelength.
    
    This stack creates:
    - Extended VPC with Wavelength Zone subnet
    - Carrier Gateway for mobile connectivity  
    - EC2 instances in Wavelength Zone for edge processing
    - Application Load Balancer for high availability
    - S3 bucket for static assets
    - CloudFront distribution with multiple origins
    - Route 53 DNS configuration
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        *,
        wavelength_zone: str,
        domain_name: str = None,
        **kwargs
    ) -> None:
        """
        Initialize the Edge Application Stack.
        
        Args:
            scope: CDK app scope
            construct_id: Unique construct identifier
            wavelength_zone: AWS Wavelength Zone name (e.g., 'us-west-2-wl1-las-wlz-1')
            domain_name: Optional custom domain name for the application
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.wavelength_zone = wavelength_zone
        self.domain_name = domain_name
        
        # Create VPC extended to Wavelength Zone
        self.vpc = self._create_vpc()
        
        # Create networking components
        self.carrier_gateway = self._create_carrier_gateway()
        self.wavelength_subnet = self._create_wavelength_subnet()
        self.regional_subnet = self._create_regional_subnet()
        
        # Configure route tables
        self._configure_routing()
        
        # Create security groups
        self.wavelength_sg, self.regional_sg = self._create_security_groups()
        
        # Deploy edge application to Wavelength Zone
        self.wavelength_instance = self._create_wavelength_instance()
        
        # Create Application Load Balancer
        self.alb, self.target_group = self._create_load_balancer()
        
        # Create S3 bucket for static assets
        self.s3_bucket = self._create_s3_bucket()
        
        # Deploy sample static content
        self._deploy_static_content()
        
        # Create CloudFront distribution
        self.cloudfront_distribution = self._create_cloudfront_distribution()
        
        # Configure DNS if domain provided
        if self.domain_name:
            self.hosted_zone = self._create_dns_configuration()
        
        # Output important resource information
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC that can be extended to Wavelength Zones.
        
        Returns:
            ec2.Vpc: VPC configured for Wavelength extension
        """
        vpc = ec2.Vpc(
            self,
            "EdgeApplicationVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=1,  # Will be extended with Wavelength subnet manually
            subnet_configuration=[],  # Manual subnet configuration
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        Tags.of(vpc).add("Name", f"{self.stack_name}-vpc")
        Tags.of(vpc).add("Purpose", "Wavelength-Extended-VPC")
        
        return vpc

    def _create_carrier_gateway(self) -> ec2.CfnCarrierGateway:
        """
        Create Carrier Gateway for mobile network connectivity.
        
        Returns:
            ec2.CfnCarrierGateway: Carrier gateway for 5G connectivity
        """
        carrier_gateway = ec2.CfnCarrierGateway(
            self,
            "CarrierGateway",
            vpc_id=self.vpc.vpc_id,
            tags=[
                {
                    "key": "Name",
                    "value": f"{self.stack_name}-carrier-gateway"
                },
                {
                    "key": "Purpose", 
                    "value": "5G-Mobile-Connectivity"
                }
            ]
        )
        
        return carrier_gateway

    def _create_wavelength_subnet(self) -> ec2.CfnSubnet:
        """
        Create subnet in the Wavelength Zone.
        
        Returns:
            ec2.CfnSubnet: Subnet in Wavelength Zone
        """
        wavelength_subnet = ec2.CfnSubnet(
            self,
            "WavelengthSubnet",
            vpc_id=self.vpc.vpc_id,
            cidr_block="10.0.1.0/24",
            availability_zone=self.wavelength_zone,
            tags=[
                {
                    "key": "Name",
                    "value": f"{self.stack_name}-wavelength-subnet"
                },
                {
                    "key": "Type",
                    "value": "Wavelength-Edge-Subnet"
                }
            ]
        )
        
        return wavelength_subnet

    def _create_regional_subnet(self) -> ec2.CfnSubnet:
        """
        Create regional subnet for backend services.
        
        Returns:
            ec2.CfnSubnet: Regional subnet for backend services
        """
        # Get first available AZ in the region
        regional_az = f"{self.region}a"
        
        regional_subnet = ec2.CfnSubnet(
            self,
            "RegionalSubnet",
            vpc_id=self.vpc.vpc_id,
            cidr_block="10.0.2.0/24",
            availability_zone=regional_az,
            tags=[
                {
                    "key": "Name",
                    "value": f"{self.stack_name}-regional-subnet"
                },
                {
                    "key": "Type",
                    "value": "Regional-Backend-Subnet"
                }
            ]
        )
        
        return regional_subnet

    def _configure_routing(self) -> None:
        """Configure route tables for Wavelength and regional subnets."""
        # Create route table for Wavelength subnet
        wavelength_route_table = ec2.CfnRouteTable(
            self,
            "WavelengthRouteTable",
            vpc_id=self.vpc.vpc_id,
            tags=[
                {
                    "key": "Name",
                    "value": f"{self.stack_name}-wavelength-rt"
                }
            ]
        )
        
        # Add route to carrier gateway for mobile traffic
        ec2.CfnRoute(
            self,
            "CarrierGatewayRoute",
            route_table_id=wavelength_route_table.ref,
            destination_cidr_block="0.0.0.0/0",
            carrier_gateway_id=self.carrier_gateway.ref
        )
        
        # Associate route table with Wavelength subnet
        ec2.CfnSubnetRouteTableAssociation(
            self,
            "WavelengthSubnetRouteAssociation",
            subnet_id=self.wavelength_subnet.ref,
            route_table_id=wavelength_route_table.ref
        )

    def _create_security_groups(self) -> tuple[ec2.SecurityGroup, ec2.SecurityGroup]:
        """
        Create security groups for Wavelength and regional resources.
        
        Returns:
            tuple: Wavelength and regional security groups
        """
        # Security group for Wavelength edge servers
        wavelength_sg = ec2.SecurityGroup(
            self,
            "WavelengthSecurityGroup",
            vpc=self.vpc,
            description="Security group for Wavelength edge applications",
            security_group_name=f"{self.stack_name}-wavelength-sg",
            allow_all_outbound=True
        )
        
        # Allow HTTP/HTTPS traffic from mobile clients
        wavelength_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="HTTP from mobile clients"
        )
        
        wavelength_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS from mobile clients"
        )
        
        # Allow custom application port
        wavelength_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(8080),
            description="Application port for edge services"
        )
        
        # Security group for regional backend services
        regional_sg = ec2.SecurityGroup(
            self,
            "RegionalSecurityGroup",
            vpc=self.vpc,
            description="Security group for regional backend services",
            security_group_name=f"{self.stack_name}-regional-sg",
            allow_all_outbound=True
        )
        
        # Allow traffic from Wavelength security group
        regional_sg.add_ingress_rule(
            peer=ec2.Peer.security_group_id(wavelength_sg.security_group_id),
            connection=ec2.Port.tcp(80),
            description="HTTP from Wavelength edge servers"
        )
        
        Tags.of(wavelength_sg).add("Name", f"{self.stack_name}-wavelength-sg")
        Tags.of(regional_sg).add("Name", f"{self.stack_name}-regional-sg")
        
        return wavelength_sg, regional_sg

    def _create_wavelength_instance(self) -> ec2.CfnInstance:
        """
        Create EC2 instance in Wavelength Zone for edge processing.
        
        Returns:
            ec2.CfnInstance: Edge application server instance
        """
        # Get latest Amazon Linux 2 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE
        )
        
        # User data script for edge application setup
        user_data_script = ec2.UserData.for_linux()
        user_data_script.add_commands(
            "yum update -y",
            "yum install -y docker",
            "systemctl start docker",
            "systemctl enable docker",
            "usermod -a -G docker ec2-user",
            "",
            "# Run a simple edge application (game server simulation)",
            "docker run -d --name edge-app -p 8080:8080 --restart unless-stopped nginx:alpine",
            "",
            "# Configure nginx for edge application",
            "docker exec edge-app sh -c 'echo \"",
            "server {",
            "    listen 8080;",
            "    location / {",
            "        return 200 \\\"Edge Server Response Time: \\$(date +%s%3N)ms\\\";",
            "        add_header Content-Type text/plain;",
            "    }",
            "    location /health {",
            "        return 200 \\\"healthy\\\";",
            "        add_header Content-Type text/plain;",
            "    }",
            "}\" > /etc/nginx/conf.d/default.conf'",
            "",
            "docker restart edge-app"
        )
        
        # Create IAM role for EC2 instance
        instance_role = iam.Role(
            self,
            "WavelengthInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
            ]
        )
        
        instance_profile = iam.CfnInstanceProfile(
            self,
            "WavelengthInstanceProfile",
            roles=[instance_role.role_name]
        )
        
        # Create EC2 instance in Wavelength Zone
        wavelength_instance = ec2.CfnInstance(
            self,
            "WavelengthInstance",
            image_id=amzn_linux.get_image(self).image_id,
            instance_type="t3.medium",
            subnet_id=self.wavelength_subnet.ref,
            security_group_ids=[self.wavelength_sg.security_group_id],
            iam_instance_profile=instance_profile.ref,
            user_data=cdk.Fn.base64(user_data_script.render()),
            tags=[
                {
                    "key": "Name",
                    "value": f"{self.stack_name}-wavelength-server"
                },
                {
                    "key": "Purpose",
                    "value": "Edge-Application-Server"
                }
            ]
        )
        
        return wavelength_instance

    def _create_load_balancer(self) -> tuple[elbv2.ApplicationLoadBalancer, elbv2.ApplicationTargetGroup]:
        """
        Create Application Load Balancer for high availability.
        
        Returns:
            tuple: ALB and target group for edge instances
        """
        # Create target group for edge instances
        target_group = elbv2.ApplicationTargetGroup(
            self,
            "EdgeTargetGroup",
            port=8080,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
            target_group_name=f"{self.stack_name}-edge-targets",
            health_check=elbv2.HealthCheck(
                path="/health",
                interval=Duration.seconds(30),
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
                timeout=Duration.seconds(5)
            ),
            targets=[
                elbv2.InstanceTarget(
                    instance_id=self.wavelength_instance.ref,
                    port=8080
                )
            ]
        )
        
        # Create Application Load Balancer
        alb = elbv2.ApplicationLoadBalancer(
            self,
            "WavelengthALB",
            vpc=self.vpc,
            internet_facing=False,  # Internal ALB for carrier gateway traffic
            load_balancer_name=f"{self.stack_name}-wavelength-alb",
            vpc_subnets=ec2.SubnetSelection(
                subnets=[
                    ec2.Subnet.from_subnet_attributes(
                        self,
                        "ImportedWavelengthSubnet",
                        subnet_id=self.wavelength_subnet.ref,
                        availability_zone=self.wavelength_zone
                    )
                ]
            ),
            security_group=self.wavelength_sg
        )
        
        # Create ALB listener
        alb.add_listener(
            "WavelengthALBListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[target_group]
        )
        
        Tags.of(alb).add("Name", f"{self.stack_name}-wavelength-alb")
        Tags.of(target_group).add("Name", f"{self.stack_name}-edge-targets")
        
        return alb, target_group

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for static assets.
        
        Returns:
            s3.Bucket: S3 bucket for static content
        """
        s3_bucket = s3.Bucket(
            self,
            "StaticAssetsBucket",
            bucket_name=f"{self.stack_name}-static-assets-{self.account}",
            versioned=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED
        )
        
        Tags.of(s3_bucket).add("Name", f"{self.stack_name}-static-assets")
        Tags.of(s3_bucket).add("Purpose", "CloudFront-Static-Content")
        
        return s3_bucket

    def _deploy_static_content(self) -> None:
        """Deploy sample static content to S3 bucket."""
        # Deploy static content to S3
        s3deploy.BucketDeployment(
            self,
            "StaticContentDeployment",
            sources=[
                s3deploy.Source.data(
                    "index.html",
                    """<!DOCTYPE html>
<html>
<head>
    <title>Edge Application</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .latency-test { background: #f0f0f0; padding: 20px; margin: 20px 0; }
        .metrics { display: flex; gap: 20px; }
        .metric { background: white; padding: 15px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>Low-Latency Edge Application</h1>
    <div class="latency-test">
        <h2>Latency Test</h2>
        <div class="metrics">
            <div class="metric">
                <h3>Page Load</h3>
                <p>Time: <span id="load-time">-</span>ms</p>
            </div>
            <div class="metric">
                <h3>Edge Response</h3>
                <p>Status: <span id="edge-status">Testing...</span></p>
            </div>
        </div>
    </div>
    <script>
        const startTime = performance.now();
        window.onload = function() {
            const loadTime = Math.round(performance.now() - startTime);
            document.getElementById('load-time').textContent = loadTime;
            
            // Test edge API response
            fetch('/api/health')
                .then(response => response.text())
                .then(data => {
                    document.getElementById('edge-status').textContent = 'Connected';
                })
                .catch(error => {
                    document.getElementById('edge-status').textContent = 'Error';
                });
        };
    </script>
</body>
</html>"""
                )
            ],
            destination_bucket=self.s3_bucket
        )

    def _create_cloudfront_distribution(self) -> cloudfront.Distribution:
        """
        Create CloudFront distribution with multiple origins.
        
        Returns:
            cloudfront.Distribution: CloudFront distribution for global delivery
        """
        # Create Origin Access Control for S3
        origin_access_control = cloudfront.CfnOriginAccessControl(
            self,
            "S3OriginAccessControl",
            origin_access_control_config=cloudfront.CfnOriginAccessControl.OriginAccessControlConfigProperty(
                name=f"{self.stack_name}-s3-oac",
                description="OAC for S3 static assets",
                origin_access_control_origin_type="s3",
                signing_behavior="always",
                signing_protocol="sigv4"
            )
        )
        
        # Create CloudFront distribution
        distribution = cloudfront.Distribution(
            self,
            "EdgeApplicationDistribution",
            comment="Edge application with Wavelength and S3 origins",
            default_root_object="index.html",
            price_class=cloudfront.PriceClass.PRICE_CLASS_ALL,
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3Origin(
                    bucket=self.s3_bucket,
                    origin_access_control_id=origin_access_control.attr_id
                ),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                compress=True
            ),
            additional_behaviors={
                "/api/*": cloudfront.BehaviorOptions(
                    origin=origins.HttpOrigin(
                        domain_name=self.alb.load_balancer_dns_name,
                        protocol_policy=cloudfront.OriginProtocolPolicy.HTTP_ONLY
                    ),
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
                    cache_policy=cloudfront.CachePolicy.CACHING_DISABLED,
                    origin_request_policy=cloudfront.OriginRequestPolicy.ALL_VIEWER,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL,
                    compress=False
                )
            }
        )
        
        # Grant CloudFront access to S3 bucket
        self.s3_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudfront.amazonaws.com")],
                actions=["s3:GetObject"],
                resources=[f"{self.s3_bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "AWS:SourceArn": f"arn:aws:cloudfront::{self.account}:distribution/{distribution.distribution_id}"
                    }
                }
            )
        )
        
        Tags.of(distribution).add("Name", f"{self.stack_name}-distribution")
        
        return distribution

    def _create_dns_configuration(self) -> route53.HostedZone:
        """
        Configure Route 53 DNS for custom domain.
        
        Returns:
            route53.HostedZone: Hosted zone for domain management
        """
        # Create hosted zone
        hosted_zone = route53.HostedZone(
            self,
            "EdgeApplicationHostedZone",
            zone_name=self.domain_name,
            comment="Edge application DNS zone"
        )
        
        # Create CNAME record for CloudFront
        route53.CnameRecord(
            self,
            "CloudFrontCNAME",
            zone=hosted_zone,
            record_name=f"app.{self.domain_name}",
            domain_name=self.cloudfront_distribution.distribution_domain_name,
            ttl=Duration.minutes(5)
        )
        
        return hosted_zone

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID extended to Wavelength Zone"
        )
        
        CfnOutput(
            self,
            "WavelengthZone",
            value=self.wavelength_zone,
            description="AWS Wavelength Zone used for edge deployment"
        )
        
        CfnOutput(
            self,
            "WavelengthInstanceId",
            value=self.wavelength_instance.ref,
            description="EC2 Instance ID in Wavelength Zone"
        )
        
        CfnOutput(
            self,
            "ApplicationLoadBalancerDNS",
            value=self.alb.load_balancer_dns_name,
            description="ALB DNS name for edge application"
        )
        
        CfnOutput(
            self,
            "S3BucketName",
            value=self.s3_bucket.bucket_name,
            description="S3 bucket for static assets"
        )
        
        CfnOutput(
            self,
            "CloudFrontDistributionId",
            value=self.cloudfront_distribution.distribution_id,
            description="CloudFront Distribution ID"
        )
        
        CfnOutput(
            self,
            "CloudFrontDomainName",
            value=self.cloudfront_distribution.distribution_domain_name,
            description="CloudFront domain name for global access"
        )
        
        if self.domain_name:
            CfnOutput(
                self,
                "ApplicationURL",
                value=f"https://app.{self.domain_name}",
                description="Application URL with custom domain"
            )
        
        CfnOutput(
            self,
            "EdgeApplicationURL",
            value=f"https://{self.cloudfront_distribution.distribution_domain_name}",
            description="Direct CloudFront URL for testing"
        )


class EdgeApplicationApp(cdk.App):
    """CDK Application for Edge Computing with AWS Wavelength and CloudFront."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get configuration from environment variables or context
        wavelength_zone = self.node.try_get_context("wavelength_zone") or os.environ.get("WAVELENGTH_ZONE", "us-west-2-wl1-las-wlz-1")
        domain_name = self.node.try_get_context("domain_name") or os.environ.get("DOMAIN_NAME")
        aws_account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        aws_region = os.environ.get("CDK_DEFAULT_REGION", "us-west-2")
        
        # Validate required parameters
        if not wavelength_zone:
            raise ValueError("Wavelength Zone must be specified via context or environment variable")
        
        # Create the main stack
        edge_stack = EdgeApplicationStack(
            self,
            "EdgeApplicationStack",
            wavelength_zone=wavelength_zone,
            domain_name=domain_name,
            env=Environment(
                account=aws_account,
                region=aws_region
            ),
            description="Low-latency edge application with AWS Wavelength and CloudFront"
        )
        
        # Add tags to all resources in the stack
        Tags.of(edge_stack).add("Project", "EdgeApplication")
        Tags.of(edge_stack).add("Environment", "Production")
        Tags.of(edge_stack).add("CostCenter", "Engineering")
        Tags.of(edge_stack).add("Owner", "DevOps")


# Create and run the CDK application
app = EdgeApplicationApp()
app.synth()