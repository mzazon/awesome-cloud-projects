#!/usr/bin/env python3
"""
CDK Python Application for Redshift Performance Optimization

This CDK application deploys a comprehensive performance optimization
infrastructure for Amazon Redshift including:
- CloudWatch monitoring dashboard
- Performance alerting via SNS
- Automated maintenance Lambda function
- EventBridge scheduled maintenance
- Custom parameter group for WLM optimization
"""

import os
from typing import Dict, Any

from aws_cdk import (
    App,
    Stack,
    StackProps,
    Duration,
    CfnOutput,
    aws_redshift as redshift,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_lambda as _lambda,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_logs as logs,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct


class RedshiftPerformanceStack(Stack):
    """
    CDK Stack for Redshift Performance Optimization Infrastructure
    
    This stack creates all the necessary resources for monitoring and optimizing
    Amazon Redshift performance including automated maintenance, alerting,
    and workload management configuration.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters with sensible defaults
        cluster_identifier = self.node.try_get_context("cluster_identifier") or "my-redshift-cluster"
        notification_email = self.node.try_get_context("notification_email") or "admin@example.com"
        maintenance_schedule = self.node.try_get_context("maintenance_schedule") or "cron(0 2 * * ? *)"
        
        # Create SNS topic for performance alerts
        alert_topic = self._create_alert_topic(notification_email)
        
        # Create CloudWatch log group for custom metrics
        log_group = self._create_log_group()
        
        # Create database credentials secret
        db_secret = self._create_database_secret()
        
        # Create optimized parameter group for WLM
        parameter_group = self._create_parameter_group()
        
        # Create IAM role for Lambda maintenance function
        lambda_role = self._create_lambda_role(db_secret)
        
        # Create Lambda function for automated maintenance
        maintenance_function = self._create_maintenance_function(
            lambda_role, db_secret, cluster_identifier
        )
        
        # Create CloudWatch dashboard
        dashboard = self._create_cloudwatch_dashboard(cluster_identifier)
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms(cluster_identifier, alert_topic)
        
        # Create EventBridge rule for scheduled maintenance
        self._create_maintenance_schedule(maintenance_function, maintenance_schedule)
        
        # Stack outputs
        self._create_outputs(
            alert_topic, parameter_group, maintenance_function, dashboard, db_secret
        )

    def _create_alert_topic(self, notification_email: str) -> sns.Topic:
        """Create SNS topic for performance alerts"""
        topic = sns.Topic(
            self, "RedshiftPerformanceAlerts",
            topic_name="redshift-performance-alerts",
            display_name="Redshift Performance Alerts"
        )
        
        # Add email subscription
        topic.add_subscription(
            sns.EmailSubscription(notification_email)
        )
        
        return topic

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for custom metrics"""
        return logs.LogGroup(
            self, "PerformanceMetricsLogGroup",
            log_group_name="/aws/redshift/performance-metrics",
            retention=logs.RetentionDays.ONE_MONTH
        )

    def _create_database_secret(self) -> secretsmanager.Secret:
        """Create Secrets Manager secret for database credentials"""
        return secretsmanager.Secret(
            self, "RedshiftMaintenanceCredentials",
            secret_name="redshift-maintenance-credentials",
            description="Database credentials for Redshift maintenance operations",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "maintenance_user"}',
                generate_string_key="password",
                exclude_characters='"@/\\'
            )
        )

    def _create_parameter_group(self) -> redshift.CfnClusterParameterGroup:
        """Create optimized parameter group with automatic WLM"""
        return redshift.CfnClusterParameterGroup(
            self, "OptimizedParameterGroup",
            description="Optimized WLM configuration for Redshift performance",
            parameter_group_family="redshift-1.0",
            parameter_group_name="optimized-wlm-config",
            parameters=[
                {
                    "parameterName": "wlm_json_configuration",
                    "parameterValue": '[{"query_group":[],"query_group_wild_card":0,"user_group":[],"user_group_wild_card":0,"concurrency_scaling":"auto"}]'
                }
            ]
        )

    def _create_lambda_role(self, db_secret: secretsmanager.Secret) -> iam.Role:
        """Create IAM role for Lambda maintenance function"""
        role = iam.Role(
            self, "RedshiftMaintenanceLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Redshift maintenance Lambda function"
        )
        
        # Add basic Lambda execution permissions
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSLambdaBasicExecutionRole"
            )
        )
        
        # Add VPC execution permissions (if Lambda needs VPC access)
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSLambdaVPCAccessExecutionRole"
            )
        )
        
        # Grant access to read database credentials
        db_secret.grant_read(role)
        
        return role

    def _create_maintenance_function(
        self, 
        lambda_role: iam.Role, 
        db_secret: secretsmanager.Secret,
        cluster_identifier: str
    ) -> _lambda.Function:
        """Create Lambda function for automated Redshift maintenance"""
        
        function_code = '''
import json
import boto3
import psycopg2
import os
import logging
from typing import Dict, Any, List, Tuple

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for automated Redshift maintenance operations.
    
    This function performs intelligent VACUUM and ANALYZE operations
    on tables that meet specific criteria to optimize performance.
    """
    try:
        # Get database connection parameters
        cluster_identifier = os.environ['CLUSTER_IDENTIFIER']
        secret_arn = os.environ['DB_SECRET_ARN']
        
        # Retrieve database credentials from Secrets Manager
        secrets_client = boto3.client('secretsmanager')
        secret_response = secrets_client.get_secret_value(SecretId=secret_arn)
        secret_data = json.loads(secret_response['SecretString'])
        
        # Get cluster endpoint
        redshift_client = boto3.client('redshift')
        cluster_response = redshift_client.describe_clusters(
            ClusterIdentifier=cluster_identifier
        )
        cluster_endpoint = cluster_response['Clusters'][0]['Endpoint']['Address']
        
        # Connect to Redshift
        conn = psycopg2.connect(
            host=cluster_endpoint,
            database='dev',  # Default database
            user=secret_data['username'],
            password=secret_data['password'],
            port=5439
        )
        
        cur = conn.cursor()
        
        # Get tables that need maintenance
        tables_processed = perform_maintenance(cur)
        
        conn.commit()
        cur.close()
        conn.close()
        
        logger.info(f"Maintenance completed successfully. Processed {len(tables_processed)} tables.")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Maintenance completed on {len(tables_processed)} tables',
                'tables_processed': tables_processed
            })
        }
        
    except Exception as e:
        logger.error(f"Error during maintenance: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def perform_maintenance(cursor) -> List[str]:
    """
    Perform intelligent maintenance operations on Redshift tables.
    
    Args:
        cursor: Database cursor for executing SQL commands
        
    Returns:
        List of table names that were processed
    """
    tables_processed = []
    
    # Query to find tables that need VACUUM
    maintenance_query = """
        SELECT TRIM(name) as table_name,
               unsorted/DECODE(rows,0,1,rows)::FLOAT * 100 as pct_unsorted,
               rows
        FROM stv_tbl_perm
        WHERE unsorted > 0 
          AND rows > 1000
          AND TRIM(name) NOT LIKE 'temp_%'
          AND TRIM(name) NOT LIKE 'stl_%'
          AND TRIM(name) NOT LIKE 'stv_%'
        ORDER BY pct_unsorted DESC
        LIMIT 10;
    """
    
    cursor.execute(maintenance_query)
    tables_needing_maintenance = cursor.fetchall()
    
    for table_name, pct_unsorted, row_count in tables_needing_maintenance:
        try:
            # Only VACUUM if >10% unsorted or large tables with >5% unsorted
            should_vacuum = (pct_unsorted > 10) or (row_count > 1000000 and pct_unsorted > 5)
            
            if should_vacuum:
                logger.info(f"Performing VACUUM on table: {table_name} ({pct_unsorted:.1f}% unsorted, {row_count} rows)")
                
                # VACUUM DELETE only (faster than full VACUUM)
                cursor.execute(f"VACUUM DELETE ONLY {table_name};")
                
                # Update table statistics
                cursor.execute(f"ANALYZE {table_name};")
                
                tables_processed.append(table_name)
                
                logger.info(f"Completed maintenance on table: {table_name}")
            
        except Exception as e:
            logger.error(f"Error processing table {table_name}: {str(e)}")
            continue
    
    return tables_processed
'''
        
        return _lambda.Function(
            self, "RedshiftMaintenanceFunction",
            function_name="redshift-maintenance",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(function_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            environment={
                "CLUSTER_IDENTIFIER": cluster_identifier,
                "DB_SECRET_ARN": db_secret.secret_arn
            },
            description="Automated Redshift maintenance function for performance optimization"
        )

    def _create_cloudwatch_dashboard(self, cluster_identifier: str) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for Redshift performance monitoring"""
        dashboard = cloudwatch.Dashboard(
            self, "RedshiftPerformanceDashboard",
            dashboard_name="Redshift-Performance-Dashboard"
        )
        
        # Cluster metrics widget
        cluster_metrics_widget = cloudwatch.GraphWidget(
            title="Redshift Cluster Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Redshift",
                    metric_name="CPUUtilization",
                    dimensions_map={"ClusterIdentifier": cluster_identifier},
                    statistic="Average"
                ),
                cloudwatch.Metric(
                    namespace="AWS/Redshift",
                    metric_name="DatabaseConnections",
                    dimensions_map={"ClusterIdentifier": cluster_identifier},
                    statistic="Average"
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/Redshift",
                    metric_name="HealthStatus",
                    dimensions_map={"ClusterIdentifier": cluster_identifier},
                    statistic="Average"
                )
            ],
            width=12,
            height=6
        )
        
        # Query queue metrics widget
        queue_metrics_widget = cloudwatch.GraphWidget(
            title="Query Queue Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Redshift",
                    metric_name="QueueLength",
                    dimensions_map={"ClusterIdentifier": cluster_identifier},
                    statistic="Average"
                ),
                cloudwatch.Metric(
                    namespace="AWS/Redshift",
                    metric_name="WLMQueueLength",
                    dimensions_map={"ClusterIdentifier": cluster_identifier},
                    statistic="Average"
                )
            ],
            width=12,
            height=6
        )
        
        # Storage and I/O metrics widget
        storage_metrics_widget = cloudwatch.GraphWidget(
            title="Storage and I/O Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Redshift",
                    metric_name="PercentageDiskSpaceUsed",
                    dimensions_map={"ClusterIdentifier": cluster_identifier},
                    statistic="Average"
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/Redshift",
                    metric_name="ReadIOPS",
                    dimensions_map={"ClusterIdentifier": cluster_identifier},
                    statistic="Average"
                ),
                cloudwatch.Metric(
                    namespace="AWS/Redshift",
                    metric_name="WriteIOPS",
                    dimensions_map={"ClusterIdentifier": cluster_identifier},
                    statistic="Average"
                )
            ],
            width=12,
            height=6
        )
        
        dashboard.add_widgets(
            cluster_metrics_widget,
            queue_metrics_widget,
            storage_metrics_widget
        )
        
        return dashboard

    def _create_cloudwatch_alarms(
        self, 
        cluster_identifier: str, 
        alert_topic: sns.Topic
    ) -> None:
        """Create CloudWatch alarms for performance monitoring"""
        
        # High CPU utilization alarm
        cloudwatch.Alarm(
            self, "RedshiftHighCPUAlarm",
            alarm_name="Redshift-High-CPU-Usage",
            alarm_description="Alert when Redshift CPU usage is consistently high",
            metric=cloudwatch.Metric(
                namespace="AWS/Redshift",
                metric_name="CPUUtilization",
                dimensions_map={"ClusterIdentifier": cluster_identifier},
                statistic="Average"
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        ).add_alarm_action(
            cloudwatch.SnsAction(alert_topic)
        )
        
        # High queue length alarm
        cloudwatch.Alarm(
            self, "RedshiftHighQueueLengthAlarm",
            alarm_name="Redshift-High-Queue-Length",
            alarm_description="Alert when query queue length is high",
            metric=cloudwatch.Metric(
                namespace="AWS/Redshift",
                metric_name="QueueLength",
                dimensions_map={"ClusterIdentifier": cluster_identifier},
                statistic="Average"
            ),
            threshold=10,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        ).add_alarm_action(
            cloudwatch.SnsAction(alert_topic)
        )
        
        # High disk usage alarm
        cloudwatch.Alarm(
            self, "RedshiftHighDiskUsageAlarm",
            alarm_name="Redshift-High-Disk-Usage",
            alarm_description="Alert when disk usage is high",
            metric=cloudwatch.Metric(
                namespace="AWS/Redshift",
                metric_name="PercentageDiskSpaceUsed",
                dimensions_map={"ClusterIdentifier": cluster_identifier},
                statistic="Average"
            ),
            threshold=85,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        ).add_alarm_action(
            cloudwatch.SnsAction(alert_topic)
        )

    def _create_maintenance_schedule(
        self, 
        maintenance_function: _lambda.Function,
        schedule_expression: str
    ) -> None:
        """Create EventBridge rule for scheduled maintenance"""
        
        # Create EventBridge rule
        maintenance_rule = events.Rule(
            self, "RedshiftMaintenanceSchedule",
            rule_name="redshift-nightly-maintenance",
            schedule=events.Schedule.expression(schedule_expression),
            description="Run Redshift maintenance tasks on schedule"
        )
        
        # Add Lambda function as target
        maintenance_rule.add_target(
            targets.LambdaFunction(maintenance_function)
        )

    def _create_outputs(
        self,
        alert_topic: sns.Topic,
        parameter_group: redshift.CfnClusterParameterGroup,
        maintenance_function: _lambda.Function,
        dashboard: cloudwatch.Dashboard,
        db_secret: secretsmanager.Secret
    ) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self, "SNSTopicArn",
            description="ARN of the SNS topic for performance alerts",
            value=alert_topic.topic_arn
        )
        
        CfnOutput(
            self, "ParameterGroupName",
            description="Name of the optimized Redshift parameter group",
            value=parameter_group.parameter_group_name or "optimized-wlm-config"
        )
        
        CfnOutput(
            self, "MaintenanceFunctionArn",
            description="ARN of the Lambda maintenance function",
            value=maintenance_function.function_arn
        )
        
        CfnOutput(
            self, "DashboardURL",
            description="URL of the CloudWatch dashboard",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={dashboard.dashboard_name}"
        )
        
        CfnOutput(
            self, "DatabaseSecretArn",
            description="ARN of the Secrets Manager secret containing database credentials",
            value=db_secret.secret_arn
        )
        
        CfnOutput(
            self, "DeploymentInstructions",
            description="Next steps after deployment",
            value="1. Update database secret with actual credentials 2. Apply parameter group to cluster 3. Subscribe to SNS topic"
        )


# CDK App
app = App()

# Create the stack
RedshiftPerformanceStack(
    app, 
    "RedshiftPerformanceStack",
    description="Comprehensive Redshift performance optimization infrastructure",
    env={
        'region': os.environ.get('CDK_DEFAULT_REGION', 'us-east-1'),
        'account': os.environ.get('CDK_DEFAULT_ACCOUNT')
    }
)

app.synth()