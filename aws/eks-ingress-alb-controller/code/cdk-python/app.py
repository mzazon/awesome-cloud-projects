#!/usr/bin/env python3
"""
AWS CDK Python application for EKS Ingress Controllers with AWS Load Balancer Controller.

This application creates an EKS cluster with the AWS Load Balancer Controller installed,
along with sample applications and various ingress configurations demonstrating
ALB and NLB capabilities.
"""

import os
from typing import Dict, Any, List

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    aws_ec2 as ec2,
    aws_eks as eks,
    aws_iam as iam,
    aws_s3 as s3,
    aws_certificatemanager as acm,
    aws_route53 as route53,
    aws_logs as logs,
    aws_ssm as ssm,
    RemovalPolicy,
    Tags,
)
from constructs import Construct


class EksIngressControllerStack(Stack):
    """
    CDK Stack for EKS cluster with AWS Load Balancer Controller and sample ingress configurations.
    
    This stack provisions:
    - VPC with public and private subnets
    - EKS cluster with managed node groups
    - AWS Load Balancer Controller with proper IAM permissions
    - Sample applications for testing ingress functionality
    - Various ingress configurations (basic ALB, advanced ALB with SSL, weighted routing, NLB)
    - S3 bucket for ALB access logs
    - CloudWatch log groups for monitoring
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        cluster_name: str,
        domain_name: str = None,
        enable_logging: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the EKS Ingress Controller stack.
        
        Args:
            scope: The parent construct
            construct_id: The construct identifier
            cluster_name: Name for the EKS cluster
            domain_name: Domain name for ingress hosts (optional)
            enable_logging: Whether to enable ALB access logging
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.cluster_name = cluster_name
        self.domain_name = domain_name or f"demo-{construct_id.lower()}.example.com"
        self.enable_logging = enable_logging

        # Create VPC
        self.vpc = self._create_vpc()

        # Create EKS cluster
        self.cluster = self._create_eks_cluster()

        # Create IAM role for AWS Load Balancer Controller
        self.lb_controller_role = self._create_load_balancer_controller_role()

        # Install AWS Load Balancer Controller
        self._install_load_balancer_controller()

        # Create S3 bucket for access logs (if logging enabled)
        if self.enable_logging:
            self.access_logs_bucket = self._create_access_logs_bucket()

        # Create SSL certificate for HTTPS
        self.ssl_certificate = self._create_ssl_certificate()

        # Deploy sample applications
        self._deploy_sample_applications()

        # Create ingress configurations
        self._create_ingress_configurations()

        # Add outputs
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
            "EksVpc",
            vpc_name=f"{self.cluster_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
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

        # Add tags required for AWS Load Balancer Controller
        for subnet in vpc.public_subnets:
            Tags.of(subnet).add("kubernetes.io/role/elb", "1")
            Tags.of(subnet).add(f"kubernetes.io/cluster/{self.cluster_name}", "shared")

        for subnet in vpc.private_subnets:
            Tags.of(subnet).add("kubernetes.io/role/internal-elb", "1")
            Tags.of(subnet).add(f"kubernetes.io/cluster/{self.cluster_name}", "shared")

        return vpc

    def _create_eks_cluster(self) -> eks.Cluster:
        """
        Create EKS cluster with managed node groups.
        
        Returns:
            eks.Cluster: The created EKS cluster
        """
        # Create CloudWatch log group for EKS cluster
        cluster_log_group = logs.LogGroup(
            self,
            "EksClusterLogGroup",
            log_group_name=f"/aws/eks/{self.cluster_name}/cluster",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create EKS cluster
        cluster = eks.Cluster(
            self,
            "EksCluster",
            cluster_name=self.cluster_name,
            version=eks.KubernetesVersion.V1_28,
            vpc=self.vpc,
            vpc_subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)],
            default_capacity=0,  # We'll add managed node groups separately
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER,
            ],
            output_cluster_name=True,
            output_config_command=True,
            output_masters_role_arn=True,
        )

        # Add managed node group
        cluster.add_nodegroup_capacity(
            "DefaultNodeGroup",
            instance_types=[ec2.InstanceType("t3.medium")],
            min_size=2,
            max_size=10,
            desired_size=3,
            subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            capacity_type=eks.CapacityType.ON_DEMAND,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            labels={
                "node-type": "default",
                "workload": "ingress-demo",
            },
            tags={
                "Name": f"{self.cluster_name}-default-node",
                "Environment": "demo",
            },
        )

        return cluster

    def _create_load_balancer_controller_role(self) -> iam.Role:
        """
        Create IAM role for AWS Load Balancer Controller with required permissions.
        
        Returns:
            iam.Role: The IAM role for the Load Balancer Controller
        """
        # Create IAM policy for AWS Load Balancer Controller
        policy_document = iam.PolicyDocument.from_json({
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
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
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
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
                        "shield:GetSubscriptionState",
                        "shield:DescribeSubscription",
                        "shield:ListProtections"
                    ],
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "ec2:AuthorizeSecurityGroupIngress",
                        "ec2:RevokeSecurityGroupIngress"
                    ],
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "ec2:CreateSecurityGroup"
                    ],
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "ec2:CreateTags"
                    ],
                    "Resource": "arn:aws:ec2:*:*:security-group/*",
                    "Condition": {
                        "StringEquals": {
                            "ec2:CreateAction": "CreateSecurityGroup"
                        },
                        "Null": {
                            "aws:RequestedRegion": "false"
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "elasticloadbalancing:CreateLoadBalancer",
                        "elasticloadbalancing:CreateTargetGroup"
                    ],
                    "Resource": "*",
                    "Condition": {
                        "Null": {
                            "aws:RequestedRegion": "false"
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "elasticloadbalancing:CreateListener",
                        "elasticloadbalancing:DeleteListener",
                        "elasticloadbalancing:CreateRule",
                        "elasticloadbalancing:DeleteRule"
                    ],
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "elasticloadbalancing:AddTags",
                        "elasticloadbalancing:RemoveTags"
                    ],
                    "Resource": [
                        "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
                        "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
                        "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
                    ],
                    "Condition": {
                        "Null": {
                            "aws:RequestedRegion": "false",
                            "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "elasticloadbalancing:ModifyLoadBalancerAttributes",
                        "elasticloadbalancing:SetIpAddressType",
                        "elasticloadbalancing:SetSecurityGroups",
                        "elasticloadbalancing:SetSubnets",
                        "elasticloadbalancing:DeleteLoadBalancer",
                        "elasticloadbalancing:ModifyTargetGroup",
                        "elasticloadbalancing:ModifyTargetGroupAttributes",
                        "elasticloadbalancing:DeleteTargetGroup"
                    ],
                    "Resource": "*",
                    "Condition": {
                        "Null": {
                            "aws:ResourceTag/elbv2.k8s.aws/cluster": "false"
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "elasticloadbalancing:RegisterTargets",
                        "elasticloadbalancing:DeregisterTargets"
                    ],
                    "Resource": "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "elasticloadbalancing:SetWebAcl",
                        "elasticloadbalancing:ModifyListener",
                        "elasticloadbalancing:AddListenerCertificates",
                        "elasticloadbalancing:RemoveListenerCertificates",
                        "elasticloadbalancing:ModifyRule"
                    ],
                    "Resource": "*"
                }
            ]
        })

        policy = iam.ManagedPolicy(
            self,
            "AWSLoadBalancerControllerPolicy",
            managed_policy_name=f"AWSLoadBalancerControllerPolicy-{self.cluster_name}",
            document=policy_document,
            description="IAM policy for AWS Load Balancer Controller",
        )

        # Create service account and IAM role for the controller
        service_account = self.cluster.add_service_account(
            "AWSLoadBalancerControllerServiceAccount",
            name="aws-load-balancer-controller",
            namespace="kube-system",
        )

        service_account.role.add_managed_policy(policy)

        return service_account.role

    def _install_load_balancer_controller(self) -> None:
        """Install AWS Load Balancer Controller using Helm chart."""
        # Add AWS Load Balancer Controller Helm chart
        load_balancer_controller = self.cluster.add_helm_chart(
            "AWSLoadBalancerController",
            chart="aws-load-balancer-controller",
            repository="https://aws.github.io/eks-charts",
            namespace="kube-system",
            values={
                "clusterName": self.cluster.cluster_name,
                "serviceAccount": {
                    "create": False,
                    "name": "aws-load-balancer-controller",
                },
                "region": self.region,
                "vpcId": self.vpc.vpc_id,
                "image": {
                    "repository": "602401143452.dkr.ecr.us-west-2.amazonaws.com/amazon/aws-load-balancer-controller",
                },
                "replicaCount": 2,
                "resources": {
                    "limits": {
                        "cpu": "200m",
                        "memory": "500Mi",
                    },
                    "requests": {
                        "cpu": "100m",
                        "memory": "200Mi",
                    },
                },
                "nodeSelector": {
                    "kubernetes.io/os": "linux",
                },
                "tolerations": [],
                "affinity": {
                    "podAntiAffinity": {
                        "preferredDuringSchedulingIgnoredDuringExecution": [
                            {
                                "weight": 100,
                                "podAffinityTerm": {
                                    "labelSelector": {
                                        "matchLabels": {
                                            "app.kubernetes.io/name": "aws-load-balancer-controller",
                                        },
                                    },
                                    "topologyKey": "kubernetes.io/hostname",
                                },
                            },
                        ],
                    },
                },
            },
        )

    def _create_access_logs_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for ALB access logs.
        
        Returns:
            s3.Bucket: The S3 bucket for access logs
        """
        bucket = s3.Bucket(
            self,
            "AccessLogsBucket",
            bucket_name=f"alb-access-logs-{self.cluster_name.lower()}-{self.account}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    enabled=True,
                    expiration=Duration.days(90),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(60),
                        ),
                    ],
                ),
            ],
        )

        # Add bucket policy for ALB service account
        elb_service_account_mapping = {
            "us-east-1": "127311923021",
            "us-east-2": "033677994240",
            "us-west-1": "027434742980",
            "us-west-2": "797873946194",
            "eu-west-1": "156460612806",
            "eu-central-1": "054676820928",
            "ap-southeast-1": "114774131450",
            "ap-northeast-1": "582318560864",
        }

        elb_service_account = elb_service_account_mapping.get(self.region, "797873946194")

        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSLogDeliveryWrite",
                effect=iam.Effect.ALLOW,
                principals=[iam.AccountPrincipal(elb_service_account)],
                actions=["s3:PutObject"],
                resources=[bucket.arn_for_objects("*")],
            )
        )

        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSLogDeliveryAclCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.AccountPrincipal(elb_service_account)],
                actions=["s3:GetBucketAcl"],
                resources=[bucket.bucket_arn],
            )
        )

        return bucket

    def _create_ssl_certificate(self) -> acm.Certificate:
        """
        Create SSL certificate for HTTPS ingress.
        
        Returns:
            acm.Certificate: The SSL certificate
        """
        certificate = acm.Certificate(
            self,
            "SSLCertificate",
            domain_name=f"*.{self.domain_name.split('.', 1)[1]}"
            if self.domain_name.startswith("demo-")
            else f"*.{self.domain_name}",
            subject_alternative_names=[self.domain_name],
            validation=acm.CertificateValidation.from_dns(),
        )

        return certificate

    def _deploy_sample_applications(self) -> None:
        """Deploy sample applications for testing ingress functionality."""
        # Create namespace for demo applications
        namespace_manifest = {
            "apiVersion": "v1",
            "kind": "Namespace",
            "metadata": {
                "name": "ingress-demo",
                "labels": {
                    "name": "ingress-demo",
                    "app.kubernetes.io/managed-by": "aws-cdk",
                },
            },
        }

        self.cluster.add_manifest("IngressDemoNamespace", namespace_manifest)

        # Deploy sample application v1
        app_v1_manifests = [
            {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {
                    "namespace": "ingress-demo",
                    "name": "sample-app-v1",
                    "labels": {
                        "app": "sample-app",
                        "version": "v1",
                        "app.kubernetes.io/managed-by": "aws-cdk",
                    },
                },
                "spec": {
                    "replicas": 3,
                    "selector": {"matchLabels": {"app": "sample-app", "version": "v1"}},
                    "template": {
                        "metadata": {
                            "labels": {
                                "app": "sample-app",
                                "version": "v1",
                            }
                        },
                        "spec": {
                            "containers": [
                                {
                                    "name": "app",
                                    "image": "nginx:1.21",
                                    "ports": [{"containerPort": 80}],
                                    "env": [{"name": "VERSION", "value": "v1"}],
                                    "resources": {
                                        "limits": {"cpu": "100m", "memory": "128Mi"},
                                        "requests": {"cpu": "50m", "memory": "64Mi"},
                                    },
                                }
                            ]
                        },
                    },
                },
            },
            {
                "apiVersion": "v1",
                "kind": "Service",
                "metadata": {
                    "namespace": "ingress-demo",
                    "name": "sample-app-v1",
                    "labels": {
                        "app": "sample-app",
                        "version": "v1",
                        "app.kubernetes.io/managed-by": "aws-cdk",
                    },
                },
                "spec": {
                    "selector": {"app": "sample-app", "version": "v1"},
                    "ports": [{"port": 80, "targetPort": 80}],
                    "type": "ClusterIP",
                },
            },
        ]

        for i, manifest in enumerate(app_v1_manifests):
            self.cluster.add_manifest(f"SampleAppV1-{i}", manifest)

        # Deploy sample application v2
        app_v2_manifests = [
            {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {
                    "namespace": "ingress-demo",
                    "name": "sample-app-v2",
                    "labels": {
                        "app": "sample-app",
                        "version": "v2",
                        "app.kubernetes.io/managed-by": "aws-cdk",
                    },
                },
                "spec": {
                    "replicas": 2,
                    "selector": {"matchLabels": {"app": "sample-app", "version": "v2"}},
                    "template": {
                        "metadata": {
                            "labels": {
                                "app": "sample-app",
                                "version": "v2",
                            }
                        },
                        "spec": {
                            "containers": [
                                {
                                    "name": "app",
                                    "image": "nginx:1.21",
                                    "ports": [{"containerPort": 80}],
                                    "env": [{"name": "VERSION", "value": "v2"}],
                                    "resources": {
                                        "limits": {"cpu": "100m", "memory": "128Mi"},
                                        "requests": {"cpu": "50m", "memory": "64Mi"},
                                    },
                                }
                            ]
                        },
                    },
                },
            },
            {
                "apiVersion": "v1",
                "kind": "Service",
                "metadata": {
                    "namespace": "ingress-demo",
                    "name": "sample-app-v2",
                    "labels": {
                        "app": "sample-app",
                        "version": "v2",
                        "app.kubernetes.io/managed-by": "aws-cdk",
                    },
                },
                "spec": {
                    "selector": {"app": "sample-app", "version": "v2"},
                    "ports": [{"port": 80, "targetPort": 80}],
                    "type": "ClusterIP",
                },
            },
        ]

        for i, manifest in enumerate(app_v2_manifests):
            self.cluster.add_manifest(f"SampleAppV2-{i}", manifest)

    def _create_ingress_configurations(self) -> None:
        """Create various ingress configurations demonstrating different features."""
        # Basic ALB Ingress
        basic_alb_ingress = {
            "apiVersion": "networking.k8s.io/v1",
            "kind": "Ingress",
            "metadata": {
                "namespace": "ingress-demo",
                "name": "sample-app-basic-alb",
                "annotations": {
                    "alb.ingress.kubernetes.io/scheme": "internet-facing",
                    "alb.ingress.kubernetes.io/target-type": "ip",
                    "alb.ingress.kubernetes.io/healthcheck-path": "/",
                    "alb.ingress.kubernetes.io/healthcheck-interval-seconds": "10",
                    "alb.ingress.kubernetes.io/healthcheck-timeout-seconds": "5",
                    "alb.ingress.kubernetes.io/healthy-threshold-count": "2",
                    "alb.ingress.kubernetes.io/unhealthy-threshold-count": "3",
                    "alb.ingress.kubernetes.io/tags": "Environment=demo,Team=platform,ManagedBy=aws-cdk",
                },
                "labels": {
                    "app.kubernetes.io/managed-by": "aws-cdk",
                },
            },
            "spec": {
                "ingressClassName": "alb",
                "rules": [
                    {
                        "host": f"basic.{self.domain_name}",
                        "http": {
                            "paths": [
                                {
                                    "path": "/",
                                    "pathType": "Prefix",
                                    "backend": {
                                        "service": {
                                            "name": "sample-app-v1",
                                            "port": {"number": 80},
                                        }
                                    },
                                }
                            ]
                        },
                    }
                ],
            },
        }

        self.cluster.add_manifest("BasicALBIngress", basic_alb_ingress)

        # Advanced ALB Ingress with SSL
        advanced_alb_annotations = {
            "alb.ingress.kubernetes.io/scheme": "internet-facing",
            "alb.ingress.kubernetes.io/target-type": "ip",
            "alb.ingress.kubernetes.io/listen-ports": '[{"HTTP": 80}, {"HTTPS": 443}]',
            "alb.ingress.kubernetes.io/ssl-redirect": "443",
            "alb.ingress.kubernetes.io/certificate-arn": self.ssl_certificate.certificate_arn,
            "alb.ingress.kubernetes.io/ssl-policy": "ELBSecurityPolicy-TLS-1-2-2019-07",
            "alb.ingress.kubernetes.io/load-balancer-attributes": "access_logs.s3.enabled=false,idle_timeout.timeout_seconds=60",
            "alb.ingress.kubernetes.io/target-group-attributes": "deregistration_delay.timeout_seconds=30,stickiness.enabled=false",
            "alb.ingress.kubernetes.io/healthcheck-path": "/",
            "alb.ingress.kubernetes.io/healthcheck-protocol": "HTTP",
            "alb.ingress.kubernetes.io/group.name": "advanced-ingress",
            "alb.ingress.kubernetes.io/group.order": "1",
            "alb.ingress.kubernetes.io/tags": "Environment=demo,Team=platform,ManagedBy=aws-cdk",
        }

        # Enable access logging if bucket was created
        if self.enable_logging and hasattr(self, "access_logs_bucket"):
            advanced_alb_annotations[
                "alb.ingress.kubernetes.io/load-balancer-attributes"
            ] = f"access_logs.s3.enabled=true,access_logs.s3.bucket={self.access_logs_bucket.bucket_name},access_logs.s3.prefix=alb-logs,idle_timeout.timeout_seconds=60"

        advanced_alb_ingress = {
            "apiVersion": "networking.k8s.io/v1",
            "kind": "Ingress",
            "metadata": {
                "namespace": "ingress-demo",
                "name": "sample-app-advanced-alb",
                "annotations": advanced_alb_annotations,
                "labels": {
                    "app.kubernetes.io/managed-by": "aws-cdk",
                },
            },
            "spec": {
                "ingressClassName": "alb",
                "rules": [
                    {
                        "host": f"advanced.{self.domain_name}",
                        "http": {
                            "paths": [
                                {
                                    "path": "/v1",
                                    "pathType": "Prefix",
                                    "backend": {
                                        "service": {
                                            "name": "sample-app-v1",
                                            "port": {"number": 80},
                                        }
                                    },
                                },
                                {
                                    "path": "/v2",
                                    "pathType": "Prefix",
                                    "backend": {
                                        "service": {
                                            "name": "sample-app-v2",
                                            "port": {"number": 80},
                                        }
                                    },
                                },
                            ]
                        },
                    }
                ],
            },
        }

        self.cluster.add_manifest("AdvancedALBIngress", advanced_alb_ingress)

        # Weighted routing ingress
        weighted_routing_ingress = {
            "apiVersion": "networking.k8s.io/v1",
            "kind": "Ingress",
            "metadata": {
                "namespace": "ingress-demo",
                "name": "sample-app-weighted-routing",
                "annotations": {
                    "alb.ingress.kubernetes.io/scheme": "internet-facing",
                    "alb.ingress.kubernetes.io/target-type": "ip",
                    "alb.ingress.kubernetes.io/group.name": "weighted-routing",
                    "alb.ingress.kubernetes.io/actions.weighted-routing": '{"type": "forward", "forwardConfig": {"targetGroups": [{"serviceName": "sample-app-v1", "servicePort": "80", "weight": 70}, {"serviceName": "sample-app-v2", "servicePort": "80", "weight": 30}]}}',
                    "alb.ingress.kubernetes.io/tags": "Environment=demo,Team=platform,ManagedBy=aws-cdk",
                },
                "labels": {
                    "app.kubernetes.io/managed-by": "aws-cdk",
                },
            },
            "spec": {
                "ingressClassName": "alb",
                "rules": [
                    {
                        "host": f"weighted.{self.domain_name}",
                        "http": {
                            "paths": [
                                {
                                    "path": "/",
                                    "pathType": "Prefix",
                                    "backend": {
                                        "service": {
                                            "name": "weighted-routing",
                                            "port": {"name": "use-annotation"},
                                        }
                                    },
                                }
                            ]
                        },
                    }
                ],
            },
        }

        self.cluster.add_manifest("WeightedRoutingIngress", weighted_routing_ingress)

        # NLB Service
        nlb_service = {
            "apiVersion": "v1",
            "kind": "Service",
            "metadata": {
                "namespace": "ingress-demo",
                "name": "sample-app-nlb",
                "annotations": {
                    "service.beta.kubernetes.io/aws-load-balancer-type": "nlb",
                    "service.beta.kubernetes.io/aws-load-balancer-scheme": "internet-facing",
                    "service.beta.kubernetes.io/aws-load-balancer-backend-protocol": "tcp",
                    "service.beta.kubernetes.io/aws-load-balancer-target-type": "ip",
                    "service.beta.kubernetes.io/aws-load-balancer-attributes": "load_balancing.cross_zone.enabled=true",
                    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol": "HTTP",
                    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path": "/",
                    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval": "10",
                    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout": "5",
                    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold": "2",
                    "service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold": "3",
                },
                "labels": {
                    "app.kubernetes.io/managed-by": "aws-cdk",
                },
            },
            "spec": {
                "selector": {"app": "sample-app", "version": "v1"},
                "ports": [{"port": 80, "targetPort": 80, "protocol": "TCP"}],
                "type": "LoadBalancer",
            },
        }

        self.cluster.add_manifest("NLBService", nlb_service)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "ClusterName",
            value=self.cluster.cluster_name,
            description="Name of the EKS cluster",
            export_name=f"{self.stack_name}-ClusterName",
        )

        CfnOutput(
            self,
            "ClusterEndpoint",
            value=self.cluster.cluster_endpoint,
            description="Endpoint URL of the EKS cluster",
            export_name=f"{self.stack_name}-ClusterEndpoint",
        )

        CfnOutput(
            self,
            "KubeconfigCommand",
            value=f"aws eks update-kubeconfig --region {self.region} --name {self.cluster.cluster_name}",
            description="Command to update kubeconfig",
        )

        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID where the EKS cluster is deployed",
            export_name=f"{self.stack_name}-VpcId",
        )

        CfnOutput(
            self,
            "LoadBalancerControllerRoleArn",
            value=self.lb_controller_role.role_arn,
            description="ARN of the IAM role for AWS Load Balancer Controller",
        )

        if self.enable_logging and hasattr(self, "access_logs_bucket"):
            CfnOutput(
                self,
                "AccessLogsBucket",
                value=self.access_logs_bucket.bucket_name,
                description="S3 bucket for ALB access logs",
            )

        CfnOutput(
            self,
            "SSLCertificateArn",
            value=self.ssl_certificate.certificate_arn,
            description="ARN of the SSL certificate",
        )

        CfnOutput(
            self,
            "DomainName",
            value=self.domain_name,
            description="Domain name used for ingress hosts",
        )

        CfnOutput(
            self,
            "IngressUrls",
            value=f"http://basic.{self.domain_name}, https://advanced.{self.domain_name}, http://weighted.{self.domain_name}",
            description="URLs to test ingress functionality",
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", "EKS-Ingress-Demo")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("ManagedBy", "AWS-CDK")
        Tags.of(self).add("Owner", "Platform-Team")
        Tags.of(self).add("CostCenter", "Engineering")


class EksIngressApp(cdk.App):
    """CDK Application for EKS Ingress Controllers."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment variables or use defaults
        cluster_name = self.node.try_get_context("cluster_name") or "eks-ingress-demo"
        domain_name = self.node.try_get_context("domain_name") or "demo.example.com"
        enable_logging = self.node.try_get_context("enable_logging") or True

        # Create the stack
        eks_stack = EksIngressControllerStack(
            self,
            "EksIngressControllerStack",
            cluster_name=cluster_name,
            domain_name=domain_name,
            enable_logging=enable_logging,
            description="EKS cluster with AWS Load Balancer Controller for ingress management",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-west-2"),
            ),
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = EksIngressApp()
    app.synth()