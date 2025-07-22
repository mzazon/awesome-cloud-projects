#!/usr/bin/env python3
"""
AWS CDK Python Application for Elastic Load Balancing with Application and Network Load Balancers

This application demonstrates implementing both Application Load Balancers (ALB) and Network Load Balancers (NLB)
with EC2 instances, target groups, and proper security configurations following AWS best practices.

Features:
- Application Load Balancer for HTTP/HTTPS traffic with Layer 7 routing
- Network Load Balancer for high-performance TCP/UDP traffic
- EC2 instances with auto-generated web content
- Target groups with health checks
- Security groups with least privilege access
- Multi-AZ deployment for high availability
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    aws_ec2 as ec2,
    aws_elasticloadbalancingv2 as elbv2,
    aws_iam as iam,
    CfnOutput,
    Tags,
)
from constructs import Construct
from typing import List, Dict, Any
import json


class ElasticLoadBalancingStack(Stack):
    """
    AWS CDK Stack for Elastic Load Balancing demonstration.
    
    This stack creates:
    - VPC with public and private subnets
    - Application Load Balancer (ALB)
    - Network Load Balancer (NLB)
    - EC2 instances with web servers
    - Target groups with health checks
    - Security groups with proper access controls
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str = "elb-demo",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.project_name = project_name
        
        # Create VPC infrastructure
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.security_groups = self._create_security_groups()
        
        # Create EC2 instances
        self.instances = self._create_ec2_instances()
        
        # Create load balancers and target groups
        self.alb, self.alb_target_group = self._create_application_load_balancer()
        self.nlb, self.nlb_target_group = self._create_network_load_balancer()
        
        # Configure target group attributes
        self._configure_target_group_attributes()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets across multiple AZs.
        
        Returns:
            ec2.Vpc: The created VPC
        """
        vpc = ec2.Vpc(
            self,
            "ElbVpc",
            vpc_name=f"{self.project_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
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
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Add VPC Flow Logs for monitoring
        vpc_flow_log_role = iam.Role(
            self,
            "VpcFlowLogRole",
            assumed_by=iam.ServicePrincipal("vpc-flow-logs.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/VPCFlowLogsDeliveryRolePolicy"
                )
            ],
        )
        
        ec2.FlowLog(
            self,
            "VpcFlowLog",
            resource_type=ec2.FlowLogResourceType.from_vpc(vpc),
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )
        
        return vpc

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """
        Create security groups for ALB, NLB, and EC2 instances.
        
        Returns:
            Dict[str, ec2.SecurityGroup]: Dictionary of security groups
        """
        # Security group for Application Load Balancer
        alb_sg = ec2.SecurityGroup(
            self,
            "AlbSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            security_group_name=f"{self.project_name}-alb-sg",
            allow_all_outbound=False,
        )
        
        # Allow HTTP and HTTPS traffic from internet
        alb_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from internet",
        )
        alb_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from internet",
        )
        
        # Allow outbound HTTP traffic to EC2 instances
        alb_sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic to EC2 instances",
        )
        
        # Security group for Network Load Balancer
        nlb_sg = ec2.SecurityGroup(
            self,
            "NlbSecurityGroup",
            vpc=self.vpc,
            description="Security group for Network Load Balancer",
            security_group_name=f"{self.project_name}-nlb-sg",
            allow_all_outbound=False,
        )
        
        # Allow TCP traffic on port 80
        nlb_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow TCP traffic on port 80",
        )
        
        # Allow outbound TCP traffic to EC2 instances
        nlb_sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow TCP traffic to EC2 instances",
        )
        
        # Security group for EC2 instances
        ec2_sg = ec2.SecurityGroup(
            self,
            "Ec2SecurityGroup",
            vpc=self.vpc,
            description="Security group for EC2 instances behind load balancers",
            security_group_name=f"{self.project_name}-ec2-sg",
            allow_all_outbound=True,
        )
        
        # Allow HTTP traffic from ALB
        ec2_sg.add_ingress_rule(
            peer=alb_sg,
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from ALB",
        )
        
        # Allow HTTP traffic from NLB
        ec2_sg.add_ingress_rule(
            peer=nlb_sg,
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from NLB",
        )
        
        # Allow SSH access for management (optional)
        ec2_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access for management",
        )
        
        return {
            "alb": alb_sg,
            "nlb": nlb_sg,
            "ec2": ec2_sg,
        }

    def _create_ec2_instances(self) -> List[ec2.Instance]:
        """
        Create EC2 instances with web servers across multiple AZs.
        
        Returns:
            List[ec2.Instance]: List of created EC2 instances
        """
        # Get the latest Amazon Linux 2 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
        )
        
        # Create IAM role for EC2 instances
        ec2_role = iam.Role(
            self,
            "Ec2Role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                )
            ],
        )
        
        # User data script for web server setup
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "yum update -y",
            "yum install -y httpd",
            "systemctl start httpd",
            "systemctl enable httpd",
            'echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html',
            'echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html',
            'echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html',
            'echo "<p>Load Balancer Test: $(date)</p>" >> /var/www/html/index.html',
        )
        
        instances = []
        
        # Create instances in private subnets across multiple AZs
        for i, subnet in enumerate(self.vpc.private_subnets[:2]):
            instance = ec2.Instance(
                self,
                f"WebServer{i+1}",
                instance_name=f"{self.project_name}-web-{i+1}",
                instance_type=ec2.InstanceType.of(
                    ec2.InstanceClass.T3, ec2.InstanceSize.MICRO
                ),
                machine_image=amzn_linux,
                vpc=self.vpc,
                vpc_subnets=ec2.SubnetSelection(subnets=[subnet]),
                security_group=self.security_groups["ec2"],
                user_data=user_data,
                role=ec2_role,
                detailed_monitoring=True,
                source_dest_check=False,
            )
            instances.append(instance)
        
        return instances

    def _create_application_load_balancer(self) -> tuple[elbv2.ApplicationLoadBalancer, elbv2.ApplicationTargetGroup]:
        """
        Create Application Load Balancer with target group and listener.
        
        Returns:
            tuple: ALB and target group
        """
        # Create Application Load Balancer
        alb = elbv2.ApplicationLoadBalancer(
            self,
            "ApplicationLoadBalancer",
            load_balancer_name=f"{self.project_name}-alb",
            vpc=self.vpc,
            internet_facing=True,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            security_group=self.security_groups["alb"],
            deletion_protection=False,
        )
        
        # Create target group for ALB
        target_group = elbv2.ApplicationTargetGroup(
            self,
            "AlbTargetGroup",
            target_group_name=f"{self.project_name}-alb-tg",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
            target_type=elbv2.TargetType.INSTANCE,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                interval=cdk.Duration.seconds(30),
                path="/",
                protocol=elbv2.Protocol.HTTP,
                timeout=cdk.Duration.seconds(5),
                healthy_threshold_count=2,
                unhealthy_threshold_count=5,
            ),
        )
        
        # Add targets to target group
        for instance in self.instances:
            target_group.add_target(
                elbv2.InstanceTarget(instance.instance_id, 80)
            )
        
        # Create listener for ALB
        listener = alb.add_listener(
            "AlbListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_action=elbv2.ListenerAction.forward([target_group]),
        )
        
        return alb, target_group

    def _create_network_load_balancer(self) -> tuple[elbv2.NetworkLoadBalancer, elbv2.NetworkTargetGroup]:
        """
        Create Network Load Balancer with target group and listener.
        
        Returns:
            tuple: NLB and target group
        """
        # Create Network Load Balancer
        nlb = elbv2.NetworkLoadBalancer(
            self,
            "NetworkLoadBalancer",
            load_balancer_name=f"{self.project_name}-nlb",
            vpc=self.vpc,
            internet_facing=True,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            deletion_protection=False,
        )
        
        # Create target group for NLB
        target_group = elbv2.NetworkTargetGroup(
            self,
            "NlbTargetGroup",
            target_group_name=f"{self.project_name}-nlb-tg",
            port=80,
            protocol=elbv2.Protocol.TCP,
            vpc=self.vpc,
            target_type=elbv2.TargetType.INSTANCE,
            health_check=elbv2.HealthCheck(
                enabled=True,
                interval=cdk.Duration.seconds(30),
                path="/",
                protocol=elbv2.Protocol.HTTP,
                timeout=cdk.Duration.seconds(6),
                healthy_threshold_count=2,
                unhealthy_threshold_count=2,
            ),
        )
        
        # Add targets to target group
        for instance in self.instances:
            target_group.add_target(
                elbv2.InstanceTarget(instance.instance_id, 80)
            )
        
        # Create listener for NLB
        listener = nlb.add_listener(
            "NlbListener",
            port=80,
            protocol=elbv2.Protocol.TCP,
            default_action=elbv2.NetworkListenerAction.forward([target_group]),
        )
        
        return nlb, target_group

    def _configure_target_group_attributes(self) -> None:
        """Configure target group attributes for optimal performance."""
        # Configure ALB target group attributes
        alb_cfn_target_group = self.alb_target_group.node.default_child
        alb_cfn_target_group.target_group_attributes = [
            {
                "key": "deregistration_delay.timeout_seconds",
                "value": "30"
            },
            {
                "key": "stickiness.enabled",
                "value": "true"
            },
            {
                "key": "stickiness.type",
                "value": "lb_cookie"
            },
            {
                "key": "stickiness.lb_cookie.duration_seconds",
                "value": "86400"
            },
        ]
        
        # Configure NLB target group attributes
        nlb_cfn_target_group = self.nlb_target_group.node.default_child
        nlb_cfn_target_group.target_group_attributes = [
            {
                "key": "deregistration_delay.timeout_seconds",
                "value": "30"
            },
            {
                "key": "preserve_client_ip.enabled",
                "value": "true"
            },
        ]

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        # VPC outputs
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID",
            export_name=f"{self.project_name}-vpc-id",
        )
        
        # ALB outputs
        CfnOutput(
            self,
            "AlbDnsName",
            value=self.alb.load_balancer_dns_name,
            description="Application Load Balancer DNS Name",
            export_name=f"{self.project_name}-alb-dns",
        )
        
        CfnOutput(
            self,
            "AlbArn",
            value=self.alb.load_balancer_arn,
            description="Application Load Balancer ARN",
            export_name=f"{self.project_name}-alb-arn",
        )
        
        # NLB outputs
        CfnOutput(
            self,
            "NlbDnsName",
            value=self.nlb.load_balancer_dns_name,
            description="Network Load Balancer DNS Name",
            export_name=f"{self.project_name}-nlb-dns",
        )
        
        CfnOutput(
            self,
            "NlbArn",
            value=self.nlb.load_balancer_arn,
            description="Network Load Balancer ARN",
            export_name=f"{self.project_name}-nlb-arn",
        )
        
        # Target group outputs
        CfnOutput(
            self,
            "AlbTargetGroupArn",
            value=self.alb_target_group.target_group_arn,
            description="ALB Target Group ARN",
            export_name=f"{self.project_name}-alb-tg-arn",
        )
        
        CfnOutput(
            self,
            "NlbTargetGroupArn",
            value=self.nlb_target_group.target_group_arn,
            description="NLB Target Group ARN",
            export_name=f"{self.project_name}-nlb-tg-arn",
        )
        
        # EC2 instance outputs
        for i, instance in enumerate(self.instances):
            CfnOutput(
                self,
                f"Instance{i+1}Id",
                value=instance.instance_id,
                description=f"EC2 Instance {i+1} ID",
                export_name=f"{self.project_name}-instance-{i+1}-id",
            )
        
        # Security group outputs
        CfnOutput(
            self,
            "AlbSecurityGroupId",
            value=self.security_groups["alb"].security_group_id,
            description="ALB Security Group ID",
            export_name=f"{self.project_name}-alb-sg-id",
        )
        
        CfnOutput(
            self,
            "NlbSecurityGroupId",
            value=self.security_groups["nlb"].security_group_id,
            description="NLB Security Group ID",
            export_name=f"{self.project_name}-nlb-sg-id",
        )
        
        CfnOutput(
            self,
            "Ec2SecurityGroupId",
            value=self.security_groups["ec2"].security_group_id,
            description="EC2 Security Group ID",
            export_name=f"{self.project_name}-ec2-sg-id",
        )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        tags = {
            "Project": self.project_name,
            "Environment": "demo",
            "ManagedBy": "CDK",
            "Recipe": "elastic-load-balancing-application-network-load-balancers",
        }
        
        for key, value in tags.items():
            Tags.of(self).add(key, value)


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get project name from context or use default
    project_name = app.node.try_get_context("project_name") or "elb-demo"
    
    # Create the stack
    stack = ElasticLoadBalancingStack(
        app,
        "ElasticLoadBalancingStack",
        project_name=project_name,
        env=Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region"),
        ),
        description="Elastic Load Balancing with Application and Network Load Balancers (CDK Python)",
    )
    
    # Add additional tags at the app level
    Tags.of(app).add("CDKVersion", cdk.VERSION)
    Tags.of(app).add("CreatedBy", "CDK-Python")
    
    # Synthesize the stack
    app.synth()


if __name__ == "__main__":
    main()