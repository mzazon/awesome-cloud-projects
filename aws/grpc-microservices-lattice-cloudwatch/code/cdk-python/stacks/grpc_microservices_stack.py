"""
gRPC Microservices Stack with VPC Lattice and CloudWatch

This stack implements a complete gRPC microservices architecture using:
- VPC Lattice Service Network for intelligent routing
- EC2 instances hosting gRPC services with health endpoints
- CloudWatch monitoring, metrics, and alarms
- Advanced routing rules for API versioning and method-based routing
"""

from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_vpclattice as vpclattice
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_logs as logs
from aws_cdk import aws_iam as iam
from constructs import Construct


class GrpcMicroservicesStack(Stack):
    """
    CDK Stack for gRPC Microservices with VPC Lattice and CloudWatch.
    
    This stack creates a complete microservices architecture optimized for gRPC
    communication with intelligent routing, health monitoring, and observability.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment_name: str = "development",
        instance_type: str = "t3.micro",
        enable_detailed_monitoring: bool = True,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.environment_name = environment_name
        self.instance_type = instance_type
        self.enable_detailed_monitoring = enable_detailed_monitoring

        # Create foundational network infrastructure
        self.vpc = self._create_vpc()
        self.security_group = self._create_security_group()

        # Create VPC Lattice service network
        self.service_network = self._create_service_network()
        self.vpc_association = self._create_vpc_association()

        # Create target groups for each gRPC service
        self.target_groups = self._create_target_groups()

        # Launch EC2 instances for gRPC services
        self.instances = self._create_ec2_instances()

        # Register instances with target groups
        self._register_instances_with_target_groups()

        # Create VPC Lattice services
        self.lattice_services = self._create_lattice_services()

        # Associate services with service network
        self.service_associations = self._create_service_associations()

        # Create listeners for gRPC services
        self.listeners = self._create_listeners()

        # Create advanced routing rules
        self._create_routing_rules()

        # Setup CloudWatch monitoring
        self._setup_cloudwatch_monitoring()

        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()

        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC for the gRPC microservices."""
        vpc = ec2.Vpc(
            self,
            "GrpcVpc",
            vpc_name=f"grpc-vpc-{self.environment_name}",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add tags
        cdk.Tags.of(vpc).add("Name", f"grpc-vpc-{self.environment_name}")
        cdk.Tags.of(vpc).add("Purpose", "gRPC-Microservices")

        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for gRPC services."""
        sg = ec2.SecurityGroup(
            self,
            "GrpcSecurityGroup",
            vpc=self.vpc,
            description="Security group for gRPC microservices",
            security_group_name=f"grpc-services-{self.environment_name}",
        )

        # Allow gRPC traffic (ports 50051-50053)
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/16"),
            connection=ec2.Port.tcp_range(50051, 50053),
            description="gRPC service ports",
        )

        # Allow health check traffic (port 8080)
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/16"),
            connection=ec2.Port.tcp(8080),
            description="Health check endpoint",
        )

        # Allow HTTPS for VPC Lattice
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/16"),
            connection=ec2.Port.tcp(443),
            description="HTTPS for VPC Lattice",
        )

        return sg

    def _create_service_network(self) -> vpclattice.CfnServiceNetwork:
        """Create VPC Lattice service network."""
        service_network = vpclattice.CfnServiceNetwork(
            self,
            "GrpcServiceNetwork",
            name=f"grpc-microservices-{self.environment_name}",
            auth_type="AWS_IAM",
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment_name),
                cdk.CfnTag(key="Purpose", value="gRPC-Services"),
            ],
        )

        return service_network

    def _create_vpc_association(self) -> vpclattice.CfnServiceNetworkVpcAssociation:
        """Associate VPC with service network."""
        vpc_association = vpclattice.CfnServiceNetworkVpcAssociation(
            self,
            "VpcAssociation",
            service_network_identifier=self.service_network.attr_id,
            vpc_identifier=self.vpc.vpc_id,
            tags=[
                cdk.CfnTag(key="Service", value="gRPC-Network"),
            ],
        )

        return vpc_association

    def _create_target_groups(self) -> Dict[str, vpclattice.CfnTargetGroup]:
        """Create target groups for each gRPC service."""
        services = ["user", "order", "inventory"]
        ports = [50051, 50052, 50053]
        target_groups = {}

        for service, port in zip(services, ports):
            target_group = vpclattice.CfnTargetGroup(
                self,
                f"{service.title()}TargetGroup",
                name=f"{service}-service-{self.environment_name}",
                type="INSTANCE",
                config=vpclattice.CfnTargetGroup.TargetGroupConfigProperty(
                    port=port,
                    protocol="HTTP",
                    protocol_version="HTTP2",
                    vpc_identifier=self.vpc.vpc_id,
                    health_check=vpclattice.CfnTargetGroup.HealthCheckConfigProperty(
                        enabled=True,
                        protocol="HTTP",
                        protocol_version="HTTP1",
                        port=8080,
                        path="/health",
                        health_check_interval_seconds=30,
                        health_check_timeout_seconds=5,
                        healthy_threshold_count=2,
                        unhealthy_threshold_count=3,
                        matcher=vpclattice.CfnTargetGroup.MatcherProperty(
                            http_code="200"
                        ),
                    ),
                ),
                tags=[
                    cdk.CfnTag(key="Service", value=f"{service.title()}Service"),
                ],
            )

            target_groups[service] = target_group

        return target_groups

    def _create_ec2_instances(self) -> Dict[str, ec2.Instance]:
        """Create EC2 instances for gRPC services."""
        # Get latest Amazon Linux 2 AMI
        ami = ec2.MachineImage.latest_amazon_linux2(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
        )

        # Create IAM role for EC2 instances
        instance_role = iam.Role(
            self,
            "InstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
            ],
        )

        # User data script for gRPC services
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "yum update -y",
            "yum install -y python3 python3-pip",
            "pip3 install grpcio grpcio-tools flask",
            "",
            "# Create a simple gRPC health server",
            "cat > /home/ec2-user/health_server.py << 'PYEOF'",
            "from flask import Flask",
            "import json",
            "app = Flask(__name__)",
            "",
            "@app.route('/health')",
            "def health():",
            "    return json.dumps({'status': 'healthy', 'service': 'grpc-service'}), 200",
            "",
            "if __name__ == '__main__':",
            "    app.run(host='0.0.0.0', port=8080)",
            "PYEOF",
            "",
            "# Start health check server",
            "nohup python3 /home/ec2-user/health_server.py &",
        )

        services = ["user", "order", "inventory"]
        instances = {}

        for service in services:
            instance = ec2.Instance(
                self,
                f"{service.title()}Instance",
                instance_name=f"{service}-service-{self.environment_name}",
                instance_type=ec2.InstanceType(self.instance_type),
                machine_image=ami,
                vpc=self.vpc,
                vpc_subnets=ec2.SubnetSelection(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
                ),
                security_group=self.security_group,
                role=instance_role,
                user_data=user_data,
                detailed_monitoring=self.enable_detailed_monitoring,
            )

            # Add tags
            cdk.Tags.of(instance).add("Service", f"{service.title()}Service")
            cdk.Tags.of(instance).add("Environment", self.environment_name)

            instances[service] = instance

        return instances

    def _register_instances_with_target_groups(self) -> None:
        """Register EC2 instances with their respective target groups."""
        services = ["user", "order", "inventory"]

        for service in services:
            instance = self.instances[service]
            target_group = self.target_groups[service]

            # Create target registration
            vpclattice.CfnTargetGroupTargetAttachment(
                self,
                f"{service.title()}TargetAttachment",
                target_group_identifier=target_group.attr_id,
                target=vpclattice.CfnTargetGroupTargetAttachment.TargetProperty(
                    id=instance.instance_id
                ),
            )

    def _create_lattice_services(self) -> Dict[str, vpclattice.CfnService]:
        """Create VPC Lattice services."""
        services = ["user", "order", "inventory"]
        lattice_services = {}

        for service in services:
            lattice_service = vpclattice.CfnService(
                self,
                f"{service.title()}Service",
                name=f"{service}-service-{self.environment_name}",
                auth_type="AWS_IAM",
                tags=[
                    cdk.CfnTag(key="Service", value=f"{service.title()}Service"),
                    cdk.CfnTag(key="Protocol", value="gRPC"),
                ],
            )

            lattice_services[service] = lattice_service

        return lattice_services

    def _create_service_associations(self) -> Dict[str, vpclattice.CfnServiceNetworkServiceAssociation]:
        """Associate services with service network."""
        services = ["user", "order", "inventory"]
        associations = {}

        for service in services:
            association = vpclattice.CfnServiceNetworkServiceAssociation(
                self,
                f"{service.title()}ServiceAssociation",
                service_network_identifier=self.service_network.attr_id,
                service_identifier=self.lattice_services[service].attr_id,
                tags=[
                    cdk.CfnTag(key="Service", value=f"{service.title()}Service"),
                ],
            )

            associations[service] = association

        return associations

    def _create_listeners(self) -> Dict[str, vpclattice.CfnListener]:
        """Create HTTP/2 listeners for gRPC services."""
        services = ["user", "order", "inventory"]
        listeners = {}

        for service in services:
            listener = vpclattice.CfnListener(
                self,
                f"{service.title()}Listener",
                service_identifier=self.lattice_services[service].attr_id,
                name="grpc-listener",
                protocol="HTTPS",
                port=443,
                default_action=vpclattice.CfnListener.DefaultActionProperty(
                    forward=vpclattice.CfnListener.ForwardProperty(
                        target_groups=[
                            vpclattice.CfnListener.WeightedTargetGroupProperty(
                                target_group_identifier=self.target_groups[service].attr_id,
                                weight=100,
                            )
                        ]
                    )
                ),
                tags=[
                    cdk.CfnTag(key="Protocol", value="gRPC"),
                ],
            )

            listeners[service] = listener

        return listeners

    def _create_routing_rules(self) -> None:
        """Create advanced routing rules for gRPC services."""
        # Create API versioning rule for User Service
        vpclattice.CfnRule(
            self,
            "UserServiceV2Rule",
            service_identifier=self.lattice_services["user"].attr_id,
            listener_identifier=self.listeners["user"].attr_id,
            name="v2-api-routing",
            priority=10,
            match=vpclattice.CfnRule.MatchProperty(
                http_match=vpclattice.CfnRule.HttpMatchProperty(
                    header_matches=[
                        vpclattice.CfnRule.HeaderMatchProperty(
                            name="grpc-version",
                            match=vpclattice.CfnRule.HeaderMatchTypeProperty(
                                exact="v2"
                            ),
                        )
                    ]
                )
            ),
            action=vpclattice.CfnRule.ActionProperty(
                forward=vpclattice.CfnRule.ForwardProperty(
                    target_groups=[
                        vpclattice.CfnRule.WeightedTargetGroupProperty(
                            target_group_identifier=self.target_groups["user"].attr_id,
                            weight=100,
                        )
                    ]
                )
            ),
            tags=[
                cdk.CfnTag(key="Purpose", value="APIVersioning"),
            ],
        )

        # Create path-based routing for Order Service methods
        vpclattice.CfnRule(
            self,
            "OrderProcessingRule",
            service_identifier=self.lattice_services["order"].attr_id,
            listener_identifier=self.listeners["order"].attr_id,
            name="order-processing-rule",
            priority=20,
            match=vpclattice.CfnRule.MatchProperty(
                http_match=vpclattice.CfnRule.HttpMatchProperty(
                    path_match=vpclattice.CfnRule.PathMatchProperty(
                        match=vpclattice.CfnRule.PathMatchTypeProperty(
                            prefix="/order.OrderService/Process"
                        )
                    )
                )
            ),
            action=vpclattice.CfnRule.ActionProperty(
                forward=vpclattice.CfnRule.ForwardProperty(
                    target_groups=[
                        vpclattice.CfnRule.WeightedTargetGroupProperty(
                            target_group_identifier=self.target_groups["order"].attr_id,
                            weight=100,
                        )
                    ]
                )
            ),
            tags=[
                cdk.CfnTag(key="Purpose", value="MethodRouting"),
            ],
        )

    def _setup_cloudwatch_monitoring(self) -> None:
        """Setup CloudWatch monitoring and logging."""
        # Create log group for VPC Lattice access logs
        self.log_group = logs.LogGroup(
            self,
            "VpcLatticeLogGroup",
            log_group_name=f"/aws/vpc-lattice/grpc-services-{self.environment_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Enable access logging for service network
        vpclattice.CfnAccessLogSubscription(
            self,
            "AccessLogSubscription",
            resource_identifier=self.service_network.attr_id,
            destination_arn=self.log_group.log_group_arn,
        )

        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "GrpcMicroservicesDashboard",
            dashboard_name=f"gRPC-Microservices-{self.environment_name}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="gRPC Request Count",
                        width=12,
                        height=6,
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="TotalRequestCount",
                                dimensions_map={
                                    "Service": f"user-service-{self.environment_name}"
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="TotalRequestCount",
                                dimensions_map={
                                    "Service": f"order-service-{self.environment_name}"
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="TotalRequestCount",
                                dimensions_map={
                                    "Service": f"inventory-service-{self.environment_name}"
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                    ),
                    cloudwatch.GraphWidget(
                        title="gRPC Request Latency",
                        width=12,
                        height=6,
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="RequestTime",
                                dimensions_map={
                                    "Service": f"user-service-{self.environment_name}"
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="RequestTime",
                                dimensions_map={
                                    "Service": f"order-service-{self.environment_name}"
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/VpcLattice",
                                metric_name="RequestTime",
                                dimensions_map={
                                    "Service": f"inventory-service-{self.environment_name}"
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                        ],
                    ),
                ],
            ],
        )

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for service health monitoring."""
        # High error rate alarm for User Service
        cloudwatch.Alarm(
            self,
            "UserServiceHighErrorRate",
            alarm_name=f"gRPC-UserService-HighErrorRate-{self.environment_name}",
            alarm_description="High error rate in User Service",
            metric=cloudwatch.Metric(
                namespace="AWS/VpcLattice",
                metric_name="HTTPCode_5XX_Count",
                dimensions_map={
                    "Service": f"user-service-{self.environment_name}"
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=10,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # High latency alarm for Order Service
        cloudwatch.Alarm(
            self,
            "OrderServiceHighLatency",
            alarm_name=f"gRPC-OrderService-HighLatency-{self.environment_name}",
            alarm_description="High latency in Order Service",
            metric=cloudwatch.Metric(
                namespace="AWS/VpcLattice",
                metric_name="RequestTime",
                dimensions_map={
                    "Service": f"order-service-{self.environment_name}"
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=1000,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # Connection failures alarm
        cloudwatch.Alarm(
            self,
            "ServicesConnectionFailures",
            alarm_name=f"gRPC-Services-ConnectionFailures-{self.environment_name}",
            alarm_description="High connection failure rate",
            metric=cloudwatch.Metric(
                namespace="AWS/VpcLattice",
                metric_name="ConnectionErrorCount",
                dimensions_map={
                    "TargetGroup": f"user-service-{self.environment_name}"
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="VPC Lattice Service Network ID",
        )

        CfnOutput(
            self,
            "ServiceNetworkDns",
            value=self.service_network.attr_dns_entry_domain_name,
            description="VPC Lattice Service Network DNS",
        )

        # Output service endpoints
        for service in ["user", "order", "inventory"]:
            CfnOutput(
                self,
                f"{service.title()}ServiceEndpoint",
                value=self.lattice_services[service].attr_dns_entry_domain_name,
                description=f"{service.title()} Service gRPC endpoint",
            )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL",
        )

        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="VPC Lattice access logs CloudWatch Log Group",
        )