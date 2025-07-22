#!/usr/bin/env python3
"""
AWS CDK Application for Secure Remote Access with Session Manager

This CDK application deploys a complete Session Manager solution that provides
secure remote access to EC2 instances without SSH keys or bastion hosts.
The solution includes IAM roles, EC2 instances, and comprehensive logging.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3 as s3,
    aws_ssm as ssm,
    RemovalPolicy,
    CfnOutput,
    Duration,
)
from constructs import Construct
import json


class SecureRemoteAccessStack(Stack):
    """
    CDK Stack for implementing secure remote access using AWS Systems Manager Session Manager.
    
    This stack creates:
    - IAM role and instance profile for EC2 instances
    - EC2 instance with Session Manager capabilities
    - S3 bucket for session logs
    - CloudWatch log group for session streaming
    - Session Manager logging configuration
    - User policy for controlled access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-6:]  # Use last 6 chars of construct address

        # Create S3 bucket for session logs with encryption and security settings
        session_logs_bucket = s3.Bucket(
            self, "SessionLogsBucket",
            bucket_name=f"sessionmanager-logs-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,  # Enable cleanup for demo purposes
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="SessionLogRetention",
                    enabled=True,
                    expiration=Duration.days(90),  # Retain logs for 90 days
                )
            ]
        )

        # Create CloudWatch log group for real-time session streaming
        session_log_group = logs.LogGroup(
            self, "SessionManagerLogGroup",
            log_group_name=f"/aws/sessionmanager/sessions-{unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create IAM role for EC2 instances to communicate with Session Manager
        instance_role = iam.Role(
            self, "SessionManagerInstanceRole",
            role_name=f"SessionManagerInstanceRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for EC2 instances to use Session Manager",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                )
            ]
        )

        # Add additional permissions for CloudWatch and S3 logging
        instance_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogStreams"
                ],
                resources=[session_log_group.log_group_arn + "*"]
            )
        )

        instance_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:PutObject",
                    "s3:GetEncryptionConfiguration"
                ],
                resources=[session_logs_bucket.bucket_arn + "/*"]
            )
        )

        # Create VPC with default configuration for the demo
        vpc = ec2.Vpc(
            self, "SessionManagerVpc",
            max_azs=2,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                )
            ]
        )

        # Create security group with no inbound rules (zero-trust approach)
        security_group = ec2.SecurityGroup(
            self, "SessionManagerSecurityGroup",
            vpc=vpc,
            description="Security group for Session Manager instances - no inbound rules",
            allow_all_outbound=True
        )

        # Get latest Amazon Linux 2 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux(
            generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE
        )

        # User data script to ensure SSM Agent is running
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "yum update -y",
            "yum install -y amazon-ssm-agent",
            "systemctl enable amazon-ssm-agent",
            "systemctl start amazon-ssm-agent"
        )

        # Create EC2 instance with Session Manager capabilities
        instance = ec2.Instance(
            self, "SessionManagerInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3,
                ec2.InstanceSize.MICRO
            ),
            machine_image=amzn_linux,
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            role=instance_role,
            security_group=security_group,
            user_data=user_data,
        )

        # Add tags for identification and access control
        cdk.Tags.of(instance).add("Name", f"SessionManagerDemo-{unique_suffix}")
        cdk.Tags.of(instance).add("Purpose", "SessionManagerTesting")
        cdk.Tags.of(instance).add("Environment", "Demo")

        # Create Session Manager logging preferences
        logging_config = {
            "schemaVersion": "1.0",
            "description": "Session Manager logging configuration",
            "sessionType": "Standard_Stream",
            "inputs": {
                "s3BucketName": session_logs_bucket.bucket_name,
                "s3KeyPrefix": "session-logs/",
                "s3EncryptionEnabled": True,
                "cloudWatchLogGroupName": session_log_group.log_group_name,
                "cloudWatchEncryptionEnabled": True,
                "cloudWatchStreamingEnabled": True
            }
        }

        # Apply logging configuration using SSM preference
        ssm.CfnPreference(
            self, "SessionManagerLoggingPreference",
            name="SessionManagerLoggingPreferences",
            value=json.dumps(logging_config)
        )

        # Create user policy for Session Manager access
        user_policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["ssm:StartSession"],
                    "Resource": [
                        f"arn:aws:ec2:{self.region}:{self.account}:instance/*"
                    ],
                    "Condition": {
                        "StringEquals": {
                            "ssm:resourceTag/Purpose": "SessionManagerTesting"
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "ssm:DescribeInstanceInformation",
                        "ssm:DescribeInstanceAssociationsStatus",
                        "ssm:GetConnectionStatus"
                    ],
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "ssm:DescribeDocumentParameters",
                        "ssm:DescribeDocument",
                        "ssm:GetDocument"
                    ],
                    "Resource": f"arn:aws:ssm:*:*:document/*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "ssm:TerminateSession",
                        "ssm:ResumeSession"
                    ],
                    "Resource": f"arn:aws:ssm:*:*:session/${{aws:username}}-*"
                }
            ]
        }

        user_access_policy = iam.ManagedPolicy(
            self, "SessionManagerUserPolicy",
            managed_policy_name=f"SessionManagerUserPolicy-{unique_suffix}",
            description="Policy for users to access Session Manager",
            document=iam.PolicyDocument.from_json(user_policy_document)
        )

        # Create outputs for reference and testing
        CfnOutput(
            self, "InstanceId",
            value=instance.instance_id,
            description="EC2 Instance ID for Session Manager testing",
            export_name=f"SessionManager-InstanceId-{unique_suffix}"
        )

        CfnOutput(
            self, "SessionLogsBucket",
            value=session_logs_bucket.bucket_name,
            description="S3 bucket for session logs",
            export_name=f"SessionManager-LogsBucket-{unique_suffix}"
        )

        CfnOutput(
            self, "CloudWatchLogGroup",
            value=session_log_group.log_group_name,
            description="CloudWatch log group for session streaming",
            export_name=f"SessionManager-LogGroup-{unique_suffix}"
        )

        CfnOutput(
            self, "UserPolicyArn",
            value=user_access_policy.managed_policy_arn,
            description="ARN of the user policy for Session Manager access",
            export_name=f"SessionManager-UserPolicy-{unique_suffix}"
        )

        CfnOutput(
            self, "StartSessionCommand",
            value=f"aws ssm start-session --target {instance.instance_id}",
            description="Command to start Session Manager session"
        )

        CfnOutput(
            self, "InstanceRoleArn",
            value=instance_role.role_arn,
            description="ARN of the instance role",
            export_name=f"SessionManager-InstanceRole-{unique_suffix}"
        )


# CDK Application entry point
app = cdk.App()

# Create the stack
SecureRemoteAccessStack(
    app, "SecureRemoteAccessStack",
    description="Secure Remote Access with AWS Systems Manager Session Manager",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

# Add tags to all resources in the application
cdk.Tags.of(app).add("Project", "SessionManagerDemo")
cdk.Tags.of(app).add("Purpose", "SecureRemoteAccess")
cdk.Tags.of(app).add("CostCenter", "Infrastructure")

app.synth()