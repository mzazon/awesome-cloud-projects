"""
Neptune Cluster Stack

This stack creates the Amazon Neptune graph database cluster with:
- Neptune cluster with encryption at rest
- Primary instance for write operations
- Read replica instances for scaling read workloads
- Automated backup and maintenance configuration
"""

from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_neptune as neptune,
    CfnOutput,
    RemovalPolicy,
)
from constructs import Construct
from typing import Optional


class NeptuneStack(Stack):
    """
    Creates Amazon Neptune cluster for graph database operations.
    
    This stack deploys a production-ready Neptune cluster with
    high availability, encryption, and automated backups.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: ec2.Vpc,
        neptune_security_group: ec2.SecurityGroup,
        subnet_group: neptune.CfnDBSubnetGroup,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.vpc = vpc
        self.neptune_security_group = neptune_security_group
        self.subnet_group = subnet_group

        # Create Neptune cluster parameter group for optimization
        self.cluster_parameter_group = neptune.CfnDBClusterParameterGroup(
            self, "NeptuneClusterParameterGroup",
            family="neptune1.3",
            description="Neptune cluster parameter group for recommendations",
            parameters={
                "neptune_enable_audit_log": "1",
                "neptune_query_timeout": "120000",  # 2 minutes
                "neptune_result_cache": "1",
            },
        )

        # Create Neptune DB parameter group for instances
        self.db_parameter_group = neptune.CfnDBParameterGroup(
            self, "NeptuneDBParameterGroup",
            family="neptune1.3",
            description="Neptune DB parameter group for recommendation instances",
            parameters={
                "neptune_query_timeout": "120000",
                "neptune_result_cache": "1",
            },
        )

        # Create Neptune cluster
        self.neptune_cluster = neptune.CfnDBCluster(
            self, "NeptuneCluster",
            engine="neptune",
            engine_version="1.3.2.0",
            db_cluster_identifier="neptune-recommendations-cluster",
            db_subnet_group_name=self.subnet_group.db_subnet_group_name,
            vpc_security_group_ids=[self.neptune_security_group.security_group_id],
            storage_encrypted=True,
            backup_retention_period=7,
            preferred_backup_window="03:00-04:00",
            preferred_maintenance_window="sun:04:00-sun:05:00",
            db_cluster_parameter_group_name=self.cluster_parameter_group.ref,
            enable_cloudwatch_logs_exports=["audit"],
            deletion_protection=False,  # Set to True for production
        )

        # Create primary Neptune instance
        self.primary_instance = neptune.CfnDBInstance(
            self, "NeptunePrimaryInstance",
            db_instance_class="db.r5.large",
            engine="neptune",
            db_cluster_identifier=self.neptune_cluster.ref,
            db_instance_identifier="neptune-primary-instance",
            publicly_accessible=False,
            db_parameter_group_name=self.db_parameter_group.ref,
            auto_minor_version_upgrade=True,
        )

        # Create first read replica instance
        self.replica_instance_1 = neptune.CfnDBInstance(
            self, "NeptuneReplicaInstance1",
            db_instance_class="db.r5.large",
            engine="neptune",
            db_cluster_identifier=self.neptune_cluster.ref,
            db_instance_identifier="neptune-replica-instance-1",
            publicly_accessible=False,
            db_parameter_group_name=self.db_parameter_group.ref,
            auto_minor_version_upgrade=True,
        )

        # Create second read replica instance for high availability
        self.replica_instance_2 = neptune.CfnDBInstance(
            self, "NeptuneReplicaInstance2",
            db_instance_class="db.r5.large",
            engine="neptune",
            db_cluster_identifier=self.neptune_cluster.ref,
            db_instance_identifier="neptune-replica-instance-2",
            publicly_accessible=False,
            db_parameter_group_name=self.db_parameter_group.ref,
            auto_minor_version_upgrade=True,
        )

        # Store Neptune endpoint for other stacks
        self.neptune_endpoint = self.neptune_cluster.attr_endpoint

        # Outputs
        CfnOutput(
            self, "NeptuneClusterEndpoint",
            value=self.neptune_cluster.attr_endpoint,
            description="Neptune cluster write endpoint",
            export_name="NeptuneClusterEndpoint"
        )

        CfnOutput(
            self, "NeptuneClusterReadEndpoint",
            value=self.neptune_cluster.attr_read_endpoint,
            description="Neptune cluster read endpoint",
            export_name="NeptuneClusterReadEndpoint"
        )

        CfnOutput(
            self, "NeptuneClusterPort",
            value=self.neptune_cluster.attr_port,
            description="Neptune cluster port",
            export_name="NeptuneClusterPort"
        )

        CfnOutput(
            self, "NeptuneClusterResourceId",
            value=self.neptune_cluster.attr_cluster_resource_id,
            description="Neptune cluster resource ID",
            export_name="NeptuneClusterResourceId"
        )

        CfnOutput(
            self, "NeptunePrimaryInstanceEndpoint",
            value=self.primary_instance.attr_endpoint,
            description="Neptune primary instance endpoint",
            export_name="NeptunePrimaryInstanceEndpoint"
        )

        CfnOutput(
            self, "NeptuneReplica1InstanceEndpoint",
            value=self.replica_instance_1.attr_endpoint,
            description="Neptune replica 1 instance endpoint",
            export_name="NeptuneReplica1InstanceEndpoint"
        )

        CfnOutput(
            self, "NeptuneReplica2InstanceEndpoint",
            value=self.replica_instance_2.attr_endpoint,
            description="Neptune replica 2 instance endpoint",
            export_name="NeptuneReplica2InstanceEndpoint"
        )