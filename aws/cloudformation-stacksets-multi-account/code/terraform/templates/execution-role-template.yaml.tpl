AWSTemplateFormatVersion: '2010-09-09'
Description: 'StackSet execution role for target accounts'

Parameters:
  AdministratorAccountId:
    Type: String
    Description: AWS account ID of the StackSet administrator account
    Default: '${administrator_account_id}'

Resources:
  ExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: AWSCloudFormationStackSetExecutionRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: !Sub 'arn:aws:iam::$${AdministratorAccountId}:role/AWSCloudFormationStackSetAdministrator'
            Action: sts:AssumeRole
      Path: /
      Policies:
        - PolicyName: StackSetExecutionPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: '*'
                Resource: '*'
      Tags:
        - Key: Purpose
          Value: StackSetExecution
        - Key: ManagedBy
          Value: CloudFormationStackSets
        - Key: CreatedBy
          Value: Terraform

Outputs:
  ExecutionRoleArn:
    Description: ARN of the execution role
    Value: !GetAtt ExecutionRole.Arn
    Export:
      Name: !Sub '$${AWS::StackName}-ExecutionRoleArn'
  
  ExecutionRoleName:
    Description: Name of the execution role
    Value: !Ref ExecutionRole
    Export:
      Name: !Sub '$${AWS::StackName}-ExecutionRoleName'