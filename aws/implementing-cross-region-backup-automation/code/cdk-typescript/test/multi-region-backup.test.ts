import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { MultiRegionBackupStack } from '../lib/multi-region-backup-stack';

describe('MultiRegionBackupStack', () => {
  test('creates backup vault with encryption', () => {
    const app = new cdk.App();
    const stack = new MultiRegionBackupStack(app, 'TestStack', {
      isPrimaryRegion: true,
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2', 
      tertiaryRegion: 'eu-west-1',
      organizationName: 'TestOrg',
      notificationEmail: 'test@example.com',
      env: { region: 'us-east-1' }
    });

    const template = Template.fromStack(stack);

    // Verify backup vault is created
    template.hasResourceProperties('AWS::Backup::BackupVault', {
      BackupVaultName: 'TestOrg-primary-vault'
    });

    // Verify KMS key is created
    template.hasResourceProperties('AWS::KMS::Key', {
      Description: 'Backup encryption key for TestOrg in us-east-1',
      EnableKeyRotation: true
    });
  });

  test('creates SNS topic for notifications', () => {
    const app = new cdk.App();
    const stack = new MultiRegionBackupStack(app, 'TestStack', {
      isPrimaryRegion: false,
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      tertiaryRegion: 'eu-west-1', 
      organizationName: 'TestOrg',
      notificationEmail: 'test@example.com',
      env: { region: 'us-west-2' }
    });

    const template = Template.fromStack(stack);

    // Verify SNS topic is created
    template.hasResourceProperties('AWS::SNS::Topic', {
      TopicName: 'backup-notifications-us-west-2'
    });

    // Verify email subscription
    template.hasResourceProperties('AWS::SNS::Subscription', {
      Protocol: 'email',
      Endpoint: 'test@example.com'
    });
  });

  test('creates backup plan only in primary region', () => {
    const app = new cdk.App();
    
    // Primary region stack should have backup plan
    const primaryStack = new MultiRegionBackupStack(app, 'PrimaryStack', {
      isPrimaryRegion: true,
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      tertiaryRegion: 'eu-west-1',
      organizationName: 'TestOrg', 
      notificationEmail: 'test@example.com',
      env: { region: 'us-east-1' }
    });

    // Secondary region stack should not have backup plan
    const secondaryStack = new MultiRegionBackupStack(app, 'SecondaryStack', {
      isPrimaryRegion: false,
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      tertiaryRegion: 'eu-west-1',
      organizationName: 'TestOrg',
      notificationEmail: 'test@example.com', 
      env: { region: 'us-west-2' }
    });

    const primaryTemplate = Template.fromStack(primaryStack);
    const secondaryTemplate = Template.fromStack(secondaryStack);

    // Primary should have backup plan
    primaryTemplate.hasResourceProperties('AWS::Backup::BackupPlan', {
      BackupPlan: {
        BackupPlanName: 'MultiRegionBackupPlan'
      }
    });

    // Secondary should not have backup plan
    secondaryTemplate.resourceCountIs('AWS::Backup::BackupPlan', 0);
  });

  test('creates Lambda validator function', () => {
    const app = new cdk.App();
    const stack = new MultiRegionBackupStack(app, 'TestStack', {
      isPrimaryRegion: true,
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      tertiaryRegion: 'eu-west-1',
      organizationName: 'TestOrg',
      notificationEmail: 'test@example.com',
      env: { region: 'us-east-1' }
    });

    const template = Template.fromStack(stack);

    // Verify Lambda function is created
    template.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'backup-validator-us-east-1',
      Runtime: 'python3.9',
      Handler: 'index.lambda_handler'
    });
  });

  test('creates EventBridge rules for monitoring', () => {
    const app = new cdk.App();
    const stack = new MultiRegionBackupStack(app, 'TestStack', {
      isPrimaryRegion: true,
      primaryRegion: 'us-east-1', 
      secondaryRegion: 'us-west-2',
      tertiaryRegion: 'eu-west-1',
      organizationName: 'TestOrg',
      notificationEmail: 'test@example.com',
      env: { region: 'us-east-1' }
    });

    const template = Template.fromStack(stack);

    // Verify EventBridge rules are created
    template.hasResourceProperties('AWS::Events::Rule', {
      Name: 'BackupJobFailureRule-us-east-1'
    });

    template.hasResourceProperties('AWS::Events::Rule', {
      Name: 'BackupJobCompletionRule-us-east-1'
    });
  });

  test('stack outputs include important ARNs', () => {
    const app = new cdk.App();
    const stack = new MultiRegionBackupStack(app, 'TestStack', {
      isPrimaryRegion: true,
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2', 
      tertiaryRegion: 'eu-west-1',
      organizationName: 'TestOrg',
      notificationEmail: 'test@example.com',
      env: { region: 'us-east-1' }
    });

    const template = Template.fromStack(stack);

    // Verify outputs are created
    template.hasOutput('BackupVaultName', {});
    template.hasOutput('BackupVaultArn', {});
    template.hasOutput('NotificationTopicArn', {});
    template.hasOutput('BackupPlanId', {});
  });
});