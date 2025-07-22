#!/usr/bin/env python3
"""
AWS CDK Python application for implementing RDS Disaster Recovery Solutions.

This application creates a comprehensive disaster recovery solution including:
- Cross-region RDS read replica
- CloudWatch monitoring and alarms
- SNS notifications
- Lambda-based automation
- CloudWatch dashboard

Author: AWS Recipe Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_rds as rds,
    aws_sns as sns,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_sns_subscriptions as subscriptions,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from constructs import Construct


class RdsDisasterRecoveryStack(Stack):
    """
    CDK Stack for RDS Disaster Recovery implementation.
    
    This stack creates all the necessary infrastructure for implementing
    a comprehensive disaster recovery solution for Amazon RDS databases.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        source_db_identifier: str,
        primary_region: str,
        secondary_region: str,
        notification_email: str = None,
        **kwargs
    ) -> None:
        """
        Initialize the RDS Disaster Recovery stack.
        
        Args:
            scope: The parent construct
            construct_id: The construct identifier
            source_db_identifier: The identifier of the source RDS database
            primary_region: The primary AWS region
            secondary_region: The secondary AWS region for DR
            notification_email: Optional email address for notifications
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.source_db_identifier = source_db_identifier
        self.primary_region = primary_region
        self.secondary_region = secondary_region
        self.notification_email = notification_email

        # Create SNS topics for notifications
        self.primary_topic = self._create_sns_topic("primary")
        self.secondary_topic = self._create_sns_topic("secondary")

        # Create Lambda function for DR automation
        self.dr_lambda = self._create_dr_lambda_function()

        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()

        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()

        # Create outputs
        self._create_outputs()

    def _create_sns_topic(self, region_type: str) -> sns.Topic:
        """
        Create SNS topic for notifications.
        
        Args:
            region_type: Either 'primary' or 'secondary'
            
        Returns:
            The created SNS topic
        """
        topic = sns.Topic(
            self,
            f"RdsDrTopic{region_type.capitalize()}",
            topic_name=f"rds-dr-notifications-{region_type}",
            display_name=f"RDS Disaster Recovery Notifications ({region_type.capitalize()} Region)",
        )

        # Add email subscription if provided
        if self.notification_email:
            topic.add_subscription(
                subscriptions.EmailSubscription(self.notification_email)
            )

        return topic

    def _create_dr_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for disaster recovery automation.
        
        Returns:
            The created Lambda function
        """
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "RdsDrLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "RdsDrPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "rds:DescribeDBInstances",
                                "rds:PromoteReadReplica",
                                "rds:ModifyDBInstance",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[
                                self.primary_topic.topic_arn,
                                self.secondary_topic.topic_arn,
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=["*"],
                        ),
                    ]
                )
            },
        )

        # Lambda function code
        lambda_code = '''
import json
import boto3
import datetime
import os
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Disaster Recovery Manager for RDS.
    Handles automated failover and notification logic.
    
    Args:
        event: CloudWatch alarm event
        context: Lambda context
        
    Returns:
        Response dictionary
    """
    
    rds = boto3.client('rds')
    sns = boto3.client('sns')
    
    try:
        # Parse the CloudWatch alarm event
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        new_state = message['NewStateValue']
        reason = message['NewStateReason']
        
        # Determine the action based on alarm type
        if 'HighCPU' in alarm_name and new_state == 'ALARM':
            return handle_high_cpu_alert(alarm_name, reason, sns)
        elif 'ReplicaLag' in alarm_name and new_state == 'ALARM':
            return handle_replica_lag_alert(alarm_name, reason, sns)
        elif 'DatabaseConnections' in alarm_name and new_state == 'ALARM':
            return handle_connection_failure(alarm_name, reason, sns, rds)
        
        return {
            'statusCode': 200,
            'body': json.dumps('No action required')
        }
        
    except Exception as e:
        error_message = f"Error processing alarm: {str(e)}"
        print(error_message)
        
        # Send error notification
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='ERROR: RDS DR Lambda Function',
            Message=error_message
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {error_message}')
        }

def handle_high_cpu_alert(alarm_name: str, reason: str, sns) -> Dict[str, Any]:
    """Handle high CPU utilization alerts."""
    message = f"""HIGH CPU ALERT: {alarm_name}
Reason: {reason}
Recommendation: Monitor performance and consider scaling.
Time: {datetime.datetime.utcnow().isoformat()}Z"""
    
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Subject='RDS Performance Alert',
        Message=message
    )
    
    return {'statusCode': 200, 'body': 'High CPU alert processed'}

def handle_replica_lag_alert(alarm_name: str, reason: str, sns) -> Dict[str, Any]:
    """Handle replica lag alerts."""
    message = f"""REPLICA LAG ALERT: {alarm_name}
Reason: {reason}
Recommendation: Check network connectivity and primary database load.
Time: {datetime.datetime.utcnow().isoformat()}Z"""
    
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Subject='RDS Replica Lag Alert',
        Message=message
    )
    
    return {'statusCode': 200, 'body': 'Replica lag alert processed'}

def handle_connection_failure(alarm_name: str, reason: str, sns, rds) -> Dict[str, Any]:
    """Handle database connection failures - potential failover scenario."""
    
    # Extract database identifier from alarm name
    db_identifier = alarm_name.split('-')[0]
    
    # Check database status
    try:
        response = rds.describe_db_instances(DBInstanceIdentifier=db_identifier)
        db_status = response['DBInstances'][0]['DBInstanceStatus']
        
        if db_status not in ['available']:
            message = f"""CRITICAL DATABASE ALERT: {alarm_name}
Database Status: {db_status}
Reason: {reason}
Time: {datetime.datetime.utcnow().isoformat()}Z

This may require manual intervention or failover to DR region.
Please investigate immediately and consider promoting read replica if necessary."""
            
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='CRITICAL: RDS Database Alert - Action Required',
                Message=message
            )
        else:
            message = f"""DATABASE CONNECTION ALERT: {alarm_name}
Database Status: {db_status} (Available)
Reason: {reason}
Time: {datetime.datetime.utcnow().isoformat()}Z

Database appears healthy but connections are low. Monitor application connectivity."""
            
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='WARNING: RDS Connection Alert',
                Message=message
            )
            
    except Exception as e:
        error_message = f"""ERROR: Could not check database status for {db_identifier}
Error: {str(e)}
Time: {datetime.datetime.utcnow().isoformat()}Z

Immediate manual investigation required."""
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='CRITICAL: RDS Monitoring Error',
            Message=error_message
        )
    
    return {'statusCode': 200, 'body': 'Connection failure alert processed'}
'''

        # Create Lambda function
        dr_function = lambda_.Function(
            self,
            "RdsDrManagerFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "SNS_TOPIC_ARN": self.primary_topic.topic_arn,
                "SOURCE_DB_IDENTIFIER": self.source_db_identifier,
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
        )

        # Subscribe Lambda to SNS topic
        self.primary_topic.add_subscription(
            subscriptions.LambdaSubscription(dr_function)
        )

        return dr_function

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for database monitoring."""
        
        # High CPU alarm for primary database
        cloudwatch.Alarm(
            self,
            "PrimaryDbHighCpuAlarm",
            alarm_name=f"{self.source_db_identifier}-HighCPU",
            alarm_description=f"High CPU utilization on primary database {self.source_db_identifier}",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="CPUUtilization",
                dimensions_map={"DBInstanceIdentifier": self.source_db_identifier},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80,
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        ).add_alarm_action(
            cloudwatch.SnsAction(self.primary_topic)
        )

        # Database connections alarm for primary database
        cloudwatch.Alarm(
            self,
            "PrimaryDbConnectionsAlarm",
            alarm_name=f"{self.source_db_identifier}-DatabaseConnections",
            alarm_description=f"Low database connections on primary database {self.source_db_identifier}",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="DatabaseConnections",
                dimensions_map={"DBInstanceIdentifier": self.source_db_identifier},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=0,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        ).add_alarm_action(
            cloudwatch.SnsAction(self.primary_topic)
        )

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for disaster recovery monitoring.
        
        Returns:
            The created CloudWatch dashboard
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "RdsDrDashboard",
            dashboard_name=f"rds-dr-dashboard-{self.source_db_identifier}",
        )

        # CPU Utilization widget
        cpu_widget = cloudwatch.GraphWidget(
            title="Database CPU Utilization",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="CPUUtilization",
                    dimensions_map={"DBInstanceIdentifier": self.source_db_identifier},
                    label="Primary Database",
                    statistic="Average",
                    period=Duration.minutes(5),
                )
            ],
            width=12,
            height=6,
        )

        # Database Connections widget
        connections_widget = cloudwatch.GraphWidget(
            title="Database Connections",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="DatabaseConnections",
                    dimensions_map={"DBInstanceIdentifier": self.source_db_identifier},
                    label="Primary Database",
                    statistic="Average",
                    period=Duration.minutes(5),
                )
            ],
            width=12,
            height=6,
        )

        # Read/Write Latency widget
        latency_widget = cloudwatch.GraphWidget(
            title="Database Latency",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="ReadLatency",
                    dimensions_map={"DBInstanceIdentifier": self.source_db_identifier},
                    label="Read Latency",
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="WriteLatency",
                    dimensions_map={"DBInstanceIdentifier": self.source_db_identifier},
                    label="Write Latency",
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
            ],
            width=24,
            height=6,
        )

        # Add widgets to dashboard
        dashboard.add_widgets(cpu_widget, connections_widget)
        dashboard.add_widgets(latency_widget)

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        
        CfnOutput(
            self,
            "PrimarySnsTopicArn",
            value=self.primary_topic.topic_arn,
            description="ARN of the primary SNS topic for notifications",
            export_name=f"{self.stack_name}-PrimarySnsTopicArn",
        )

        CfnOutput(
            self,
            "SecondarySnsTopicArn",
            value=self.secondary_topic.topic_arn,
            description="ARN of the secondary SNS topic for notifications",
            export_name=f"{self.stack_name}-SecondarySnsTopicArn",
        )

        CfnOutput(
            self,
            "DrLambdaFunctionArn",
            value=self.dr_lambda.function_arn,
            description="ARN of the disaster recovery Lambda function",
            export_name=f"{self.stack_name}-DrLambdaFunctionArn",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=rds-dr-dashboard-{self.source_db_identifier}",
            description="URL to the CloudWatch dashboard",
        )


class RdsReadReplicaStack(Stack):
    """
    Separate stack for creating cross-region read replica.
    This should be deployed in the secondary region.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        source_db_arn: str,
        replica_identifier: str,
        sns_topic_arn: str,
        **kwargs
    ) -> None:
        """
        Initialize the RDS Read Replica stack.
        
        Args:
            scope: The parent construct
            construct_id: The construct identifier
            source_db_arn: ARN of the source database
            replica_identifier: Identifier for the read replica
            sns_topic_arn: ARN of the SNS topic for notifications
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.source_db_arn = source_db_arn
        self.replica_identifier = replica_identifier
        self.sns_topic_arn = sns_topic_arn

        # Import SNS topic
        self.sns_topic = sns.Topic.from_topic_arn(
            self, "ImportedSnsTopic", self.sns_topic_arn
        )

        # Create read replica
        self.read_replica = self._create_read_replica()

        # Create replica-specific alarms
        self._create_replica_alarms()

        # Create outputs
        self._create_outputs()

    def _create_read_replica(self) -> rds.DatabaseInstanceReadReplica:
        """
        Create cross-region read replica.
        
        Returns:
            The created read replica instance
        """
        # Note: CDK does not directly support cross-region read replicas
        # This would need to be created using CfnDBInstance with SourceDBInstanceIdentifier
        # pointing to the source database ARN
        
        # For demonstration, we'll show the structure
        # In practice, you might need to use L1 constructs or custom resources
        
        replica = rds.DatabaseInstanceReadReplica(
            self,
            "ReadReplica",
            source_database_instance=rds.DatabaseInstance.from_database_instance_attributes(
                self,
                "SourceDb",
                instance_identifier="placeholder",  # This would be the source DB
                instance_endpoint_address="placeholder",
                port=3306,
                security_groups=[],
            ),
            instance_type=rds.InstanceType.of(
                rds.InstanceClass.BURSTABLE3, rds.InstanceSize.MICRO
            ),
            deletion_protection=False,
            delete_automated_backups=False,
        )

        # Add tags
        cdk.Tags.of(replica).add("Purpose", "DisasterRecovery")
        cdk.Tags.of(replica).add("Environment", "Production")

        return replica

    def _create_replica_alarms(self) -> None:
        """Create CloudWatch alarms specific to the read replica."""
        
        # Replica lag alarm
        cloudwatch.Alarm(
            self,
            "ReplicaLagAlarm",
            alarm_name=f"{self.replica_identifier}-ReplicaLag",
            alarm_description=f"High replica lag on read replica {self.replica_identifier}",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="ReplicaLag",
                dimensions_map={"DBInstanceIdentifier": self.replica_identifier},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=300,  # 5 minutes
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        ).add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for the replica stack."""
        
        CfnOutput(
            self,
            "ReadReplicaEndpoint",
            value=self.read_replica.instance_endpoint.hostname,
            description="Endpoint of the read replica database",
            export_name=f"{self.stack_name}-ReadReplicaEndpoint",
        )

        CfnOutput(
            self,
            "ReadReplicaIdentifier",
            value=self.replica_identifier,
            description="Identifier of the read replica database",
            export_name=f"{self.stack_name}-ReadReplicaIdentifier",
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = cdk.App()

    # Get configuration from environment variables or context
    source_db_identifier = app.node.try_get_context("source_db_identifier") or os.environ.get("SOURCE_DB_IDENTIFIER", "my-database")
    primary_region = app.node.try_get_context("primary_region") or os.environ.get("PRIMARY_REGION", "us-east-1")
    secondary_region = app.node.try_get_context("secondary_region") or os.environ.get("SECONDARY_REGION", "us-west-2")
    notification_email = app.node.try_get_context("notification_email") or os.environ.get("NOTIFICATION_EMAIL")

    # Primary stack (deployed in primary region)
    primary_stack = RdsDisasterRecoveryStack(
        app,
        "RdsDisasterRecoveryStack",
        source_db_identifier=source_db_identifier,
        primary_region=primary_region,
        secondary_region=secondary_region,
        notification_email=notification_email,
        env=cdk.Environment(region=primary_region),
        description="RDS Disaster Recovery Infrastructure (Primary Region)",
    )

    # Note: For cross-region deployment, you would typically deploy the replica stack
    # separately in the secondary region, or use CDK Pipelines for cross-region deployment
    
    # Add tags to all resources
    cdk.Tags.of(app).add("Project", "RdsDisasterRecovery")
    cdk.Tags.of(app).add("Environment", "Production")
    cdk.Tags.of(app).add("ManagedBy", "CDK")

    app.synth()


if __name__ == "__main__":
    main()