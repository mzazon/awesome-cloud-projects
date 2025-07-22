#!/usr/bin/env python3
"""
CDK Application for Real-Time Vehicle Telemetry Analytics
with AWS IoT FleetWise and Amazon Timestream

This application creates a complete vehicle telemetry analytics infrastructure
including signal catalogs, vehicle models, decoder manifests, fleets, campaigns,
Timestream database, and Amazon Managed Grafana workspace.
"""

import os
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_iam as iam,
    aws_iotfleetwise as iotfleetwise,
    aws_timestream as timestream,
    aws_s3 as s3,
    aws_grafana as grafana,
)
from constructs import Construct


class VehicleTelemetryAnalyticsStack(Stack):
    """
    CDK Stack for Vehicle Telemetry Analytics using AWS IoT FleetWise and Timestream.
    
    This stack creates:
    - Signal catalog for standardizing vehicle data
    - Vehicle model and decoder manifest
    - Fleet and campaign for data collection
    - Timestream database and table for time-series storage
    - S3 bucket for data archival
    - IAM roles and policies for secure access
    - Amazon Managed Grafana workspace for visualization
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context('unique_suffix') or 'demo'
        
        # Create S3 bucket for telemetry data archival
        telemetry_bucket = s3.Bucket(
            self, 'TelemetryDataBucket',
            bucket_name=f'fleetwise-telemetry-{unique_suffix}',
            versioned=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id='ArchiveOldData',
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )

        # Create Timestream database for vehicle telemetry
        timestream_database = timestream.CfnDatabase(
            self, 'TelemetryDatabase',
            database_name=f'telemetry_db_{unique_suffix.replace("-", "_")}',
            tags=[
                {
                    'key': 'Purpose',
                    'value': 'VehicleTelemetryAnalytics'
                }
            ]
        )

        # Create Timestream table with retention policies
        timestream_table = timestream.CfnTable(
            self, 'TelemetryTable',
            database_name=timestream_database.database_name,
            table_name='vehicle_metrics',
            retention_properties=timestream.CfnTable.RetentionPropertiesProperty(
                memory_store_retention_period_in_hours='24',
                magnetic_store_retention_period_in_days='30'
            ),
            tags=[
                {
                    'key': 'Purpose',
                    'value': 'VehicleTelemetryStorage'
                }
            ]
        )
        timestream_table.add_dependency(timestream_database)

        # Create IAM role for AWS IoT FleetWise service
        fleetwise_service_role = iam.Role(
            self, 'FleetWiseServiceRole',
            role_name=f'FleetWiseServiceRole-{unique_suffix}',
            assumed_by=iam.ServicePrincipal('iotfleetwise.amazonaws.com'),
            description='Service role for AWS IoT FleetWise to access Timestream and S3',
            inline_policies={
                'TimestreamWritePolicy': iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                'timestream:WriteRecords',
                                'timestream:DescribeEndpoints'
                            ],
                            resources=[
                                f'arn:aws:timestream:{self.region}:{self.account}:database/{timestream_database.database_name}/table/{timestream_table.table_name}'
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=['timestream:DescribeEndpoints'],
                            resources=['*']
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                's3:PutObject',
                                's3:GetObject',
                                's3:DeleteObject'
                            ],
                            resources=[f'{telemetry_bucket.bucket_arn}/*']
                        )
                    ]
                )
            }
        )

        # Create signal catalog for vehicle data standardization
        signal_catalog = iotfleetwise.CfnSignalCatalog(
            self, 'VehicleSignalCatalog',
            name='VehicleSignalCatalog',
            description='Standard vehicle telemetry signals for fleet analytics',
            nodes=[
                # Root vehicle branch
                iotfleetwise.CfnSignalCatalog.NodeProperty(
                    branch=iotfleetwise.CfnSignalCatalog.BranchProperty(
                        fully_qualified_name='Vehicle',
                        description='Root vehicle node'
                    )
                ),
                # Engine branch
                iotfleetwise.CfnSignalCatalog.NodeProperty(
                    branch=iotfleetwise.CfnSignalCatalog.BranchProperty(
                        fully_qualified_name='Vehicle.Engine',
                        description='Engine-related signals'
                    )
                ),
                # Engine RPM sensor
                iotfleetwise.CfnSignalCatalog.NodeProperty(
                    sensor=iotfleetwise.CfnSignalCatalog.SensorProperty(
                        fully_qualified_name='Vehicle.Engine.RPM',
                        data_type='DOUBLE',
                        description='Engine revolutions per minute',
                        unit='rpm',
                        min=0,
                        max=8000
                    )
                ),
                # Vehicle speed sensor
                iotfleetwise.CfnSignalCatalog.NodeProperty(
                    sensor=iotfleetwise.CfnSignalCatalog.SensorProperty(
                        fully_qualified_name='Vehicle.Speed',
                        data_type='DOUBLE',
                        description='Vehicle speed',
                        unit='km/h',
                        min=0,
                        max=300
                    )
                ),
                # Engine temperature sensor
                iotfleetwise.CfnSignalCatalog.NodeProperty(
                    sensor=iotfleetwise.CfnSignalCatalog.SensorProperty(
                        fully_qualified_name='Vehicle.Engine.Temperature',
                        data_type='DOUBLE',
                        description='Engine coolant temperature',
                        unit='Celsius',
                        min=-40,
                        max=200
                    )
                ),
                # Fuel level sensor
                iotfleetwise.CfnSignalCatalog.NodeProperty(
                    sensor=iotfleetwise.CfnSignalCatalog.SensorProperty(
                        fully_qualified_name='Vehicle.FuelLevel',
                        data_type='DOUBLE',
                        description='Fuel tank level percentage',
                        unit='Percentage',
                        min=0,
                        max=100
                    )
                )
            ],
            tags=[
                {
                    'key': 'Purpose',
                    'value': 'VehicleDataStandardization'
                }
            ]
        )

        # Create vehicle model manifest
        model_manifest = iotfleetwise.CfnModelManifest(
            self, 'StandardVehicleModel',
            name='StandardVehicleModel',
            description='Model for standard fleet vehicles with essential telemetry',
            signal_catalog_arn=signal_catalog.attr_arn,
            nodes=[
                'Vehicle.Engine.RPM',
                'Vehicle.Speed',
                'Vehicle.Engine.Temperature',
                'Vehicle.FuelLevel'
            ],
            status='ACTIVE',
            tags=[
                {
                    'key': 'Purpose',
                    'value': 'VehicleModelDefinition'
                }
            ]
        )
        model_manifest.add_dependency(signal_catalog)

        # Create decoder manifest for CAN signal mapping
        decoder_manifest = iotfleetwise.CfnDecoderManifest(
            self, 'StandardDecoder',
            name='StandardDecoder',
            description='Decoder for standard vehicle CAN signals',
            model_manifest_arn=model_manifest.attr_arn,
            signal_decoders=[
                # Engine RPM CAN signal decoder
                iotfleetwise.CfnDecoderManifest.SignalDecodersItemsProperty(
                    fully_qualified_name='Vehicle.Engine.RPM',
                    type='CAN_SIGNAL',
                    can_signal=iotfleetwise.CfnDecoderManifest.CanSignalProperty(
                        message_id=419364097,
                        is_big_endian=False,
                        is_signed=False,
                        start_bit=24,
                        offset=0.0,
                        factor=0.25,
                        length=16,
                        name='EngineRPM'
                    )
                ),
                # Vehicle speed CAN signal decoder
                iotfleetwise.CfnDecoderManifest.SignalDecodersItemsProperty(
                    fully_qualified_name='Vehicle.Speed',
                    type='CAN_SIGNAL',
                    can_signal=iotfleetwise.CfnDecoderManifest.CanSignalProperty(
                        message_id=419364352,
                        is_big_endian=False,
                        is_signed=False,
                        start_bit=0,
                        offset=0.0,
                        factor=0.01,
                        length=16,
                        name='VehicleSpeed'
                    )
                ),
                # Engine temperature CAN signal decoder
                iotfleetwise.CfnDecoderManifest.SignalDecodersItemsProperty(
                    fully_qualified_name='Vehicle.Engine.Temperature',
                    type='CAN_SIGNAL',
                    can_signal=iotfleetwise.CfnDecoderManifest.CanSignalProperty(
                        message_id=419364608,
                        is_big_endian=False,
                        is_signed=True,
                        start_bit=8,
                        offset=-40.0,
                        factor=1.0,
                        length=8,
                        name='EngineTemperature'
                    )
                ),
                # Fuel level CAN signal decoder
                iotfleetwise.CfnDecoderManifest.SignalDecodersItemsProperty(
                    fully_qualified_name='Vehicle.FuelLevel',
                    type='CAN_SIGNAL',
                    can_signal=iotfleetwise.CfnDecoderManifest.CanSignalProperty(
                        message_id=419364864,
                        is_big_endian=False,
                        is_signed=False,
                        start_bit=16,
                        offset=0.0,
                        factor=0.39,
                        length=8,
                        name='FuelLevel'
                    )
                )
            ],
            status='ACTIVE',
            tags=[
                {
                    'key': 'Purpose',
                    'value': 'CANSignalDecoding'
                }
            ]
        )
        decoder_manifest.add_dependency(model_manifest)

        # Create vehicle fleet
        vehicle_fleet = iotfleetwise.CfnFleet(
            self, 'VehicleFleet',
            id=f'vehicle-fleet-{unique_suffix}',
            description='Production vehicle fleet for telemetry collection',
            signal_catalog_arn=signal_catalog.attr_arn,
            tags=[
                {
                    'key': 'Purpose',
                    'value': 'ProductionFleet'
                },
                {
                    'key': 'Environment',
                    'value': 'Production'
                }
            ]
        )
        vehicle_fleet.add_dependency(signal_catalog)

        # Create data collection campaign
        telemetry_campaign = iotfleetwise.CfnCampaign(
            self, 'TelemetryCampaign',
            name=f'TelemetryCampaign-{unique_suffix}',
            description='Continuous collection of vehicle telemetry data',
            signal_catalog_arn=signal_catalog.attr_arn,
            target_arn=vehicle_fleet.attr_arn,
            action='APPROVE',  # Auto-approve for deployment
            data_destination_configs=[
                iotfleetwise.CfnCampaign.DataDestinationConfigProperty(
                    timestream_config=iotfleetwise.CfnCampaign.TimestreamConfigProperty(
                        timestream_table_arn=f'arn:aws:timestream:{self.region}:{self.account}:database/{timestream_database.database_name}/table/{timestream_table.table_name}',
                        execution_role_arn=fleetwise_service_role.role_arn
                    )
                ),
                iotfleetwise.CfnCampaign.DataDestinationConfigProperty(
                    s3_config=iotfleetwise.CfnCampaign.S3ConfigProperty(
                        bucket_arn=telemetry_bucket.bucket_arn,
                        data_format='JSON',
                        prefix='telemetry-data/',
                        storage_compression_format='GZIP'
                    )
                )
            ],
            collection_scheme=iotfleetwise.CfnCampaign.CollectionSchemeProperty(
                time_based_collection_scheme=iotfleetwise.CfnCampaign.TimeBasedCollectionSchemeProperty(
                    period_ms=10000  # Collect data every 10 seconds
                )
            ),
            signals_to_collect=[
                iotfleetwise.CfnCampaign.SignalInformationProperty(
                    name='Vehicle.Engine.RPM',
                    max_sample_count=1000
                ),
                iotfleetwise.CfnCampaign.SignalInformationProperty(
                    name='Vehicle.Speed',
                    max_sample_count=1000
                ),
                iotfleetwise.CfnCampaign.SignalInformationProperty(
                    name='Vehicle.Engine.Temperature',
                    max_sample_count=1000
                ),
                iotfleetwise.CfnCampaign.SignalInformationProperty(
                    name='Vehicle.FuelLevel',
                    max_sample_count=1000
                )
            ],
            post_trigger_collection_duration=0,
            diagnostics_mode='OFF',
            spooling_mode='TO_DISK',
            compression='SNAPPY',
            tags=[
                {
                    'key': 'Purpose',
                    'value': 'TelemetryCollection'
                }
            ]
        )
        telemetry_campaign.add_dependency(vehicle_fleet)
        telemetry_campaign.add_dependency(timestream_table)
        telemetry_campaign.add_dependency(fleetwise_service_role)

        # Create Amazon Managed Grafana workspace
        grafana_workspace = grafana.CfnWorkspace(
            self, 'FleetTelemetryWorkspace',
            workspace_name=f'FleetTelemetry-{unique_suffix}',
            workspace_description='Vehicle telemetry analytics dashboards and monitoring',
            account_access_type='CURRENT_ACCOUNT',
            authentication_providers=['AWS_SSO'],
            permission_type='SERVICE_MANAGED',
            workspace_data_sources=['TIMESTREAM'],
            workspace_notification_destinations=['SNS'],
            workspace_organizational_units=[],
            tags={
                'Purpose': 'TelemetryVisualization',
                'Environment': 'Production'
            }
        )

        # Create outputs for important resource information
        CfnOutput(
            self, 'SignalCatalogArn',
            value=signal_catalog.attr_arn,
            description='ARN of the IoT FleetWise Signal Catalog'
        )

        CfnOutput(
            self, 'FleetId',
            value=vehicle_fleet.id,
            description='ID of the Vehicle Fleet'
        )

        CfnOutput(
            self, 'TimestreamDatabase',
            value=timestream_database.database_name,
            description='Name of the Timestream database'
        )

        CfnOutput(
            self, 'TimestreamTable',
            value=timestream_table.table_name,
            description='Name of the Timestream table'
        )

        CfnOutput(
            self, 'TelemetryBucket',
            value=telemetry_bucket.bucket_name,
            description='S3 bucket for telemetry data archival'
        )

        CfnOutput(
            self, 'CampaignName',
            value=telemetry_campaign.name,
            description='Name of the telemetry collection campaign'
        )

        CfnOutput(
            self, 'GrafanaWorkspaceId',
            value=grafana_workspace.attr_id,
            description='ID of the Grafana workspace'
        )

        CfnOutput(
            self, 'GrafanaWorkspaceEndpoint',
            value=grafana_workspace.attr_endpoint,
            description='Endpoint URL for the Grafana workspace'
        )

        CfnOutput(
            self, 'FleetWiseServiceRoleArn',
            value=fleetwise_service_role.role_arn,
            description='ARN of the FleetWise service role'
        )


def main():
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get environment variables for deployment
    env_region = os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
    env_account = os.getenv('CDK_DEFAULT_ACCOUNT')
    
    # Create the stack
    VehicleTelemetryAnalyticsStack(
        app, 
        'VehicleTelemetryAnalyticsStack',
        description='Real-time vehicle telemetry analytics with AWS IoT FleetWise and Timestream',
        env={
            'account': env_account,
            'region': env_region
        }
    )
    
    app.synth()


if __name__ == '__main__':
    main()