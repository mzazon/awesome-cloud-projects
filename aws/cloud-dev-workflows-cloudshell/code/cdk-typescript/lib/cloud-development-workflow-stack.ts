import * as cdk from 'aws-cdk-lib';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import { Construct } from 'constructs';

/**
 * Stack Properties for Cloud Development Workflow
 */
export interface CloudDevelopmentWorkflowStackProps extends cdk.StackProps {
  readonly environmentName: string;
  readonly repositoryName: string;
}

/**
 * CloudDevelopmentWorkflowStack
 * 
 * Creates infrastructure for cloud-based development workflows using
 * AWS CloudShell and CodeCommit. This stack provides:
 * 
 * - CodeCommit repository for source control
 * - IAM roles and policies for CloudShell access
 * - SNS notifications for repository events
 * - EventBridge rules for workflow automation
 * - Security configurations following AWS best practices
 */
export class CloudDevelopmentWorkflowStack extends cdk.Stack {
  public readonly repository: codecommit.Repository;
  public readonly developerRole: iam.Role;
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: CloudDevelopmentWorkflowStackProps) {
    super(scope, id, props);

    // Create CodeCommit repository for source control
    this.repository = this.createCodeCommitRepository(props);

    // Create IAM roles and policies for developers
    this.developerRole = this.createDeveloperRole(props);

    // Create SNS topic for notifications
    this.notificationTopic = this.createNotificationTopic(props);

    // Set up EventBridge rules for repository events
    this.createRepositoryEventRules(props);

    // Create CloudFormation outputs for important resources
    this.createOutputs(props);
  }

  /**
   * Creates a CodeCommit repository with proper configuration
   */
  private createCodeCommitRepository(props: CloudDevelopmentWorkflowStackProps): codecommit.Repository {
    const repository = new codecommit.Repository(this, 'DevelopmentRepository', {
      repositoryName: `${props.repositoryName}-${props.environmentName}`,
      description: `Cloud-based development workflow repository for ${props.environmentName} environment`,
      code: codecommit.Code.fromDirectory('initial-code/', 'main'), // Optional: seed with initial code
    });

    // Add repository-level tags
    cdk.Tags.of(repository).add('Component', 'SourceControl');
    cdk.Tags.of(repository).add('Purpose', 'DevelopmentWorkflow');

    return repository;
  }

  /**
   * Creates IAM role for developers with appropriate permissions
   */
  private createDeveloperRole(props: CloudDevelopmentWorkflowStackProps): iam.Role {
    // Create developer role that can be assumed by authenticated users
    const developerRole = new iam.Role(this, 'DeveloperRole', {
      roleName: `${props.repositoryName}-developer-role-${props.environmentName}`,
      description: 'Role for developers using CloudShell and CodeCommit',
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'), // CloudShell service
      maxSessionDuration: cdk.Duration.hours(12), // Maximum CloudShell session duration
    });

    // Grant CloudShell access permissions
    developerRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCloudShellFullAccess')
    );

    // Grant CodeCommit permissions for the specific repository
    const codecommitPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'codecommit:BatchGet*',
        'codecommit:BatchDescribe*',
        'codecommit:Describe*',
        'codecommit:EvaluatePullRequestApprovalRules',
        'codecommit:Get*',
        'codecommit:List*',
        'codecommit:GitPull',
        'codecommit:GitPush',
        'codecommit:CreateBranch',
        'codecommit:CreatePullRequest',
        'codecommit:CreateCommit',
        'codecommit:DeleteBranch',
        'codecommit:MergeBranchesByFastForward',
        'codecommit:MergeBranchesBySquash',
        'codecommit:MergeBranchesByThreeWay',
        'codecommit:MergePullRequestByFastForward',
        'codecommit:MergePullRequestBySquash',
        'codecommit:MergePullRequestByThreeWay',
        'codecommit:PostCommentForComparedCommit',
        'codecommit:PostCommentForPullRequest',
        'codecommit:PostCommentReply',
        'codecommit:PutCommentReaction',
        'codecommit:PutFile',
        'codecommit:UpdateComment',
        'codecommit:UpdatePullRequestApprovalRuleContent',
        'codecommit:UpdatePullRequestApprovalState',
        'codecommit:UpdatePullRequestDescription',
        'codecommit:UpdatePullRequestStatus',
        'codecommit:UpdatePullRequestTitle'
      ],
      resources: [this.repository.repositoryArn],
      conditions: {
        StringEquals: {
          'aws:RequestedRegion': this.region
        }
      }
    });

    developerRole.addToPolicy(codecommitPolicy);

    // Add Git credential helper permissions
    const gitCredentialPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'codecommit:GetRepository',
        'codecommit:ListRepositories'
      ],
      resources: ['*'], // Required for Git credential helper
      conditions: {
        StringEquals: {
          'aws:RequestedRegion': this.region
        }
      }
    });

    developerRole.addToPolicy(gitCredentialPolicy);

    // Add basic CloudWatch Logs permissions for debugging
    const logsPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogGroups',
        'logs:DescribeLogStreams'
      ],
      resources: [
        `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/cloudshell/*`
      ]
    });

    developerRole.addToPolicy(logsPolicy);

    // Tag the role
    cdk.Tags.of(developerRole).add('Component', 'IAM');
    cdk.Tags.of(developerRole).add('Purpose', 'DeveloperAccess');

    return developerRole;
  }

  /**
   * Creates SNS topic for repository notifications
   */
  private createNotificationTopic(props: CloudDevelopmentWorkflowStackProps): sns.Topic {
    const topic = new sns.Topic(this, 'RepositoryNotifications', {
      topicName: `${props.repositoryName}-notifications-${props.environmentName}`,
      displayName: `Development Workflow Notifications (${props.environmentName})`,
      description: 'Notifications for repository events and development workflow activities'
    });

    // Create a notification rule for the repository
    const notificationRule = new codecommit.CfnNotificationRule(this, 'RepositoryNotificationRule', {
      name: `${props.repositoryName}-events-${props.environmentName}`,
      detailType: 'FULL',
      eventTypeIds: [
        'codecommit-repository-commits-on-main-branch',
        'codecommit-repository-pull-request-created',
        'codecommit-repository-pull-request-source-updated',
        'codecommit-repository-pull-request-status-changed',
        'codecommit-repository-pull-request-merge-status-updated'
      ],
      resource: this.repository.repositoryArn,
      targets: [{
        targetType: 'SNS',
        targetAddress: topic.topicArn
      }],
      status: 'ENABLED',
      tags: {
        Component: 'Notifications',
        Purpose: 'DevelopmentWorkflow'
      }
    });

    // Grant the notification service permission to publish to SNS
    topic.addToResourcePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('codestar-notifications.amazonaws.com')],
      actions: ['sns:Publish'],
      resources: [topic.topicArn],
      conditions: {
        StringEquals: {
          'aws:SourceAccount': this.account
        }
      }
    }));

    // Tag the topic
    cdk.Tags.of(topic).add('Component', 'Notifications');
    cdk.Tags.of(topic).add('Purpose', 'DevelopmentWorkflow');

    return topic;
  }

  /**
   * Creates EventBridge rules for repository automation
   */
  private createRepositoryEventRules(props: CloudDevelopmentWorkflowStackProps): void {
    // Create EventBridge rule for CodeCommit state changes
    const repositoryRule = new events.Rule(this, 'RepositoryStateChangeRule', {
      ruleName: `${props.repositoryName}-state-changes-${props.environmentName}`,
      description: 'Captures CodeCommit repository state changes for workflow automation',
      eventPattern: {
        source: ['aws.codecommit'],
        detailType: ['CodeCommit Repository State Change'],
        detail: {
          repositoryName: [this.repository.repositoryName]
        }
      },
      enabled: true
    });

    // Add SNS target to the rule
    repositoryRule.addTarget(new targets.SnsTopic(this.notificationTopic, {
      message: events.RuleTargetInput.fromText(
        `Repository Event: ${events.EventField.fromPath('$.detail.event')} occurred in repository ${events.EventField.fromPath('$.detail.repositoryName')}`
      )
    }));

    // Create EventBridge rule for pull request events
    const pullRequestRule = new events.Rule(this, 'PullRequestEventRule', {
      ruleName: `${props.repositoryName}-pull-requests-${props.environmentName}`,
      description: 'Captures CodeCommit pull request events for workflow automation',
      eventPattern: {
        source: ['aws.codecommit'],
        detailType: ['CodeCommit Pull Request State Change'],
        detail: {
          repositoryName: [this.repository.repositoryName]
        }
      },
      enabled: true
    });

    // Add SNS target for pull request events
    pullRequestRule.addTarget(new targets.SnsTopic(this.notificationTopic, {
      message: events.RuleTargetInput.fromText(
        `Pull Request ${events.EventField.fromPath('$.detail.pullRequestStatus')}: ${events.EventField.fromPath('$.detail.title')} in repository ${events.EventField.fromPath('$.detail.repositoryName')}`
      )
    }));

    // Tag the rules
    cdk.Tags.of(repositoryRule).add('Component', 'EventBridge');
    cdk.Tags.of(repositoryRule).add('Purpose', 'RepositoryAutomation');
    cdk.Tags.of(pullRequestRule).add('Component', 'EventBridge');
    cdk.Tags.of(pullRequestRule).add('Purpose', 'PullRequestAutomation');
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(props: CloudDevelopmentWorkflowStackProps): void {
    // Repository information
    new cdk.CfnOutput(this, 'RepositoryName', {
      value: this.repository.repositoryName,
      description: 'Name of the CodeCommit repository',
      exportName: `${this.stackName}-RepositoryName`
    });

    new cdk.CfnOutput(this, 'RepositoryCloneUrlHttp', {
      value: this.repository.repositoryCloneUrlHttp,
      description: 'HTTPS clone URL for the CodeCommit repository',
      exportName: `${this.stackName}-RepositoryCloneUrlHttp`
    });

    new cdk.CfnOutput(this, 'RepositoryCloneUrlSsh', {
      value: this.repository.repositoryCloneUrlSsh,
      description: 'SSH clone URL for the CodeCommit repository',
      exportName: `${this.stackName}-RepositoryCloneUrlSsh`
    });

    // IAM role information
    new cdk.CfnOutput(this, 'DeveloperRoleArn', {
      value: this.developerRole.roleArn,
      description: 'ARN of the developer IAM role',
      exportName: `${this.stackName}-DeveloperRoleArn`
    });

    new cdk.CfnOutput(this, 'DeveloperRoleName', {
      value: this.developerRole.roleName,
      description: 'Name of the developer IAM role',
      exportName: `${this.stackName}-DeveloperRoleName`
    });

    // Notification topic information
    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS notification topic',
      exportName: `${this.stackName}-NotificationTopicArn`
    });

    new cdk.CfnOutput(this, 'NotificationTopicName', {
      value: this.notificationTopic.topicName,
      description: 'Name of the SNS notification topic',
      exportName: `${this.stackName}-NotificationTopicName`
    });

    // CloudShell access information
    new cdk.CfnOutput(this, 'CloudShellAccessInstructions', {
      value: `Access CloudShell from AWS Console: https://${this.region}.console.aws.amazon.com/cloudshell/home?region=${this.region}`,
      description: 'Direct link to CloudShell in this region'
    });

    // Git setup commands
    new cdk.CfnOutput(this, 'GitSetupCommands', {
      value: [
        'git config --global credential.helper "!aws codecommit credential-helper $@"',
        'git config --global credential.UseHttpPath true',
        `git clone ${this.repository.repositoryCloneUrlHttp}`
      ].join(' && '),
      description: 'Commands to configure Git for CodeCommit access'
    });
  }
}