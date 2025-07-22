#!/usr/bin/env python3
"""
CDK Python Application for CloudFormation Nested Stacks with Cross-Stack References

This application demonstrates how to build modular infrastructure using CDK stacks
that mirror CloudFormation nested stack patterns. It creates a three-tier architecture
with proper separation of concerns and cross-stack dependencies.

Author: AWS CDK Team
License: MIT
"""

import os
from typing import List, Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    StackProps,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_elasticloadbalancingv2 as elbv2,
    aws_autoscaling as autoscaling,
    aws_rds as rds,
    aws_secretsmanager as secretsmanager,
    aws_logs as logs,
)
from constructs import Construct


class NetworkStack(Stack):
    """
    Network infrastructure stack providing VPC, subnets, and routing.
    
    This stack creates the foundational network components including:
    - VPC with DNS support
    - Public and private subnets across multiple AZs
    - Internet Gateway and NAT Gateways
    - Route tables and associations
    
    Outputs VPC and subnet IDs for use by other stacks.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment: str,
        project_name: str,
        vpc_cidr: str = "10.0.0.0/16",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.environment = environment
        self.project_name = project_name

        # Create VPC with public and private subnets
        self.vpc = ec2.Vpc(
            self,
            "VPC",
            vpc_name=f"{project_name}-{environment}-vpc",
            ip_addresses=ec2.IpAddresses.cidr(vpc_cidr),
            max_azs=2,
            enable_dns_hostnames=True,
            enable_dns_support=True,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            nat_gateways=2,  # One per AZ for high availability
        )

        # Tag all subnets appropriately
        for subnet in self.vpc.public_subnets:
            cdk.Tags.of(subnet).add("Name", f"{project_name}-{environment}-public-subnet-{subnet.node.addr}")
            cdk.Tags.of(subnet).add("Type", "Public")
            cdk.Tags.of(subnet).add("Environment", environment)

        for subnet in self.vpc.private_subnets:
            cdk.Tags.of(subnet).add("Name", f"{project_name}-{environment}-private-subnet-{subnet.node.addr}")
            cdk.Tags.of(subnet).add("Type", "Private")
            cdk.Tags.of(subnet).add("Environment", environment)

        # Create stack outputs for cross-stack references
        self.vpc_id_output = CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID",
            export_name=f"{self.stack_name}-VpcId",
        )

        self.vpc_cidr_output = CfnOutput(
            self,
            "VpcCidr",
            value=self.vpc.vpc_cidr_block,
            description="VPC CIDR Block",
            export_name=f"{self.stack_name}-VpcCidr",
        )

        # Export public subnet IDs
        for i, subnet in enumerate(self.vpc.public_subnets):
            CfnOutput(
                self,
                f"PublicSubnet{i+1}Id",
                value=subnet.subnet_id,
                description=f"Public Subnet {i+1} ID",
                export_name=f"{self.stack_name}-PublicSubnet{i+1}Id",
            )

        # Export private subnet IDs
        for i, subnet in enumerate(self.vpc.private_subnets):
            CfnOutput(
                self,
                f"PrivateSubnet{i+1}Id",
                value=subnet.subnet_id,
                description=f"Private Subnet {i+1} ID",
                export_name=f"{self.stack_name}-PrivateSubnet{i+1}Id",
            )

        # Export subnet lists as comma-separated values
        CfnOutput(
            self,
            "PublicSubnets",
            value=",".join([subnet.subnet_id for subnet in self.vpc.public_subnets]),
            description="List of public subnet IDs",
            export_name=f"{self.stack_name}-PublicSubnets",
        )

        CfnOutput(
            self,
            "PrivateSubnets",
            value=",".join([subnet.subnet_id for subnet in self.vpc.private_subnets]),
            description="List of private subnet IDs",
            export_name=f"{self.stack_name}-PrivateSubnets",
        )


class SecurityStack(Stack):
    """
    Security infrastructure stack providing IAM roles and security groups.
    
    This stack creates security resources including:
    - Security groups for different application tiers
    - IAM roles and policies for EC2 instances and RDS
    - Instance profiles for EC2 service access
    
    Depends on network stack for VPC ID and implements least privilege access.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment: str,
        project_name: str,
        vpc: ec2.IVpc,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.environment = environment
        self.project_name = project_name
        self.vpc = vpc

        # Create security groups
        self._create_security_groups()
        
        # Create IAM roles
        self._create_iam_roles()

        # Create stack outputs
        self._create_outputs()

    def _create_security_groups(self) -> None:
        """Create security groups for different application tiers."""
        
        # Application Load Balancer Security Group
        self.alb_security_group = ec2.SecurityGroup(
            self,
            "ALBSecurityGroup",
            vpc=self.vpc,
            security_group_name=f"{self.project_name}-{self.environment}-alb-sg",
            description="Security group for Application Load Balancer",
            allow_all_outbound=True,
        )

        # Allow HTTP and HTTPS traffic from internet
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from internet",
        )
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from internet",
        )

        # Application Security Group
        self.application_security_group = ec2.SecurityGroup(
            self,
            "ApplicationSecurityGroup",
            vpc=self.vpc,
            security_group_name=f"{self.project_name}-{self.environment}-app-sg",
            description="Security group for application instances",
            allow_all_outbound=True,
        )

        # Bastion Host Security Group
        self.bastion_security_group = ec2.SecurityGroup(
            self,
            "BastionSecurityGroup",
            vpc=self.vpc,
            security_group_name=f"{self.project_name}-{self.environment}-bastion-sg",
            description="Security group for bastion host",
            allow_all_outbound=True,
        )

        # Allow SSH from internet to bastion
        self.bastion_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access from internet",
        )

        # Allow HTTP from ALB to application instances
        self.application_security_group.add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.alb_security_group.security_group_id),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from ALB",
        )

        # Allow SSH from bastion to application instances
        self.application_security_group.add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.bastion_security_group.security_group_id),
            connection=ec2.Port.tcp(22),
            description="Allow SSH from bastion host",
        )

        # Database Security Group
        self.database_security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            security_group_name=f"{self.project_name}-{self.environment}-db-sg",
            description="Security group for database",
            allow_all_outbound=False,
        )

        # Allow MySQL access from application instances
        self.database_security_group.add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.application_security_group.security_group_id),
            connection=ec2.Port.tcp(3306),
            description="Allow MySQL access from application",
        )

        # Tag security groups
        cdk.Tags.of(self.alb_security_group).add("Component", "LoadBalancer")
        cdk.Tags.of(self.application_security_group).add("Component", "Application")
        cdk.Tags.of(self.bastion_security_group).add("Component", "Bastion")
        cdk.Tags.of(self.database_security_group).add("Component", "Database")

    def _create_iam_roles(self) -> None:
        """Create IAM roles and policies for EC2 instances and RDS."""
        
        # EC2 Instance Role
        self.ec2_instance_role = iam.Role(
            self,
            "EC2InstanceRole",
            role_name=f"{self.project_name}-{self.environment}-ec2-role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
            ],
        )

        # Add S3 access policy
        s3_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetObject",
                "s3:PutObject",
            ],
            resources=[f"arn:aws:s3:::{self.project_name}-{self.environment}-*/*"],
        )

        s3_list_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["s3:ListBucket"],
            resources=[f"arn:aws:s3:::{self.project_name}-{self.environment}-*"],
        )

        self.ec2_instance_role.add_to_policy(s3_policy)
        self.ec2_instance_role.add_to_policy(s3_list_policy)

        # Instance Profile
        self.ec2_instance_profile = iam.CfnInstanceProfile(
            self,
            "EC2InstanceProfile",
            instance_profile_name=f"{self.project_name}-{self.environment}-ec2-profile",
            roles=[self.ec2_instance_role.role_name],
        )

        # RDS Enhanced Monitoring Role
        self.rds_monitoring_role = iam.Role(
            self,
            "RDSEnhancedMonitoringRole",
            role_name=f"{self.project_name}-{self.environment}-rds-monitoring-role",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                ),
            ],
        )

        # Tag IAM resources
        cdk.Tags.of(self.ec2_instance_role).add("Component", "Compute")
        cdk.Tags.of(self.rds_monitoring_role).add("Component", "Database")

    def _create_outputs(self) -> None:
        """Create stack outputs for cross-stack references."""
        
        CfnOutput(
            self,
            "ALBSecurityGroupId",
            value=self.alb_security_group.security_group_id,
            description="Application Load Balancer Security Group ID",
            export_name=f"{self.stack_name}-ALBSecurityGroupId",
        )

        CfnOutput(
            self,
            "ApplicationSecurityGroupId",
            value=self.application_security_group.security_group_id,
            description="Application Security Group ID",
            export_name=f"{self.stack_name}-ApplicationSecurityGroupId",
        )

        CfnOutput(
            self,
            "BastionSecurityGroupId",
            value=self.bastion_security_group.security_group_id,
            description="Bastion Security Group ID",
            export_name=f"{self.stack_name}-BastionSecurityGroupId",
        )

        CfnOutput(
            self,
            "DatabaseSecurityGroupId",
            value=self.database_security_group.security_group_id,
            description="Database Security Group ID",
            export_name=f"{self.stack_name}-DatabaseSecurityGroupId",
        )

        CfnOutput(
            self,
            "EC2InstanceRoleArn",
            value=self.ec2_instance_role.role_arn,
            description="EC2 Instance Role ARN",
            export_name=f"{self.stack_name}-EC2InstanceRoleArn",
        )

        CfnOutput(
            self,
            "EC2InstanceProfileArn",
            value=self.ec2_instance_profile.attr_arn,
            description="EC2 Instance Profile ARN",
            export_name=f"{self.stack_name}-EC2InstanceProfileArn",
        )

        CfnOutput(
            self,
            "RDSMonitoringRoleArn",
            value=self.rds_monitoring_role.role_arn,
            description="RDS Enhanced Monitoring Role ARN",
            export_name=f"{self.stack_name}-RDSMonitoringRoleArn",
        )


class ApplicationStack(Stack):
    """
    Application infrastructure stack providing compute, load balancing, and database.
    
    This stack creates the application tier resources including:
    - Application Load Balancer with target groups
    - Auto Scaling Group with launch template
    - RDS MySQL database with security
    - CloudWatch logging configuration
    
    Depends on network and security stacks for infrastructure foundations.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment: str,
        project_name: str,
        vpc: ec2.IVpc,
        alb_security_group: ec2.ISecurityGroup,
        application_security_group: ec2.ISecurityGroup,
        database_security_group: ec2.ISecurityGroup,
        ec2_instance_role: iam.IRole,
        rds_monitoring_role: iam.IRole,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.environment = environment
        self.project_name = project_name
        self.vpc = vpc

        # Environment-specific configuration
        self.config = self._get_environment_config()

        # Create application resources
        self._create_load_balancer(alb_security_group)
        self._create_auto_scaling_group(application_security_group, ec2_instance_role)
        self._create_database(database_security_group, rds_monitoring_role)

        # Create stack outputs
        self._create_outputs()

    def _get_environment_config(self) -> Dict[str, Any]:
        """Get environment-specific configuration."""
        
        configs = {
            "development": {
                "instance_type": ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
                "min_size": 1,
                "max_size": 2,
                "desired_capacity": 1,
                "db_instance_class": ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
                "db_allocated_storage": 20,
                "multi_az": False,
                "deletion_protection": False,
            },
            "staging": {
                "instance_type": ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.SMALL),
                "min_size": 2,
                "max_size": 4,
                "desired_capacity": 2,
                "db_instance_class": ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.SMALL),
                "db_allocated_storage": 50,
                "multi_az": False,
                "deletion_protection": False,
            },
            "production": {
                "instance_type": ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
                "min_size": 2,
                "max_size": 6,
                "desired_capacity": 3,
                "db_instance_class": ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
                "db_allocated_storage": 100,
                "multi_az": True,
                "deletion_protection": True,
            },
        }
        
        return configs.get(self.environment, configs["development"])

    def _create_load_balancer(self, alb_security_group: ec2.ISecurityGroup) -> None:
        """Create Application Load Balancer and target group."""
        
        # Application Load Balancer
        self.load_balancer = elbv2.ApplicationLoadBalancer(
            self,
            "ApplicationLoadBalancer",
            load_balancer_name=f"{self.project_name}-{self.environment}-alb",
            vpc=self.vpc,
            internet_facing=True,
            security_group=alb_security_group,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
        )

        # Target Group
        self.target_group = elbv2.ApplicationTargetGroup(
            self,
            "ApplicationTargetGroup",
            target_group_name=f"{self.project_name}-{self.environment}-tg",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
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
            target_type=elbv2.TargetType.INSTANCE,
            deregistration_delay=Duration.seconds(300),
        )

        # Listener
        self.load_balancer.add_listener(
            "ApplicationListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[self.target_group],
        )

        # Tag load balancer resources
        cdk.Tags.of(self.load_balancer).add("Component", "LoadBalancer")
        cdk.Tags.of(self.target_group).add("Component", "LoadBalancer")

    def _create_auto_scaling_group(
        self,
        application_security_group: ec2.ISecurityGroup,
        ec2_instance_role: iam.IRole,
    ) -> None:
        """Create Auto Scaling Group with launch template."""
        
        # User data script for EC2 instances
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "yum update -y",
            "yum install -y httpd",
            "systemctl start httpd",
            "systemctl enable httpd",
            "",
            "# Create simple health check endpoint",
            f"echo '<html><body><h1>Application Running</h1><p>Environment: {self.environment}</p></body></html>' > /var/www/html/index.html",
            "echo 'OK' > /var/www/html/health",
            "",
            "# Install CloudWatch agent",
            "yum install -y amazon-cloudwatch-agent",
            "",
            "# Configure CloudWatch agent",
            "cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'",
            "{",
            '  "logs": {',
            '    "logs_collected": {',
            '      "files": {',
            '        "collect_list": [',
            "          {",
            '            "file_path": "/var/log/httpd/access_log",',
            f'            "log_group_name": "/aws/ec2/{self.project_name}-{self.environment}/httpd/access",',
            '            "log_stream_name": "{instance_id}"',
            "          }",
            "        ]",
            "      }",
            "    }",
            "  }",
            "}",
            "CWCONFIG",
            "",
            "# Start CloudWatch agent",
            "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \\",
            "  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s",
        )

        # Launch Template
        launch_template = ec2.LaunchTemplate(
            self,
            "ApplicationLaunchTemplate",
            launch_template_name=f"{self.project_name}-{self.environment}-template",
            instance_type=self.config["instance_type"],
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            security_group=application_security_group,
            role=ec2_instance_role,
            user_data=user_data,
        )

        # Auto Scaling Group
        self.auto_scaling_group = autoscaling.AutoScalingGroup(
            self,
            "ApplicationAutoScalingGroup",
            auto_scaling_group_name=f"{self.project_name}-{self.environment}-asg",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            launch_template=launch_template,
            min_capacity=self.config["min_size"],
            max_capacity=self.config["max_size"],
            desired_capacity=self.config["desired_capacity"],
            health_check=autoscaling.HealthCheck.elb(grace=Duration.seconds(300)),
        )

        # Attach to target group
        self.auto_scaling_group.attach_to_application_target_group(self.target_group)

        # Tag Auto Scaling Group
        cdk.Tags.of(self.auto_scaling_group).add("Component", "Application")

    def _create_database(
        self,
        database_security_group: ec2.ISecurityGroup,
        rds_monitoring_role: iam.IRole,
    ) -> None:
        """Create RDS MySQL database with security."""
        
        # Database credentials secret
        self.database_secret = secretsmanager.Secret(
            self,
            "DatabaseSecret",
            secret_name=f"{self.project_name}-{self.environment}-db-secret",
            description="Database credentials",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "admin"}',
                generate_string_key="password",
                password_length=16,
                exclude_characters='"@/\\',
            ),
        )

        # Database subnet group
        db_subnet_group = rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            description="Subnet group for RDS database",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
        )

        # RDS Database Instance
        self.database = rds.DatabaseInstance(
            self,
            "DatabaseInstance",
            instance_identifier=f"{self.project_name}-{self.environment}-db",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            instance_type=self.config["db_instance_class"],
            credentials=rds.Credentials.from_secret(self.database_secret),
            allocated_storage=self.config["db_allocated_storage"],
            storage_type=rds.StorageType.GP2,
            storage_encrypted=True,
            vpc=self.vpc,
            security_groups=[database_security_group],
            subnet_group=db_subnet_group,
            backup_retention=Duration.days(7),
            multi_az=self.config["multi_az"],
            monitoring_interval=Duration.seconds(60),
            monitoring_role=rds_monitoring_role,
            enable_performance_insights=True,
            deletion_protection=self.config["deletion_protection"],
            removal_policy=RemovalPolicy.DESTROY if self.environment != "production" else RemovalPolicy.RETAIN,
        )

        # Tag database resources
        cdk.Tags.of(self.database).add("Component", "Database")
        cdk.Tags.of(self.database_secret).add("Component", "Database")

    def _create_outputs(self) -> None:
        """Create stack outputs for verification and integration."""
        
        CfnOutput(
            self,
            "LoadBalancerDNS",
            value=self.load_balancer.load_balancer_dns_name,
            description="Application Load Balancer DNS name",
            export_name=f"{self.stack_name}-LoadBalancerDNS",
        )

        CfnOutput(
            self,
            "LoadBalancerArn",
            value=self.load_balancer.load_balancer_arn,
            description="Application Load Balancer ARN",
            export_name=f"{self.stack_name}-LoadBalancerArn",
        )

        CfnOutput(
            self,
            "AutoScalingGroupName",
            value=self.auto_scaling_group.auto_scaling_group_name,
            description="Auto Scaling Group name",
            export_name=f"{self.stack_name}-AutoScalingGroupName",
        )

        CfnOutput(
            self,
            "DatabaseEndpoint",
            value=self.database.instance_endpoint.hostname,
            description="RDS database endpoint",
            export_name=f"{self.stack_name}-DatabaseEndpoint",
        )

        CfnOutput(
            self,
            "DatabasePort",
            value=str(self.database.instance_endpoint.port),
            description="RDS database port",
            export_name=f"{self.stack_name}-DatabasePort",
        )

        CfnOutput(
            self,
            "DatabaseSecretArn",
            value=self.database_secret.secret_arn,
            description="Database secret ARN",
            export_name=f"{self.stack_name}-DatabaseSecretArn",
        )


class NestedStacksApp(cdk.App):
    """
    Main CDK application that orchestrates the nested stack architecture.
    
    This class creates multiple stacks with proper dependencies:
    1. Network Stack - VPC and networking infrastructure
    2. Security Stack - IAM roles and security groups
    3. Application Stack - Load balancer, compute, and database
    
    The stacks communicate through direct references and demonstrate
    the same patterns as CloudFormation nested stacks.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or use defaults
        environment = os.environ.get("ENVIRONMENT", "development")
        project_name = os.environ.get("PROJECT_NAME", "webapp")
        aws_account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        aws_region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

        # Validate environment
        if environment not in ["development", "staging", "production"]:
            raise ValueError(f"Invalid environment: {environment}. Must be one of: development, staging, production")

        # Create environment for stack deployment
        env = Environment(account=aws_account, region=aws_region)

        # Common stack props
        common_props = StackProps(
            env=env,
            tags={
                "Environment": environment,
                "Project": project_name,
                "ManagedBy": "CDK",
            },
        )

        # Create Network Stack
        network_stack = NetworkStack(
            self,
            f"{project_name}-{environment}-network",
            environment=environment,
            project_name=project_name,
            **common_props,
        )

        # Create Security Stack (depends on Network Stack)
        security_stack = SecurityStack(
            self,
            f"{project_name}-{environment}-security",
            environment=environment,
            project_name=project_name,
            vpc=network_stack.vpc,
            **common_props,
        )
        security_stack.add_dependency(network_stack)

        # Create Application Stack (depends on Network and Security Stacks)
        application_stack = ApplicationStack(
            self,
            f"{project_name}-{environment}-application",
            environment=environment,
            project_name=project_name,
            vpc=network_stack.vpc,
            alb_security_group=security_stack.alb_security_group,
            application_security_group=security_stack.application_security_group,
            database_security_group=security_stack.database_security_group,
            ec2_instance_role=security_stack.ec2_instance_role,
            rds_monitoring_role=security_stack.rds_monitoring_role,
            **common_props,
        )
        application_stack.add_dependency(network_stack)
        application_stack.add_dependency(security_stack)


# Create and run the application
app = NestedStacksApp()
app.synth()