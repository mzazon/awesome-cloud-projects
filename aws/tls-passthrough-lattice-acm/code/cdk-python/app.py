#!/usr/bin/env python3
"""
AWS CDK Application for TLS Passthrough with VPC Lattice
========================================================

This CDK application implements end-to-end encryption using VPC Lattice TLS passthrough,
AWS Certificate Manager, and Route 53 for DNS resolution. The architecture ensures
complete end-to-end encryption while simplifying service discovery and load balancing
across microservices architectures.

Architecture Components:
- VPC with public/private subnets
- EC2 instances with self-signed TLS certificates
- VPC Lattice service network with TLS passthrough
- AWS Certificate Manager for custom domain certificates
- Route 53 for DNS resolution
- Security groups with least privilege access

Security Features:
- End-to-end TLS encryption from client to target
- Custom domain with ACM-managed certificates
- Security groups following least privilege principle
- VPC isolation with controlled internet access

Compliance:
- Supports PCI DSS requirement 4.1 (encrypt transmission of cardholder data)
- HIPAA technical safeguards for data transmission security
- Zero-trust networking principles
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    Tags,
    RemovalPolicy,
    Duration,
)
from aws_cdk import (
    aws_ec2 as ec2,
    aws_certificatemanager as acm,
    aws_route53 as route53,
    aws_vpclattice as vpclattice,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct
from typing import Dict, List, Optional
import json


class TlsPassthroughLatticeStack(Stack):
    """
    CDK Stack implementing VPC Lattice TLS Passthrough with end-to-end encryption.
    
    This stack creates a complete infrastructure for demonstrating TLS passthrough
    capabilities using VPC Lattice, ensuring encrypted traffic flows directly from
    clients to target applications without intermediate decryption points.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        custom_domain: str,
        certificate_domain: str,
        hosted_zone_name: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.custom_domain = custom_domain
        self.certificate_domain = certificate_domain
        self.hosted_zone_name = hosted_zone_name

        # Create VPC infrastructure
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.security_group = self._create_security_group()
        
        # Create SSL/TLS certificate
        self.certificate = self._create_certificate()
        
        # Create target EC2 instances
        self.target_instances = self._create_target_instances()
        
        # Create VPC Lattice components
        self.service_network = self._create_service_network()
        self.target_group = self._create_target_group()
        self.lattice_service = self._create_lattice_service()
        self.listener = self._create_listener()
        
        # Configure DNS
        self.dns_record = self._create_dns_record()
        
        # Add comprehensive outputs
        self._create_outputs()
        
        # Apply tags for resource management
        self._apply_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets for target instances.
        
        Returns:
            ec2.Vpc: The created VPC with proper CIDR and subnet configuration
        """
        vpc = ec2.Vpc(
            self,
            "TlsPassthroughVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add VPC Flow Logs for security monitoring
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

        vpc_flow_log_group = logs.LogGroup(
            self,
            "VpcFlowLogGroup",
            log_group_name=f"/aws/vpc/flowlogs/{self.stack_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        ec2.FlowLog(
            self,
            "VpcFlowLog",
            resource_type=ec2.FlowLogResourceType.from_vpc(vpc),
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                vpc_flow_log_group, vpc_flow_log_role
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )

        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """
        Create security group for target instances with least privilege access.
        
        Returns:
            ec2.SecurityGroup: Security group allowing HTTPS traffic from VPC Lattice
        """
        security_group = ec2.SecurityGroup(
            self,
            "TargetInstancesSecurityGroup",
            vpc=self.vpc,
            description="Security group for VPC Lattice TLS passthrough target instances",
            allow_all_outbound=True,
        )

        # Allow HTTPS traffic from VPC Lattice service network range
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/8"),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from VPC Lattice service network",
        )

        # Allow SSH access for administration (optional - can be removed for production)
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/16"),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access within VPC",
        )

        return security_group

    def _create_certificate(self) -> acm.Certificate:
        """
        Create AWS Certificate Manager certificate for custom domain.
        
        Returns:
            acm.Certificate: ACM certificate with DNS validation
        """
        # Create or reference existing hosted zone
        hosted_zone = route53.HostedZone.from_lookup(
            self,
            "HostedZone",
            domain_name=self.hosted_zone_name,
        )

        certificate = acm.Certificate(
            self,
            "TlsPassthroughCertificate",
            domain_name=self.certificate_domain,
            subject_alternative_names=[self.custom_domain],
            validation=acm.CertificateValidation.from_dns(hosted_zone),
        )

        return certificate

    def _create_target_instances(self) -> List[ec2.Instance]:
        """
        Create EC2 target instances with self-signed TLS certificates.
        
        Returns:
            List[ec2.Instance]: List of target instances configured with HTTPS
        """
        # Get latest Amazon Linux 2023 AMI
        amazon_linux = ec2.MachineImage.latest_amazon_linux2023(
            edition=ec2.AmazonLinux2023ImageSsmParameterEdition.STANDARD,
        )

        # User data script for configuring HTTPS on target instances
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "dnf update -y",
            "dnf install -y httpd mod_ssl openssl",
            "",
            "# Generate self-signed certificate for target",
            "openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\",
            "    -keyout /etc/pki/tls/private/server.key \\",
            "    -out /etc/pki/tls/certs/server.crt \\",
            f'    -subj "/C=US/ST=State/L=City/O=Organization/CN={self.custom_domain}"',
            "",
            "# Configure SSL virtual host",
            "cat > /etc/httpd/conf.d/ssl.conf << 'SSLCONF'",
            "LoadModule ssl_module modules/mod_ssl.so",
            "Listen 443",
            "<VirtualHost *:443>",
            f"    ServerName {self.custom_domain}",
            "    DocumentRoot /var/www/html",
            "    SSLEngine on",
            "    SSLCertificateFile /etc/pki/tls/certs/server.crt",
            "    SSLCertificateKeyFile /etc/pki/tls/private/server.key",
            "    SSLProtocol TLSv1.2 TLSv1.3",
            "    SSLCipherSuite ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS",
            "</VirtualHost>",
            "SSLCONF",
            "",
            "# Create simple HTTPS response with instance identification",
            "INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",
            "echo '<h1>Target Instance Response - TLS Passthrough Success</h1>' > /var/www/html/index.html",
            "echo '<p>Instance ID: '${INSTANCE_ID}'</p>' >> /var/www/html/index.html",
            "echo '<p>Timestamp: '$(date)'</p>' >> /var/www/html/index.html",
            "",
            "# Start Apache",
            "systemctl enable httpd",
            "systemctl start httpd",
        )

        # Create IAM role for EC2 instances with SSM access
        instance_role = iam.Role(
            self,
            "TargetInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                )
            ],
        )

        instances = []
        for i in range(2):
            instance = ec2.Instance(
                self,
                f"TargetInstance{i+1}",
                instance_type=ec2.InstanceType.of(
                    ec2.InstanceClass.T3, ec2.InstanceSize.MICRO
                ),
                machine_image=amazon_linux,
                vpc=self.vpc,
                vpc_subnets=ec2.SubnetSelection(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
                ),
                security_group=self.security_group,
                user_data=user_data,
                role=instance_role,
                detailed_monitoring=True,
            )
            instances.append(instance)

        return instances

    def _create_service_network(self) -> vpclattice.CfnServiceNetwork:
        """
        Create VPC Lattice service network for service-to-service communication.
        
        Returns:
            vpclattice.CfnServiceNetwork: The created service network
        """
        service_network = vpclattice.CfnServiceNetwork(
            self,
            "TlsPassthroughServiceNetwork",
            name=f"tls-passthrough-network-{self.node.addr}",
            auth_type="NONE",
        )

        # Associate VPC with service network
        vpclattice.CfnServiceNetworkVpcAssociation(
            self,
            "ServiceNetworkVpcAssociation",
            service_network_identifier=service_network.attr_id,
            vpc_identifier=self.vpc.vpc_id,
        )

        return service_network

    def _create_target_group(self) -> vpclattice.CfnTargetGroup:
        """
        Create TCP target group for TLS passthrough.
        
        Returns:
            vpclattice.CfnTargetGroup: Target group configured for TCP protocol
        """
        targets = []
        for i, instance in enumerate(self.target_instances):
            targets.append(
                vpclattice.CfnTargetGroup.TargetProperty(
                    id=instance.instance_id,
                    port=443,
                )
            )

        target_group = vpclattice.CfnTargetGroup(
            self,
            "TlsPassthroughTargetGroup",
            name=f"tls-passthrough-targets-{self.node.addr}",
            type="INSTANCE",
            protocol="TCP",
            port=443,
            vpc_identifier=self.vpc.vpc_id,
            targets=targets,
            config=vpclattice.CfnTargetGroup.TargetGroupConfigProperty(
                health_check=vpclattice.CfnTargetGroup.HealthCheckConfigProperty(
                    enabled=True,
                    protocol="TCP",
                    port=443,
                    healthy_threshold_count=2,
                    unhealthy_threshold_count=2,
                    interval_seconds=30,
                    timeout_seconds=5,
                )
            ),
        )

        return target_group

    def _create_lattice_service(self) -> vpclattice.CfnService:
        """
        Create VPC Lattice service with custom domain configuration.
        
        Returns:
            vpclattice.CfnService: VPC Lattice service with custom domain
        """
        lattice_service = vpclattice.CfnService(
            self,
            "TlsPassthroughService",
            name=f"tls-passthrough-service-{self.node.addr}",
            custom_domain_name=self.custom_domain,
            certificate_arn=self.certificate.certificate_arn,
            auth_type="NONE",
        )

        # Associate service with service network
        vpclattice.CfnServiceNetworkServiceAssociation(
            self,
            "ServiceNetworkServiceAssociation",
            service_network_identifier=self.service_network.attr_id,
            service_identifier=lattice_service.attr_id,
        )

        return lattice_service

    def _create_listener(self) -> vpclattice.CfnListener:
        """
        Create TLS passthrough listener for the VPC Lattice service.
        
        Returns:
            vpclattice.CfnListener: Listener configured for TLS passthrough
        """
        listener = vpclattice.CfnListener(
            self,
            "TlsPassthroughListener",
            service_identifier=self.lattice_service.attr_id,
            name="tls-passthrough-listener",
            protocol="TLS_PASSTHROUGH",
            port=443,
            default_action=vpclattice.CfnListener.DefaultActionProperty(
                forward=vpclattice.CfnListener.ForwardProperty(
                    target_groups=[
                        vpclattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=self.target_group.attr_id,
                            weight=100,
                        )
                    ]
                )
            ),
        )

        return listener

    def _create_dns_record(self) -> route53.CnameRecord:
        """
        Create Route 53 CNAME record pointing to VPC Lattice service.
        
        Returns:
            route53.CnameRecord: DNS record for custom domain
        """
        # Reference the existing hosted zone
        hosted_zone = route53.HostedZone.from_lookup(
            self,
            "DnsHostedZone",
            domain_name=self.hosted_zone_name,
        )

        dns_record = route53.CnameRecord(
            self,
            "ServiceDnsRecord",
            zone=hosted_zone,
            record_name=self.custom_domain.replace(f".{self.hosted_zone_name}", ""),
            domain_name=self.lattice_service.attr_dns_entry_domain_name,
            ttl=Duration.minutes(5),
        )

        return dns_record

    def _create_outputs(self) -> None:
        """Create comprehensive CloudFormation outputs for verification and integration."""
        
        # VPC and networking outputs
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for target instances",
        )

        # VPC Lattice service outputs
        CfnOutput(
            self,
            "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="VPC Lattice Service Network ID",
        )

        CfnOutput(
            self,
            "LatticeServiceId",
            value=self.lattice_service.attr_id,
            description="VPC Lattice Service ID",
        )

        CfnOutput(
            self,
            "LatticeServiceDns",
            value=self.lattice_service.attr_dns_entry_domain_name,
            description="VPC Lattice Service DNS name",
        )

        CfnOutput(
            self,
            "TargetGroupId",
            value=self.target_group.attr_id,
            description="Target Group ID for EC2 instances",
        )

        # Certificate and DNS outputs
        CfnOutput(
            self,
            "CertificateArn",
            value=self.certificate.certificate_arn,
            description="ACM Certificate ARN for custom domain",
        )

        CfnOutput(
            self,
            "CustomDomain",
            value=self.custom_domain,
            description="Custom domain name for TLS passthrough service",
        )

        # Instance outputs
        for i, instance in enumerate(self.target_instances):
            CfnOutput(
                self,
                f"TargetInstance{i+1}Id",
                value=instance.instance_id,
                description=f"Target Instance {i+1} ID",
            )

        # Test URL output
        CfnOutput(
            self,
            "TestUrl",
            value=f"https://{self.custom_domain}",
            description="Test URL for TLS passthrough validation (use -k flag with curl for self-signed certs)",
        )

    def _apply_tags(self) -> None:
        """Apply comprehensive tags to all resources for cost allocation and management."""
        
        Tags.of(self).add("Project", "TLS-Passthrough-VPC-Lattice")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("Owner", "CDK-Application")
        Tags.of(self).add("CostCenter", "Infrastructure")
        Tags.of(self).add("Compliance", "End-to-End-Encryption")


def main():
    """
    Main application entry point.
    
    This function creates the CDK app and instantiates the TLS passthrough stack
    with appropriate configuration parameters.
    """
    app = App()

    # Get configuration from CDK context or environment variables
    custom_domain = app.node.try_get_context("custom_domain") or "api-service.example.com"
    certificate_domain = app.node.try_get_context("certificate_domain") or "*.example.com"
    hosted_zone_name = app.node.try_get_context("hosted_zone_name") or "example.com"
    
    # Get deployment environment
    account = app.node.try_get_context("account") or app.account
    region = app.node.try_get_context("region") or app.region

    TlsPassthroughLatticeStack(
        app,
        "TlsPassthroughLatticeStack",
        custom_domain=custom_domain,
        certificate_domain=certificate_domain,
        hosted_zone_name=hosted_zone_name,
        env=Environment(account=account, region=region),
        description="End-to-end encryption with VPC Lattice TLS passthrough, ACM, and Route 53",
    )

    app.synth()


if __name__ == "__main__":
    main()