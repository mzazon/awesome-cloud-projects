#!/usr/bin/env python3
"""
AWS CDK Python application for Database Performance Tuning with Parameter Groups.

This CDK application creates:
- VPC with subnets across multiple AZs
- Security groups for database access
- Custom RDS parameter group with optimized settings
- RDS PostgreSQL instance with Performance Insights
- Read replica for read scaling
- CloudWatch dashboard for monitoring
- CloudWatch alarms for performance thresholds

Author: AWS Recipes Team
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_rds as rds,
    aws_ec2 as ec2,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_iam as iam,
)
from constructs import Construct


class DatabasePerformanceTuningStack(Stack):
    """CDK Stack for Database Performance Tuning with Parameter Groups."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.db_instance_class = "db.t3.medium"
        self.engine_version = "15.4"
        self.allocated_storage = 100
        self.backup_retention_days = 7
        self.monitoring_interval = 60

        # Create VPC and networking resources
        self._create_vpc()
        
        # Create security groups
        self._create_security_groups()
        
        # Create enhanced monitoring role
        self._create_monitoring_role()
        
        # Create custom parameter group
        self._create_parameter_group()
        
        # Create RDS subnet group
        self._create_subnet_group()
        
        # Create primary database instance
        self._create_database_instance()
        
        # Create read replica
        self._create_read_replica()
        
        # Create CloudWatch dashboard
        self._create_monitoring_dashboard()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> None:
        """Create VPC with public and private subnets across multiple AZs."""
        self.vpc = ec2.Vpc(
            self,
            "PerformanceTuningVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            nat_gateways=0,  # No NAT gateways needed for this demo
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="DatabaseSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Add VPC endpoint for CloudWatch (for monitoring without internet access)
        self.vpc.add_interface_endpoint(
            "CloudWatchEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_MONITORING
        )

    def _create_security_groups(self) -> None:
        """Create security groups for database access."""
        # Security group for RDS instance
        self.db_security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for PostgreSQL database",
            allow_all_outbound=False
        )

        # Allow PostgreSQL access from within VPC
        self.db_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(5432),
            description="PostgreSQL access from VPC"
        )

        # Allow HTTPS outbound for monitoring
        self.db_security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS outbound for monitoring"
        )

    def _create_monitoring_role(self) -> None:
        """Create IAM role for RDS enhanced monitoring."""
        self.monitoring_role = iam.Role(
            self,
            "RDSMonitoringRole",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                )
            ],
            description="Role for RDS Enhanced Monitoring"
        )

    def _create_parameter_group(self) -> None:
        """Create custom parameter group with optimized PostgreSQL settings."""
        # Define optimized parameters for db.t3.medium (4 vCPUs, 4 GB RAM)
        optimized_parameters: Dict[str, str] = {
            # Memory allocation parameters
            "shared_buffers": "1024MB",  # 25% of RAM for shared buffers
            "work_mem": "16MB",  # Increased for complex queries
            "maintenance_work_mem": "256MB",  # For maintenance operations
            "effective_cache_size": "3GB",  # 75% of RAM for OS cache estimation
            
            # Connection parameters
            "max_connections": "200",  # Increased from default 100
            
            # Query planner cost parameters
            "random_page_cost": "1.1",  # Optimized for SSD storage
            "seq_page_cost": "1.0",  # Sequential read cost
            "effective_io_concurrency": "200",  # SSD optimization
            "cpu_tuple_cost": "0.01",  # CPU cost per tuple
            "cpu_index_tuple_cost": "0.005",  # CPU cost per index tuple
            
            # Query planner parameters
            "default_statistics_target": "500",  # Increased for better statistics
            "constraint_exclusion": "partition",  # Enable constraint exclusion
            "from_collapse_limit": "20",  # Limit for FROM item collapsing
            "join_collapse_limit": "20",  # Limit for JOIN collapsing
            "geqo_threshold": "15",  # Genetic query optimization threshold
            "geqo_effort": "8",  # GEQO planning effort
            
            # Parallel query parameters
            "max_parallel_workers_per_gather": "2",  # Parallel workers per query
            "max_parallel_workers": "4",  # Total parallel workers
            "parallel_tuple_cost": "0.1",  # Cost of parallel tuple processing
            "parallel_setup_cost": "1000",  # Cost of parallel query setup
            
            # Checkpoint and WAL parameters
            "checkpoint_completion_target": "0.9",  # Spread checkpoints
            "wal_buffers": "16MB",  # WAL buffer size
            "checkpoint_timeout": "15min",  # Checkpoint frequency
            
            # Autovacuum parameters
            "autovacuum_vacuum_scale_factor": "0.1",  # Vacuum threshold
            "autovacuum_analyze_scale_factor": "0.05",  # Analyze threshold
            "autovacuum_work_mem": "256MB",  # Memory for autovacuum
            
            # Logging parameters
            "log_min_duration_statement": "1000",  # Log slow queries (1 second)
            "log_checkpoints": "1",  # Log checkpoint activity
            "log_connections": "1",  # Log connections
            "log_disconnections": "1",  # Log disconnections
            "log_lock_waits": "1",  # Log lock waits
            "log_temp_files": "0",  # Log temporary files
        }

        self.parameter_group = rds.ParameterGroup(
            self,
            "OptimizedParameterGroup",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_4
            ),
            description="Optimized PostgreSQL parameter group for performance tuning",
            parameters=optimized_parameters
        )

    def _create_subnet_group(self) -> None:
        """Create DB subnet group for RDS instances."""
        self.subnet_group = rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            description="Subnet group for performance tuning database",
            vpc=self.vpc,
            subnet_group_name="performance-tuning-subnet-group",
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            )
        )

    def _create_database_instance(self) -> None:
        """Create primary RDS PostgreSQL instance with optimized configuration."""
        self.primary_instance = rds.DatabaseInstance(
            self,
            "PrimaryDatabase",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_15_4
            ),
            instance_type=ec2.InstanceType(self.db_instance_class),
            allocated_storage=self.allocated_storage,
            storage_type=rds.StorageType.GP3,
            storage_encrypted=True,
            multi_az=False,  # Single AZ for cost optimization in demo
            
            # Database configuration
            database_name="performancedb",
            credentials=rds.Credentials.from_generated_secret(
                "dbadmin",
                secret_name="performance-tuning-db-credentials"
            ),
            
            # Parameter group and subnet group
            parameter_group=self.parameter_group,
            subnet_group=self.subnet_group,
            security_groups=[self.db_security_group],
            
            # Backup and maintenance
            backup_retention=Duration.days(self.backup_retention_days),
            delete_automated_backups=True,
            deletion_protection=False,  # Allow deletion for demo cleanup
            
            # Monitoring configuration
            monitoring_interval=Duration.seconds(self.monitoring_interval),
            monitoring_role=self.monitoring_role,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            
            # CloudWatch logs
            cloudwatch_logs_exports=["postgresql"],
            cloudwatch_logs_retention=logs.RetentionDays.ONE_WEEK,
            
            # Maintenance and updates
            auto_minor_version_upgrade=True,
            copy_tags_to_snapshot=True,
            
            # Removal policy for demo purposes
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_read_replica(self) -> None:
        """Create read replica with the same optimized parameter group."""
        self.read_replica = rds.DatabaseInstanceReadReplica(
            self,
            "ReadReplica",
            source_database_instance=self.primary_instance,
            instance_type=ec2.InstanceType(self.db_instance_class),
            
            # Use same parameter group for consistency
            parameter_group=self.parameter_group,
            
            # Monitoring configuration
            monitoring_interval=Duration.seconds(self.monitoring_interval),
            monitoring_role=self.monitoring_role,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            
            # Auto scaling and updates
            auto_minor_version_upgrade=True,
            delete_automated_backups=True,
            deletion_protection=False,  # Allow deletion for demo cleanup
            
            # Removal policy for demo purposes
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_monitoring_dashboard(self) -> None:
        """Create CloudWatch dashboard for database performance monitoring."""
        self.dashboard = cloudwatch.Dashboard(
            self,
            "DatabasePerformanceDashboard",
            dashboard_name="Database-Performance-Tuning",
            period_override=cloudwatch.PeriodOverride.AUTO,
            start="-PT6H"  # Show last 6 hours by default
        )

        # Primary instance metrics widget
        primary_metrics_widget = cloudwatch.GraphWidget(
            title="Primary Database Performance",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="CPUUtilization",
                    dimensions_map={"DBInstanceIdentifier": self.primary_instance.instance_identifier},
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="DatabaseConnections",
                    dimensions_map={"DBInstanceIdentifier": self.primary_instance.instance_identifier},
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="FreeableMemory",
                    dimensions_map={"DBInstanceIdentifier": self.primary_instance.instance_identifier},
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )

        # I/O performance widget
        io_metrics_widget = cloudwatch.GraphWidget(
            title="Database I/O Performance",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="ReadIOPS",
                    dimensions_map={"DBInstanceIdentifier": self.primary_instance.instance_identifier},
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="WriteIOPS",
                    dimensions_map={"DBInstanceIdentifier": self.primary_instance.instance_identifier},
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="ReadLatency",
                    dimensions_map={"DBInstanceIdentifier": self.primary_instance.instance_identifier},
                    statistic="Average",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/RDS",
                    metric_name="WriteLatency",
                    dimensions_map={"DBInstanceIdentifier": self.primary_instance.instance_identifier},
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )

        # Add widgets to dashboard
        self.dashboard.add_widgets(primary_metrics_widget, io_metrics_widget)

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for database performance monitoring."""
        # High CPU utilization alarm
        self.cpu_alarm = cloudwatch.Alarm(
            self,
            "DatabaseHighCPU",
            alarm_name="Database-High-CPU-Utilization",
            alarm_description="High CPU utilization on primary database instance",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="CPUUtilization",
                dimensions_map={"DBInstanceIdentifier": self.primary_instance.instance_identifier},
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # High connection count alarm
        self.connection_alarm = cloudwatch.Alarm(
            self,
            "DatabaseHighConnections",
            alarm_name="Database-High-Connection-Count",
            alarm_description="High connection count on primary database instance",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="DatabaseConnections",
                dimensions_map={"DBInstanceIdentifier": self.primary_instance.instance_identifier},
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=150,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # High read latency alarm
        self.read_latency_alarm = cloudwatch.Alarm(
            self,
            "DatabaseHighReadLatency",
            alarm_name="Database-High-Read-Latency",
            alarm_description="High read latency on primary database instance",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="ReadLatency",
                dimensions_map={"DBInstanceIdentifier": self.primary_instance.instance_identifier},
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=0.1,  # 100ms
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "PrimaryDatabaseEndpoint",
            value=self.primary_instance.instance_endpoint.hostname,
            description="Primary database endpoint for connections",
            export_name=f"{self.stack_name}-PrimaryDBEndpoint"
        )

        CfnOutput(
            self,
            "ReadReplicaEndpoint",
            value=self.read_replica.instance_endpoint.hostname,
            description="Read replica endpoint for read-only connections",
            export_name=f"{self.stack_name}-ReadReplicaEndpoint"
        )

        CfnOutput(
            self,
            "DatabasePort",
            value="5432",
            description="Database port for connections",
            export_name=f"{self.stack_name}-DatabasePort"
        )

        CfnOutput(
            self,
            "ParameterGroupName",
            value=self.parameter_group.parameter_group_name,
            description="Name of the optimized parameter group",
            export_name=f"{self.stack_name}-ParameterGroup"
        )

        CfnOutput(
            self,
            "DatabaseCredentialsSecret",
            value=self.primary_instance.secret.secret_name,
            description="Secrets Manager secret containing database credentials",
            export_name=f"{self.stack_name}-DBCredentials"
        )

        CfnOutput(
            self,
            "CloudWatchDashboard",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch dashboard URL for monitoring",
            export_name=f"{self.stack_name}-Dashboard"
        )

        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for the database infrastructure",
            export_name=f"{self.stack_name}-VPCId"
        )


def main() -> None:
    """Main function to create and deploy the CDK app."""
    app = cdk.App()
    
    # Get environment from context or use defaults
    env = cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )
    
    # Create the stack
    DatabasePerformanceTuningStack(
        app,
        "DatabasePerformanceTuningStack",
        env=env,
        description="Database Performance Tuning with Optimized Parameter Groups",
        tags={
            "Project": "DatabasePerformanceTuning",
            "Environment": "Demo",
            "ManagedBy": "CDK"
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()