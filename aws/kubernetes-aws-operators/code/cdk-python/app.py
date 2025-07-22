#!/usr/bin/env python3
"""
CDK Python application for Kubernetes Operators for AWS Resources

This application creates the infrastructure required for managing AWS resources
through Kubernetes operators using AWS Controllers for Kubernetes (ACK).
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_eks as eks,
    aws_iam as iam,
    aws_ec2 as ec2,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_logs as logs,
    CfnOutput,
    RemovalPolicy,
    Duration,
    Tags
)
from constructs import Construct
from typing import List, Dict, Any


class KubernetesOperatorsStack(Stack):
    """
    CDK Stack for Kubernetes Operators managing AWS Resources
    
    This stack creates:
    - EKS cluster with proper OIDC configuration
    - IAM roles for ACK controllers
    - Sample S3 bucket, IAM role, and Lambda function
    - Necessary service accounts and RBAC configurations
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get environment variables or use defaults
        cluster_name = self.node.try_get_context("cluster_name") or "ack-operators-cluster"
        ack_namespace = self.node.try_get_context("ack_namespace") or "ack-system"
        
        # Create VPC for EKS cluster
        vpc = self._create_vpc()
        
        # Create EKS cluster
        cluster = self._create_eks_cluster(vpc, cluster_name)
        
        # Create IAM roles for ACK controllers
        ack_role = self._create_ack_controller_role(cluster, ack_namespace)
        
        # Create sample AWS resources that will be managed by operators
        sample_bucket = self._create_sample_s3_bucket()
        sample_lambda_role = self._create_sample_lambda_role()
        sample_lambda = self._create_sample_lambda_function(sample_lambda_role)
        
        # Create custom operator namespace and service account
        custom_operator_role = self._create_custom_operator_role(cluster)
        
        # Apply tags to all resources
        self._apply_tags()
        
        # Create outputs
        self._create_outputs(cluster, ack_role, sample_bucket, sample_lambda)

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC for EKS cluster with proper subnet configuration"""
        return ec2.Vpc(
            self, "KubernetesOperatorsVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="PublicSubnet",
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name="PrivateSubnet",
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

    def _create_eks_cluster(self, vpc: ec2.Vpc, cluster_name: str) -> eks.Cluster:
        """Create EKS cluster with OIDC provider and managed node group"""
        
        # Create EKS cluster
        cluster = eks.Cluster(
            self, "KubernetesOperatorsCluster",
            cluster_name=cluster_name,
            version=eks.KubernetesVersion.V1_28,
            vpc=vpc,
            vpc_subnets=[ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            )],
            default_capacity=0,  # We'll add managed node groups separately
            endpoint_access=eks.EndpointAccess.PUBLIC_AND_PRIVATE,
            cluster_logging=[
                eks.ClusterLoggingTypes.API,
                eks.ClusterLoggingTypes.AUDIT,
                eks.ClusterLoggingTypes.AUTHENTICATOR,
                eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
                eks.ClusterLoggingTypes.SCHEDULER
            ]
        )
        
        # Add managed node group
        cluster.add_nodegroup_capacity(
            "OperatorNodeGroup",
            instance_types=[ec2.InstanceType("t3.medium")],
            min_size=2,
            max_size=4,
            desired_size=2,
            subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            capacity_type=eks.CapacityType.ON_DEMAND,
            ami_type=eks.NodegroupAmiType.AL2_X86_64,
            disk_size=20,
            remote_access=eks.NodegroupRemoteAccess(
                ec2_ssh_key="eks-node-key"  # Make sure this key exists
            )
        )
        
        return cluster

    def _create_ack_controller_role(self, cluster: eks.Cluster, namespace: str) -> iam.Role:
        """Create IAM role for ACK controllers with necessary permissions"""
        
        # Create service account for ACK controllers
        service_account = cluster.add_service_account(
            "ACKControllerServiceAccount",
            name="ack-controller",
            namespace=namespace
        )
        
        # Define managed policies for ACK controllers
        managed_policies = [
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3FullAccess"),
            iam.ManagedPolicy.from_aws_managed_policy_name("IAMFullAccess"),
            iam.ManagedPolicy.from_aws_managed_policy_name("AWSLambda_FullAccess")
        ]
        
        # Attach managed policies to service account
        for policy in managed_policies:
            service_account.role.add_managed_policy(policy)
        
        # Add custom policy for additional ACK permissions
        ack_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "sts:AssumeRole",
                        "sts:GetCallerIdentity",
                        "iam:PassRole",
                        "iam:CreateServiceLinkedRole",
                        "iam:GetRole",
                        "iam:ListRoles",
                        "iam:TagRole",
                        "iam:UntagRole"
                    ],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetBucketLocation",
                        "s3:ListAllMyBuckets",
                        "s3:GetBucketVersioning",
                        "s3:GetBucketPublicAccessBlock"
                    ],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "lambda:GetFunction",
                        "lambda:ListFunctions",
                        "lambda:GetFunctionConfiguration",
                        "lambda:ListTags",
                        "lambda:TagResource",
                        "lambda:UntagResource"
                    ],
                    resources=["*"]
                )
            ]
        )
        
        ack_custom_policy = iam.Policy(
            self, "ACKControllerCustomPolicy",
            document=ack_policy,
            policy_name="ACKControllerCustomPolicy"
        )
        
        service_account.role.attach_inline_policy(ack_custom_policy)
        
        return service_account.role

    def _create_custom_operator_role(self, cluster: eks.Cluster) -> iam.Role:
        """Create IAM role for custom platform operator"""
        
        # Create service account for custom operator
        service_account = cluster.add_service_account(
            "CustomOperatorServiceAccount",
            name="platform-operator-controller-manager",
            namespace="platform-operator-system"
        )
        
        # Define permissions for custom operator
        custom_operator_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:ListBucket",
                        "s3:GetBucketLocation",
                        "s3:CreateBucket",
                        "s3:DeleteBucket",
                        "s3:PutBucketPolicy",
                        "s3:GetBucketPolicy"
                    ],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "iam:CreateRole",
                        "iam:DeleteRole",
                        "iam:GetRole",
                        "iam:PutRolePolicy",
                        "iam:DeleteRolePolicy",
                        "iam:AttachRolePolicy",
                        "iam:DetachRolePolicy"
                    ],
                    resources=["*"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "lambda:CreateFunction",
                        "lambda:DeleteFunction",
                        "lambda:GetFunction",
                        "lambda:UpdateFunctionCode",
                        "lambda:UpdateFunctionConfiguration"
                    ],
                    resources=["*"]
                )
            ]
        )
        
        custom_policy = iam.Policy(
            self, "CustomOperatorPolicy",
            document=custom_operator_policy,
            policy_name="CustomOperatorPolicy"
        )
        
        service_account.role.attach_inline_policy(custom_policy)
        
        return service_account.role

    def _create_sample_s3_bucket(self) -> s3.Bucket:
        """Create sample S3 bucket for demonstration"""
        return s3.Bucket(
            self, "SampleOperatorBucket",
            bucket_name=f"sample-operator-bucket-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30)
                )
            ]
        )

    def _create_sample_lambda_role(self) -> iam.Role:
        """Create IAM role for sample Lambda function"""
        return iam.Role(
            self, "SampleLambdaRole",
            role_name=f"SampleLambdaRole-{self.region}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "S3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject"
                            ],
                            resources=[
                                f"arn:aws:s3:::sample-operator-bucket-{self.account}-{self.region}/*"
                            ]
                        )
                    ]
                )
            }
        )

    def _create_sample_lambda_function(self, role: iam.Role) -> lambda_.Function:
        """Create sample Lambda function for demonstration"""
        
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self, "SampleLambdaLogGroup",
            log_group_name="/aws/lambda/sample-operator-function",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return lambda_.Function(
            self, "SampleLambdaFunction",
            function_name="sample-operator-function",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=role,
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    '''
    Sample Lambda function for Kubernetes Operators demo
    '''
    logger.info(f"Received event: {json.dumps(event)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Hello from Kubernetes Operators Lambda!',
            'event': event
        })
    }
            """),
            description="Sample Lambda function managed by Kubernetes operators",
            timeout=Duration.minutes(1),
            memory_size=128,
            log_group=log_group,
            environment={
                "STAGE": "demo",
                "REGION": self.region
            }
        )

    def _apply_tags(self) -> None:
        """Apply common tags to all resources in the stack"""
        tags_to_apply = {
            "Project": "KubernetesOperators",
            "Environment": "Demo",
            "ManagedBy": "CDK",
            "Recipe": "kubernetes-operators-aws-resources"
        }
        
        for key, value in tags_to_apply.items():
            Tags.of(self).add(key, value)

    def _create_outputs(
        self, 
        cluster: eks.Cluster, 
        ack_role: iam.Role, 
        bucket: s3.Bucket, 
        lambda_func: lambda_.Function
    ) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self, "ClusterName",
            description="Name of the EKS cluster",
            value=cluster.cluster_name
        )
        
        CfnOutput(
            self, "ClusterEndpoint",
            description="EKS cluster endpoint",
            value=cluster.cluster_endpoint
        )
        
        CfnOutput(
            self, "ClusterArn",
            description="EKS cluster ARN",
            value=cluster.cluster_arn
        )
        
        CfnOutput(
            self, "ACKControllerRoleArn",
            description="IAM role ARN for ACK controllers",
            value=ack_role.role_arn
        )
        
        CfnOutput(
            self, "SampleBucketName",
            description="Name of the sample S3 bucket",
            value=bucket.bucket_name
        )
        
        CfnOutput(
            self, "SampleLambdaFunctionName",
            description="Name of the sample Lambda function",
            value=lambda_func.function_name
        )
        
        CfnOutput(
            self, "SampleLambdaFunctionArn",
            description="ARN of the sample Lambda function",
            value=lambda_func.function_arn
        )
        
        CfnOutput(
            self, "KubectlCommand",
            description="Command to configure kubectl for this cluster",
            value=f"aws eks update-kubeconfig --region {self.region} --name {cluster.cluster_name}"
        )


class KubernetesOperatorsApp(cdk.App):
    """CDK Application for Kubernetes Operators"""
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        
        # Get environment configuration
        env = cdk.Environment(
            account=self.node.try_get_context("account") or None,
            region=self.node.try_get_context("region") or "us-east-1"
        )
        
        # Create the main stack
        KubernetesOperatorsStack(
            self, "KubernetesOperatorsStack",
            env=env,
            description="Infrastructure for Kubernetes Operators managing AWS Resources"
        )


# Main entry point
if __name__ == "__main__":
    app = KubernetesOperatorsApp()
    app.synth()