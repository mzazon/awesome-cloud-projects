# CDK Python Application for Real-Time Chat Application

This CDK Python application creates a complete infrastructure for a full-stack real-time chat application using AWS AppSync, Amazon Cognito, DynamoDB, and Lambda functions.

## Architecture Overview

The application deploys the following AWS services:

- **Amazon Cognito**: User authentication and authorization with user groups
- **AWS AppSync**: GraphQL API with real-time subscriptions
- **Amazon DynamoDB**: NoSQL database for storing chat data with GSI indexes
- **AWS Lambda**: Serverless functions for real-time operations
- **Amazon CloudWatch**: Logging and monitoring
- **AWS IAM**: Security roles and policies

## Features

- **Real-time messaging**: Live chat with WebSocket connections
- **User presence tracking**: Online/offline status indicators
- **Typing indicators**: Real-time typing notifications
- **Message reactions**: Emoji reactions to messages
- **Room management**: Create and join chat rooms
- **User authentication**: Secure login with Cognito
- **Role-based access**: Admin, Moderator, and User roles
- **Message threading**: Reply to messages
- **Notification system**: Real-time notifications

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate credentials
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Docker (for Lambda function packaging)

## Installation

1. **Clone the repository and navigate to the CDK directory:**
   ```bash
   cd aws/full-stack-real-time-applications-amplify-appsync-subscriptions/code/cdk-python/
   ```

2. **Create a virtual environment:**
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (if not already done):**
   ```bash
   cdk bootstrap
   ```

## Configuration

The application can be configured through CDK context variables in `cdk.json`:

```json
{
  "context": {
    "app_name": "realtime-app",
    "environment": "dev",
    "real-time-app-config": {
      "enable_xray": true,
      "enable_detailed_monitoring": true,
      "log_retention_days": 7
    }
  }
}
```

You can also override these values via command line:
```bash
cdk deploy -c app_name=my-chat-app -c environment=prod
```

## Deployment

### Deploy all resources:
```bash
cdk deploy
```

### Deploy with confirmation:
```bash
cdk deploy --require-approval never
```

### Deploy to specific environment:
```bash
cdk deploy -c environment=prod
```

### View deployment plan:
```bash
cdk diff
```

### Synthesize CloudFormation template:
```bash
cdk synth
```

## Stack Outputs

After deployment, the stack outputs important values:

- **GraphQLAPIId**: AppSync API ID
- **GraphQLAPIURL**: AppSync GraphQL endpoint
- **GraphQLAPIKey**: API key for public access
- **UserPoolId**: Cognito User Pool ID
- **UserPoolClientId**: Cognito User Pool Client ID
- **Region**: AWS region
- **Table names**: DynamoDB table names

## Usage

### Frontend Integration

To use this backend with a frontend application:

1. **Install AWS Amplify libraries:**
   ```bash
   npm install aws-amplify @aws-amplify/ui-react
   ```

2. **Configure Amplify with stack outputs:**
   ```javascript
   import { Amplify } from 'aws-amplify';
   
   Amplify.configure({
     Auth: {
       region: 'us-east-1',
       userPoolId: 'your-user-pool-id',
       userPoolWebClientId: 'your-user-pool-client-id'
     },
     API: {
       GraphQL: {
         endpoint: 'your-appsync-endpoint',
         region: 'us-east-1',
         defaultAuthMode: 'userPool'
       }
     }
   });
   ```

3. **Use GraphQL operations:**
   ```javascript
   import { generateClient } from 'aws-amplify/api';
   
   const client = generateClient();
   
   // Create a chat room
   const createRoom = await client.graphql({
     query: `
       mutation CreateChatRoom($input: CreateChatRoomInput!) {
         createChatRoom(input: $input) {
           id
           name
           description
         }
       }
     `,
     variables: {
       input: {
         name: "General Chat",
         description: "General discussion room"
       }
     }
   });
   
   // Subscribe to new messages
   const subscription = client.graphql({
     query: `
       subscription OnMessageCreated($chatRoomId: ID!) {
         onMessageCreated(chatRoomId: $chatRoomId) {
           id
           content
           authorName
           createdAt
         }
       }
     `,
     variables: { chatRoomId: "room-id" }
   }).subscribe({
     next: ({ data }) => {
       console.log('New message:', data.onMessageCreated);
     }
   });
   ```

## GraphQL Schema

The application uses a comprehensive GraphQL schema with the following main types:

- **ChatRoom**: Chat room entities with members and settings
- **Message**: Individual chat messages with threading support
- **Reaction**: Emoji reactions to messages
- **UserPresence**: User online/offline status
- **Notification**: System notifications
- **TypingIndicator**: Real-time typing status

### Key Operations

**Queries:**
- `listChatRooms`: Get all chat rooms
- `getChatRoom(id)`: Get specific chat room
- `messagesByRoom(chatRoomId)`: Get messages in a room
- `getUserPresence(id)`: Get user presence status

**Mutations:**
- `createChatRoom(input)`: Create new chat room
- `createMessage(input)`: Send new message
- `createReaction(input)`: Add reaction to message
- `startTyping(chatRoomId)`: Start typing indicator
- `updatePresence(status)`: Update user presence

**Subscriptions:**
- `onMessageCreated(chatRoomId)`: New messages in room
- `onUserPresenceChanged`: User presence updates
- `onTypingStarted(chatRoomId)`: Typing indicators
- `onReactionAdded(messageId)`: New reactions

## Testing

### Unit Tests
```bash
python -m pytest tests/unit/
```

### Integration Tests
```bash
python -m pytest tests/integration/
```

### End-to-End Tests
```bash
python -m pytest tests/e2e/
```

## Monitoring and Logging

The application includes comprehensive monitoring:

- **CloudWatch Logs**: All Lambda functions log to CloudWatch
- **AWS X-Ray**: Distributed tracing for AppSync and Lambda
- **CloudWatch Metrics**: Custom metrics for application performance
- **AppSync Logging**: GraphQL operation logging

### Viewing Logs
```bash
# Lambda function logs
aws logs tail /aws/lambda/realtime-app-realtime-handler-dev --follow

# AppSync logs
aws logs tail /aws/appsync/apis/your-api-id --follow
```

## Security

The application implements several security best practices:

- **IAM Roles**: Least privilege access for all services
- **Cognito Authentication**: User authentication and authorization
- **VTL Authorization**: Field-level access control in GraphQL
- **Encryption**: Data encryption at rest and in transit
- **API Keys**: Optional API key authentication
- **Rate Limiting**: Built-in AppSync rate limiting

## Cost Optimization

To optimize costs:

1. **DynamoDB**: Uses on-demand billing (pay-per-request)
2. **Lambda**: Serverless execution model
3. **AppSync**: Pay-per-request pricing
4. **CloudWatch**: Configurable log retention
5. **Cognito**: Free tier for up to 50,000 MAUs

### Estimated Monthly Costs (dev environment):
- AppSync: $5-15 (depends on requests)
- DynamoDB: $2-10 (depends on usage)
- Lambda: $1-5 (depends on executions)
- Cognito: Free (under 50k MAUs)
- CloudWatch: $1-3 (depends on logs)

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Error:**
   ```bash
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

2. **Python Dependencies:**
   ```bash
   pip install --upgrade aws-cdk-lib
   ```

3. **Schema Validation:**
   ```bash
   # Check schema.graphql syntax
   npx graphql-schema-linter schema.graphql
   ```

4. **Lambda Timeout:**
   - Check CloudWatch logs for function execution time
   - Increase timeout in CDK configuration if needed

5. **AppSync Resolver Errors:**
   - Enable field-level logging in AppSync console
   - Check CloudWatch logs for resolver execution

## Development

### Code Structure
```
├── app.py                 # Main CDK application
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration
├── schema.graphql        # GraphQL schema
├── README.md             # This file
└── tests/                # Test files
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

### Code Style

The project uses:
- **Black** for code formatting
- **Flake8** for linting
- **MyPy** for type checking
- **Pytest** for testing

Run code quality checks:
```bash
black .
flake8 .
mypy .
pytest
```

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
cdk destroy
```

This will remove all AWS resources created by the stack.

## Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS AppSync Documentation](https://docs.aws.amazon.com/appsync/)
- [AWS Amplify Documentation](https://docs.amplify.aws/)
- [GraphQL Documentation](https://graphql.org/learn/)

## License

This sample code is licensed under the MIT-0 License. See the LICENSE file.

## Support

For issues and questions:
- Check the [AWS CDK GitHub repository](https://github.com/aws/aws-cdk)
- Visit the [AWS AppSync forum](https://forums.aws.amazon.com/forum.jspa?forumID=280)
- Create an issue in this repository