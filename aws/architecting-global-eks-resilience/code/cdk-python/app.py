#!/usr/bin/env python3
"""
Multi-Cluster EKS Deployments with Cross-Region Networking
AWS CDK Python Application

This CDK application creates a multi-cluster Amazon EKS architecture spanning
multiple AWS regions, connected through AWS Transit Gateway with cross-region
peering and AWS VPC Lattice for service mesh federation.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_iam as iam,
    aws_logs as logs,
    aws_route53 as route53,
    aws_vpclattice as vpclattice,
)
from constructs import Construct


class MultiClusterEksStack(Stack):
    """
    Main stack for multi-cluster EKS deployment with cross-region networking.
    
    This stack creates:
    - Primary and secondary region VPCs with Transit Gateways
    - Cross-region Transit Gateway peering
    - EKS clusters in both regions with managed node groups
    - VPC Lattice service network for service mesh federation
    - Route 53 health checks for global load balancing
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        primary_region: str = "us-east-1",
        secondary_region: str = "us-west-2",
        cluster_version: str = "1.28",
        node_instance_type: str = "m5.large",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.primary_region = primary_region
        self.secondary_region = secondary_region
        self.cluster_version = cluster_version
        self.node_instance_type = node_instance_type

        # Generate unique suffix for resource naming
        self.resource_suffix = self.node.try_get_context("resource_suffix") or "multicluster"

        # Create IAM roles
        self.cluster_role = self._create_cluster_role()
        self.nodegroup_role = self._create_nodegroup_role()

        # Create primary region infrastructure
        self.primary_vpc = self._create_vpc(
            vpc_id="PrimaryVPC",
            cidr="10.1.0.0/16",
            region_name="primary"
        )
        
        self.primary_tgw = self._create_transit_gateway(
            tgw_id="PrimaryTransitGateway",
            asn=64512,
            region_name="primary"
        )

        # Create secondary region infrastructure (cross-region stack)
        self.secondary_stack = SecondaryRegionStack(
            self,
            "SecondaryRegionStack",
            env=cdk.Environment(region=self.secondary_region),
            primary_tgw_id=self.primary_tgw.ref,
            primary_region=self.primary_region,
            resource_suffix=self.resource_suffix,
            cluster_role_arn=self.cluster_role.role_arn,
            nodegroup_role_arn=self.nodegroup_role.role_arn,
            cluster_version=self.cluster_version,
            node_instance_type=self.node_instance_type
        )

        # Create EKS cluster in primary region
        self.primary_cluster = self._create_eks_cluster(
            cluster_id="PrimaryEKSCluster",
            vpc=self.primary_vpc,
            region_name="primary"
        )

        # Create VPC Lattice service network
        self.service_network = self._create_vpc_lattice_service_network()

        # Attach VPCs to Transit Gateway
        self._attach_vpc_to_tgw(self.primary_vpc, self.primary_tgw, "PrimaryTGWAttachment")

        # Create Transit Gateway peering (will be accepted in secondary region)
        self.tgw_peering = self._create_tgw_peering()

        # Configure routing between regions
        self._configure_cross_region_routing()

        # Create Route 53 health checks
        self._create_route53_health_checks()

        # Output important values
        self._create_outputs()

    def _create_cluster_role(self) -> iam.Role:
        """Create IAM role for EKS clusters."""
        role = iam.Role(
            self,
            "EKSClusterRole",
            role_name=f"eks-cluster-role-{self.resource_suffix}",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy")
            ],
            description="IAM role for EKS cluster service"
        )
        return role

    def _create_nodegroup_role(self) -> iam.Role:
        """Create IAM role for EKS node groups."""
        role = iam.Role(
            self,
            "EKSNodeGroupRole",
            role_name=f"eks-nodegroup-role-{self.resource_suffix}",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSWorkerNodePolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKS_CNI_Policy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryReadOnly"),
            ],
            description="IAM role for EKS worker nodes"
        )
        return role

    def _create_vpc(self, vpc_id: str, cidr: str, region_name: str) -> ec2.Vpc:
        """Create VPC with public and private subnets across multiple AZs."""
        vpc = ec2.Vpc(
            self,
            vpc_id,
            vpc_name=f"vpc-{region_name}-{self.resource_suffix}",
            ip_addresses=ec2.IpAddresses.cidr(cidr),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name=f"{region_name}-public",
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name=f"{region_name}-private",
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Add tags for EKS subnet discovery
        for subnet in vpc.public_subnets + vpc.private_subnets:
            cdk.Tags.of(subnet).add("kubernetes.io/role/elb", "1")
            if subnet in vpc.private_subnets:
                cdk.Tags.of(subnet).add("kubernetes.io/role/internal-elb", "1")

        return vpc

    def _create_transit_gateway(self, tgw_id: str, asn: int, region_name: str) -> ec2.CfnTransitGateway:
        """Create Transit Gateway for inter-VPC connectivity."""
        tgw = ec2.CfnTransitGateway(
            self,
            tgw_id,
            amazon_side_asn=asn,
            auto_accept_shared_attachments="enable",
            default_route_table_association="enable",
            default_route_table_propagation="enable",
            description=f"{region_name.title()} region Transit Gateway",
            tags=[
                cdk.CfnTag(key="Name", value=f"tgw-{region_name}-{self.resource_suffix}")
            ]
        )
        return tgw

    def _create_eks_cluster(self, cluster_id: str, vpc: ec2.Vpc, region_name: str) -> eks.Cluster:
        """Create EKS cluster with managed node group."""
        
        # Create CloudWatch log group for cluster logging
        log_group = logs.LogGroup(
            self,
            f"{cluster_id}LogGroup",
            log_group_name=f"/aws/eks/{region_name}-cluster-{self.resource_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

        # Create EKS cluster
        cluster = eks.Cluster(
            self,
            cluster_id,
            cluster_name=f"eks-{region_name}-{self.resource_suffix}",
            version=eks.KubernetesVersion.of(self.cluster_version),
            role=self.cluster_role,
            vpc=vpc,
            vpc_subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)],
            default_capacity=0,  # We'll add managed node groups separately
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR
            ],
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            cluster_handler_environment={
                "cluster": f"eks-{region_name}-{self.resource_suffix}"
            }
        )

        # Add managed node group
        cluster.add_nodegroup_capacity(
            f"{region_name}-nodes",
            nodegroup_name=f"{region_name}-nodes",
            node_role=self.nodegroup_role,
            instance_types=[ec2.InstanceType(self.node_instance_type)],
            min_size=2,
            max_size=6,
            desired_size=3,
            capacity_type=eks.CapacityType.ON_DEMAND,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            tags={
                "Name": f"{region_name}-worker-nodes",
                "Environment": "production",
                "Project": "multi-cluster-eks"
            }
        )

        # Install VPC Lattice Gateway API Controller
        self._install_vpc_lattice_controller(cluster, region_name)

        return cluster

    def _install_vpc_lattice_controller(self, cluster: eks.Cluster, region_name: str) -> None:
        """Install VPC Lattice Gateway API Controller on the EKS cluster."""
        
        # Create service account for VPC Lattice controller
        service_account = cluster.add_service_account(
            f"vpc-lattice-controller-{region_name}",
            name="vpc-lattice-gateway-controller-service-account",
            namespace="aws-application-networking-system"
        )

        # Add necessary IAM policies for VPC Lattice
        service_account.role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("VPCLatticeFullAccess")
        )

        # Install the VPC Lattice Gateway API Controller using a Helm chart
        cluster.add_helm_chart(
            f"vpc-lattice-controller-{region_name}",
            chart="gateway-api-controller",
            repository="https://aws.github.io/aws-application-networking-k8s",
            namespace="aws-application-networking-system",
            create_namespace=True,
            values={
                "serviceAccount": {
                    "create": False,
                    "name": service_account.service_account_name
                },
                "region": self.region,
                "clusterName": cluster.cluster_name
            }
        )

    def _attach_vpc_to_tgw(self, vpc: ec2.Vpc, tgw: ec2.CfnTransitGateway, attachment_id: str) -> ec2.CfnTransitGatewayVpcAttachment:
        """Attach VPC to Transit Gateway."""
        attachment = ec2.CfnTransitGatewayVpcAttachment(
            self,
            attachment_id,
            transit_gateway_id=tgw.ref,
            vpc_id=vpc.vpc_id,
            subnet_ids=[subnet.subnet_id for subnet in vpc.private_subnets],
            tags=[
                cdk.CfnTag(key="Name", value=f"{attachment_id.lower()}-{self.resource_suffix}")
            ]
        )
        attachment.add_dependency(tgw)
        return attachment

    def _create_tgw_peering(self) -> ec2.CfnTransitGatewayPeeringAttachment:
        """Create Transit Gateway peering attachment between regions."""
        peering = ec2.CfnTransitGatewayPeeringAttachment(
            self,
            "TransitGatewayPeering",
            transit_gateway_id=self.primary_tgw.ref,
            peer_transit_gateway_id=self.secondary_stack.secondary_tgw.ref,
            peer_region=self.secondary_region,
            tags=[
                cdk.CfnTag(key="Name", value=f"multi-cluster-tgw-peering-{self.resource_suffix}")
            ]
        )
        peering.add_dependency(self.primary_tgw)
        return peering

    def _configure_cross_region_routing(self) -> None:
        """Configure routing between Transit Gateways for cross-region connectivity."""
        
        # Get default route table for primary TGW
        primary_route_table = ec2.CfnTransitGatewayRouteTable(
            self,
            "PrimaryTGWRouteTable",
            transit_gateway_id=self.primary_tgw.ref,
            tags=[
                cdk.CfnTag(key="Name", value=f"primary-tgw-rt-{self.resource_suffix}")
            ]
        )

        # Add route to secondary region
        primary_route = ec2.CfnTransitGatewayRoute(
            self,
            "PrimaryToSecondaryRoute",
            route_table_id=primary_route_table.ref,
            destination_cidr_block="10.2.0.0/16",
            transit_gateway_peering_attachment_id=self.tgw_peering.ref
        )
        primary_route.add_dependency(self.tgw_peering)

    def _create_vpc_lattice_service_network(self) -> vpclattice.CfnServiceNetwork:
        """Create VPC Lattice service network for cross-cluster service discovery."""
        service_network = vpclattice.CfnServiceNetwork(
            self,
            "VPCLatticeServiceNetwork",
            name=f"multi-cluster-service-network-{self.resource_suffix}",
            auth_type="AWS_IAM",
            tags=[
                cdk.CfnTag(key="Name", value=f"multi-cluster-service-network-{self.resource_suffix}"),
                cdk.CfnTag(key="Environment", value="production"),
                cdk.CfnTag(key="Project", value="multi-cluster-eks")
            ]
        )

        # Associate primary VPC with service network
        vpclattice.CfnServiceNetworkVpcAssociation(
            self,
            "PrimaryVPCAssociation",
            service_network_identifier=service_network.ref,
            vpc_identifier=self.primary_vpc.vpc_id,
            tags=[
                cdk.CfnTag(key="Name", value=f"primary-vpc-association-{self.resource_suffix}")
            ]
        )

        return service_network

    def _create_route53_health_checks(self) -> None:
        """Create Route 53 health checks for global load balancing."""
        
        # Health check for primary region VPC Lattice endpoint
        primary_health_check = route53.CfnHealthCheck(
            self,
            "PrimaryHealthCheck",
            type="HTTP",
            resource_path="/",
            port=80,
            request_interval=30,
            failure_threshold=3,
            tags=[
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Name",
                    value=f"primary-lattice-health-{self.resource_suffix}"
                )
            ]
        )

        # Health check for secondary region VPC Lattice endpoint
        secondary_health_check = route53.CfnHealthCheck(
            self,
            "SecondaryHealthCheck",
            type="HTTP",
            resource_path="/",
            port=80,
            request_interval=30,
            failure_threshold=3,
            tags=[
                route53.CfnHealthCheck.HealthCheckTagProperty(
                    key="Name",
                    value=f"secondary-lattice-health-{self.resource_suffix}"
                )
            ]
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self,
            "PrimaryEKSClusterName",
            description="Primary EKS cluster name",
            value=self.primary_cluster.cluster_name,
            export_name=f"PrimaryEKSClusterName-{self.resource_suffix}"
        )

        CfnOutput(
            self,
            "PrimaryVPCId",
            description="Primary VPC ID",
            value=self.primary_vpc.vpc_id,
            export_name=f"PrimaryVPCId-{self.resource_suffix}"
        )

        CfnOutput(
            self,
            "PrimaryTransitGatewayId",
            description="Primary Transit Gateway ID",
            value=self.primary_tgw.ref,
            export_name=f"PrimaryTransitGatewayId-{self.resource_suffix}"
        )

        CfnOutput(
            self,
            "VPCLatticeServiceNetworkId",
            description="VPC Lattice Service Network ID",
            value=self.service_network.ref,
            export_name=f"VPCLatticeServiceNetworkId-{self.resource_suffix}"
        )

        CfnOutput(
            self,
            "KubectlUpdateCommands",
            description="Commands to update kubectl configuration",
            value=f"aws eks update-kubeconfig --name {self.primary_cluster.cluster_name} --region {self.primary_region} --alias primary-cluster"
        )


class SecondaryRegionStack(Stack):
    """
    Stack for secondary region infrastructure including VPC, Transit Gateway, and EKS cluster.
    
    This stack is deployed in the secondary region and creates:
    - Secondary region VPC and Transit Gateway
    - EKS cluster with managed node groups
    - Cross-region networking configuration
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        primary_tgw_id: str,
        primary_region: str,
        resource_suffix: str,
        cluster_role_arn: str,
        nodegroup_role_arn: str,
        cluster_version: str,
        node_instance_type: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.primary_tgw_id = primary_tgw_id
        self.primary_region = primary_region
        self.resource_suffix = resource_suffix
        self.cluster_version = cluster_version
        self.node_instance_type = node_instance_type

        # Import IAM roles from primary region
        self.cluster_role = iam.Role.from_role_arn(
            self, "ImportedClusterRole", cluster_role_arn
        )
        self.nodegroup_role = iam.Role.from_role_arn(
            self, "ImportedNodeGroupRole", nodegroup_role_arn
        )

        # Create secondary region infrastructure
        self.secondary_vpc = self._create_vpc(
            vpc_id="SecondaryVPC",
            cidr="10.2.0.0/16",
            region_name="secondary"
        )

        self.secondary_tgw = self._create_transit_gateway(
            tgw_id="SecondaryTransitGateway",
            asn=64513,
            region_name="secondary"
        )

        # Create EKS cluster in secondary region
        self.secondary_cluster = self._create_eks_cluster(
            cluster_id="SecondaryEKSCluster",
            vpc=self.secondary_vpc,
            region_name="secondary"
        )

        # Attach VPC to Transit Gateway
        self._attach_vpc_to_tgw(self.secondary_vpc, self.secondary_tgw, "SecondaryTGWAttachment")

        # Configure cross-region routing
        self._configure_secondary_routing()

        # Create outputs
        self._create_outputs()

    def _create_vpc(self, vpc_id: str, cidr: str, region_name: str) -> ec2.Vpc:
        """Create VPC with public and private subnets across multiple AZs."""
        vpc = ec2.Vpc(
            self,
            vpc_id,
            vpc_name=f"vpc-{region_name}-{self.resource_suffix}",
            ip_addresses=ec2.IpAddresses.cidr(cidr),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name=f"{region_name}-public",
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name=f"{region_name}-private",
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Add tags for EKS subnet discovery
        for subnet in vpc.public_subnets + vpc.private_subnets:
            cdk.Tags.of(subnet).add("kubernetes.io/role/elb", "1")
            if subnet in vpc.private_subnets:
                cdk.Tags.of(subnet).add("kubernetes.io/role/internal-elb", "1")

        return vpc

    def _create_transit_gateway(self, tgw_id: str, asn: int, region_name: str) -> ec2.CfnTransitGateway:
        """Create Transit Gateway for inter-VPC connectivity."""
        tgw = ec2.CfnTransitGateway(
            self,
            tgw_id,
            amazon_side_asn=asn,
            auto_accept_shared_attachments="enable",
            default_route_table_association="enable",
            default_route_table_propagation="enable",
            description=f"{region_name.title()} region Transit Gateway",
            tags=[
                cdk.CfnTag(key="Name", value=f"tgw-{region_name}-{self.resource_suffix}")
            ]
        )
        return tgw

    def _create_eks_cluster(self, cluster_id: str, vpc: ec2.Vpc, region_name: str) -> eks.Cluster:
        """Create EKS cluster with managed node group."""
        
        # Create CloudWatch log group for cluster logging
        log_group = logs.LogGroup(
            self,
            f"{cluster_id}LogGroup",
            log_group_name=f"/aws/eks/{region_name}-cluster-{self.resource_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

        # Create EKS cluster
        cluster = eks.Cluster(
            self,
            cluster_id,
            cluster_name=f"eks-{region_name}-{self.resource_suffix}",
            version=eks.KubernetesVersion.of(self.cluster_version),
            role=self.cluster_role,
            vpc=vpc,
            vpc_subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)],
            default_capacity=0,  # We'll add managed node groups separately
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR
            ],
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            cluster_handler_environment={
                "cluster": f"eks-{region_name}-{self.resource_suffix}"
            }
        )

        # Add managed node group
        cluster.add_nodegroup_capacity(
            f"{region_name}-nodes",
            nodegroup_name=f"{region_name}-nodes",
            node_role=self.nodegroup_role,
            instance_types=[ec2.InstanceType(self.node_instance_type)],
            min_size=2,
            max_size=6,
            desired_size=3,
            capacity_type=eks.CapacityType.ON_DEMAND,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            tags={
                "Name": f"{region_name}-worker-nodes",
                "Environment": "production",
                "Project": "multi-cluster-eks"
            }
        )

        # Install VPC Lattice Gateway API Controller
        self._install_vpc_lattice_controller(cluster, region_name)

        return cluster

    def _install_vpc_lattice_controller(self, cluster: eks.Cluster, region_name: str) -> None:
        """Install VPC Lattice Gateway API Controller on the EKS cluster."""
        
        # Create service account for VPC Lattice controller
        service_account = cluster.add_service_account(
            f"vpc-lattice-controller-{region_name}",
            name="vpc-lattice-gateway-controller-service-account",
            namespace="aws-application-networking-system"
        )

        # Add necessary IAM policies for VPC Lattice
        service_account.role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("VPCLatticeFullAccess")
        )

        # Install the VPC Lattice Gateway API Controller using a Helm chart
        cluster.add_helm_chart(
            f"vpc-lattice-controller-{region_name}",
            chart="gateway-api-controller",
            repository="https://aws.github.io/aws-application-networking-k8s",
            namespace="aws-application-networking-system",
            create_namespace=True,
            values={
                "serviceAccount": {
                    "create": False,
                    "name": service_account.service_account_name
                },
                "region": self.region,
                "clusterName": cluster.cluster_name
            }
        )

    def _attach_vpc_to_tgw(self, vpc: ec2.Vpc, tgw: ec2.CfnTransitGateway, attachment_id: str) -> ec2.CfnTransitGatewayVpcAttachment:
        """Attach VPC to Transit Gateway."""
        attachment = ec2.CfnTransitGatewayVpcAttachment(
            self,
            attachment_id,
            transit_gateway_id=tgw.ref,
            vpc_id=vpc.vpc_id,
            subnet_ids=[subnet.subnet_id for subnet in vpc.private_subnets],
            tags=[
                cdk.CfnTag(key="Name", value=f"{attachment_id.lower()}-{self.resource_suffix}")
            ]
        )
        attachment.add_dependency(tgw)
        return attachment

    def _configure_secondary_routing(self) -> None:
        """Configure routing in secondary region for cross-region connectivity."""
        
        # Get default route table for secondary TGW
        secondary_route_table = ec2.CfnTransitGatewayRouteTable(
            self,
            "SecondaryTGWRouteTable",
            transit_gateway_id=self.secondary_tgw.ref,
            tags=[
                cdk.CfnTag(key="Name", value=f"secondary-tgw-rt-{self.resource_suffix}")
            ]
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self,
            "SecondaryEKSClusterName",
            description="Secondary EKS cluster name",
            value=self.secondary_cluster.cluster_name,
            export_name=f"SecondaryEKSClusterName-{self.resource_suffix}"
        )

        CfnOutput(
            self,
            "SecondaryVPCId",
            description="Secondary VPC ID",
            value=self.secondary_vpc.vpc_id,
            export_name=f"SecondaryVPCId-{self.resource_suffix}"
        )

        CfnOutput(
            self,
            "SecondaryTransitGatewayId",
            description="Secondary Transit Gateway ID",
            value=self.secondary_tgw.ref,
            export_name=f"SecondaryTransitGatewayId-{self.resource_suffix}"
        )

        CfnOutput(
            self,
            "SecondaryKubectlUpdateCommand",
            description="Command to update kubectl configuration for secondary cluster",
            value=f"aws eks update-kubeconfig --name {self.secondary_cluster.cluster_name} --region {self.region} --alias secondary-cluster"
        )


def main():
    """Main function to create and deploy the CDK application."""
    app = cdk.App()

    # Get configuration from context or environment variables
    primary_region = app.node.try_get_context("primary_region") or os.environ.get("PRIMARY_REGION", "us-east-1")
    secondary_region = app.node.try_get_context("secondary_region") or os.environ.get("SECONDARY_REGION", "us-west-2")
    cluster_version = app.node.try_get_context("cluster_version") or os.environ.get("CLUSTER_VERSION", "1.28")
    node_instance_type = app.node.try_get_context("node_instance_type") or os.environ.get("NODE_INSTANCE_TYPE", "m5.large")

    # Create the main stack in the primary region
    MultiClusterEksStack(
        app,
        "MultiClusterEksStack",
        primary_region=primary_region,
        secondary_region=secondary_region,
        cluster_version=cluster_version,
        node_instance_type=node_instance_type,
        env=cdk.Environment(region=primary_region),
        description="Multi-cluster EKS deployment with cross-region networking using Transit Gateway and VPC Lattice"
    )

    app.synth()


if __name__ == "__main__":
    main()