#!/usr/bin/env python3
"""
AWS CDK Python application for deploying microservices on EKS with App Mesh.

This CDK application creates a complete microservices architecture on Amazon EKS
with AWS App Mesh for service mesh capabilities, including:
- EKS cluster with managed node groups
- AWS App Mesh configuration with virtual nodes, services, and routers
- ECR repositories for container images
- Application Load Balancer for external access
- X-Ray tracing and CloudWatch monitoring
- Sample microservices with automatic sidecar injection

Author: AWS Solutions Architecture Team
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Tags,
    Duration,
)
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_eks as eks
from aws_cdk import aws_ecr as ecr
from aws_cdk import aws_iam as iam
from aws_cdk import aws_appmesh as appmesh
from aws_cdk import aws_elasticloadbalancingv2 as elbv2
from aws_cdk import aws_logs as logs
from constructs import Construct
import random
import string


class MicroservicesEksAppMeshStack(Stack):
    """
    CDK Stack for deploying microservices on EKS with AWS App Mesh.
    
    This stack creates a complete microservices architecture with service mesh
    capabilities, including EKS cluster, App Mesh resources, container registry,
    and monitoring components.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        random_suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
        
        # Define common variables
        cluster_name = f"demo-mesh-cluster-{random_suffix}"
        mesh_name = f"demo-mesh-{random_suffix}"
        namespace = "demo"
        ecr_repo_prefix = f"demo-microservices-{random_suffix}"

        # Create VPC for EKS cluster
        vpc = ec2.Vpc(
            self, "EksVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Create ECR repositories for microservices
        frontend_repo = ecr.Repository(
            self, "FrontendRepo",
            repository_name=f"{ecr_repo_prefix}/frontend",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    max_image_count=10,
                    rule_priority=1,
                    description="Keep only 10 most recent images"
                )
            ]
        )

        backend_repo = ecr.Repository(
            self, "BackendRepo",
            repository_name=f"{ecr_repo_prefix}/backend",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    max_image_count=10,
                    rule_priority=1,
                    description="Keep only 10 most recent images"
                )
            ]
        )

        database_repo = ecr.Repository(
            self, "DatabaseRepo",
            repository_name=f"{ecr_repo_prefix}/database",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    max_image_count=10,
                    rule_priority=1,
                    description="Keep only 10 most recent images"
                )
            ]
        )

        # Create IAM role for EKS cluster
        cluster_role = iam.Role(
            self, "EksClusterRole",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy")
            ]
        )

        # Create IAM role for EKS node group
        node_role = iam.Role(
            self, "EksNodeRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSWorkerNodePolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKS_CNI_Policy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryReadOnly"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSXRayDaemonWriteAccess")
            ]
        )

        # Add App Mesh permissions to node role
        node_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "appmesh:*",
                    "servicediscovery:CreateService",
                    "servicediscovery:GetService",
                    "servicediscovery:RegisterInstance",
                    "servicediscovery:DeregisterInstance",
                    "servicediscovery:ListInstances",
                    "servicediscovery:ListNamespaces",
                    "servicediscovery:ListServices",
                    "route53:GetHealthCheck",
                    "route53:CreateHealthCheck",
                    "route53:UpdateHealthCheck",
                    "route53:ChangeResourceRecordSets",
                    "route53:DeleteHealthCheck"
                ],
                resources=["*"]
            )
        )

        # Create CloudWatch log group for EKS cluster
        cluster_log_group = logs.LogGroup(
            self, "EksClusterLogGroup",
            log_group_name=f"/aws/eks/{cluster_name}/cluster",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

        # Create EKS cluster
        cluster = eks.Cluster(
            self, "EksCluster",
            cluster_name=cluster_name,
            version=eks.KubernetesVersion.V1_28,
            vpc=vpc,
            role=cluster_role,
            default_capacity=0,  # We'll add managed node groups separately
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER
            ],
            cluster_handler_environment={
                "CLUSTER_NAME": cluster_name
            }
        )

        # Add managed node group
        node_group = cluster.add_nodegroup_capacity(
            "StandardWorkers",
            instance_types=[ec2.InstanceType("m5.large")],
            min_size=1,
            max_size=4,
            desired_size=3,
            nodegroup_name="standard-workers",
            node_role=node_role,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            capacity_type=eks.CapacityType.ON_DEMAND,
            disk_size=20,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            tags={
                "Name": f"{cluster_name}-worker-node",
                "k8s.io/cluster-autoscaler/enabled": "true",
                f"k8s.io/cluster-autoscaler/{cluster_name}": "owned"
            }
        )

        # Install AWS Load Balancer Controller
        alb_controller_policy = iam.Policy(
            self, "AlbControllerPolicy",
            policy_name=f"AWSLoadBalancerControllerIAMPolicy-{random_suffix}",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "iam:CreateServiceLinkedRole",
                        "ec2:DescribeAccountAttributes",
                        "ec2:DescribeAddresses",
                        "ec2:DescribeAvailabilityZones",
                        "ec2:DescribeInternetGateways",
                        "ec2:DescribeVpcs",
                        "ec2:DescribeSubnets",
                        "ec2:DescribeSecurityGroups",
                        "ec2:DescribeInstances",
                        "ec2:DescribeNetworkInterfaces",
                        "ec2:DescribeTags",
                        "ec2:GetCoipPoolUsage",
                        "ec2:DescribeCoipPools",
                        "elasticloadbalancing:DescribeLoadBalancers",
                        "elasticloadbalancing:DescribeLoadBalancerAttributes",
                        "elasticloadbalancing:DescribeListeners",
                        "elasticloadbalancing:DescribeListenerCertificates",
                        "elasticloadbalancing:DescribeSSLPolicies",
                        "elasticloadbalancing:DescribeRules",
                        "elasticloadbalancing:DescribeTargetGroups",
                        "elasticloadbalancing:DescribeTargetGroupAttributes",
                        "elasticloadbalancing:DescribeTargetHealth",
                        "elasticloadbalancing:DescribeTags"
                    ],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cognito-idp:DescribeUserPoolClient",
                        "acm:ListCertificates",
                        "acm:DescribeCertificate",
                        "iam:ListServerCertificates",
                        "iam:GetServerCertificate",
                        "waf-regional:GetWebACL",
                        "waf-regional:GetWebACLForResource",
                        "waf-regional:AssociateWebACL",
                        "waf-regional:DisassociateWebACL",
                        "wafv2:GetWebACL",
                        "wafv2:GetWebACLForResource",
                        "wafv2:AssociateWebACL",
                        "wafv2:DisassociateWebACL",
                        "shield:DescribeProtection",
                        "shield:CreateProtection",
                        "shield:DescribeSubscription",
                        "shield:ListProtections",
                        "elasticloadbalancing:CreateListener",
                        "elasticloadbalancing:DeleteListener",
                        "elasticloadbalancing:CreateRule",
                        "elasticloadbalancing:DeleteRule",
                        "elasticloadbalancing:SetWebAcl",
                        "elasticloadbalancing:ModifyListener",
                        "elasticloadbalancing:AddListenerCertificates",
                        "elasticloadbalancing:RemoveListenerCertificates",
                        "elasticloadbalancing:ModifyRule"
                    ],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "elasticloadbalancing:CreateLoadBalancer",
                        "elasticloadbalancing:CreateTargetGroup"
                    ],
                    resources=["*"],
                    conditions={
                        "Null": {
                            "aws:RequestedRegion": "false"
                        }
                    }
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "elasticloadbalancing:CreateLoadBalancer",
                        "elasticloadbalancing:CreateTargetGroup",
                        "elasticloadbalancing:DeleteLoadBalancer",
                        "elasticloadbalancing:DeleteTargetGroup",
                        "elasticloadbalancing:ModifyLoadBalancerAttributes",
                        "elasticloadbalancing:ModifyTargetGroup",
                        "elasticloadbalancing:ModifyTargetGroupAttributes",
                        "elasticloadbalancing:RegisterTargets",
                        "elasticloadbalancing:DeregisterTargets",
                        "elasticloadbalancing:SetSecurityGroups",
                        "elasticloadbalancing:SetSubnets",
                        "elasticloadbalancing:SetIpAddressType",
                        "elasticloadbalancing:AddTags",
                        "elasticloadbalancing:RemoveTags"
                    ],
                    resources=[
                        f"arn:aws:elasticloadbalancing:*:{self.account}:targetgroup/*/*",
                        f"arn:aws:elasticloadbalancing:*:{self.account}:loadbalancer/net/*/*",
                        f"arn:aws:elasticloadbalancing:*:{self.account}:loadbalancer/app/*/*"
                    ]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "tag:GetResources",
                        "tag:TagResources"
                    ],
                    resources=["*"],
                    conditions={
                        "Null": {
                            "aws:RequestedRegion": "false"
                        }
                    }
                )
            ]
        )

        # Create service account for AWS Load Balancer Controller
        alb_controller_sa = cluster.add_service_account(
            "AlbControllerServiceAccount",
            name="aws-load-balancer-controller",
            namespace="kube-system"
        )
        alb_controller_sa.role.attach_inline_policy(alb_controller_policy)

        # Install AWS Load Balancer Controller using Helm
        alb_controller_chart = cluster.add_helm_chart(
            "AlbController",
            chart="aws-load-balancer-controller",
            repository="https://aws.github.io/eks-charts",
            namespace="kube-system",
            values={
                "clusterName": cluster_name,
                "serviceAccount": {
                    "create": False,
                    "name": "aws-load-balancer-controller"
                },
                "region": self.region,
                "vpcId": vpc.vpc_id
            }
        )
        alb_controller_chart.node.add_dependency(alb_controller_sa)

        # Create IAM role for App Mesh controller
        app_mesh_controller_policy = iam.Policy(
            self, "AppMeshControllerPolicy",
            policy_name=f"AppMeshControllerPolicy-{random_suffix}",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "appmesh:*",
                        "servicediscovery:CreateService",
                        "servicediscovery:DeleteService",
                        "servicediscovery:GetService",
                        "servicediscovery:GetInstance",
                        "servicediscovery:RegisterInstance",
                        "servicediscovery:DeregisterInstance",
                        "servicediscovery:ListInstances",
                        "servicediscovery:ListNamespaces",
                        "servicediscovery:ListServices",
                        "servicediscovery:GetInstancesHealthStatus",
                        "servicediscovery:UpdateInstanceCustomHealthStatus",
                        "servicediscovery:GetOperation",
                        "route53:GetHealthCheck",
                        "route53:CreateHealthCheck",
                        "route53:UpdateHealthCheck",
                        "route53:ChangeResourceRecordSets",
                        "route53:DeleteHealthCheck",
                        "acm:ListCertificates",
                        "acm:DescribeCertificate"
                    ],
                    resources=["*"]
                )
            ]
        )

        # Create service account for App Mesh controller
        app_mesh_controller_sa = cluster.add_service_account(
            "AppMeshControllerServiceAccount",
            name="appmesh-controller",
            namespace="appmesh-system"
        )
        app_mesh_controller_sa.role.attach_inline_policy(app_mesh_controller_policy)

        # Install App Mesh CRDs and controller using Helm
        app_mesh_controller_chart = cluster.add_helm_chart(
            "AppMeshController",
            chart="appmesh-controller",
            repository="https://aws.github.io/eks-charts",
            namespace="appmesh-system",
            create_namespace=True,
            values={
                "region": self.region,
                "serviceAccount": {
                    "create": False,
                    "name": "appmesh-controller"
                },
                "tracing": {
                    "enabled": True,
                    "provider": "x-ray"
                }
            }
        )
        app_mesh_controller_chart.node.add_dependency(app_mesh_controller_sa)

        # Create App Mesh
        mesh = appmesh.Mesh(
            self, "DemoMesh",
            mesh_name=mesh_name,
            egress_filter=appmesh.MeshFilterType.ALLOW_ALL
        )

        # Create virtual nodes for each microservice
        frontend_virtual_node = appmesh.VirtualNode(
            self, "FrontendVirtualNode",
            mesh=mesh,
            virtual_node_name="frontend-virtual-node",
            service_discovery=appmesh.ServiceDiscovery.dns(f"frontend.{namespace}.svc.cluster.local"),
            listeners=[
                appmesh.VirtualNodeListener.http(
                    port=8080,
                    health_check=appmesh.HealthCheck.http(
                        healthy_threshold=2,
                        interval=Duration.seconds(5),
                        path="/",
                        timeout=Duration.seconds(2),
                        unhealthy_threshold=2
                    )
                )
            ],
            access_log=appmesh.AccessLog.from_file_path("/dev/stdout")
        )

        backend_virtual_node = appmesh.VirtualNode(
            self, "BackendVirtualNode",
            mesh=mesh,
            virtual_node_name="backend-virtual-node",
            service_discovery=appmesh.ServiceDiscovery.dns(f"backend.{namespace}.svc.cluster.local"),
            listeners=[
                appmesh.VirtualNodeListener.http(
                    port=8080,
                    health_check=appmesh.HealthCheck.http(
                        healthy_threshold=2,
                        interval=Duration.seconds(5),
                        path="/api/data",
                        timeout=Duration.seconds(2),
                        unhealthy_threshold=2
                    )
                )
            ],
            access_log=appmesh.AccessLog.from_file_path("/dev/stdout")
        )

        database_virtual_node = appmesh.VirtualNode(
            self, "DatabaseVirtualNode",
            mesh=mesh,
            virtual_node_name="database-virtual-node",
            service_discovery=appmesh.ServiceDiscovery.dns(f"database.{namespace}.svc.cluster.local"),
            listeners=[
                appmesh.VirtualNodeListener.http(
                    port=5432,
                    health_check=appmesh.HealthCheck.http(
                        healthy_threshold=2,
                        interval=Duration.seconds(5),
                        path="/query",
                        timeout=Duration.seconds(2),
                        unhealthy_threshold=2
                    )
                )
            ],
            access_log=appmesh.AccessLog.from_file_path("/dev/stdout")
        )

        # Create virtual services
        frontend_virtual_service = appmesh.VirtualService(
            self, "FrontendVirtualService",
            virtual_service_provider=appmesh.VirtualServiceProvider.virtual_node(frontend_virtual_node),
            virtual_service_name="frontend-virtual-service"
        )

        database_virtual_service = appmesh.VirtualService(
            self, "DatabaseVirtualService",
            virtual_service_provider=appmesh.VirtualServiceProvider.virtual_node(database_virtual_node),
            virtual_service_name="database-virtual-service"
        )

        # Create virtual router for backend with advanced routing
        backend_virtual_router = appmesh.VirtualRouter(
            self, "BackendVirtualRouter",
            mesh=mesh,
            virtual_router_name="backend-virtual-router",
            listeners=[
                appmesh.VirtualRouterListener.http(port=8080)
            ]
        )

        # Create route with retry policy
        backend_route = appmesh.Route(
            self, "BackendRoute",
            route_spec=appmesh.RouteSpec.http(
                weighted_targets=[
                    appmesh.WeightedTarget(
                        virtual_node=backend_virtual_node,
                        weight=100
                    )
                ],
                retry_policy=appmesh.HttpRetryPolicy(
                    http_retry_events=[
                        appmesh.HttpRetryEvent.SERVER_ERROR,
                        appmesh.HttpRetryEvent.GATEWAY_ERROR
                    ],
                    tcp_retry_events=[
                        appmesh.TcpRetryEvent.CONNECTION_ERROR
                    ],
                    retry_attempts=3,
                    retry_timeout=Duration.seconds(15)
                )
            ),
            virtual_router=backend_virtual_router,
            route_name="backend-route"
        )

        backend_virtual_service = appmesh.VirtualService(
            self, "BackendVirtualService",
            virtual_service_provider=appmesh.VirtualServiceProvider.virtual_router(backend_virtual_router),
            virtual_service_name="backend-virtual-service"
        )

        # Add backend dependencies
        frontend_virtual_node.add_backend(appmesh.Backend.virtual_service(backend_virtual_service))
        backend_virtual_node.add_backend(appmesh.Backend.virtual_service(database_virtual_service))

        # Add tags to all resources
        Tags.of(self).add("Project", "MicroservicesEksAppMesh")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("ManagedBy", "CDK")

        # Outputs
        CfnOutput(
            self, "ClusterName",
            value=cluster.cluster_name,
            description="EKS Cluster Name"
        )

        CfnOutput(
            self, "ClusterEndpoint",
            value=cluster.cluster_endpoint,
            description="EKS Cluster Endpoint"
        )

        CfnOutput(
            self, "MeshName",
            value=mesh.mesh_name,
            description="App Mesh Name"
        )

        CfnOutput(
            self, "FrontendRepoUri",
            value=frontend_repo.repository_uri,
            description="Frontend ECR Repository URI"
        )

        CfnOutput(
            self, "BackendRepoUri",
            value=backend_repo.repository_uri,
            description="Backend ECR Repository URI"
        )

        CfnOutput(
            self, "DatabaseRepoUri",
            value=database_repo.repository_uri,
            description="Database ECR Repository URI"
        )

        CfnOutput(
            self, "VpcId",
            value=vpc.vpc_id,
            description="VPC ID"
        )

        CfnOutput(
            self, "UpdateKubeconfigCommand",
            value=f"aws eks update-kubeconfig --region {self.region} --name {cluster_name}",
            description="Command to update kubeconfig"
        )


app = cdk.App()

# Get environment from context or use defaults
env = Environment(
    account=app.node.try_get_context("account") or cdk.Aws.ACCOUNT_ID,
    region=app.node.try_get_context("region") or "us-east-1"
)

MicroservicesEksAppMeshStack(
    app, 
    "MicroservicesEksAppMeshStack",
    env=env,
    description="CDK Stack for deploying microservices on EKS with AWS App Mesh service mesh capabilities"
)

app.synth()