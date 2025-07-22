import json
import boto3
from datetime import datetime, timezone
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')

def handler(event, context):
    """
    Lambda function to load sample data into DynamoDB tables
    """
    try:
        action = event.get('action', 'load_sample_data')
        
        if action == 'load_sample_data':
            return load_sample_products()
        else:
            raise ValueError(f"Unknown action: {action}")
            
    except Exception as e:
        logger.error(f"Error in data loader: {str(e)}")
        raise

def load_sample_products():
    """
    Load comprehensive sample product data into the Products table
    """
    table_name = "${products_table_name}"
    table = dynamodb.Table(table_name)
    
    # Current timestamp for consistency
    current_time = datetime.now(timezone.utc).isoformat()
    
    # Comprehensive sample product data
    sample_products = [
        {
            "productId": "prod-001",
            "name": "Wireless Bluetooth Headphones",
            "description": "Premium wireless headphones with active noise cancellation, 30-hour battery life, and superior sound quality. Perfect for music lovers and professionals who demand the best audio experience.",
            "price": 299.99,
            "category": "electronics",
            "priceRange": "HIGH",
            "inStock": True,
            "createdAt": current_time,
            "updatedAt": current_time,
            "tags": ["wireless", "bluetooth", "audio", "premium", "noise-cancellation"],
            "imageUrl": "https://example.com/images/headphones.jpg",
            "seller": "AudioTech Pro",
            "rating": 4.5,
            "reviewCount": 156,
            "sku": "WBH-001",
            "weight": "250g",
            "warranty": "2 years"
        },
        {
            "productId": "prod-002",
            "name": "Smartphone Protective Case",
            "description": "Ultra-durable protective case for smartphones with military-grade drop protection and wireless charging compatibility. Slim design that doesn't compromise on protection.",
            "price": 24.99,
            "category": "electronics",
            "priceRange": "LOW",
            "inStock": True,
            "createdAt": current_time,
            "updatedAt": current_time,
            "tags": ["protection", "mobile", "accessories", "wireless-charging"],
            "imageUrl": "https://example.com/images/phone-case.jpg",
            "seller": "ProtectMax",
            "rating": 4.2,
            "reviewCount": 89,
            "sku": "SPC-002",
            "weight": "45g",
            "warranty": "1 year"
        },
        {
            "productId": "prod-003",
            "name": "Ergonomic Office Chair",
            "description": "Professional ergonomic office chair with lumbar support, adjustable height, and breathable mesh fabric. Designed for all-day comfort and productivity.",
            "price": 449.99,
            "category": "furniture",
            "priceRange": "HIGH",
            "inStock": True,
            "createdAt": current_time,
            "updatedAt": current_time,
            "tags": ["office", "ergonomic", "comfort", "productivity", "adjustable"],
            "imageUrl": "https://example.com/images/office-chair.jpg",
            "seller": "ErgoWork",
            "rating": 4.7,
            "reviewCount": 234,
            "sku": "EOC-003",
            "weight": "22kg",
            "warranty": "5 years"
        },
        {
            "productId": "prod-004",
            "name": "Stainless Steel Water Bottle",
            "description": "Double-wall insulated stainless steel water bottle that keeps drinks cold for 24 hours or hot for 12 hours. BPA-free and environmentally friendly.",
            "price": 29.99,
            "category": "lifestyle",
            "priceRange": "LOW",
            "inStock": True,
            "createdAt": current_time,
            "updatedAt": current_time,
            "tags": ["water-bottle", "insulated", "eco-friendly", "stainless-steel"],
            "imageUrl": "https://example.com/images/water-bottle.jpg",
            "seller": "HydroLife",
            "rating": 4.3,
            "reviewCount": 67,
            "sku": "SWB-004",
            "weight": "350g",
            "warranty": "lifetime"
        },
        {
            "productId": "prod-005",
            "name": "Gaming Mechanical Keyboard",
            "description": "RGB backlit mechanical gaming keyboard with customizable keys, anti-ghosting technology, and programmable macros. Built for competitive gaming.",
            "price": 159.99,
            "category": "electronics",
            "priceRange": "MEDIUM",
            "inStock": True,
            "createdAt": current_time,
            "updatedAt": current_time,
            "tags": ["gaming", "mechanical", "rgb", "keyboard", "programmable"],
            "imageUrl": "https://example.com/images/gaming-keyboard.jpg",
            "seller": "GameTech",
            "rating": 4.6,
            "reviewCount": 142,
            "sku": "GMK-005",
            "weight": "1.2kg",
            "warranty": "2 years"
        },
        {
            "productId": "prod-006",
            "name": "Yoga Exercise Mat",
            "description": "Non-slip premium yoga mat made from eco-friendly TPE material. Extra thick for joint protection with alignment lines for proper positioning.",
            "price": 39.99,
            "category": "fitness",
            "priceRange": "LOW",
            "inStock": True,
            "createdAt": current_time,
            "updatedAt": current_time,
            "tags": ["yoga", "exercise", "fitness", "eco-friendly", "non-slip"],
            "imageUrl": "https://example.com/images/yoga-mat.jpg",
            "seller": "ZenFit",
            "rating": 4.4,
            "reviewCount": 98,
            "sku": "YEM-006",
            "weight": "1kg",
            "warranty": "1 year"
        },
        {
            "productId": "prod-007",
            "name": "Smart Fitness Watch",
            "description": "Advanced fitness tracker with heart rate monitoring, GPS, sleep tracking, and 50+ workout modes. Waterproof design with 7-day battery life.",
            "price": 249.99,
            "category": "electronics",
            "priceRange": "MEDIUM",
            "inStock": False,
            "createdAt": current_time,
            "updatedAt": current_time,
            "tags": ["smartwatch", "fitness", "gps", "heart-rate", "waterproof"],
            "imageUrl": "https://example.com/images/fitness-watch.jpg",
            "seller": "FitTech",
            "rating": 4.1,
            "reviewCount": 203,
            "sku": "SFW-007",
            "weight": "65g",
            "warranty": "2 years"
        },
        {
            "productId": "prod-008",
            "name": "Coffee Maker with Grinder",
            "description": "Automatic drip coffee maker with built-in burr grinder, programmable brewing, and thermal carafe. Makes perfect coffee from bean to cup.",
            "price": 199.99,
            "category": "appliances",
            "priceRange": "MEDIUM",
            "inStock": True,
            "createdAt": current_time,
            "updatedAt": current_time,
            "tags": ["coffee", "grinder", "automatic", "programmable", "thermal"],
            "imageUrl": "https://example.com/images/coffee-maker.jpg",
            "seller": "BrewMaster",
            "rating": 4.5,
            "reviewCount": 187,
            "sku": "CMG-008",
            "weight": "6.5kg",
            "warranty": "3 years"
        },
        {
            "productId": "prod-009",
            "name": "LED Desk Lamp",
            "description": "Adjustable LED desk lamp with touch controls, multiple brightness levels, and USB charging port. Eye-caring technology reduces eye strain.",
            "price": 79.99,
            "category": "lighting",
            "priceRange": "MEDIUM",
            "inStock": True,
            "createdAt": current_time,
            "updatedAt": current_time,
            "tags": ["led", "desk-lamp", "adjustable", "usb-charging", "eye-care"],
            "imageUrl": "https://example.com/images/desk-lamp.jpg",
            "seller": "LuminaTech",
            "rating": 4.3,
            "reviewCount": 124,
            "sku": "LDL-009",
            "weight": "1.5kg",
            "warranty": "2 years"
        },
        {
            "productId": "prod-010",
            "name": "Wireless Phone Charger",
            "description": "Fast wireless charging pad compatible with all Qi-enabled devices. Anti-slip design with LED indicator and overcharge protection.",
            "price": 19.99,
            "category": "electronics",
            "priceRange": "LOW",
            "inStock": True,
            "createdAt": current_time,
            "updatedAt": current_time,
            "tags": ["wireless-charging", "qi-compatible", "fast-charging", "led-indicator"],
            "imageUrl": "https://example.com/images/wireless-charger.jpg",
            "seller": "ChargeTech",
            "rating": 4.0,
            "reviewCount": 76,
            "sku": "WPC-010",
            "weight": "200g",
            "warranty": "1 year"
        }
    ]
    
    # Batch write items to DynamoDB
    try:
        with table.batch_writer() as batch:
            for product in sample_products:
                batch.put_item(Item=product)
                logger.info(f"Added product: {product['productId']} - {product['name']}")
        
        logger.info(f"Successfully loaded {len(sample_products)} sample products")
        
        return {
            'statusCode': 200,
            'body': {
                'message': f'Successfully loaded {len(sample_products)} sample products',
                'products_loaded': len(sample_products),
                'table_name': table_name
            }
        }
        
    except Exception as e:
        logger.error(f"Error loading sample data: {str(e)}")
        raise