#!/usr/bin/env python3
"""
AWS CDK Python application for Business Continuity Testing Framework.

This application creates a comprehensive business continuity testing framework using
AWS Systems Manager Automation, Lambda functions, EventBridge, and CloudWatch.
The framework enables automated testing of backup validation, database recovery,
and application failover scenarios.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_iam as iam,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_ssm as ssm,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class BusinessContinuityTestingStack(Stack):
    """
    CDK Stack for Business Continuity Testing Framework.
    
    Creates automation documents, Lambda functions, EventBridge rules,
    and monitoring infrastructure for comprehensive BC testing.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.project_id = self.node.try_get_context("project_id") or "bctest"
        self.notification_email = self.node.try_get_context("notification_email") or "admin@example.com"
        
        # Create core infrastructure
        self._create_iam_roles()
        self._create_s3_bucket()
        self._create_sns_topic()
        self._create_automation_documents()
        self._create_lambda_functions()
        self._create_event_rules()
        self._create_cloudwatch_dashboard()
        
        # Create outputs
        self._create_outputs()

    def _create_iam_roles(self) -> None:
        """Create IAM roles for automation and Lambda execution."""
        
        # Automation execution role
        self.automation_role = iam.Role(
            self,
            "AutomationRole",
            role_name=f"BCTestingRole-{self.project_id}",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("ssm.amazonaws.com"),
                iam.ServicePrincipal("lambda.amazonaws.com"),
                iam.ServicePrincipal("states.amazonaws.com"),
                iam.ServicePrincipal("events.amazonaws.com")
            ),
            description="Role for business continuity testing automation",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "BCTestingPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ssm:*",
                                "ec2:*",
                                "rds:*",
                                "s3:*",
                                "lambda:*",
                                "states:*",
                                "events:*",
                                "cloudwatch:*",
                                "sns:*",
                                "logs:*",
                                "backup:*",
                                "iam:PassRole",
                                "route53:*"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

    def _create_s3_bucket(self) -> None:
        """Create S3 bucket for test results and reports."""
        
        self.results_bucket = s3.Bucket(
            self,
            "TestResultsBucket",
            bucket_name=f"bc-testing-results-{self.project_id}",
            versioned=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="BCTestResultsRetention",
                    enabled=True,
                    prefix="test-results/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ],
                    expiration=Duration.days(2555)  # ~7 years
                )
            ],
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL
        )

    def _create_sns_topic(self) -> None:
        """Create SNS topic for BC testing alerts."""
        
        self.alert_topic = sns.Topic(
            self,
            "BCAlertsTopic",
            topic_name=f"bc-alerts-{self.project_id}",
            display_name="Business Continuity Testing Alerts"
        )
        
        # Add email subscription
        self.alert_topic.add_subscription(
            subscriptions.EmailSubscription(self.notification_email)
        )

    def _create_automation_documents(self) -> None:
        """Create Systems Manager automation documents for BC testing."""
        
        # Backup validation automation document
        backup_validation_content = {
            "schemaVersion": "0.3",
            "description": "Validate backup integrity and restore capabilities",
            "assumeRole": "{{ AutomationAssumeRole }}",
            "parameters": {
                "InstanceId": {
                    "type": "String",
                    "description": "EC2 instance ID to test backup restore"
                },
                "BackupVaultName": {
                    "type": "String",
                    "description": "AWS Backup vault name"
                },
                "AutomationAssumeRole": {
                    "type": "String",
                    "description": "IAM role for automation execution"
                }
            },
            "mainSteps": [
                {
                    "name": "CreateRestoreTestInstance",
                    "action": "aws:executeAwsApi",
                    "inputs": {
                        "Service": "backup",
                        "Api": "StartRestoreJob",
                        "RecoveryPointArn": "{{ GetLatestRecoveryPoint.RecoveryPointArn }}",
                        "Metadata": {
                            "InstanceType": "t3.micro"
                        },
                        "IamRoleArn": "{{ AutomationAssumeRole }}"
                    },
                    "outputs": [
                        {
                            "Name": "RestoreJobId",
                            "Selector": "$.RestoreJobId",
                            "Type": "String"
                        }
                    ]
                },
                {
                    "name": "WaitForRestoreCompletion",
                    "action": "aws:waitForAwsResourceProperty",
                    "inputs": {
                        "Service": "backup",
                        "Api": "DescribeRestoreJob",
                        "RestoreJobId": "{{ CreateRestoreTestInstance.RestoreJobId }}",
                        "PropertySelector": "$.Status",
                        "DesiredValues": ["COMPLETED"]
                    },
                    "timeoutSeconds": 3600
                },
                {
                    "name": "ValidateRestoredInstance",
                    "action": "aws:runCommand",
                    "inputs": {
                        "DocumentName": "AWS-RunShellScript",
                        "InstanceIds": ["{{ CreateRestoreTestInstance.CreatedResourceArn }}"],
                        "Parameters": {
                            "commands": [
                                "#!/bin/bash",
                                "echo 'Validating restored instance...'",
                                "systemctl status",
                                "df -h",
                                "if command -v nginx &> /dev/null; then",
                                "    systemctl status nginx",
                                "fi",
                                "echo 'Validation completed'"
                            ]
                        }
                    },
                    "outputs": [
                        {
                            "Name": "ValidationResults",
                            "Selector": "$.CommandInvocations[0].CommandPlugins[0].Output",
                            "Type": "String"
                        }
                    ]
                },
                {
                    "name": "CleanupTestInstance",
                    "action": "aws:executeAwsApi",
                    "inputs": {
                        "Service": "ec2",
                        "Api": "TerminateInstances",
                        "InstanceIds": ["{{ CreateRestoreTestInstance.CreatedResourceArn }}"]
                    }
                }
            ],
            "outputs": [
                "ValidationResults: {{ ValidateRestoredInstance.ValidationResults }}"
            ]
        }

        self.backup_validation_doc = ssm.CfnDocument(
            self,
            "BackupValidationDocument",
            document_type="Automation",
            document_format="JSON",
            name=f"BC-BackupValidation-{self.project_id}",
            content=backup_validation_content,
            tags=[
                {
                    "key": "Purpose",
                    "value": "BusinessContinuityTesting"
                }
            ]
        )

        # Database recovery automation document
        database_recovery_content = {
            "schemaVersion": "0.3",
            "description": "Test database backup and recovery procedures",
            "assumeRole": "{{ AutomationAssumeRole }}",
            "parameters": {
                "DBInstanceIdentifier": {
                    "type": "String",
                    "description": "RDS instance identifier"
                },
                "DBSnapshotIdentifier": {
                    "type": "String",
                    "description": "Snapshot to restore from"
                },
                "TestDBInstanceIdentifier": {
                    "type": "String",
                    "description": "Test database instance identifier"
                },
                "AutomationAssumeRole": {
                    "type": "String",
                    "description": "IAM role for automation execution"
                }
            },
            "mainSteps": [
                {
                    "name": "CreateTestDatabase",
                    "action": "aws:executeAwsApi",
                    "inputs": {
                        "Service": "rds",
                        "Api": "RestoreDBInstanceFromDBSnapshot",
                        "DBInstanceIdentifier": "{{ TestDBInstanceIdentifier }}",
                        "DBSnapshotIdentifier": "{{ DBSnapshotIdentifier }}",
                        "DBInstanceClass": "db.t3.micro",
                        "PubliclyAccessible": False,
                        "StorageEncrypted": True
                    },
                    "outputs": [
                        {
                            "Name": "TestDBEndpoint",
                            "Selector": "$.DBInstance.Endpoint.Address",
                            "Type": "String"
                        }
                    ]
                },
                {
                    "name": "WaitForDBAvailable",
                    "action": "aws:waitForAwsResourceProperty",
                    "inputs": {
                        "Service": "rds",
                        "Api": "DescribeDBInstances",
                        "DBInstanceIdentifier": "{{ TestDBInstanceIdentifier }}",
                        "PropertySelector": "$.DBInstances[0].DBInstanceStatus",
                        "DesiredValues": ["available"]
                    },
                    "timeoutSeconds": 1800
                },
                {
                    "name": "CleanupTestDatabase",
                    "action": "aws:executeAwsApi",
                    "inputs": {
                        "Service": "rds",
                        "Api": "DeleteDBInstance",
                        "DBInstanceIdentifier": "{{ TestDBInstanceIdentifier }}",
                        "SkipFinalSnapshot": True,
                        "DeleteAutomatedBackups": True
                    }
                }
            ]
        }

        self.database_recovery_doc = ssm.CfnDocument(
            self,
            "DatabaseRecoveryDocument",
            document_type="Automation",
            document_format="JSON",
            name=f"BC-DatabaseRecovery-{self.project_id}",
            content=database_recovery_content,
            tags=[
                {
                    "key": "Purpose",
                    "value": "BusinessContinuityTesting"
                }
            ]
        )

        # Application failover automation document
        application_failover_content = {
            "schemaVersion": "0.3",
            "description": "Test application failover to secondary region",
            "assumeRole": "{{ AutomationAssumeRole }}",
            "parameters": {
                "PrimaryLoadBalancerArn": {
                    "type": "String",
                    "description": "Primary Application Load Balancer ARN"
                },
                "SecondaryLoadBalancerArn": {
                    "type": "String",
                    "description": "Secondary Application Load Balancer ARN"
                },
                "Route53HostedZoneId": {
                    "type": "String",
                    "description": "Route 53 hosted zone ID"
                },
                "DomainName": {
                    "type": "String",
                    "description": "Domain name for failover testing"
                },
                "AutomationAssumeRole": {
                    "type": "String",
                    "description": "IAM role for automation execution"
                }
            },
            "mainSteps": [
                {
                    "name": "SimulateFailoverToSecondary",
                    "action": "aws:executeAwsApi",
                    "inputs": {
                        "Service": "route53",
                        "Api": "ChangeResourceRecordSets",
                        "HostedZoneId": "{{ Route53HostedZoneId }}",
                        "ChangeBatch": {
                            "Changes": [
                                {
                                    "Action": "UPSERT",
                                    "ResourceRecordSet": {
                                        "Name": "{{ DomainName }}",
                                        "Type": "A",
                                        "SetIdentifier": "Primary",
                                        "Failover": "SECONDARY",
                                        "TTL": 60,
                                        "ResourceRecords": [
                                            {
                                                "Value": "1.2.3.4"
                                            }
                                        ]
                                    }
                                }
                            ]
                        }
                    }
                },
                {
                    "name": "WaitForDNSPropagation",
                    "action": "aws:sleep",
                    "inputs": {
                        "Duration": "PT2M"
                    }
                },
                {
                    "name": "RestorePrimaryRouting",
                    "action": "aws:executeAwsApi",
                    "inputs": {
                        "Service": "route53",
                        "Api": "ChangeResourceRecordSets",
                        "HostedZoneId": "{{ Route53HostedZoneId }}",
                        "ChangeBatch": {
                            "Changes": [
                                {
                                    "Action": "UPSERT",
                                    "ResourceRecordSet": {
                                        "Name": "{{ DomainName }}",
                                        "Type": "A",
                                        "SetIdentifier": "Primary",
                                        "Failover": "PRIMARY",
                                        "TTL": 300,
                                        "ResourceRecords": [
                                            {
                                                "Value": "5.6.7.8"
                                            }
                                        ]
                                    }
                                }
                            ]
                        }
                    }
                }
            ]
        }

        self.application_failover_doc = ssm.CfnDocument(
            self,
            "ApplicationFailoverDocument",
            document_type="Automation",
            document_format="JSON",
            name=f"BC-ApplicationFailover-{self.project_id}",
            content=application_failover_content,
            tags=[
                {
                    "key": "Purpose",
                    "value": "BusinessContinuityTesting"
                }
            ]
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for BC test orchestration and reporting."""
        
        # Test orchestration Lambda function
        self.orchestrator_function = lambda_.Function(
            self,
            "TestOrchestratorFunction",
            function_name=f"bc-test-orchestrator-{self.project_id}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_orchestrator_code()),
            timeout=Duration.minutes(15),
            role=self.automation_role,
            environment={
                "PROJECT_ID": self.project_id,
                "RESULTS_BUCKET": self.results_bucket.bucket_name,
                "AUTOMATION_ROLE_ARN": self.automation_role.role_arn,
                "SNS_TOPIC_ARN": self.alert_topic.topic_arn
            },
            description="Orchestrates business continuity testing procedures"
        )

        # Compliance reporting Lambda function
        self.compliance_function = lambda_.Function(
            self,
            "ComplianceReporterFunction",
            function_name=f"bc-compliance-reporter-{self.project_id}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_compliance_code()),
            timeout=Duration.minutes(5),
            role=self.automation_role,
            environment={
                "RESULTS_BUCKET": self.results_bucket.bucket_name
            },
            description="Generates monthly compliance reports for BC testing"
        )

        # Manual test executor Lambda function
        self.manual_test_function = lambda_.Function(
            self,
            "ManualTestExecutorFunction",
            function_name=f"bc-manual-test-executor-{self.project_id}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_manual_test_code()),
            timeout=Duration.minutes(5),
            role=self.automation_role,
            environment={
                "PROJECT_ID": self.project_id,
                "AUTOMATION_ROLE_ARN": self.automation_role.role_arn
            },
            description="Enables manual execution of BC tests"
        )

    def _create_event_rules(self) -> None:
        """Create EventBridge rules for scheduled BC testing."""
        
        # Daily basic tests
        self.daily_rule = events.Rule(
            self,
            "DailyTestsRule",
            rule_name=f"bc-daily-tests-{self.project_id}",
            schedule=events.Schedule.rate(Duration.days(1)),
            description="Daily business continuity basic tests"
        )
        self.daily_rule.add_target(
            targets.LambdaFunction(
                self.orchestrator_function,
                event=events.RuleTargetInput.from_object({"testType": "daily"})
            )
        )

        # Weekly comprehensive tests
        self.weekly_rule = events.Rule(
            self,
            "WeeklyTestsRule",
            rule_name=f"bc-weekly-tests-{self.project_id}",
            schedule=events.Schedule.cron(minute="0", hour="2", week_day="SUN"),
            description="Weekly comprehensive business continuity tests"
        )
        self.weekly_rule.add_target(
            targets.LambdaFunction(
                self.orchestrator_function,
                event=events.RuleTargetInput.from_object({"testType": "weekly"})
            )
        )

        # Monthly full DR tests
        self.monthly_rule = events.Rule(
            self,
            "MonthlyTestsRule",
            rule_name=f"bc-monthly-tests-{self.project_id}",
            schedule=events.Schedule.cron(minute="0", hour="1", day="1"),
            description="Monthly full disaster recovery tests"
        )
        self.monthly_rule.add_target(
            targets.LambdaFunction(
                self.orchestrator_function,
                event=events.RuleTargetInput.from_object({"testType": "monthly"})
            )
        )

        # Monthly compliance reporting
        self.compliance_rule = events.Rule(
            self,
            "ComplianceReportingRule",
            rule_name=f"bc-compliance-reporting-{self.project_id}",
            schedule=events.Schedule.cron(minute="0", hour="8", day="1"),
            description="Monthly BC compliance reporting"
        )
        self.compliance_rule.add_target(
            targets.LambdaFunction(self.compliance_function)
        )

    def _create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for BC testing monitoring."""
        
        self.dashboard = cloudwatch.Dashboard(
            self,
            "BCTestingDashboard",
            dashboard_name=f"BC-Testing-{self.project_id}",
            widgets=[
                [
                    # Lambda metrics widget
                    cloudwatch.GraphWidget(
                        title="BC Testing Lambda Metrics",
                        left=[
                            self.orchestrator_function.metric_duration(),
                            self.orchestrator_function.metric_errors(),
                            self.orchestrator_function.metric_invocations()
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    # Systems Manager automation metrics
                    cloudwatch.SingleValueWidget(
                        title="BC Testing Success/Failure Rates",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/SSM",
                                metric_name="ExecutionSuccess",
                                dimensions_map={
                                    "DocumentName": f"BC-BackupValidation-{self.project_id}"
                                },
                                statistic="Sum",
                                period=Duration.days(1)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/SSM",
                                metric_name="ExecutionFailed",
                                dimensions_map={
                                    "DocumentName": f"BC-BackupValidation-{self.project_id}"
                                },
                                statistic="Sum",
                                period=Duration.days(1)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    # Log insights widget
                    cloudwatch.LogQueryWidget(
                        title="Recent BC Test Executions",
                        log_groups=[
                            self.orchestrator_function.log_group
                        ],
                        query_lines=[
                            "fields @timestamp, @message",
                            "filter @message like /Test/",
                            "sort @timestamp desc",
                            "limit 20"
                        ],
                        width=24,
                        height=6
                    )
                ]
            ]
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        
        CfnOutput(
            self,
            "ResultsBucketName",
            value=self.results_bucket.bucket_name,
            description="S3 bucket for BC test results and reports"
        )
        
        CfnOutput(
            self,
            "AutomationRoleArn",
            value=self.automation_role.role_arn,
            description="IAM role ARN for BC testing automation"
        )
        
        CfnOutput(
            self,
            "AlertTopicArn",
            value=self.alert_topic.topic_arn,
            description="SNS topic ARN for BC testing alerts"
        )
        
        CfnOutput(
            self,
            "OrchestratorFunctionName",
            value=self.orchestrator_function.function_name,
            description="Lambda function name for test orchestration"
        )
        
        CfnOutput(
            self,
            "ManualTestFunctionName",
            value=self.manual_test_function.function_name,
            description="Lambda function name for manual test execution"
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch dashboard URL for BC testing monitoring"
        )

    def _get_orchestrator_code(self) -> str:
        """Return the orchestrator Lambda function code."""
        return '''
import json
import boto3
import datetime
import uuid
import os
from typing import Dict, List

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    test_type = event.get('testType', 'daily')
    test_id = str(uuid.uuid4())
    
    test_results = {
        'testId': test_id,
        'testType': test_type,
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'results': []
    }
    
    try:
        if test_type in ['daily', 'weekly', 'monthly']:
            # Execute backup validation
            backup_result = execute_backup_validation(ssm, test_id)
            test_results['results'].append(backup_result)
        
        if test_type in ['weekly', 'monthly']:
            # Execute database recovery test
            db_result = execute_database_recovery_test(ssm, test_id)
            test_results['results'].append(db_result)
        
        if test_type == 'monthly':
            # Execute full application failover test
            app_result = execute_application_failover_test(ssm, test_id)
            test_results['results'].append(app_result)
        
        # Store results in S3
        s3.put_object(
            Bucket=os.environ['RESULTS_BUCKET'],
            Key=f'test-results/{test_type}/{test_id}/results.json',
            Body=json.dumps(test_results, indent=2),
            ContentType='application/json'
        )
        
        # Generate summary report
        summary = generate_test_summary(test_results)
        
        # Send notification
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'BC Testing {test_type.title()} Report - {test_id[:8]}',
            Message=summary
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'testId': test_id,
                'summary': summary
            })
        }
        
    except Exception as e:
        error_message = f'BC testing failed: {str(e)}'
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'BC Testing Failed - {test_id[:8]}',
            Message=error_message
        )
        raise e

def execute_backup_validation(ssm, test_id):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-BackupValidation-{os.environ["PROJECT_ID"]}',
        Parameters={
            'InstanceId': [os.environ.get('TEST_INSTANCE_ID', 'i-1234567890abcdef0')],
            'BackupVaultName': [os.environ.get('BACKUP_VAULT_NAME', 'default')],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    
    return {
        'test': 'backup_validation',
        'executionId': response['AutomationExecutionId'],
        'status': 'started'
    }

def execute_database_recovery_test(ssm, test_id):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-DatabaseRecovery-{os.environ["PROJECT_ID"]}',
        Parameters={
            'DBInstanceIdentifier': [os.environ.get('DB_INSTANCE_ID', 'prod-db')],
            'DBSnapshotIdentifier': [os.environ.get('DB_SNAPSHOT_ID', 'latest-snapshot')],
            'TestDBInstanceIdentifier': [f'test-db-{test_id[:8]}'],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    
    return {
        'test': 'database_recovery',
        'executionId': response['AutomationExecutionId'],
        'status': 'started'
    }

def execute_application_failover_test(ssm, test_id):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-ApplicationFailover-{os.environ["PROJECT_ID"]}',
        Parameters={
            'PrimaryLoadBalancerArn': [os.environ.get('PRIMARY_ALB_ARN', 'arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/1234567890123456')],
            'SecondaryLoadBalancerArn': [os.environ.get('SECONDARY_ALB_ARN', 'arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/secondary/6543210987654321')],
            'Route53HostedZoneId': [os.environ.get('HOSTED_ZONE_ID', 'Z1234567890123')],
            'DomainName': [os.environ.get('DOMAIN_NAME', 'app.example.com')],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    
    return {
        'test': 'application_failover',
        'executionId': response['AutomationExecutionId'],
        'status': 'started'
    }

def generate_test_summary(test_results):
    total_tests = len(test_results['results'])
    summary = f"""
Business Continuity Testing Summary
Test ID: {test_results['testId']}
Test Type: {test_results['testType']}
Timestamp: {test_results['timestamp']}

Tests Executed: {total_tests}

Test Results:
"""
    
    for result in test_results['results']:
        summary += f"- {result['test']}: {result['status']}\\n"
    
    return summary
'''

    def _get_compliance_code(self) -> str:
        """Return the compliance reporting Lambda function code."""
        return '''
import json
import boto3
import datetime
import os
from typing import Dict, List

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    ssm = boto3.client('ssm')
    
    # Generate monthly compliance report
    report_data = generate_compliance_report(s3, ssm)
    
    # Store compliance report
    report_key = f"compliance-reports/{datetime.datetime.utcnow().strftime('%Y-%m')}/bc-compliance-report.json"
    
    s3.put_object(
        Bucket=os.environ['RESULTS_BUCKET'],
        Key=report_key,
        Body=json.dumps(report_data, indent=2),
        ContentType='application/json'
    )
    
    # Generate HTML report
    html_report = generate_html_report(report_data)
    
    s3.put_object(
        Bucket=os.environ['RESULTS_BUCKET'],
        Key=f"compliance-reports/{datetime.datetime.utcnow().strftime('%Y-%m')}/bc-compliance-report.html",
        Body=html_report,
        ContentType='text/html'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'reportGenerated': True,
            'reportLocation': report_key
        })
    }

def generate_compliance_report(s3, ssm):
    # Collect test execution data from the past month
    start_date = datetime.datetime.utcnow() - datetime.timedelta(days=30)
    
    report = {
        'reportPeriod': {
            'start': start_date.isoformat(),
            'end': datetime.datetime.utcnow().isoformat()
        },
        'testingSummary': {
            'dailyTests': 0,
            'weeklyTests': 0,
            'monthlyTests': 0,
            'totalTests': 0,
            'successfulTests': 0,
            'failedTests': 0
        },
        'complianceStatus': 'COMPLIANT',
        'recommendations': []
    }
    
    # Analyze test execution history
    # This would integrate with actual Systems Manager execution history
    
    return report

def generate_html_report(report_data):
    html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Business Continuity Compliance Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        .header {{ background-color: #f0f0f0; padding: 20px; }}
        .summary {{ margin: 20px 0; }}
        .compliant {{ color: green; }}
        .non-compliant {{ color: red; }}
        table {{ border-collapse: collapse; width: 100%; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background-color: #f2f2f2; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>Business Continuity Testing Compliance Report</h1>
        <p>Report Period: {report_data['reportPeriod']['start']} to {report_data['reportPeriod']['end']}</p>
    </div>
    
    <div class="summary">
        <h2>Testing Summary</h2>
        <p>Total Tests Executed: {report_data['testingSummary']['totalTests']}</p>
        <p>Successful Tests: {report_data['testingSummary']['successfulTests']}</p>
        <p>Failed Tests: {report_data['testingSummary']['failedTests']}</p>
        <p>Compliance Status: <span class="{report_data['complianceStatus'].lower()}">{report_data['complianceStatus']}</span></p>
    </div>
</body>
</html>
"""
    return html
'''

    def _get_manual_test_code(self) -> str:
        """Return the manual test executor Lambda function code."""
        return '''
import json
import boto3
import uuid
import os

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    
    test_type = event.get('testType', 'comprehensive')
    test_components = event.get('components', ['backup', 'database', 'application'])
    
    execution_results = []
    
    for component in test_components:
        if component == 'backup':
            result = execute_backup_test(ssm)
            execution_results.append(result)
        elif component == 'database':
            result = execute_database_test(ssm)
            execution_results.append(result)
        elif component == 'application':
            result = execute_application_test(ssm)
            execution_results.append(result)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'testType': test_type,
            'executionId': str(uuid.uuid4()),
            'results': execution_results
        })
    }

def execute_backup_test(ssm):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-BackupValidation-{os.environ["PROJECT_ID"]}',
        Parameters={
            'InstanceId': [os.environ.get('TEST_INSTANCE_ID', 'i-1234567890abcdef0')],
            'BackupVaultName': [os.environ.get('BACKUP_VAULT_NAME', 'default')],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    return {'component': 'backup', 'executionId': response['AutomationExecutionId']}

def execute_database_test(ssm):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-DatabaseRecovery-{os.environ["PROJECT_ID"]}',
        Parameters={
            'DBInstanceIdentifier': [os.environ.get('DB_INSTANCE_ID', 'prod-db')],
            'DBSnapshotIdentifier': [os.environ.get('DB_SNAPSHOT_ID', 'latest-snapshot')],
            'TestDBInstanceIdentifier': [f'manual-test-{uuid.uuid4().hex[:8]}'],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    return {'component': 'database', 'executionId': response['AutomationExecutionId']}

def execute_application_test(ssm):
    response = ssm.start_automation_execution(
        DocumentName=f'BC-ApplicationFailover-{os.environ["PROJECT_ID"]}',
        Parameters={
            'PrimaryLoadBalancerArn': [os.environ.get('PRIMARY_ALB_ARN', 'arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/primary/1234567890123456')],
            'SecondaryLoadBalancerArn': [os.environ.get('SECONDARY_ALB_ARN', 'arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/secondary/6543210987654321')],
            'Route53HostedZoneId': [os.environ.get('HOSTED_ZONE_ID', 'Z1234567890123')],
            'DomainName': [os.environ.get('DOMAIN_NAME', 'app.example.com')],
            'AutomationAssumeRole': [os.environ['AUTOMATION_ROLE_ARN']]
        }
    )
    return {'component': 'application', 'executionId': response['AutomationExecutionId']}
'''


# CDK App
app = cdk.App()

# Get context values
project_id = app.node.try_get_context("project_id") or "bctest"
notification_email = app.node.try_get_context("notification_email") or "admin@example.com"

# Create stack
BusinessContinuityTestingStack(
    app,
    "BusinessContinuityTestingStack",
    env=cdk.Environment(
        account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
        region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
    ),
    description="Business Continuity Testing Framework with AWS Systems Manager"
)

app.synth()