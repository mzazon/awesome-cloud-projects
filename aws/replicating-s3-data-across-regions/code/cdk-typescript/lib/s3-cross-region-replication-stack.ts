import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the S3 Cross-Region Replication Stack
 */
export interface S3CrossRegionReplicationStackProps extends cdk.StackProps {
  /**
   * Whether this stack is deployed in the primary region
   */
  readonly isPrimaryRegion: boolean;

  /**
   * The primary region for the source bucket
   */
  readonly primaryRegion: string;

  /**
   * The secondary region for the destination bucket
   */
  readonly secondaryRegion: string;

  /**
   * Project name for resource naming
   */
  readonly projectName: string;

  /**
   * ARN of the source bucket (required for secondary region stack)
   */
  readonly sourceBucketArn?: string;

  /**
   * ARN of the source KMS key (required for secondary region stack)
   */
  readonly sourceKmsKeyArn?: string;
}

/**
 * AWS CDK Stack for S3 Cross-Region Replication with Encryption and Access Controls
 * 
 * This stack creates the infrastructure for secure cross-region replication of S3 objects
 * including KMS encryption, IAM roles, and CloudWatch monitoring.
 */
export class S3CrossRegionReplicationStack extends cdk.Stack {
  /**
   * The source S3 bucket (only created in primary region)
   */
  public readonly sourceBucket?: s3.Bucket;

  /**
   * The destination S3 bucket (only created in secondary region)
   */
  public readonly destinationBucket?: s3.Bucket;

  /**
   * The source KMS key (only created in primary region)
   */
  public readonly sourceKmsKey?: kms.Key;

  /**
   * The destination KMS key (only created in secondary region)
   */
  public readonly destinationKmsKey?: kms.Key;

  /**
   * The replication IAM role (only created in primary region)
   */
  public readonly replicationRole?: iam.Role;

  /**
   * ARN of the source bucket for cross-stack references
   */
  public readonly sourceBucketArn: string;

  /**
   * ARN of the source KMS key for cross-stack references
   */
  public readonly sourceKmsKeyArn: string;

  constructor(scope: Construct, id: string, props: S3CrossRegionReplicationStackProps) {
    super(scope, id, props);

    const { isPrimaryRegion, primaryRegion, secondaryRegion, projectName } = props;

    if (isPrimaryRegion) {
      // Primary region resources
      this.createPrimaryRegionResources(projectName, primaryRegion, secondaryRegion);
    } else {
      // Secondary region resources
      this.createSecondaryRegionResources(
        projectName,
        primaryRegion,
        secondaryRegion,
        props.sourceBucketArn!,
        props.sourceKmsKeyArn!
      );
    }
  }

  /**
   * Create resources in the primary region (source bucket, source KMS key, replication role)
   */
  private createPrimaryRegionResources(
    projectName: string,
    primaryRegion: string,
    secondaryRegion: string
  ): void {
    // Create KMS key for source bucket encryption
    this.sourceKmsKey = new kms.Key(this, 'SourceKmsKey', {
      description: `S3 Cross-Region Replication Source Key - ${projectName}`,
      enableKeyRotation: true,
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'EnableIAMUserPermissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'AllowS3Service',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('s3.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:CreateGrant',
              'kms:DescribeKey',
            ],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create alias for source KMS key
    new kms.Alias(this, 'SourceKmsKeyAlias', {
      aliasName: `alias/s3-crr-source-${projectName.toLowerCase()}`,
      targetKey: this.sourceKmsKey,
    });

    // Create source S3 bucket with versioning and encryption
    this.sourceBucket = new s3.Bucket(this, 'SourceBucket', {
      bucketName: `crr-source-${projectName.toLowerCase()}-${cdk.Aws.ACCOUNT_ID}`,
      versioned: true,
      encryptionKey: this.sourceKmsKey,
      encryption: s3.BucketEncryption.KMS,
      bucketKeyEnabled: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
    });

    // Create replication role
    this.replicationRole = new iam.Role(this, 'ReplicationRole', {
      roleName: `S3ReplicationRole-${projectName}`,
      assumedBy: new iam.ServicePrincipal('s3.amazonaws.com'),
      description: 'S3 Cross-Region Replication Role',
    });

    // Add permissions to replication role
    this.replicationRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'GetObjectPermissions',
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObjectVersion',
          's3:GetObjectVersionAcl',
          's3:GetObjectVersionForReplication',
          's3:GetObjectVersionTagging',
        ],
        resources: [`${this.sourceBucket.bucketArn}/*`],
      })
    );

    this.replicationRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'ListBucketPermissions',
        effect: iam.Effect.ALLOW,
        actions: ['s3:ListBucket', 's3:GetBucketVersioning'],
        resources: [this.sourceBucket.bucketArn],
      })
    );

    this.replicationRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'ReplicateObjectPermissions',
        effect: iam.Effect.ALLOW,
        actions: [
          's3:ReplicateObject',
          's3:ReplicateDelete',
          's3:ReplicateTags',
        ],
        resources: [`arn:aws:s3:::crr-dest-${projectName.toLowerCase()}-${cdk.Aws.ACCOUNT_ID}/*`],
      })
    );

    this.replicationRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'KMSDecryptPermissions',
        effect: iam.Effect.ALLOW,
        actions: ['kms:Decrypt'],
        resources: [this.sourceKmsKey.keyArn],
      })
    );

    this.replicationRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'KMSEncryptPermissions',
        effect: iam.Effect.ALLOW,
        actions: ['kms:GenerateDataKey'],
        resources: [
          `arn:aws:kms:${secondaryRegion}:${cdk.Aws.ACCOUNT_ID}:key/*`,
        ],
      })
    );

    // Add bucket policy to enforce encryption and secure transport
    this.sourceBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'DenyUnencryptedObjectUploads',
        effect: iam.Effect.DENY,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:PutObject'],
        resources: [`${this.sourceBucket.bucketArn}/*`],
        conditions: {
          StringNotEquals: {
            's3:x-amz-server-side-encryption': 'aws:kms',
          },
        },
      })
    );

    this.sourceBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'DenyInsecureConnections',
        effect: iam.Effect.DENY,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:*'],
        resources: [
          this.sourceBucket.bucketArn,
          `${this.sourceBucket.bucketArn}/*`,
        ],
        conditions: {
          Bool: {
            'aws:SecureTransport': 'false',
          },
        },
      })
    );

    // Create CloudWatch alarm for replication failures
    new cloudwatch.Alarm(this, 'ReplicationFailureAlarm', {
      alarmName: `S3-Replication-Failures-${this.sourceBucket.bucketName}`,
      alarmDescription: 'Alert when S3 replication fails',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/S3',
        metricName: 'ReplicationLatency',
        dimensionsMap: {
          SourceBucket: this.sourceBucket.bucketName,
          DestinationBucket: `crr-dest-${projectName.toLowerCase()}-${cdk.Aws.ACCOUNT_ID}`,
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 900, // 15 minutes
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    // Export values for cross-stack references
    this.sourceBucketArn = this.sourceBucket.bucketArn;
    this.sourceKmsKeyArn = this.sourceKmsKey.keyArn;

    // Create CloudFormation outputs
    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: this.sourceBucket.bucketName,
      description: 'Name of the source S3 bucket',
      exportName: `${this.stackName}-SourceBucketName`,
    });

    new cdk.CfnOutput(this, 'SourceBucketArn', {
      value: this.sourceBucket.bucketArn,
      description: 'ARN of the source S3 bucket',
      exportName: `${this.stackName}-SourceBucketArn`,
    });

    new cdk.CfnOutput(this, 'SourceKmsKeyId', {
      value: this.sourceKmsKey.keyId,
      description: 'ID of the source KMS key',
      exportName: `${this.stackName}-SourceKmsKeyId`,
    });

    new cdk.CfnOutput(this, 'SourceKmsKeyArn', {
      value: this.sourceKmsKey.keyArn,
      description: 'ARN of the source KMS key',
      exportName: `${this.stackName}-SourceKmsKeyArn`,
    });

    new cdk.CfnOutput(this, 'ReplicationRoleArn', {
      value: this.replicationRole.roleArn,
      description: 'ARN of the replication IAM role',
      exportName: `${this.stackName}-ReplicationRoleArn`,
    });
  }

  /**
   * Create resources in the secondary region (destination bucket, destination KMS key)
   */
  private createSecondaryRegionResources(
    projectName: string,
    primaryRegion: string,
    secondaryRegion: string,
    sourceBucketArn: string,
    sourceKmsKeyArn: string
  ): void {
    // Create KMS key for destination bucket encryption
    this.destinationKmsKey = new kms.Key(this, 'DestinationKmsKey', {
      description: `S3 Cross-Region Replication Destination Key - ${projectName}`,
      enableKeyRotation: true,
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'EnableIAMUserPermissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'AllowS3Service',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('s3.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:CreateGrant',
              'kms:DescribeKey',
            ],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'AllowReplicationRole',
            effect: iam.Effect.ALLOW,
            principals: [
              new iam.ArnPrincipal(`arn:aws:iam::${cdk.Aws.ACCOUNT_ID}:role/S3ReplicationRole-${projectName}`),
            ],
            actions: ['kms:GenerateDataKey'],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create alias for destination KMS key
    new kms.Alias(this, 'DestinationKmsKeyAlias', {
      aliasName: `alias/s3-crr-dest-${projectName.toLowerCase()}`,
      targetKey: this.destinationKmsKey,
    });

    // Create destination S3 bucket with versioning and encryption
    this.destinationBucket = new s3.Bucket(this, 'DestinationBucket', {
      bucketName: `crr-dest-${projectName.toLowerCase()}-${cdk.Aws.ACCOUNT_ID}`,
      versioned: true,
      encryptionKey: this.destinationKmsKey,
      encryption: s3.BucketEncryption.KMS,
      bucketKeyEnabled: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
    });

    // Add bucket policy to enforce secure transport and allow replication
    this.destinationBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'DenyInsecureConnections',
        effect: iam.Effect.DENY,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:*'],
        resources: [
          this.destinationBucket.bucketArn,
          `${this.destinationBucket.bucketArn}/*`,
        ],
        conditions: {
          Bool: {
            'aws:SecureTransport': 'false',
          },
        },
      })
    );

    this.destinationBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowReplicationRole',
        effect: iam.Effect.ALLOW,
        principals: [
          new iam.ArnPrincipal(`arn:aws:iam::${cdk.Aws.ACCOUNT_ID}:role/S3ReplicationRole-${projectName}`),
        ],
        actions: [
          's3:ReplicateObject',
          's3:ReplicateDelete',
          's3:ReplicateTags',
        ],
        resources: [`${this.destinationBucket.bucketArn}/*`],
      })
    );

    // Configure cross-region replication on the source bucket
    // Note: This is done via custom resource since CDK doesn't have direct support
    // for cross-region replication configuration
    const replicationConfig = new cdk.CustomResource(this, 'ReplicationConfiguration', {
      serviceToken: this.createReplicationConfigProvider().serviceToken,
      properties: {
        SourceBucketArn: sourceBucketArn,
        DestinationBucketArn: this.destinationBucket.bucketArn,
        DestinationKmsKeyArn: this.destinationKmsKey.keyArn,
        ReplicationRoleArn: `arn:aws:iam::${cdk.Aws.ACCOUNT_ID}:role/S3ReplicationRole-${projectName}`,
        ProjectName: projectName,
      },
    });

    // Set values for cross-stack references
    this.sourceBucketArn = sourceBucketArn;
    this.sourceKmsKeyArn = sourceKmsKeyArn;

    // Create CloudFormation outputs
    new cdk.CfnOutput(this, 'DestinationBucketName', {
      value: this.destinationBucket.bucketName,
      description: 'Name of the destination S3 bucket',
      exportName: `${this.stackName}-DestinationBucketName`,
    });

    new cdk.CfnOutput(this, 'DestinationBucketArn', {
      value: this.destinationBucket.bucketArn,
      description: 'ARN of the destination S3 bucket',
      exportName: `${this.stackName}-DestinationBucketArn`,
    });

    new cdk.CfnOutput(this, 'DestinationKmsKeyId', {
      value: this.destinationKmsKey.keyId,
      description: 'ID of the destination KMS key',
      exportName: `${this.stackName}-DestinationKmsKeyId`,
    });

    new cdk.CfnOutput(this, 'DestinationKmsKeyArn', {
      value: this.destinationKmsKey.keyArn,
      description: 'ARN of the destination KMS key',
      exportName: `${this.stackName}-DestinationKmsKeyArn`,
    });
  }

  /**
   * Create a Lambda-backed custom resource provider for S3 replication configuration
   */
  private createReplicationConfigProvider(): cdk.Provider {
    // Lambda function to configure S3 replication
    const replicationConfigLambda = new cdk.aws_lambda.Function(this, 'ReplicationConfigLambda', {
      runtime: cdk.aws_lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      timeout: cdk.Duration.minutes(5),
      code: cdk.aws_lambda.Code.fromInline(`
import boto3
import json
import logging
import urllib3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Custom resource handler for S3 cross-region replication configuration
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Parse the request
        request_type = event['RequestType']
        properties = event['ResourceProperties']
        
        source_bucket_arn = properties['SourceBucketArn']
        destination_bucket_arn = properties['DestinationBucketArn']
        destination_kms_key_arn = properties['DestinationKmsKeyArn']
        replication_role_arn = properties['ReplicationRoleArn']
        project_name = properties['ProjectName']
        
        # Extract bucket names from ARNs
        source_bucket_name = source_bucket_arn.split(':')[-1]
        destination_bucket_name = destination_bucket_arn.split(':')[-1]
        
        # Create S3 client for the primary region
        s3_client = boto3.client('s3', region_name='${primaryRegion}')
        
        if request_type in ['Create', 'Update']:
            # Configure replication
            replication_config = {
                'Role': replication_role_arn,
                'Rules': [
                    {
                        'ID': 'ReplicateEncryptedObjects',
                        'Status': 'Enabled',
                        'Priority': 1,
                        'DeleteMarkerReplication': {
                            'Status': 'Enabled'
                        },
                        'Filter': {
                            'Prefix': ''
                        },
                        'Destination': {
                            'Bucket': destination_bucket_arn,
                            'StorageClass': 'STANDARD_IA',
                            'EncryptionConfiguration': {
                                'ReplicaKmsKeyID': destination_kms_key_arn
                            }
                        },
                        'SourceSelectionCriteria': {
                            'SseKmsEncryptedObjects': {
                                'Status': 'Enabled'
                            }
                        }
                    }
                ]
            }
            
            logger.info(f"Configuring replication for bucket: {source_bucket_name}")
            s3_client.put_bucket_replication(
                Bucket=source_bucket_name,
                ReplicationConfiguration=replication_config
            )
            
            logger.info("Replication configuration applied successfully")
            
        elif request_type == 'Delete':
            try:
                logger.info(f"Removing replication configuration from bucket: {source_bucket_name}")
                s3_client.delete_bucket_replication(Bucket=source_bucket_name)
                logger.info("Replication configuration removed successfully")
            except Exception as e:
                logger.warning(f"Failed to remove replication configuration: {str(e)}")
                # Don't fail the deletion if replication config removal fails
        
        # Send success response
        send_response(event, context, 'SUCCESS', {
            'SourceBucket': source_bucket_name,
            'DestinationBucket': destination_bucket_name
        })
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        send_response(event, context, 'FAILED', {'Error': str(e)})

def send_response(event, context, status, data):
    """Send response to CloudFormation"""
    response_body = {
        'Status': status,
        'Reason': f'See CloudWatch Log Stream: {context.log_stream_name}',
        'PhysicalResourceId': f"replication-config-{event['ResourceProperties']['ProjectName']}",
        'StackId': event['StackId'],
        'RequestId': event['RequestId'],
        'LogicalResourceId': event['LogicalResourceId'],
        'Data': data
    }
    
    logger.info(f"Sending response: {json.dumps(response_body)}")
    
    http = urllib3.PoolManager()
    response = http.request(
        'PUT',
        event['ResponseURL'],
        body=json.dumps(response_body).encode('utf-8'),
        headers={'Content-Type': 'application/json'}
    )
    
    logger.info(f"Response status: {response.status}")
`),
    });

    // Grant permissions to the Lambda function
    replicationConfigLambda.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:PutBucketReplication',
          's3:DeleteBucketReplication',
          's3:GetBucketReplication',
        ],
        resources: ['*'],
      })
    );

    // Create the custom resource provider
    return new cdk.Provider(this, 'ReplicationConfigProvider', {
      onEventHandler: replicationConfigLambda,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });
  }
}