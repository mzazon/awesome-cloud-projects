#!/usr/bin/env python3
"""
CDK Python Application for CloudFormation StackSets Multi-Account Multi-Region Management

This application deploys a comprehensive StackSets solution for organization-wide governance
across multiple AWS accounts and regions using AWS CDK Python.
"""

import json
import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Environment,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_cloudformation as cfn,
    aws_cloudtrail as cloudtrail,
    aws_config as config,
    aws_guardduty as guardduty,
    aws_iam as iam,
    aws_kms as kms,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_events as events,
    aws_events_targets as targets,
)

from constructs import Construct


class StackSetAdministratorStack(Stack):
    """
    Stack that creates the StackSet administrator role and related resources
    in the management account.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        organization_id: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.organization_id = organization_id

        # Create S3 bucket for StackSet templates
        self.template_bucket = s3.Bucket(
            self,
            "StackSetTemplatesBucket",
            bucket_name=f"stackset-templates-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioning=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create StackSet administrator role
        self.stackset_admin_role = iam.Role(
            self,
            "StackSetAdministratorRole",
            role_name="AWSCloudFormationStackSetAdministrator",
            assumed_by=iam.ServicePrincipal("cloudformation.amazonaws.com"),
            description="CloudFormation StackSet Administrator Role",
        )

        # Create policy for StackSet administrator
        stackset_admin_policy = iam.Policy(
            self,
            "StackSetAdministratorPolicy",
            policy_name="AWSCloudFormationStackSetAdministratorPolicy",
            description="Policy for CloudFormation StackSet Administrator",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["sts:AssumeRole"],
                    resources=[
                        "arn:aws:iam::*:role/AWSCloudFormationStackSetExecutionRole"
                    ],
                )
            ],
        )

        # Attach policy to role
        self.stackset_admin_role.attach_inline_policy(stackset_admin_policy)

        # Create SNS topic for StackSet alerts
        self.alert_topic = sns.Topic(
            self,
            "StackSetAlertTopic",
            topic_name=f"StackSetAlerts-{self.region}",
            display_name="StackSet Operations Alerts",
        )

        # Create CloudWatch log group for StackSet operations
        self.stackset_log_group = logs.LogGroup(
            self,
            "StackSetOperationsLogGroup",
            log_group_name="/aws/cloudformation/stackset-operations",
            retention=logs.RetentionDays.ONE_YEAR,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create Lambda execution role for drift detection
        self.drift_detection_role = iam.Role(
            self,
            "DriftDetectionRole",
            role_name="StackSetDriftDetectionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add permissions for drift detection
        self.drift_detection_role.add_inline_policy(
            iam.Policy(
                self,
                "DriftDetectionPolicy",
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        actions=[
                            "cloudformation:DetectStackSetDrift",
                            "cloudformation:DescribeStackSetOperation",
                            "cloudformation:ListStackInstances",
                            "cloudformation:DescribeStackInstance",
                            "cloudformation:DescribeStackSet",
                            "cloudformation:ListStackSets",
                            "sns:Publish",
                        ],
                        resources=["*"],
                    )
                ],
            )
        )

        # Create Lambda function for drift detection
        self.drift_detection_lambda = lambda_.Function(
            self,
            "DriftDetectionFunction",
            function_name=f"stackset-drift-detection-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_drift_detection_code()),
            timeout=Duration.minutes(15),
            role=self.drift_detection_role,
            environment={
                "SNS_TOPIC_ARN": self.alert_topic.topic_arn,
                "LOG_GROUP_NAME": self.stackset_log_group.log_group_name,
            },
        )

        # Create EventBridge rule for scheduled drift detection
        drift_detection_rule = events.Rule(
            self,
            "DriftDetectionSchedule",
            rule_name="StackSetDriftDetectionSchedule",
            description="Scheduled drift detection for StackSets",
            schedule=events.Schedule.rate(Duration.hours(6)),
        )

        # Add Lambda as target for the rule
        drift_detection_rule.add_target(
            targets.LambdaFunction(self.drift_detection_lambda)
        )

        # Create CloudWatch dashboard for StackSet monitoring
        self.dashboard = cloudwatch.Dashboard(
            self,
            "StackSetDashboard",
            dashboard_name=f"StackSet-Monitoring-{self.region}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="StackSet Operation Results",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/CloudFormation",
                                metric_name="StackSetOperationSuccessCount",
                                dimensions_map={"StackSetName": "ALL"},
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/CloudFormation",
                                metric_name="StackSetOperationFailureCount",
                                dimensions_map={"StackSetName": "ALL"},
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                    )
                ]
            ],
        )

        # Output important ARNs
        cdk.CfnOutput(
            self,
            "StackSetAdministratorRoleArn",
            value=self.stackset_admin_role.role_arn,
            description="ARN of the StackSet administrator role",
        )

        cdk.CfnOutput(
            self,
            "TemplatesBucketName",
            value=self.template_bucket.bucket_name,
            description="Name of the S3 bucket for StackSet templates",
        )

        cdk.CfnOutput(
            self,
            "AlertTopicArn",
            value=self.alert_topic.topic_arn,
            description="ARN of the SNS topic for StackSet alerts",
        )

        cdk.CfnOutput(
            self,
            "DriftDetectionLambdaArn",
            value=self.drift_detection_lambda.function_arn,
            description="ARN of the drift detection Lambda function",
        )

    def _get_drift_detection_code(self) -> str:
        """
        Returns the inline code for the drift detection Lambda function.
        """
        return """
import boto3
import json
import logging
import os
from datetime import datetime
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Lambda function to detect and report StackSet drift across all StackSets.
    \"\"\"
    try:
        cf_client = boto3.client('cloudformation')
        sns_client = boto3.client('sns')
        
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        # Get all StackSets
        paginator = cf_client.get_paginator('list_stack_sets')
        stacksets = []
        
        for page in paginator.paginate():
            stacksets.extend(page['Summaries'])
        
        logger.info(f"Found {len(stacksets)} StackSets to check for drift")
        
        drift_results = []
        
        for stackset in stacksets:
            stackset_name = stackset['StackSetName']
            
            try:
                # Initiate drift detection
                logger.info(f"Starting drift detection for StackSet: {stackset_name}")
                
                response = cf_client.detect_stack_set_drift(StackSetName=stackset_name)
                operation_id = response['OperationId']
                
                # Wait for operation to complete
                waiter = cf_client.get_waiter('stack_set_operation_complete')
                waiter.wait(
                    StackSetName=stackset_name,
                    OperationId=operation_id,
                    WaiterConfig={'Delay': 30, 'MaxAttempts': 20}
                )
                
                # Get drift results
                drift_operation = cf_client.describe_stack_set_operation(
                    StackSetName=stackset_name,
                    OperationId=operation_id
                )
                
                # Get stack instances
                instances_paginator = cf_client.get_paginator('list_stack_instances')
                instances = []
                
                for page in instances_paginator.paginate(StackSetName=stackset_name):
                    instances.extend(page['Summaries'])
                
                drifted_instances = []
                for instance in instances:
                    if instance.get('DriftStatus') == 'DRIFTED':
                        drifted_instances.append({
                            'Account': instance['Account'],
                            'Region': instance['Region'],
                            'DriftStatus': instance['DriftStatus'],
                            'StatusReason': instance.get('StatusReason', '')
                        })
                
                stackset_result = {
                    'StackSetName': stackset_name,
                    'TotalInstances': len(instances),
                    'DriftedInstances': len(drifted_instances),
                    'DriftedDetails': drifted_instances,
                    'OperationId': operation_id
                }
                
                drift_results.append(stackset_result)
                
                logger.info(f"Drift detection complete for {stackset_name}. "
                           f"Found {len(drifted_instances)} drifted instances")
                
            except Exception as e:
                logger.error(f"Error processing StackSet {stackset_name}: {str(e)}")
                continue
        
        # Generate summary report
        total_stacksets = len(stacksets)
        total_drifted = sum(1 for result in drift_results if result['DriftedInstances'] > 0)
        total_drifted_instances = sum(result['DriftedInstances'] for result in drift_results)
        
        report = {
            'timestamp': datetime.utcnow().isoformat(),
            'total_stacksets': total_stacksets,
            'stacksets_with_drift': total_drifted,
            'total_drifted_instances': total_drifted_instances,
            'details': drift_results
        }
        
        logger.info(f"Drift detection complete. "
                   f"{total_drifted} of {total_stacksets} StackSets have drift")
        
        # Send notification if drift detected
        if total_drifted_instances > 0 and sns_topic_arn:
            message = f\"\"\"
StackSet Drift Detection Summary

Total StackSets: {total_stacksets}
StackSets with Drift: {total_drifted}
Total Drifted Instances: {total_drifted_instances}

Detailed Results:
{json.dumps(drift_results, indent=2)}

Timestamp: {datetime.utcnow().isoformat()}
\"\"\"
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Subject=f'StackSet Drift Alert: {total_drifted_instances} instances detected',
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps(report, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Error in drift detection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
"""


class GovernanceStackSetStack(Stack):
    """
    Stack that creates the governance StackSet and related templates.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        organization_id: str,
        template_bucket_name: str,
        alert_topic_arn: str,
        target_regions: List[str],
        target_accounts: Optional[List[str]] = None,
        target_ous: Optional[List[str]] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.organization_id = organization_id
        self.template_bucket_name = template_bucket_name
        self.alert_topic_arn = alert_topic_arn
        self.target_regions = target_regions
        self.target_accounts = target_accounts or []
        self.target_ous = target_ous or []

        # Reference existing template bucket
        template_bucket = s3.Bucket.from_bucket_name(
            self, "TemplatesBucket", self.template_bucket_name
        )

        # Upload CloudFormation templates
        self._upload_templates(template_bucket)

        # Create execution role StackSet
        self.execution_role_stackset = cfn.CfnStackSet(
            self,
            "ExecutionRoleStackSet",
            stack_set_name=f"execution-roles-stackset-{self.region}",
            description="Deploy StackSet execution roles to target accounts",
            template_url=f"https://{self.template_bucket_name}.s3.{self.region}.amazonaws.com/execution-role-template.json",
            parameters=[
                cfn.CfnStackSet.ParameterProperty(
                    parameter_key="AdministratorAccountId",
                    parameter_value=self.account,
                )
            ],
            capabilities=["CAPABILITY_NAMED_IAM"],
            permission_model="SELF_MANAGED",
        )

        # Create governance StackSet
        self.governance_stackset = cfn.CfnStackSet(
            self,
            "GovernanceStackSet",
            stack_set_name=f"org-governance-stackset-{self.region}",
            description="Organization-wide governance and security policies",
            template_url=f"https://{self.template_bucket_name}.s3.{self.region}.amazonaws.com/governance-template.json",
            parameters=[
                cfn.CfnStackSet.ParameterProperty(
                    parameter_key="Environment",
                    parameter_value="all",
                ),
                cfn.CfnStackSet.ParameterProperty(
                    parameter_key="OrganizationId",
                    parameter_value=self.organization_id,
                ),
                cfn.CfnStackSet.ParameterProperty(
                    parameter_key="ComplianceLevel",
                    parameter_value="standard",
                ),
            ],
            capabilities=["CAPABILITY_IAM"],
            permission_model="SERVICE_MANAGED",
            auto_deployment=cfn.CfnStackSet.AutoDeploymentProperty(
                enabled=True,
                retain_stacks_on_account_removal=False,
            ),
            operation_preferences=cfn.CfnStackSet.OperationPreferencesProperty(
                region_concurrency_type="PARALLEL",
                max_concurrent_percentage=50,
                failure_tolerance_percentage=10,
            ),
        )

        # Create CloudWatch alarms for StackSet monitoring
        self._create_stackset_alarms()

        # Output StackSet information
        cdk.CfnOutput(
            self,
            "ExecutionRoleStackSetName",
            value=self.execution_role_stackset.stack_set_name,
            description="Name of the execution role StackSet",
        )

        cdk.CfnOutput(
            self,
            "GovernanceStackSetName",
            value=self.governance_stackset.stack_set_name,
            description="Name of the governance StackSet",
        )

    def _upload_templates(self, template_bucket: s3.Bucket) -> None:
        """
        Upload CloudFormation templates to S3 bucket.
        """
        # Deploy templates to S3
        s3_deployment.BucketDeployment(
            self,
            "TemplateDeployment",
            sources=[
                s3_deployment.Source.data(
                    "execution-role-template.json",
                    json.dumps(self._get_execution_role_template(), indent=2)
                ),
                s3_deployment.Source.data(
                    "governance-template.json",
                    json.dumps(self._get_governance_template(), indent=2)
                ),
            ],
            destination_bucket=template_bucket,
        )

    def _get_execution_role_template(self) -> Dict:
        """
        Returns the CloudFormation template for StackSet execution roles.
        """
        return {
            "AWSTemplateFormatVersion": "2010-09-09",
            "Description": "StackSet execution role for target accounts",
            "Parameters": {
                "AdministratorAccountId": {
                    "Type": "String",
                    "Description": "AWS account ID of the StackSet administrator account"
                }
            },
            "Resources": {
                "ExecutionRole": {
                    "Type": "AWS::IAM::Role",
                    "Properties": {
                        "RoleName": "AWSCloudFormationStackSetExecutionRole",
                        "AssumeRolePolicyDocument": {
                            "Version": "2012-10-17",
                            "Statement": [
                                {
                                    "Effect": "Allow",
                                    "Principal": {
                                        "AWS": {
                                            "Fn::Sub": "arn:aws:iam::${AdministratorAccountId}:role/AWSCloudFormationStackSetAdministrator"
                                        }
                                    },
                                    "Action": "sts:AssumeRole"
                                }
                            ]
                        },
                        "Path": "/",
                        "Policies": [
                            {
                                "PolicyName": "StackSetExecutionPolicy",
                                "PolicyDocument": {
                                    "Version": "2012-10-17",
                                    "Statement": [
                                        {
                                            "Effect": "Allow",
                                            "Action": "*",
                                            "Resource": "*"
                                        }
                                    ]
                                }
                            }
                        ],
                        "Tags": [
                            {
                                "Key": "Purpose",
                                "Value": "StackSetExecution"
                            },
                            {
                                "Key": "ManagedBy",
                                "Value": "CloudFormationStackSets"
                            }
                        ]
                    }
                }
            },
            "Outputs": {
                "ExecutionRoleArn": {
                    "Description": "ARN of the execution role",
                    "Value": {
                        "Fn::GetAtt": ["ExecutionRole", "Arn"]
                    },
                    "Export": {
                        "Name": {
                            "Fn::Sub": "${AWS::StackName}-ExecutionRoleArn"
                        }
                    }
                }
            }
        }

    def _get_governance_template(self) -> Dict:
        """
        Returns the CloudFormation template for governance policies.
        """
        return {
            "AWSTemplateFormatVersion": "2010-09-09",
            "Description": "Organization-wide governance and security policies",
            "Parameters": {
                "Environment": {
                    "Type": "String",
                    "Default": "all",
                    "AllowedValues": ["development", "staging", "production", "all"],
                    "Description": "Environment for which policies apply"
                },
                "OrganizationId": {
                    "Type": "String",
                    "Description": "AWS Organizations ID"
                },
                "ComplianceLevel": {
                    "Type": "String",
                    "Default": "standard",
                    "AllowedValues": ["basic", "standard", "strict"],
                    "Description": "Compliance level for security policies"
                }
            },
            "Mappings": {
                "ComplianceConfig": {
                    "basic": {
                        "PasswordMinLength": 8,
                        "RequireMFA": "false",
                        "S3PublicReadBlock": "true",
                        "S3PublicWriteBlock": "true"
                    },
                    "standard": {
                        "PasswordMinLength": 12,
                        "RequireMFA": "true",
                        "S3PublicReadBlock": "true",
                        "S3PublicWriteBlock": "true"
                    },
                    "strict": {
                        "PasswordMinLength": 16,
                        "RequireMFA": "true",
                        "S3PublicReadBlock": "true",
                        "S3PublicWriteBlock": "true"
                    }
                }
            },
            "Resources": {
                "PasswordPolicy": {
                    "Type": "AWS::IAM::AccountPasswordPolicy",
                    "Properties": {
                        "MinimumPasswordLength": {
                            "Fn::FindInMap": ["ComplianceConfig", {"Ref": "ComplianceLevel"}, "PasswordMinLength"]
                        },
                        "RequireUppercaseCharacters": True,
                        "RequireLowercaseCharacters": True,
                        "RequireNumbers": True,
                        "RequireSymbols": True,
                        "MaxPasswordAge": 90,
                        "PasswordReusePrevention": 12,
                        "HardExpiry": False,
                        "AllowUsersToChangePassword": True
                    }
                },
                "AuditBucket": {
                    "Type": "AWS::S3::Bucket",
                    "Properties": {
                        "BucketName": {
                            "Fn::Sub": "org-audit-logs-${AWS::AccountId}-${AWS::Region}-${OrganizationId}"
                        },
                        "PublicAccessBlockConfiguration": {
                            "BlockPublicAcls": True,
                            "BlockPublicPolicy": True,
                            "IgnorePublicAcls": True,
                            "RestrictPublicBuckets": True
                        },
                        "BucketEncryption": {
                            "ServerSideEncryptionConfiguration": [
                                {
                                    "ServerSideEncryptionByDefault": {
                                        "SSEAlgorithm": "AES256"
                                    }
                                }
                            ]
                        },
                        "VersioningConfiguration": {
                            "Status": "Enabled"
                        },
                        "LifecycleConfiguration": {
                            "Rules": [
                                {
                                    "Id": "DeleteOldLogs",
                                    "Status": "Enabled",
                                    "ExpirationInDays": 2555,
                                    "NoncurrentVersionExpirationInDays": 365
                                }
                            ]
                        },
                        "Tags": [
                            {
                                "Key": "Purpose",
                                "Value": "AuditLogs"
                            },
                            {
                                "Key": "Environment",
                                "Value": {"Ref": "Environment"}
                            }
                        ]
                    }
                },
                "OrganizationCloudTrail": {
                    "Type": "AWS::CloudTrail::Trail",
                    "Properties": {
                        "TrailName": {
                            "Fn::Sub": "organization-audit-trail-${AWS::AccountId}-${AWS::Region}"
                        },
                        "S3BucketName": {"Ref": "AuditBucket"},
                        "S3KeyPrefix": {
                            "Fn::Sub": "cloudtrail-logs/${AWS::AccountId}/"
                        },
                        "IncludeGlobalServiceEvents": True,
                        "IsMultiRegionTrail": True,
                        "EnableLogFileValidation": True,
                        "EventSelectors": [
                            {
                                "ReadWriteType": "All",
                                "IncludeManagementEvents": True,
                                "DataResources": [
                                    {
                                        "Type": "AWS::S3::Object",
                                        "Values": ["arn:aws:s3:::*/*"]
                                    }
                                ]
                            }
                        ],
                        "Tags": [
                            {
                                "Key": "Purpose",
                                "Value": "OrganizationAudit"
                            },
                            {
                                "Key": "Environment",
                                "Value": {"Ref": "Environment"}
                            }
                        ]
                    }
                },
                "AuditBucketPolicy": {
                    "Type": "AWS::S3::BucketPolicy",
                    "Properties": {
                        "Bucket": {"Ref": "AuditBucket"},
                        "PolicyDocument": {
                            "Version": "2012-10-17",
                            "Statement": [
                                {
                                    "Sid": "AWSCloudTrailAclCheck",
                                    "Effect": "Allow",
                                    "Principal": {
                                        "Service": "cloudtrail.amazonaws.com"
                                    },
                                    "Action": "s3:GetBucketAcl",
                                    "Resource": {
                                        "Fn::GetAtt": ["AuditBucket", "Arn"]
                                    }
                                },
                                {
                                    "Sid": "AWSCloudTrailWrite",
                                    "Effect": "Allow",
                                    "Principal": {
                                        "Service": "cloudtrail.amazonaws.com"
                                    },
                                    "Action": "s3:PutObject",
                                    "Resource": {
                                        "Fn::Sub": "${AuditBucket}/*"
                                    },
                                    "Condition": {
                                        "StringEquals": {
                                            "s3:x-amz-acl": "bucket-owner-full-control"
                                        }
                                    }
                                }
                            ]
                        }
                    }
                },
                "AuditLogGroup": {
                    "Type": "AWS::Logs::LogGroup",
                    "Properties": {
                        "LogGroupName": {
                            "Fn::Sub": "/aws/cloudtrail/${AWS::AccountId}"
                        },
                        "RetentionInDays": 365,
                        "Tags": [
                            {
                                "Key": "Purpose",
                                "Value": "AuditLogs"
                            },
                            {
                                "Key": "Environment",
                                "Value": {"Ref": "Environment"}
                            }
                        ]
                    }
                },
                "GuardDutyDetector": {
                    "Type": "AWS::GuardDuty::Detector",
                    "Properties": {
                        "Enable": True,
                        "FindingPublishingFrequency": "FIFTEEN_MINUTES",
                        "Tags": [
                            {
                                "Key": "Purpose",
                                "Value": "SecurityMonitoring"
                            },
                            {
                                "Key": "Environment",
                                "Value": {"Ref": "Environment"}
                            }
                        ]
                    }
                },
                "ConfigBucket": {
                    "Type": "AWS::S3::Bucket",
                    "Properties": {
                        "BucketName": {
                            "Fn::Sub": "org-config-logs-${AWS::AccountId}-${AWS::Region}-${OrganizationId}"
                        },
                        "PublicAccessBlockConfiguration": {
                            "BlockPublicAcls": True,
                            "BlockPublicPolicy": True,
                            "IgnorePublicAcls": True,
                            "RestrictPublicBuckets": True
                        },
                        "BucketEncryption": {
                            "ServerSideEncryptionConfiguration": [
                                {
                                    "ServerSideEncryptionByDefault": {
                                        "SSEAlgorithm": "AES256"
                                    }
                                }
                            ]
                        },
                        "Tags": [
                            {
                                "Key": "Purpose",
                                "Value": "ConfigLogs"
                            },
                            {
                                "Key": "Environment",
                                "Value": {"Ref": "Environment"}
                            }
                        ]
                    }
                },
                "ConfigRole": {
                    "Type": "AWS::IAM::Role",
                    "Properties": {
                        "AssumeRolePolicyDocument": {
                            "Version": "2012-10-17",
                            "Statement": [
                                {
                                    "Effect": "Allow",
                                    "Principal": {
                                        "Service": "config.amazonaws.com"
                                    },
                                    "Action": "sts:AssumeRole"
                                }
                            ]
                        },
                        "ManagedPolicyArns": [
                            "arn:aws:iam::aws:policy/service-role/ConfigRole"
                        ],
                        "Policies": [
                            {
                                "PolicyName": "ConfigS3Policy",
                                "PolicyDocument": {
                                    "Version": "2012-10-17",
                                    "Statement": [
                                        {
                                            "Effect": "Allow",
                                            "Action": [
                                                "s3:GetBucketAcl",
                                                "s3:GetBucketLocation",
                                                "s3:ListBucket"
                                            ],
                                            "Resource": {
                                                "Fn::GetAtt": ["ConfigBucket", "Arn"]
                                            }
                                        },
                                        {
                                            "Effect": "Allow",
                                            "Action": [
                                                "s3:PutObject",
                                                "s3:GetObject"
                                            ],
                                            "Resource": {
                                                "Fn::Sub": "${ConfigBucket}/*"
                                            },
                                            "Condition": {
                                                "StringEquals": {
                                                    "s3:x-amz-acl": "bucket-owner-full-control"
                                                }
                                            }
                                        }
                                    ]
                                }
                            }
                        ]
                    }
                },
                "ConfigurationRecorder": {
                    "Type": "AWS::Config::ConfigurationRecorder",
                    "Properties": {
                        "Name": {
                            "Fn::Sub": "organization-config-${AWS::AccountId}"
                        },
                        "RoleARN": {
                            "Fn::GetAtt": ["ConfigRole", "Arn"]
                        },
                        "RecordingGroup": {
                            "AllSupported": True,
                            "IncludeGlobalResourceTypes": True
                        }
                    }
                },
                "ConfigDeliveryChannel": {
                    "Type": "AWS::Config::DeliveryChannel",
                    "Properties": {
                        "Name": {
                            "Fn::Sub": "organization-config-delivery-${AWS::AccountId}"
                        },
                        "S3BucketName": {"Ref": "ConfigBucket"},
                        "S3KeyPrefix": {
                            "Fn::Sub": "config-logs/${AWS::AccountId}/"
                        },
                        "ConfigSnapshotDeliveryProperties": {
                            "DeliveryFrequency": "TwentyFour_Hours"
                        }
                    }
                }
            },
            "Outputs": {
                "CloudTrailArn": {
                    "Description": "CloudTrail ARN",
                    "Value": {
                        "Fn::GetAtt": ["OrganizationCloudTrail", "Arn"]
                    },
                    "Export": {
                        "Name": {
                            "Fn::Sub": "${AWS::StackName}-CloudTrailArn"
                        }
                    }
                },
                "AuditBucketName": {
                    "Description": "Audit bucket name",
                    "Value": {"Ref": "AuditBucket"},
                    "Export": {
                        "Name": {
                            "Fn::Sub": "${AWS::StackName}-AuditBucketName"
                        }
                    }
                },
                "GuardDutyDetectorId": {
                    "Description": "GuardDuty detector ID",
                    "Value": {"Ref": "GuardDutyDetector"},
                    "Export": {
                        "Name": {
                            "Fn::Sub": "${AWS::StackName}-GuardDutyDetectorId"
                        }
                    }
                },
                "ConfigRecorderName": {
                    "Description": "Config recorder name",
                    "Value": {"Ref": "ConfigurationRecorder"},
                    "Export": {
                        "Name": {
                            "Fn::Sub": "${AWS::StackName}-ConfigRecorderName"
                        }
                    }
                }
            }
        }

    def _create_stackset_alarms(self) -> None:
        """
        Create CloudWatch alarms for StackSet operation monitoring.
        """
        # Reference the SNS topic
        alert_topic = sns.Topic.from_topic_arn(
            self, "AlertTopic", self.alert_topic_arn
        )

        # Create alarm for StackSet operation failures
        cloudwatch.Alarm(
            self,
            "StackSetOperationFailureAlarm",
            alarm_name=f"StackSetOperationFailure-{self.governance_stackset.stack_set_name}",
            alarm_description="Alert when StackSet operations fail",
            metric=cloudwatch.Metric(
                namespace="AWS/CloudFormation",
                metric_name="StackSetOperationFailureCount",
                dimensions_map={"StackSetName": self.governance_stackset.stack_set_name},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
        ).add_alarm_action(
            cloudwatch_actions.SnsAction(alert_topic)
        )


class StackSetComplianceReportingStack(Stack):
    """
    Stack that creates compliance reporting tools for StackSets.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for compliance reports
        self.reports_bucket = s3.Bucket(
            self,
            "ComplianceReportsBucket",
            bucket_name=f"stackset-compliance-reports-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioning=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldReports",
                    expiration=Duration.days(365),
                    noncurrent_version_expiration=Duration.days(90),
                )
            ],
        )

        # Create IAM role for compliance reporting
        self.compliance_role = iam.Role(
            self,
            "ComplianceReportingRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add permissions for compliance reporting
        self.compliance_role.add_inline_policy(
            iam.Policy(
                self,
                "ComplianceReportingPolicy",
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        actions=[
                            "cloudformation:DescribeStackSet",
                            "cloudformation:ListStackSets",
                            "cloudformation:ListStackInstances",
                            "cloudformation:ListStackSetOperations",
                            "cloudformation:DescribeStackSetOperation",
                            "organizations:ListAccounts",
                            "organizations:DescribeOrganization",
                            "organizations:ListOrganizationalUnitsForParent",
                        ],
                        resources=["*"],
                    ),
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        actions=[
                            "s3:PutObject",
                            "s3:GetObject",
                            "s3:DeleteObject",
                        ],
                        resources=[f"{self.reports_bucket.bucket_arn}/*"],
                    ),
                ],
            )
        )

        # Create Lambda function for compliance reporting
        self.compliance_lambda = lambda_.Function(
            self,
            "ComplianceReportingFunction",
            function_name=f"stackset-compliance-reporting-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_compliance_reporting_code()),
            timeout=Duration.minutes(15),
            role=self.compliance_role,
            environment={
                "REPORTS_BUCKET": self.reports_bucket.bucket_name,
            },
        )

        # Create EventBridge rule for scheduled compliance reporting
        compliance_rule = events.Rule(
            self,
            "ComplianceReportingSchedule",
            rule_name="StackSetComplianceReportingSchedule",
            description="Scheduled compliance reporting for StackSets",
            schedule=events.Schedule.rate(Duration.days(1)),
        )

        # Add Lambda as target for the rule
        compliance_rule.add_target(
            targets.LambdaFunction(self.compliance_lambda)
        )

        # Output bucket name
        cdk.CfnOutput(
            self,
            "ComplianceReportsBucketName",
            value=self.reports_bucket.bucket_name,
            description="Name of the S3 bucket for compliance reports",
        )

    def _get_compliance_reporting_code(self) -> str:
        """
        Returns the inline code for the compliance reporting Lambda function.
        """
        return """
import boto3
import json
import os
from datetime import datetime, timezone
from typing import Dict, List, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Generate comprehensive compliance reports for all StackSets.
    \"\"\"
    try:
        cf_client = boto3.client('cloudformation')
        s3_client = boto3.client('s3')
        org_client = boto3.client('organizations')
        
        reports_bucket = os.environ['REPORTS_BUCKET']
        timestamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
        
        # Get organization information
        try:
            org_info = org_client.describe_organization()
            organization_id = org_info['Organization']['Id']
        except Exception:
            organization_id = 'unknown'
        
        # Get all StackSets
        stacksets = []
        paginator = cf_client.get_paginator('list_stack_sets')
        
        for page in paginator.paginate():
            stacksets.extend(page['Summaries'])
        
        compliance_report = {
            'timestamp': timestamp,
            'organization_id': organization_id,
            'total_stacksets': len(stacksets),
            'stacksets': []
        }
        
        for stackset in stacksets:
            stackset_name = stackset['StackSetName']
            
            # Get StackSet details
            stackset_detail = cf_client.describe_stack_set(StackSetName=stackset_name)
            
            # Get stack instances
            instances = []
            instances_paginator = cf_client.get_paginator('list_stack_instances')
            
            for page in instances_paginator.paginate(StackSetName=stackset_name):
                instances.extend(page['Summaries'])
            
            # Get operation history
            operations = []
            operations_paginator = cf_client.get_paginator('list_stack_set_operations')
            
            for page in operations_paginator.paginate(StackSetName=stackset_name):
                operations.extend(page['Summaries'][:10])  # Last 10 operations
            
            # Analyze instance status
            status_counts = {}
            drift_counts = {}
            
            for instance in instances:
                status = instance['Status']
                drift_status = instance.get('DriftStatus', 'UNKNOWN')
                
                status_counts[status] = status_counts.get(status, 0) + 1
                drift_counts[drift_status] = drift_counts.get(drift_status, 0) + 1
            
            stackset_report = {
                'name': stackset_name,
                'status': stackset_detail['StackSet']['Status'],
                'description': stackset_detail['StackSet'].get('Description', ''),
                'permission_model': stackset_detail['StackSet'].get('PermissionModel', 'UNKNOWN'),
                'total_instances': len(instances),
                'instance_status_counts': status_counts,
                'drift_status_counts': drift_counts,
                'recent_operations': [
                    {
                        'operation_id': op['OperationId'],
                        'action': op['Action'],
                        'status': op['Status'],
                        'creation_timestamp': op['CreationTimestamp'].isoformat()
                    }
                    for op in operations
                ],
                'instances': [
                    {
                        'account': instance['Account'],
                        'region': instance['Region'],
                        'status': instance['Status'],
                        'drift_status': instance.get('DriftStatus', 'UNKNOWN'),
                        'status_reason': instance.get('StatusReason', '')
                    }
                    for instance in instances
                ]
            }
            
            compliance_report['stacksets'].append(stackset_report)
        
        # Generate summary statistics
        total_instances = sum(len(ss['instances']) for ss in compliance_report['stacksets'])
        healthy_instances = sum(
            ss['instance_status_counts'].get('CURRENT', 0) 
            for ss in compliance_report['stacksets']
        )
        
        compliance_report['summary'] = {
            'total_instances': total_instances,
            'healthy_instances': healthy_instances,
            'healthy_percentage': (healthy_instances / total_instances * 100) if total_instances > 0 else 0
        }
        
        # Upload report to S3
        report_key = f'compliance-reports/{timestamp}/stackset-compliance-report.json'
        
        s3_client.put_object(
            Bucket=reports_bucket,
            Key=report_key,
            Body=json.dumps(compliance_report, indent=2),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Compliance report generated successfully',
                'report_location': f's3://{reports_bucket}/{report_key}',
                'summary': compliance_report['summary']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
"""


class StackSetApp(cdk.App):
    """
    Main CDK application for StackSets multi-account multi-region management.
    """

    def __init__(self):
        super().__init__()

        # Environment configuration
        env = Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )

        # Configuration parameters
        organization_id = self.node.try_get_context("organization_id") or "r-example"
        target_regions = self.node.try_get_context("target_regions") or [
            "us-east-1",
            "us-west-2",
            "eu-west-1",
        ]
        target_accounts = self.node.try_get_context("target_accounts") or []
        target_ous = self.node.try_get_context("target_ous") or []

        # Create StackSet administrator stack
        admin_stack = StackSetAdministratorStack(
            self,
            "StackSetAdministratorStack",
            organization_id=organization_id,
            env=env,
            description="StackSet administrator resources for multi-account management",
        )

        # Create governance StackSet stack
        governance_stack = GovernanceStackSetStack(
            self,
            "GovernanceStackSetStack",
            organization_id=organization_id,
            template_bucket_name=admin_stack.template_bucket.bucket_name,
            alert_topic_arn=admin_stack.alert_topic.topic_arn,
            target_regions=target_regions,
            target_accounts=target_accounts,
            target_ous=target_ous,
            env=env,
            description="StackSet for organization-wide governance policies",
        )

        # Create compliance reporting stack
        compliance_stack = StackSetComplianceReportingStack(
            self,
            "ComplianceReportingStack",
            env=env,
            description="Compliance reporting tools for StackSets",
        )

        # Add stack dependencies
        governance_stack.add_dependency(admin_stack)
        compliance_stack.add_dependency(governance_stack)

        # Add stack tags
        cdk.Tags.of(admin_stack).add("Purpose", "StackSetAdministration")
        cdk.Tags.of(governance_stack).add("Purpose", "OrganizationGovernance")
        cdk.Tags.of(compliance_stack).add("Purpose", "ComplianceReporting")
        cdk.Tags.of(self).add("Project", "StackSetsMultiAccountManagement")
        cdk.Tags.of(self).add("Environment", "production")


# Create and run the application
app = StackSetApp()
app.synth()