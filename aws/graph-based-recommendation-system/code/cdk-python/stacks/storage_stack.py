"""
Storage Stack for Neptune Sample Data

This stack creates S3 infrastructure for storing sample graph data:
- S3 bucket for CSV files and Gremlin scripts
- Bucket policy for secure access
- Sample data files for e-commerce recommendation system
"""

from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_s3_deployment as s3_deploy,
    CfnOutput,
    RemovalPolicy,
)
from constructs import Construct


class StorageStack(Stack):
    """
    Creates S3 storage infrastructure for Neptune sample data.
    
    This stack provides secure storage for graph data files
    and sample datasets used in recommendation algorithms.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for sample data storage
        self.sample_data_bucket = s3.Bucket(
            self, "NeptuneSampleDataBucket",
            bucket_name=None,  # Auto-generated unique name
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For development - use RETAIN for production
            auto_delete_objects=True,  # For development - remove for production
            enforce_ssl=True,
        )

        # Deploy sample data files to S3 bucket
        s3_deploy.BucketDeployment(
            self, "DeploySampleData",
            sources=[
                s3_deploy.Source.data(
                    "sample-users.csv",
                    "id,name,age,city,interests\n"
                    "user1,Alice,28,Seattle,books;technology;travel\n"
                    "user2,Bob,35,Portland,sports;music;cooking\n"
                    "user3,Carol,42,Vancouver,art;books;photography\n"
                    "user4,David,31,San Francisco,technology;gaming;fitness\n"
                    "user5,Eve,26,Los Angeles,fashion;travel;music\n"
                ),
                s3_deploy.Source.data(
                    "sample-products.csv",
                    "id,name,category,price,brand,tags\n"
                    "prod1,Laptop,Electronics,999.99,TechCorp,technology;work;portable\n"
                    "prod2,Running Shoes,Sports,129.99,SportsBrand,fitness;running;comfort\n"
                    "prod3,Camera,Electronics,599.99,PhotoPro,photography;hobby;travel\n"
                    "prod4,Cookbook,Books,29.99,FoodPress,cooking;recipes;kitchen\n"
                    "prod5,Headphones,Electronics,199.99,AudioMax,music;technology;wireless\n"
                ),
                s3_deploy.Source.data(
                    "sample-purchases.csv",
                    "user_id,product_id,quantity,purchase_date,rating\n"
                    "user1,prod1,1,2024-01-15,5\n"
                    "user1,prod3,1,2024-01-20,4\n"
                    "user2,prod2,1,2024-01-18,5\n"
                    "user2,prod4,2,2024-01-25,4\n"
                    "user3,prod3,1,2024-01-22,5\n"
                    "user3,prod4,1,2024-01-28,3\n"
                    "user4,prod1,1,2024-01-30,4\n"
                    "user4,prod5,1,2024-02-02,5\n"
                    "user5,prod5,1,2024-02-05,4\n"
                ),
                s3_deploy.Source.data(
                    "load-data.groovy",
                    "// Clear existing data\n"
                    "g.V().drop().iterate()\n\n"
                    "// Create user vertices\n"
                    "g.addV('user').property('id', 'user1').property('name', 'Alice').property('age', 28).property('city', 'Seattle').next()\n"
                    "g.addV('user').property('id', 'user2').property('name', 'Bob').property('age', 35).property('city', 'Portland').next()\n"
                    "g.addV('user').property('id', 'user3').property('name', 'Carol').property('age', 42).property('city', 'Vancouver').next()\n"
                    "g.addV('user').property('id', 'user4').property('name', 'David').property('age', 31).property('city', 'San Francisco').next()\n"
                    "g.addV('user').property('id', 'user5').property('name', 'Eve').property('age', 26).property('city', 'Los Angeles').next()\n\n"
                    "// Create product vertices\n"
                    "g.addV('product').property('id', 'prod1').property('name', 'Laptop').property('category', 'Electronics').property('price', 999.99).next()\n"
                    "g.addV('product').property('id', 'prod2').property('name', 'Running Shoes').property('category', 'Sports').property('price', 129.99).next()\n"
                    "g.addV('product').property('id', 'prod3').property('name', 'Camera').property('category', 'Electronics').property('price', 599.99).next()\n"
                    "g.addV('product').property('id', 'prod4').property('name', 'Cookbook').property('category', 'Books').property('price', 29.99).next()\n"
                    "g.addV('product').property('id', 'prod5').property('name', 'Headphones').property('category', 'Electronics').property('price', 199.99).next()\n\n"
                    "// Create purchase relationships\n"
                    "g.V().has('user', 'id', 'user1').as('u').V().has('product', 'id', 'prod1').addE('purchased').from('u').property('rating', 5).property('date', '2024-01-15').next()\n"
                    "g.V().has('user', 'id', 'user1').as('u').V().has('product', 'id', 'prod3').addE('purchased').from('u').property('rating', 4).property('date', '2024-01-20').next()\n"
                    "g.V().has('user', 'id', 'user2').as('u').V().has('product', 'id', 'prod2').addE('purchased').from('u').property('rating', 5).property('date', '2024-01-18').next()\n"
                    "g.V().has('user', 'id', 'user2').as('u').V().has('product', 'id', 'prod4').addE('purchased').from('u').property('rating', 4).property('date', '2024-01-25').next()\n"
                    "g.V().has('user', 'id', 'user3').as('u').V().has('product', 'id', 'prod3').addE('purchased').from('u').property('rating', 5).property('date', '2024-01-22').next()\n"
                    "g.V().has('user', 'id', 'user3').as('u').V().has('product', 'id', 'prod4').addE('purchased').from('u').property('rating', 3).property('date', '2024-01-28').next()\n"
                    "g.V().has('user', 'id', 'user4').as('u').V().has('product', 'id', 'prod1').addE('purchased').from('u').property('rating', 4).property('date', '2024-01-30').next()\n"
                    "g.V().has('user', 'id', 'user4').as('u').V().has('product', 'id', 'prod5').addE('purchased').from('u').property('rating', 5).property('date', '2024-02-02').next()\n"
                    "g.V().has('user', 'id', 'user5').as('u').V().has('product', 'id', 'prod5').addE('purchased').from('u').property('rating', 4).property('date', '2024-02-05').next()\n\n"
                    "// Create category relationships\n"
                    "g.V().has('product', 'category', 'Electronics').as('p1').V().has('product', 'category', 'Electronics').as('p2').where(neq('p1')).addE('same_category').from('p1').to('p2').next()\n\n"
                    "// Commit the transaction\n"
                    "g.tx().commit()\n\n"
                    "println 'Data loaded successfully'\n"
                ),
                s3_deploy.Source.data(
                    "collaborative-filtering.groovy",
                    "// Collaborative Filtering: Find products purchased by similar users\n"
                    "def findSimilarUsers(userId) {\n"
                    "    return g.V().has('user', 'id', userId).\n"
                    "           out('purchased').\n"
                    "           in('purchased').\n"
                    "           where(neq(V().has('user', 'id', userId))).\n"
                    "           groupCount().\n"
                    "           order(local).by(values, desc).\n"
                    "           limit(local, 3)\n"
                    "}\n\n"
                    "def recommendProducts(userId) {\n"
                    "    // Find users who bought similar products\n"
                    "    def similarUsers = g.V().has('user', 'id', userId).\n"
                    "                      out('purchased').\n"
                    "                      in('purchased').\n"
                    "                      where(neq(V().has('user', 'id', userId))).\n"
                    "                      dedup().limit(5)\n\n"
                    "    // Get products purchased by similar users that target user hasn't bought\n"
                    "    def userProducts = g.V().has('user', 'id', userId).out('purchased').id().toSet()\n\n"
                    "    return similarUsers.\n"
                    "           out('purchased').\n"
                    "           where(not(within(userProducts))).\n"
                    "           groupCount().\n"
                    "           order(local).by(values, desc).\n"
                    "           limit(local, 3)\n"
                    "}\n\n"
                    "// Test the recommendation for user1\n"
                    "println 'Similar users for user1:'\n"
                    "findSimilarUsers('user1').each { user, count ->\n"
                    "    println \"${user.values('name').next()}: ${count} common purchases\"\n"
                    "}\n\n"
                    "println '\\nRecommendations for user1:'\n"
                    "recommendProducts('user1').each { product, score ->\n"
                    "    println \"${product.values('name').next()}: score ${score}\"\n"
                    "}\n"
                ),
                s3_deploy.Source.data(
                    "content-based.groovy",
                    "// Content-Based Filtering: Recommend based on product attributes\n"
                    "def recommendBySimilarProducts(userId) {\n"
                    "    // Get user's purchased products\n"
                    "    def userProducts = g.V().has('user', 'id', userId).out('purchased').toList()\n\n"
                    "    // Get categories of purchased products\n"
                    "    def userCategories = userProducts.collect { it.values('category').next() }.unique()\n\n"
                    "    // Find products in same categories not yet purchased\n"
                    "    def userProductIds = userProducts.collect { it.values('id').next() }.toSet()\n\n"
                    "    return g.V().has('product', 'category', within(userCategories)).\n"
                    "           where(not(has('id', within(userProductIds)))).\n"
                    "           project('name', 'category', 'price').\n"
                    "           by('name').by('category').by('price').\n"
                    "           limit(3)\n"
                    "}\n\n"
                    "// Test content-based recommendations for user2\n"
                    "println 'Content-based recommendations for user2:'\n"
                    "recommendBySimilarProducts('user2').each { recommendation ->\n"
                    "    println \"${recommendation.name} (${recommendation.category}): $${recommendation.price}\"\n"
                    "}\n"
                ),
            ],
            destination_bucket=self.sample_data_bucket,
            destination_key_prefix="sample-data/",
        )

        # Outputs
        CfnOutput(
            self, "SampleDataBucketName",
            value=self.sample_data_bucket.bucket_name,
            description="S3 bucket name for Neptune sample data",
            export_name="NeptuneSampleDataBucketName"
        )

        CfnOutput(
            self, "SampleDataBucketArn",
            value=self.sample_data_bucket.bucket_arn,
            description="S3 bucket ARN for Neptune sample data",
            export_name="NeptuneSampleDataBucketArn"
        )