import json
import logging
import uuid
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging for debugging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def lookup_customer(customer_id: str) -> Dict[str, Any]:
    """Retrieves customer information from CRM system.
    
    Args:
        customer_id (str): Customer identifier or phone number
        
    Returns:
        Dict[str, Any]: Customer profile with account status and history
    """
    # Simulate customer database lookup
    customers = {
        "12345": {
            "name": "John Smith",
            "tier": "Premium",
            "account_status": "Active",
            "last_contact": "2025-07-10",
            "open_tickets": 1,
            "phone": "+1-555-0123",
            "email": "john.smith@email.com"
        },
        "67890": {
            "name": "Sarah Johnson", 
            "tier": "Standard",
            "account_status": "Active",
            "last_contact": "2025-07-08",
            "open_tickets": 0,
            "phone": "+1-555-0456",
            "email": "sarah.johnson@email.com"
        },
        "11111": {
            "name": "Mike Wilson",
            "tier": "Business",
            "account_status": "Suspended",
            "last_contact": "2025-07-05",
            "open_tickets": 2,
            "phone": "+1-555-0789",
            "email": "mike.wilson@business.com"
        }
    }
    
    if customer_id in customers:
        logger.info(f"Customer lookup successful for ID: {customer_id}")
        return {"status": "success", "customer": customers[customer_id]}
    else:
        logger.warning(f"Customer not found for ID: {customer_id}")
        return {"status": "error", "message": "Customer not found"}

def create_support_ticket(customer_id: str, issue_type: str, description: str, 
                         priority: str = "medium") -> Dict[str, Any]:
    """Creates a new customer support ticket.
    
    Args:
        customer_id (str): Customer identifier
        issue_type (str): Category of the issue (billing, technical, account)
        description (str): Detailed description of the customer's issue
        priority (str): Priority level (low, medium, high, urgent)
        
    Returns:
        Dict[str, Any]: Ticket creation status and ticket number
    """
    # Generate unique ticket ID
    ticket_id = f"TICK-{str(uuid.uuid4())[:8].upper()}"
    
    # Validate priority level
    valid_priorities = ["low", "medium", "high", "urgent"]
    if priority.lower() not in valid_priorities:
        priority = "medium"
    
    # Validate issue type
    valid_issue_types = ["billing", "technical", "account", "general", "complaint"]
    if issue_type.lower() not in valid_issue_types:
        issue_type = "general"
    
    ticket_data = {
        "ticket_id": ticket_id,
        "customer_id": customer_id,
        "issue_type": issue_type.lower(),
        "description": description,
        "priority": priority.lower(),
        "status": "Open",
        "created_at": datetime.now().isoformat(),
        "assigned_to": "AI Voice Agent",
        "estimated_resolution": "24-48 hours",
        "category": issue_type.title()
    }
    
    logger.info(f"Created ticket {ticket_id} for customer {customer_id} - Priority: {priority}")
    return {"status": "success", "ticket": ticket_data}

def search_knowledge_base(query: str) -> Dict[str, Any]:
    """Searches internal knowledge base for solutions.
    
    Args:
        query (str): Search query for finding relevant solutions
        
    Returns:
        Dict[str, Any]: Search results with relevant articles and solutions
    """
    # Simulate knowledge base search with more comprehensive entries
    knowledge_items = {
        "password reset": {
            "title": "Password Reset Instructions",
            "solution": "Go to login page, click 'Forgot Password', enter email, check inbox for reset link. If no email received, check spam folder or contact support.",
            "category": "Account Access",
            "article_id": "KB001",
            "last_updated": "2025-07-01"
        },
        "billing issue": {
            "title": "Billing Questions and Disputes", 
            "solution": "Review billing statement for accuracy, verify all charges, contact billing department for disputes. For payment issues, update payment method in account settings.",
            "category": "Billing",
            "article_id": "KB002",
            "last_updated": "2025-06-15"
        },
        "technical problem": {
            "title": "Technical Troubleshooting Guide",
            "solution": "Clear browser cache and cookies, disable browser extensions, try incognito/private mode, restart application. If issues persist, check system requirements.",
            "category": "Technical",
            "article_id": "KB003",
            "last_updated": "2025-06-20"
        },
        "account locked": {
            "title": "Account Lock Resolution",
            "solution": "Account locks usually occur after multiple failed login attempts. Wait 30 minutes and try again, or use password reset option. Contact support for immediate unlock.",
            "category": "Account Access",
            "article_id": "KB004",
            "last_updated": "2025-07-05"
        },
        "slow performance": {
            "title": "Performance Optimization Guide",
            "solution": "Check internet connection speed, close unnecessary applications, clear temporary files, restart device. For persistent issues, check system resource usage.",
            "category": "Performance",
            "article_id": "KB005",
            "last_updated": "2025-06-25"
        },
        "payment failed": {
            "title": "Payment Failure Resolution",
            "solution": "Verify payment method details, check account balance, ensure billing address matches bank records. Try alternative payment method or contact bank.",
            "category": "Billing", 
            "article_id": "KB006",
            "last_updated": "2025-07-08"
        }
    }
    
    # Enhanced keyword matching for demo
    query_lower = query.lower()
    matches = []
    
    for key, item in knowledge_items.items():
        # Check for keyword matches in title, solution, or category
        if (key in query_lower or 
            any(word in item['title'].lower() for word in query_lower.split()) or
            any(word in item['solution'].lower() for word in query_lower.split()) or
            any(word in item['category'].lower() for word in query_lower.split())):
            matches.append(item)
    
    if matches:
        # Return the best match (first one found)
        best_match = matches[0]
        logger.info(f"Knowledge base search successful for query: '{query}' - Found article: {best_match['article_id']}")
        return {
            "status": "success", 
            "solution": best_match,
            "additional_matches": len(matches) - 1 if len(matches) > 1 else 0
        }
    else:
        logger.warning(f"No knowledge base results found for query: '{query}'")
        return {
            "status": "not_found", 
            "message": "No relevant solutions found in knowledge base",
            "suggestion": "Please describe your issue in more detail or contact human support"
        }

def get_customer_history(customer_id: str) -> Dict[str, Any]:
    """Retrieves customer interaction history.
    
    Args:
        customer_id (str): Customer identifier
        
    Returns:
        Dict[str, Any]: Customer interaction history
    """
    # Simulate customer history lookup
    history_data = {
        "12345": [
            {"date": "2025-07-10", "type": "call", "duration": "15 min", "resolved": True, "issue": "billing question"},
            {"date": "2025-06-28", "type": "chat", "duration": "8 min", "resolved": True, "issue": "password reset"},
            {"date": "2025-06-15", "type": "email", "duration": "2 days", "resolved": True, "issue": "technical support"}
        ],
        "67890": [
            {"date": "2025-07-08", "type": "chat", "duration": "5 min", "resolved": True, "issue": "account question"}
        ],
        "11111": [
            {"date": "2025-07-05", "type": "call", "duration": "25 min", "resolved": False, "issue": "billing dispute"},
            {"date": "2025-07-01", "type": "email", "duration": "3 days", "resolved": False, "issue": "account suspension"}
        ]
    }
    
    if customer_id in history_data:
        return {"status": "success", "history": history_data[customer_id]}
    else:
        return {"status": "no_history", "message": "No interaction history found for this customer"}

# Create ADK agent with voice support functions
def create_voice_support_agent():
    """Create the ADK agent with customer service capabilities."""
    try:
        # In a real implementation, this would use the actual ADK Agent class
        # For this demo, we return a mock agent configuration
        agent_config = {
            "name": "VoiceSupportAgent",
            "instructions": """You are a helpful customer support agent with a warm, professional voice. 
            You can lookup customer information, create support tickets, and search for solutions.
            Always be empathetic and aim to resolve customer issues efficiently.
            Speak naturally and ask clarifying questions when needed.""",
            "tools": [
                {
                    "name": "lookup_customer",
                    "description": "Look up customer information by ID",
                    "function": lookup_customer
                },
                {
                    "name": "create_support_ticket", 
                    "description": "Create a new support ticket",
                    "function": create_support_ticket
                },
                {
                    "name": "search_knowledge_base",
                    "description": "Search knowledge base for solutions", 
                    "function": search_knowledge_base
                },
                {
                    "name": "get_customer_history",
                    "description": "Get customer interaction history",
                    "function": get_customer_history
                }
            ],
            "model": "${gemini_model}",
            "voice_config": {
                "voice_name": "${voice_name}",
                "language_code": "${language_code}"
            }
        }
        
        logger.info("Voice support agent configuration created successfully")
        return agent_config
        
    except Exception as e:
        logger.error(f"Error creating voice support agent: {e}")
        raise

def create_live_streaming_agent():
    """Initialize ADK agent with Gemini Live API streaming."""
    try:
        voice_support_agent = create_voice_support_agent()
        
        # In a real implementation, this would use the actual LiveAPIStreaming class
        streaming_config = {
            "agent": voice_support_agent,
            "model": "${gemini_model}",
            "voice_config": {
                "voice_name": "${voice_name}",
                "language_code": "${language_code}"
            },
            "audio_config": {
                "sample_rate": 24000,
                "encoding": "LINEAR16",
                "chunk_size": 4096
            },
            "streaming_enabled": True,
            "real_time_processing": True
        }
        
        logger.info("Live streaming agent configuration created successfully")
        return streaming_config
        
    except Exception as e:
        logger.error(f"Error creating streaming agent: {e}")
        raise

# Utility functions for voice processing
def process_voice_input(audio_data: bytes, session_id: str) -> Dict[str, Any]:
    """Process incoming voice audio data.
    
    Args:
        audio_data (bytes): Raw audio data from client
        session_id (str): Session identifier
        
    Returns:
        Dict[str, Any]: Processing results
    """
    try:
        # In a real implementation, this would process audio with Speech-to-Text
        # and then pass to the agent for processing
        return {
            "status": "processed",
            "session_id": session_id,
            "audio_length": len(audio_data),
            "processing_note": "Voice processing would be implemented here"
        }
    except Exception as e:
        logger.error(f"Error processing voice input: {e}")
        return {"status": "error", "message": str(e)}

def generate_voice_response(text_response: str, voice_config: Dict[str, Any]) -> bytes:
    """Generate voice response from text.
    
    Args:
        text_response (str): Text to convert to speech
        voice_config (Dict[str, Any]): Voice synthesis configuration
        
    Returns:
        bytes: Audio data for voice response
    """
    try:
        # In a real implementation, this would use Text-to-Speech API
        # For demo purposes, return placeholder
        logger.info(f"Generating voice response: {text_response[:50]}...")
        return b"placeholder_audio_data"
    except Exception as e:
        logger.error(f"Error generating voice response: {e}")
        return b""