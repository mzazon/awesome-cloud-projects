# Conversation Agent Configuration Template
# This template file is used by Terraform to generate the agent configuration

from google.cloud import firestore
from google.cloud import storage
from google.cloud import aiplatform
import json
import datetime
import uuid
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ConversationAgent:
    """
    Advanced conversational AI agent with persistent memory using Firestore
    and integration with Vertex AI for natural language processing.
    """
    
    def __init__(self, project_id="${project_id}", region="${region}", database_id="${firestore_database}"):
        """Initialize the conversation agent with Google Cloud services."""
        self.project_id = project_id
        self.region = region
        self.bucket_name = "${bucket_name}"
        
        # Initialize Firestore client
        self.firestore_client = firestore.Client(
            project=project_id, 
            database=database_id
        )
        
        # Initialize Cloud Storage client
        self.storage_client = storage.Client(project=project_id)
        
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location=region)
        
        logger.info(f"ConversationAgent initialized for project {project_id}")
    
    def process_conversation(self, user_id, message, session_id=None):
        """
        Process user message and generate intelligent response using Vertex AI.
        
        Args:
            user_id (str): Unique identifier for the user
            message (str): User's message content
            session_id (str, optional): Session identifier for conversation tracking
            
        Returns:
            str: Generated response from the AI agent
        """
        try:
            # Generate session ID if not provided
            if not session_id:
                session_id = str(uuid.uuid4())
            
            # Retrieve conversation history from Firestore
            conversation_ref = self.firestore_client.collection('conversations').document(user_id)
            conversation_doc = conversation_ref.get()
            
            conversation_history = []
            if conversation_doc.exists:
                conversation_data = conversation_doc.to_dict()
                conversation_history = conversation_data.get('messages', [])
            
            # Add user message to history
            user_message = {
                'role': 'user',
                'content': message,
                'timestamp': datetime.datetime.now().isoformat(),
                'session_id': session_id,
                'message_id': str(uuid.uuid4())
            }
            conversation_history.append(user_message)
            
            # Generate response using Vertex AI (simplified implementation)
            response = self._generate_ai_response(message, conversation_history[-10:])
            
            # Add assistant response to history
            assistant_message = {
                'role': 'assistant',
                'content': response,
                'timestamp': datetime.datetime.now().isoformat(),
                'session_id': session_id,
                'message_id': str(uuid.uuid4())
            }
            conversation_history.append(assistant_message)
            
            # Store updated conversation in Firestore
            conversation_ref.set({
                'messages': conversation_history,
                'last_updated': datetime.datetime.now(),
                'user_id': user_id,
                'session_id': session_id,
                'message_count': len(conversation_history)
            })
            
            # Update user context
            self._update_user_context(user_id, message, response)
            
            logger.info(f"Processed conversation for user {user_id}, session {session_id}")
            return response
            
        except Exception as e:
            logger.error(f"Error processing conversation: {str(e)}")
            return "I apologize, but I'm experiencing technical difficulties. Please try again later."
    
    def _generate_ai_response(self, message, conversation_history):
        """
        Generate AI response using Vertex AI models.
        This is a simplified implementation - in production, you would use
        the full Agent Development Kit with Gemini integration.
        """
        try:
            # Build context from conversation history
            context = self._build_conversation_context(conversation_history)
            
            # Simple response generation (replace with actual ADK implementation)
            if any(greeting in message.lower() for greeting in ['hello', 'hi', 'hey']):
                return "Hello! I'm your AI assistant. How can I help you today?"
            elif 'help' in message.lower():
                return "I'm here to assist you! You can ask me questions, have a conversation, or let me help you with various tasks. What would you like to know?"
            elif any(farewell in message.lower() for farewell in ['bye', 'goodbye', 'see you']):
                return "Goodbye! Feel free to come back anytime if you need assistance."
            else:
                return f"Thank you for your message: '{message}'. I'm processing your request and learning from our conversation. How else can I assist you?"
                
        except Exception as e:
            logger.error(f"Error generating AI response: {str(e)}")
            return "I understand your message, but I'm having trouble formulating a response right now. Please try rephrasing your question."
    
    def _build_conversation_context(self, conversation_history):
        """Build conversation context for AI model input."""
        context = []
        for msg in conversation_history:
            context.append(f"{msg['role']}: {msg['content']}")
        return "\n".join(context)
    
    def _update_user_context(self, user_id, user_message, ai_response):
        """Update user context and analytics in Firestore."""
        try:
            # Update user context collection
            user_context_ref = self.firestore_client.collection('user_contexts').document(user_id)
            user_context_doc = user_context_ref.get()
            
            if user_context_doc.exists:
                # Update existing context
                user_context_ref.update({
                    'last_active': datetime.datetime.now(),
                    'total_conversations': firestore.Increment(1),
                    'last_message': user_message
                })
            else:
                # Create new user context
                user_context_ref.set({
                    'user_id': user_id,
                    'first_interaction': datetime.datetime.now(),
                    'last_active': datetime.datetime.now(),
                    'total_conversations': 1,
                    'preferences': {},
                    'conversation_topics': [],
                    'last_message': user_message
                })
            
            # Store conversation analytics
            analytics_ref = self.firestore_client.collection('conversation_analytics').document()
            analytics_ref.set({
                'user_id': user_id,
                'timestamp': datetime.datetime.now(),
                'user_message_length': len(user_message),
                'ai_response_length': len(ai_response),
                'session_timestamp': datetime.datetime.now().isoformat()
            })
            
        except Exception as e:
            logger.error(f"Error updating user context: {str(e)}")
    
    def get_user_context(self, user_id):
        """Retrieve comprehensive user context from Firestore."""
        try:
            user_context_ref = self.firestore_client.collection('user_contexts').document(user_id)
            user_context_doc = user_context_ref.get()
            
            if user_context_doc.exists:
                return user_context_doc.to_dict()
            else:
                return {
                    'user_id': user_id,
                    'total_conversations': 0,
                    'preferences': {},
                    'conversation_topics': []
                }
                
        except Exception as e:
            logger.error(f"Error retrieving user context: {str(e)}")
            return None
    
    def get_conversation_suggestions(self, user_id):
        """Generate conversation suggestions based on user context."""
        try:
            user_context = self.get_user_context(user_id)
            if not user_context:
                return ["How can I help you today?", "What would you like to know?"]
            
            suggestions = []
            total_conversations = user_context.get('total_conversations', 0)
            
            if total_conversations == 0:
                suggestions = [
                    "Welcome! How can I assist you today?",
                    "What brings you here today?",
                    "I'm here to help. What would you like to know?"
                ]
            else:
                suggestions = [
                    "How can I help you today?",
                    "Would you like to continue our previous conversation?",
                    "What new topic would you like to explore?"
                ]
            
            return suggestions
            
        except Exception as e:
            logger.error(f"Error generating suggestions: {str(e)}")
            return ["How can I help you today?"]