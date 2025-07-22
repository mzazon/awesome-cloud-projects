AWSTemplateFormatVersion: '2010-09-09'
Description: 'Organization-wide governance and security policies'

Parameters:
  Environment:
    Type: String
    Default: 'all'
    AllowedValues: ['development', 'staging', 'production', 'all']
    Description: Environment for which policies apply
  
  OrganizationId:
    Type: String
    Description: AWS Organizations ID
  
  ComplianceLevel:
    Type: String
    Default: '${compliance_level}'
    AllowedValues: ['basic', 'standard', 'strict']
    Description: Compliance level for security policies

Mappings:
  ComplianceConfig:
    basic:
      PasswordMinLength: 8
      RequireMFA: false
      S3PublicReadBlock: true
      S3PublicWriteBlock: true
      CloudTrailLogLevel: 'ReadOnly'
      ConfigDeliveryFrequency: 'TwentyFour_Hours'
      GuardDutyFindingFrequency: 'SIX_HOURS'
    standard:
      PasswordMinLength: 12
      RequireMFA: true
      S3PublicReadBlock: true
      S3PublicWriteBlock: true
      CloudTrailLogLevel: 'All'
      ConfigDeliveryFrequency: 'TwentyFour_Hours'
      GuardDutyFindingFrequency: 'FIFTEEN_MINUTES'
    strict:
      PasswordMinLength: 16
      RequireMFA: true
      S3PublicReadBlock: true
      S3PublicWriteBlock: true
      CloudTrailLogLevel: 'All'
      ConfigDeliveryFrequency: 'Six_Hours'
      GuardDutyFindingFrequency: 'FIFTEEN_MINUTES'

Resources:
  # Organization-wide password policy
  PasswordPolicy:
    Type: AWS::IAM::AccountPasswordPolicy
    Properties:
      MinimumPasswordLength: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, PasswordMinLength]
      RequireUppercaseCharacters: ${password_policy.require_uppercase_characters}
      RequireLowercaseCharacters: ${password_policy.require_lowercase_characters}
      RequireNumbers: ${password_policy.require_numbers}
      RequireSymbols: ${password_policy.require_symbols}
      MaxPasswordAge: ${password_policy.max_password_age}
      PasswordReusePrevention: ${password_policy.password_reuse_prevention}
      HardExpiry: ${password_policy.hard_expiry}
      AllowUsersToChangePassword: ${password_policy.allow_users_to_change_password}

  # KMS key for encryption
  AuditBucketKMSKey:
    Type: AWS::KMS::Key
    Properties:
      Description: KMS key for audit bucket encryption
      KeyPolicy:
        Version: '2012-10-17'
        Statement:
          - Sid: Enable IAM User Permissions
            Effect: Allow
            Principal:
              AWS: !Sub 'arn:aws:iam::$${AWS::AccountId}:root'
            Action: 'kms:*'
            Resource: '*'
          - Sid: Allow CloudTrail to encrypt logs
            Effect: Allow
            Principal:
              Service: cloudtrail.amazonaws.com
            Action:
              - kms:Decrypt
              - kms:GenerateDataKey
            Resource: '*'
          - Sid: Allow Config to encrypt logs
            Effect: Allow
            Principal:
              Service: config.amazonaws.com
            Action:
              - kms:Decrypt
              - kms:GenerateDataKey
            Resource: '*'
      Tags:
        - Key: Purpose
          Value: AuditBucketEncryption
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: CloudFormationStackSets

  # KMS key alias
  AuditBucketKMSKeyAlias:
    Type: AWS::KMS::Alias
    Properties:
      AliasName: !Sub 'alias/audit-bucket-$${AWS::AccountId}'
      TargetKeyId: !Ref AuditBucketKMSKey

  # S3 bucket for CloudTrail logs
  AuditBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub 'org-audit-logs-$${AWS::AccountId}-$${AWS::Region}-$${OrganizationId}'
      PublicAccessBlockConfiguration:
        BlockPublicAcls: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, S3PublicReadBlock]
        BlockPublicPolicy: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, S3PublicWriteBlock]
        IgnorePublicAcls: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, S3PublicReadBlock]
        RestrictPublicBuckets: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, S3PublicWriteBlock]
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: aws:kms
              KMSMasterKeyID: !Ref AuditBucketKMSKey
      VersioningConfiguration:
        Status: ${s3_config.versioning_enabled ? "Enabled" : "Suspended"}
      LifecycleConfiguration:
        Rules:
          - Id: AuditLogLifecycle
            Status: ${s3_config.lifecycle_enabled ? "Enabled" : "Disabled"}
            ExpirationInDays: ${s3_config.log_expiration_days}
            NoncurrentVersionExpirationInDays: ${s3_config.noncurrent_version_expiration_days}
            Transitions:
              - TransitionInDays: ${s3_config.transition_to_ia_days}
                StorageClass: STANDARD_IA
              - TransitionInDays: ${s3_config.transition_to_glacier_days}
                StorageClass: GLACIER
      NotificationConfiguration:
        CloudWatchConfigurations:
          - Event: s3:ObjectCreated:*
            CloudWatchConfiguration:
              LogGroupName: !Ref AuditLogGroup
      Tags:
        - Key: Purpose
          Value: AuditLogs
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: CloudFormationStackSets

  # CloudTrail bucket policy
  AuditBucketPolicy:
    Type: AWS::S3::BucketPolicy
    Properties:
      Bucket: !Ref AuditBucket
      PolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Sid: AWSCloudTrailAclCheck
            Effect: Allow
            Principal:
              Service: cloudtrail.amazonaws.com
            Action: s3:GetBucketAcl
            Resource: !GetAtt AuditBucket.Arn
          - Sid: AWSCloudTrailWrite
            Effect: Allow
            Principal:
              Service: cloudtrail.amazonaws.com
            Action: s3:PutObject
            Resource: !Sub '$${AuditBucket.Arn}/*'
            Condition:
              StringEquals:
                's3:x-amz-acl': bucket-owner-full-control
          - Sid: AWSConfigBucketPermissionsCheck
            Effect: Allow
            Principal:
              Service: config.amazonaws.com
            Action: s3:GetBucketAcl
            Resource: !GetAtt AuditBucket.Arn
          - Sid: AWSConfigBucketDelivery
            Effect: Allow
            Principal:
              Service: config.amazonaws.com
            Action: s3:PutObject
            Resource: !Sub '$${AuditBucket.Arn}/*'
            Condition:
              StringEquals:
                's3:x-amz-acl': bucket-owner-full-control

  # CloudWatch Log Group for monitoring
  AuditLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub '/aws/cloudtrail/$${AWS::AccountId}'
      RetentionInDays: 365
      KmsKeyId: !GetAtt AuditBucketKMSKey.Arn
      Tags:
        - Key: Purpose
          Value: AuditLogs
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: CloudFormationStackSets

  # CloudTrail for auditing
  OrganizationCloudTrail:
    Type: AWS::CloudTrail::Trail
    Properties:
      TrailName: !Sub 'organization-audit-trail-$${AWS::AccountId}-$${AWS::Region}'
      S3BucketName: !Ref AuditBucket
      S3KeyPrefix: !Sub '$${cloudtrail_config.s3_key_prefix}/$${AWS::AccountId}/'
      IncludeGlobalServiceEvents: ${cloudtrail_config.include_global_service_events}
      IsMultiRegionTrail: ${cloudtrail_config.is_multi_region_trail}
      EnableLogFileValidation: ${cloudtrail_config.enable_log_file_validation}
      CloudWatchLogsLogGroupArn: !GetAtt AuditLogGroup.Arn
      CloudWatchLogsRoleArn: !GetAtt CloudTrailLogRole.Arn
      KMSKeyId: !Ref AuditBucketKMSKey
      EventSelectors:
        - ReadWriteType: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, CloudTrailLogLevel]
          IncludeManagementEvents: true
          DataResources:
            - Type: AWS::S3::Object
              Values: 
                - "arn:aws:s3:::*/*"
            - Type: AWS::Lambda::Function
              Values:
                - "arn:aws:lambda:*:*:function:*"
      InsightSelectors:
        - InsightType: ApiCallRateInsight
      Tags:
        - Key: Purpose
          Value: OrganizationAudit
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: CloudFormationStackSets

  # CloudTrail CloudWatch Logs Role
  CloudTrailLogRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: cloudtrail.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: CloudTrailLogPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - logs:CreateLogGroup
                  - logs:CreateLogStream
                  - logs:PutLogEvents
                Resource: !GetAtt AuditLogGroup.Arn

  # GuardDuty Detector
  GuardDutyDetector:
    Type: AWS::GuardDuty::Detector
    Properties:
      Enable: ${guardduty_config.enable}
      FindingPublishingFrequency: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, GuardDutyFindingFrequency]
      DataSources:
        S3Logs:
          Enable: ${guardduty_config.datasources_s3_logs_enable}
        Kubernetes:
          AuditLogs:
            Enable: ${guardduty_config.datasources_kubernetes_enable}
        MalwareProtection:
          ScanEc2InstanceWithFindings:
            EbsVolumes: ${guardduty_config.datasources_malware_protection_enable}
      Tags:
        - Key: Purpose
          Value: SecurityMonitoring
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: CloudFormationStackSets

  # S3 bucket for Config
  ConfigBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub 'org-config-logs-$${AWS::AccountId}-$${AWS::Region}-$${OrganizationId}'
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: aws:kms
              KMSMasterKeyID: !Ref AuditBucketKMSKey
      VersioningConfiguration:
        Status: ${s3_config.versioning_enabled ? "Enabled" : "Suspended"}
      LifecycleConfiguration:
        Rules:
          - Id: ConfigLogLifecycle
            Status: ${s3_config.lifecycle_enabled ? "Enabled" : "Disabled"}
            ExpirationInDays: ${s3_config.log_expiration_days}
            NoncurrentVersionExpirationInDays: ${s3_config.noncurrent_version_expiration_days}
      Tags:
        - Key: Purpose
          Value: ConfigLogs
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: CloudFormationStackSets

  # IAM Role for Config
  ConfigRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: config.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/ConfigRole
      Policies:
        - PolicyName: ConfigS3Policy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:GetBucketAcl
                  - s3:GetBucketLocation
                  - s3:ListBucket
                Resource: !GetAtt ConfigBucket.Arn
              - Effect: Allow
                Action:
                  - s3:PutObject
                  - s3:GetObject
                Resource: !Sub '$${ConfigBucket.Arn}/*'
                Condition:
                  StringEquals:
                    's3:x-amz-acl': bucket-owner-full-control
              - Effect: Allow
                Action:
                  - kms:Decrypt
                  - kms:GenerateDataKey
                Resource: !GetAtt AuditBucketKMSKey.Arn
      Tags:
        - Key: Purpose
          Value: ConfigService
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: CloudFormationStackSets

  # Config Configuration Recorder
  ConfigurationRecorder:
    Type: AWS::Config::ConfigurationRecorder
    Properties:
      Name: !Sub 'organization-config-$${AWS::AccountId}'
      RoleARN: !GetAtt ConfigRole.Arn
      RecordingGroup:
        AllSupported: ${config_configuration.enable_all_supported}
        IncludeGlobalResourceTypes: ${config_configuration.include_global_resource_types}
        ResourceTypes: []

  # Config Delivery Channel
  ConfigDeliveryChannel:
    Type: AWS::Config::DeliveryChannel
    Properties:
      Name: !Sub 'organization-config-delivery-$${AWS::AccountId}'
      S3BucketName: !Ref ConfigBucket
      S3KeyPrefix: !Sub 'config-logs/$${AWS::AccountId}/'
      ConfigSnapshotDeliveryProperties:
        DeliveryFrequency: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, ConfigDeliveryFrequency]

  # Config Rules for compliance monitoring
  RequiredTagsRule:
    Type: AWS::Config::ConfigRule
    Properties:
      ConfigRuleName: required-tags
      Description: Checks whether resources are tagged with required tags
      Source:
        Owner: AWS
        SourceIdentifier: REQUIRED_TAGS
      InputParameters: |
        {
          "tag1Key": "Environment",
          "tag2Key": "ManagedBy",
          "tag3Key": "Purpose"
        }
    DependsOn: ConfigurationRecorder

  S3BucketPublicAccessProhibitedRule:
    Type: AWS::Config::ConfigRule
    Properties:
      ConfigRuleName: s3-bucket-public-access-prohibited
      Description: Checks that S3 buckets do not allow public access
      Source:
        Owner: AWS
        SourceIdentifier: S3_BUCKET_PUBLIC_ACCESS_PROHIBITED
    DependsOn: ConfigurationRecorder

  RootAccessKeyCheckRule:
    Type: AWS::Config::ConfigRule
    Properties:
      ConfigRuleName: root-access-key-check
      Description: Checks whether the root user access key is available
      Source:
        Owner: AWS
        SourceIdentifier: ROOT_ACCESS_KEY_CHECK
    DependsOn: ConfigurationRecorder

Outputs:
  CloudTrailArn:
    Description: CloudTrail ARN
    Value: !GetAtt OrganizationCloudTrail.Arn
    Export:
      Name: !Sub '$${AWS::StackName}-CloudTrailArn'

  AuditBucketName:
    Description: Audit bucket name
    Value: !Ref AuditBucket
    Export:
      Name: !Sub '$${AWS::StackName}-AuditBucketName'

  ConfigBucketName:
    Description: Config bucket name
    Value: !Ref ConfigBucket
    Export:
      Name: !Sub '$${AWS::StackName}-ConfigBucketName'

  GuardDutyDetectorId:
    Description: GuardDuty detector ID
    Value: !Ref GuardDutyDetector
    Export:
      Name: !Sub '$${AWS::StackName}-GuardDutyDetectorId'

  ConfigRecorderName:
    Description: Config recorder name
    Value: !Ref ConfigurationRecorder
    Export:
      Name: !Sub '$${AWS::StackName}-ConfigRecorderName'

  KMSKeyId:
    Description: KMS key ID for audit bucket encryption
    Value: !Ref AuditBucketKMSKey
    Export:
      Name: !Sub '$${AWS::StackName}-KMSKeyId'

  KMSKeyArn:
    Description: KMS key ARN for audit bucket encryption
    Value: !GetAtt AuditBucketKMSKey.Arn
    Export:
      Name: !Sub '$${AWS::StackName}-KMSKeyArn'

  ComplianceLevel:
    Description: Compliance level applied
    Value: !Ref ComplianceLevel
    Export:
      Name: !Sub '$${AWS::StackName}-ComplianceLevel'

  Environment:
    Description: Environment for which policies apply
    Value: !Ref Environment
    Export:
      Name: !Sub '$${AWS::StackName}-Environment'