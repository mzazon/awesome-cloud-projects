"""
Firestore Data Initialization Function

This Cloud Function initializes sample data in Firestore for the email template
generator. It creates default user preferences and campaign type configurations
that serve as the foundation for AI-powered email generation.

Author: Cloud Recipe Generator
Version: 1.0
"""

import os
import logging
from typing import Dict, Any
from google.cloud import firestore
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Firestore client with specific database
DATABASE_ID = "${database_id}"
db = firestore.Client(database=DATABASE_ID)


@functions_framework.http
def initialize_data(request):
    """
    Initialize sample data in Firestore for email template generation.
    
    This function creates:
    - Default user preferences with company and brand information
    - Campaign type configurations for different email types
    - Sample templates for demonstration purposes
    """
    try:
        logger.info("Starting Firestore data initialization")
        
        # Initialize user preferences
        _create_user_preferences()
        
        # Initialize campaign types
        _create_campaign_types()
        
        # Initialize sample templates (optional)
        _create_sample_templates()
        
        logger.info("Successfully initialized all sample data")
        
        return {
            "success": True,
            "message": "Sample data initialized successfully",
            "collections_created": [
                "userPreferences",
                "campaignTypes", 
                "generatedTemplates"
            ]
        }, 200
        
    except Exception as e:
        logger.error(f"Error initializing data: {str(e)}", exc_info=True)
        return {
            "success": False,
            "error": f"Data initialization failed: {str(e)}"
        }, 500


def _create_user_preferences() -> None:
    """Create default user preferences in Firestore."""
    try:
        # Sample user preferences for TechStart Solutions
        user_prefs = {
            "company": "TechStart Solutions",
            "industry": "Software",
            "tone": "professional yet friendly",
            "primaryColor": "#2196F3",
            "targetAudience": "B2B technology decision makers",
            "brandVoice": "innovative, trustworthy, solution-focused",
            "websiteUrl": "https://techstartsolutions.com",
            "headquarters": "San Francisco, CA",
            "foundedYear": 2020,
            "employeeCount": "50-100",
            "specialties": [
                "Cloud Solutions",
                "AI/ML Integration", 
                "Digital Transformation",
                "SaaS Development"
            ],
            "valuePropositions": [
                "Cutting-edge technology solutions",
                "Rapid deployment and scaling",
                "24/7 expert support",
                "Cost-effective innovation"
            ],
            "created_at": firestore.SERVER_TIMESTAMP,
            "updated_at": firestore.SERVER_TIMESTAMP
        }
        
        # Set default user preferences
        db.collection('userPreferences').document('default').set(user_prefs)
        logger.info("Created default user preferences")
        
        # Create additional user preference templates
        _create_additional_user_profiles()
        
    except Exception as e:
        logger.error(f"Error creating user preferences: {str(e)}")
        raise


def _create_additional_user_profiles() -> None:
    """Create additional user preference profiles for different use cases."""
    profiles = {
        "startup": {
            "company": "InnovateCorp",
            "industry": "Technology Startup",
            "tone": "energetic and innovative",
            "primaryColor": "#FF5722",
            "targetAudience": "Early adopters and investors",
            "brandVoice": "bold, disruptive, visionary",
            "created_at": firestore.SERVER_TIMESTAMP
        },
        "enterprise": {
            "company": "Global Enterprise Inc",
            "industry": "Enterprise Software",
            "tone": "formal and authoritative",
            "primaryColor": "#1976D2",
            "targetAudience": "C-level executives and IT decision makers",
            "brandVoice": "reliable, experienced, comprehensive",
            "created_at": firestore.SERVER_TIMESTAMP
        },
        "nonprofit": {
            "company": "Community Impact Foundation",
            "industry": "Non-profit",
            "tone": "warm and inspiring",
            "primaryColor": "#4CAF50",
            "targetAudience": "Donors and volunteers",
            "brandVoice": "compassionate, transparent, mission-driven",
            "created_at": firestore.SERVER_TIMESTAMP
        }
    }
    
    for profile_name, profile_data in profiles.items():
        db.collection('userPreferences').document(profile_name).set(profile_data)
        logger.info(f"Created user profile: {profile_name}")


def _create_campaign_types() -> None:
    """Create campaign type configurations in Firestore."""
    try:
        campaign_types = {
            "newsletter": {
                "purpose": "weekly company updates and industry insights",
                "cta": "Read More",
                "length": "medium",
                "frequency": "weekly",
                "typical_sections": [
                    "Company news",
                    "Industry insights", 
                    "Product updates",
                    "Team highlights"
                ],
                "best_practices": [
                    "Keep subject line under 50 characters",
                    "Include 2-3 main topics maximum",
                    "Add clear unsubscribe link",
                    "Use engaging visuals"
                ],
                "created_at": firestore.SERVER_TIMESTAMP
            },
            "product_launch": {
                "purpose": "introduce new features and capabilities",
                "cta": "Learn More",
                "length": "long",
                "frequency": "as-needed",
                "typical_sections": [
                    "Product announcement",
                    "Key features and benefits",
                    "Customer testimonials",
                    "Getting started guide"
                ],
                "best_practices": [
                    "Lead with the main benefit",
                    "Include social proof",
                    "Provide clear next steps",
                    "Create urgency when appropriate"
                ],
                "created_at": firestore.SERVER_TIMESTAMP
            },
            "welcome": {
                "purpose": "onboard new subscribers",
                "cta": "Get Started",
                "length": "short",
                "frequency": "triggered",
                "typical_sections": [
                    "Welcome message",
                    "What to expect",
                    "Quick start guide",
                    "Contact information"
                ],
                "best_practices": [
                    "Send immediately after signup",
                    "Set clear expectations",
                    "Provide immediate value",
                    "Make it personal"
                ],
                "created_at": firestore.SERVER_TIMESTAMP
            },
            "promotional": {
                "purpose": "promote special offers and deals",
                "cta": "Shop Now",
                "length": "medium",
                "frequency": "campaign-based",
                "typical_sections": [
                    "Offer headline",
                    "Product showcase",
                    "Discount details",
                    "Limited time notice"
                ],
                "best_practices": [
                    "Create sense of urgency",
                    "Highlight savings clearly",
                    "Use compelling visuals",
                    "Include expiration date"
                ],
                "created_at": firestore.SERVER_TIMESTAMP
            },
            "follow_up": {
                "purpose": "re-engage inactive subscribers",
                "cta": "Reconnect",
                "length": "short",
                "frequency": "triggered",
                "typical_sections": [
                    "We miss you message",
                    "Recent updates",
                    "Special comeback offer",
                    "Preference center link"
                ],
                "best_practices": [
                    "Acknowledge the gap",
                    "Provide value immediately",
                    "Offer preference options",
                    "Make it easy to re-engage"
                ],
                "created_at": firestore.SERVER_TIMESTAMP
            },
            "event_invitation": {
                "purpose": "invite to webinars, conferences, and events",
                "cta": "Register Now",
                "length": "medium",
                "frequency": "event-based",
                "typical_sections": [
                    "Event announcement",
                    "Agenda highlights",
                    "Speaker information",
                    "Registration details"
                ],
                "best_practices": [
                    "Highlight key speakers",
                    "Show clear value proposition",
                    "Include date and time prominently",
                    "Offer calendar integration"
                ],
                "created_at": firestore.SERVER_TIMESTAMP
            }
        }
        
        # Initialize campaign types
        for campaign_type, config in campaign_types.items():
            db.collection('campaignTypes').document(campaign_type).set(config)
            logger.info(f"Created campaign type: {campaign_type}")
            
    except Exception as e:
        logger.error(f"Error creating campaign types: {str(e)}")
        raise


def _create_sample_templates() -> None:
    """Create sample generated templates for demonstration."""
    try:
        sample_templates = [
            {
                "campaign_type": "newsletter",
                "subject_theme": "monthly product updates",
                "subject_line": "Exciting New Features This Month - TechStart",
                "email_body": """Hello [First Name],

We hope you're having a fantastic month! We're excited to share some incredible updates from the TechStart Solutions team.

This month, we've launched three game-changing features that our customers have been requesting. Our new AI-powered analytics dashboard gives you real-time insights into your business performance, while our enhanced security protocols ensure your data stays protected.

We'd love to show you how these updates can transform your workflow and boost your productivity.

Best regards,
The TechStart Solutions Team""",
                "generated_at": firestore.SERVER_TIMESTAMP,
                "model_used": "gemini-1.5-flash",
                "is_sample": True
            },
            {
                "campaign_type": "welcome",
                "subject_theme": "welcome new users",
                "subject_line": "Welcome to TechStart Solutions!",
                "email_body": """Hello [First Name],

Welcome to the TechStart Solutions family! We're thrilled to have you on board.

Over the next few days, you'll receive helpful guides to get you started with our platform. Our team is here to support you every step of the way.

Ready to begin? Click below to access your dashboard and start exploring.

Welcome aboard!
The TechStart Solutions Team""",
                "generated_at": firestore.SERVER_TIMESTAMP,
                "model_used": "gemini-1.5-flash", 
                "is_sample": True
            }
        ]
        
        for template in sample_templates:
            db.collection('generatedTemplates').add(template)
            
        logger.info(f"Created {len(sample_templates)} sample templates")
        
    except Exception as e:
        logger.error(f"Error creating sample templates: {str(e)}")
        # Don't raise - sample templates are optional