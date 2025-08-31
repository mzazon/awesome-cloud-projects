#!/usr/bin/env python3
"""
AWS CDK Python Application for Self-Managed Kubernetes Integration with VPC Lattice IP Targets

This application deploys infrastructure for connecting self-managed Kubernetes clusters across VPCs
using VPC Lattice as a service mesh layer with IP targets for direct pod communication.

The architecture includes:
- Two separate VPCs (VPC A and VPC B) for Kubernetes clusters
- VPC Lattice service network for cross-VPC communication
- IP target groups for direct pod registration
- CloudWatch monitoring and logging
- Security groups with VPC Lattice integration
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    Environment,
    Stack,
    Tags,
)
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from aws_cdk import aws_vpclattice as lattice
from aws_cdk import aws_cloudwatch as cloudwatch

from constructs import Construct


class KubernetesVPCLatticeStack(Stack):
    """
    CDK Stack for Kubernetes Integration with VPC Lattice IP Targets.
    
    This stack creates a complete infrastructure for connecting self-managed
    Kubernetes clusters across VPCs using VPC Lattice service mesh.
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        deployment_name: str,
        ssh_key_name: Optional[str] = None,
        **kwargs,
    ) -> None:
        """
        Initialize the Kubernetes VPC Lattice Stack.
        
        Args:
            scope: The CDK scope (usually the CDK App)
            construct_id: Unique identifier for this construct
            deployment_name: Name prefix for all resources
            ssh_key_name: Name of EC2 key pair for SSH access (optional)
            **kwargs: Additional stack configuration
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.deployment_name = deployment_name
        self.ssh_key_name = ssh_key_name
        
        # Create VPC infrastructure for both Kubernetes clusters
        self.vpc_a, self.subnet_a, self.sg_a = self._create_kubernetes_vpc(
            "ClusterA", "10.0.0.0/16", "10.0.1.0/24"
        )
        
        self.vpc_b, self.subnet_b, self.sg_b = self._create_kubernetes_vpc(
            "ClusterB", "10.1.0.0/16", "10.1.1.0/24"
        )
        
        # Create EC2 instances for Kubernetes control planes
        self.instance_a = self._create_kubernetes_instance(
            "InstanceA", self.vpc_a, self.subnet_a, self.sg_a
        )
        
        self.instance_b = self._create_kubernetes_instance(
            "InstanceB", self.vpc_b, self.subnet_b, self.sg_b
        )
        
        # Create VPC Lattice service network
        self.service_network = self._create_service_network()
        
        # Associate VPCs with service network
        self._associate_vpcs_with_service_network()
        
        # Create target groups for pod IP addresses
        self.frontend_target_group = self._create_target_group(
            "FrontendTG", self.vpc_a, 8080, "/health"
        )
        
        self.backend_target_group = self._create_target_group(
            "BackendTG", self.vpc_b, 9090, "/health"
        )
        
        # Create VPC Lattice services and listeners
        self.frontend_service = self._create_lattice_service(
            "FrontendService", self.frontend_target_group
        )
        
        self.backend_service = self._create_lattice_service(
            "BackendService", self.backend_target_group
        )
        
        # Associate services with service network
        self._associate_services_with_network()
        
        # Create CloudWatch monitoring
        self._create_monitoring()
        
        # Create stack outputs
        self._create_outputs()
        
        # Add resource tags
        self._add_tags()
    
    def _create_kubernetes_vpc(
        self,
        cluster_name: str,
        vpc_cidr: str,
        subnet_cidr: str,
    ) -> tuple[ec2.Vpc, ec2.Subnet, ec2.SecurityGroup]:
        """
        Create VPC infrastructure for a Kubernetes cluster.
        
        Args:
            cluster_name: Name identifier for the cluster
            vpc_cidr: CIDR block for the VPC
            subnet_cidr: CIDR block for the subnet
            
        Returns:
            Tuple of (VPC, Subnet, SecurityGroup)
        """
        # Create VPC
        vpc = ec2.Vpc(
            self,
            f"VPC{cluster_name}",
            ip_addresses=ec2.IpAddresses.cidr(vpc_cidr),
            max_azs=1,
            enable_dns_hostnames=True,
            enable_dns_support=True,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name=f"Public{cluster_name}",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                )
            ],
        )
        
        # Get the public subnet
        subnet = vpc.public_subnets[0]
        
        # Create security group for Kubernetes cluster
        security_group = ec2.SecurityGroup(
            self,
            f"SecurityGroup{cluster_name}",
            vpc=vpc,
            description=f"Security group for Kubernetes {cluster_name}",
            allow_all_outbound=True,
        )
        
        # Allow SSH access
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="SSH access",
        )
        
        # Allow all traffic within security group for Kubernetes communication
        security_group.add_ingress_rule(
            peer=ec2.Peer.security_group_id(security_group.security_group_id),
            connection=ec2.Port.all_traffic(),
            description="Kubernetes internal communication",
        )
        
        # Add VPC Lattice managed prefix list rules
        # Frontend service port
        if cluster_name == "ClusterA":
            port = 8080
        else:  # ClusterB
            port = 9090
            
        # Note: VPC Lattice managed prefix list is added via custom resource
        # as CDK doesn't yet support dynamic reference to managed prefix lists
        vpc_lattice_rule = ec2.CfnSecurityGroupIngress(
            self,
            f"VPCLatticeIngress{cluster_name}",
            group_id=security_group.security_group_id,
            ip_protocol="tcp",
            from_port=port,
            to_port=port,
            source_prefix_list_id="pl-029c0d75", # VPC Lattice managed prefix list
            description="VPC Lattice health checks",
        )
        
        Tags.of(vpc).add("Name", f"{self.deployment_name}-vpc-{cluster_name.lower()}")
        Tags.of(security_group).add("Name", f"{self.deployment_name}-sg-{cluster_name.lower()}")
        
        return vpc, subnet, security_group
    
    def _create_kubernetes_instance(
        self,
        instance_name: str,
        vpc: ec2.Vpc,
        subnet: ec2.Subnet,
        security_group: ec2.SecurityGroup,
    ) -> ec2.Instance:
        """
        Create EC2 instance for Kubernetes control plane.
        
        Args:
            instance_name: Name for the instance
            vpc: VPC to deploy in
            subnet: Subnet to deploy in
            security_group: Security group to attach
            
        Returns:
            EC2 Instance construct
        """
        # Get latest Amazon Linux 2 AMI
        ami = ec2.MachineImage.latest_amazon_linux(
            generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
            cpu_type=ec2.AmazonLinuxCpuType.X86_64,
        )
        
        # Create IAM role for EC2 instance
        role = iam.Role(
            self,
            f"InstanceRole{instance_name}",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
            ],
        )
        
        # User data script for Kubernetes installation
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "#!/bin/bash",
            "yum update -y",
            "yum install -y docker",
            "systemctl start docker",
            "systemctl enable docker",
            "usermod -aG docker ec2-user",
            "",
            "# Install Kubernetes components using new repository",
            "cat <<REPO > /etc/yum.repos.d/kubernetes.repo",
            "[kubernetes]",
            "name=Kubernetes",
            "baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/",
            "enabled=1",
            "gpgcheck=1",
            "gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key",
            "exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni",
            "REPO",
            "",
            "yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes",
            "systemctl enable kubelet",
            "",
            "# Configure container runtime",
            "echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf",
            "echo 'net.bridge.bridge-nf-call-ip6tables = 1' >> /etc/sysctl.conf",
            "echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf",
            "sysctl --system",
        )
        
        # Create EC2 instance
        instance = ec2.Instance(
            self,
            instance_name,
            instance_type=ec2.InstanceType("t3.medium"),
            machine_image=ami,
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnets=[subnet]),
            security_group=security_group,
            key_name=self.ssh_key_name,
            role=role,
            user_data=user_data,
        )
        
        Tags.of(instance).add("Name", f"{self.deployment_name}-{instance_name.lower()}")
        
        return instance
    
    def _create_service_network(self) -> lattice.CfnServiceNetwork:
        """
        Create VPC Lattice service network.
        
        Returns:
            VPC Lattice service network construct
        """
        service_network = lattice.CfnServiceNetwork(
            self,
            "ServiceNetwork",
            name=f"{self.deployment_name}-service-network",
        )
        
        Tags.of(service_network).add("Name", f"{self.deployment_name}-service-network")
        
        return service_network
    
    def _associate_vpcs_with_service_network(self) -> None:
        """Associate both VPCs with the VPC Lattice service network."""
        # Associate VPC A
        lattice.CfnServiceNetworkVpcAssociation(
            self,
            "ServiceNetworkVpcAssociationA",
            service_network_identifier=self.service_network.attr_id,
            vpc_identifier=self.vpc_a.vpc_id,
            security_group_ids=[self.sg_a.security_group_id],
        )
        
        # Associate VPC B
        lattice.CfnServiceNetworkVpcAssociation(
            self,
            "ServiceNetworkVpcAssociationB",
            service_network_identifier=self.service_network.attr_id,
            vpc_identifier=self.vpc_b.vpc_id,
            security_group_ids=[self.sg_b.security_group_id],
        )
    
    def _create_target_group(
        self,
        target_group_name: str,
        vpc: ec2.Vpc,
        port: int,
        health_check_path: str,
    ) -> lattice.CfnTargetGroup:
        """
        Create VPC Lattice target group for IP targets.
        
        Args:
            target_group_name: Name for the target group
            vpc: VPC for the target group
            port: Port for health checks and traffic
            health_check_path: HTTP path for health checks
            
        Returns:
            VPC Lattice target group construct
        """
        target_group = lattice.CfnTargetGroup(
            self,
            target_group_name,
            name=f"{self.deployment_name}-{target_group_name.lower()}",
            type="IP",
            protocol="HTTP",
            port=port,
            vpc_identifier=vpc.vpc_id,
            health_check=lattice.CfnTargetGroup.HealthCheckConfigProperty(
                enabled=True,
                health_check_interval_seconds=30,
                health_check_timeout_seconds=5,
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
                protocol="HTTP",
                port=port,
                path=health_check_path,
            ),
        )
        
        Tags.of(target_group).add("Name", f"{self.deployment_name}-{target_group_name.lower()}")
        
        return target_group
    
    def _create_lattice_service(
        self,
        service_name: str,
        target_group: lattice.CfnTargetGroup,
    ) -> lattice.CfnService:
        """
        Create VPC Lattice service with listener.
        
        Args:
            service_name: Name for the service
            target_group: Target group to route traffic to
            
        Returns:
            VPC Lattice service construct
        """
        # Create service
        service = lattice.CfnService(
            self,
            service_name,
            name=f"{self.deployment_name}-{service_name.lower()}",
        )
        
        # Create listener
        lattice.CfnListener(
            self,
            f"{service_name}Listener",
            service_identifier=service.attr_id,
            name=f"{service_name.lower()}-listener",
            protocol="HTTP",
            port=80,
            default_action=lattice.CfnListener.DefaultActionProperty(
                forward=lattice.CfnListener.ForwardProperty(
                    target_groups=[
                        lattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=target_group.attr_id,
                            weight=100,
                        )
                    ]
                )
            ),
        )
        
        Tags.of(service).add("Name", f"{self.deployment_name}-{service_name.lower()}")
        
        return service
    
    def _associate_services_with_network(self) -> None:
        """Associate VPC Lattice services with the service network."""
        # Associate frontend service
        lattice.CfnServiceNetworkServiceAssociation(
            self,
            "FrontendServiceAssociation",
            service_network_identifier=self.service_network.attr_id,
            service_identifier=self.frontend_service.attr_id,
        )
        
        # Associate backend service
        lattice.CfnServiceNetworkServiceAssociation(
            self,
            "BackendServiceAssociation",
            service_network_identifier=self.service_network.attr_id,
            service_identifier=self.backend_service.attr_id,
        )
    
    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring resources."""
        # Create CloudWatch log group for VPC Lattice access logs
        log_group = logs.LogGroup(
            self,
            "VPCLatticeLogGroup",
            log_group_name=f"/aws/vpc-lattice/{self.deployment_name}-service-network",
            retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Enable access logging for service network
        lattice.CfnAccessLogSubscription(
            self,
            "ServiceNetworkAccessLogs",
            resource_identifier=self.service_network.attr_id,
            destination_arn=log_group.log_group_arn,
        )
        
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "VPCLatticeDashboard",
            dashboard_name=f"{self.deployment_name}-vpc-lattice-monitoring",
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="VPC Lattice Service Network Connections",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/VPCLattice",
                        metric_name="ActiveConnectionCount",
                        dimensions_map={
                            "ServiceNetwork": self.service_network.attr_id,
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/VPCLattice",
                        metric_name="NewConnectionCount",
                        dimensions_map={
                            "ServiceNetwork": self.service_network.attr_id,
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
                width=24,
                height=6,
            )
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "VPCAId",
            value=self.vpc_a.vpc_id,
            description="VPC ID for Kubernetes Cluster A",
        )
        
        CfnOutput(
            self,
            "VPCBId",
            value=self.vpc_b.vpc_id,
            description="VPC ID for Kubernetes Cluster B",
        )
        
        CfnOutput(
            self,
            "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="VPC Lattice Service Network ID",
        )
        
        CfnOutput(
            self,
            "ServiceNetworkDomain",
            value=self.service_network.attr_dns_entry_domain_name,
            description="VPC Lattice Service Network Domain Name",
        )
        
        CfnOutput(
            self,
            "FrontendServiceId",
            value=self.frontend_service.attr_id,
            description="Frontend VPC Lattice Service ID",
        )
        
        CfnOutput(
            self,
            "BackendServiceId",
            value=self.backend_service.attr_id,
            description="Backend VPC Lattice Service ID",
        )
        
        CfnOutput(
            self,
            "FrontendTargetGroupId",
            value=self.frontend_target_group.attr_id,
            description="Frontend Target Group ID",
        )
        
        CfnOutput(
            self,
            "BackendTargetGroupId",
            value=self.backend_target_group.attr_id,
            description="Backend Target Group ID",
        )
        
        CfnOutput(
            self,
            "InstanceAPrivateIP",
            value=self.instance_a.instance_private_ip,
            description="Private IP of Kubernetes Instance A",
        )
        
        CfnOutput(
            self,
            "InstanceBPrivateIP",
            value=self.instance_b.instance_private_ip,
            description="Private IP of Kubernetes Instance B",
        )
        
        if self.ssh_key_name:
            CfnOutput(
                self,
                "SSHKeyName",
                value=self.ssh_key_name,
                description="SSH Key Name for EC2 Instances",
            )
    
    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", "kubernetes-vpc-lattice-integration")
        Tags.of(self).add("Environment", "demo")
        Tags.of(self).add("ManagedBy", "AWS-CDK")


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get configuration from environment variables or use defaults
    deployment_name = app.node.try_get_context("deployment_name") or "k8s-lattice"
    ssh_key_name = app.node.try_get_context("ssh_key_name")
    
    # Get AWS environment from context or environment variables
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION"),
    )
    
    # Create the stack
    KubernetesVPCLatticeStack(
        app,
        "KubernetesVPCLatticeStack",
        deployment_name=deployment_name,
        ssh_key_name=ssh_key_name,
        env=env,
        description="Infrastructure for Self-Managed Kubernetes Integration with VPC Lattice IP Targets",
    )
    
    app.synth()


if __name__ == "__main__":
    main()