"""
Setup configuration for Auto Scaling with ALB and Target Groups CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = "CDK Python application for Auto Scaling with Load Balancers"

setup(
    name="auto-scaling-alb-cdk",
    version="1.0.0",
    description="AWS CDK Python application for auto scaling with Application Load Balancers and Target Groups",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Recipe Generator",
    author_email="engineering@example.com",
    url="https://github.com/your-org/auto-scaling-alb-cdk",
    packages=find_packages(),
    install_requires=requirements,
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Environment :: Console",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Natural Language :: English",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Clustering",
        "Topic :: System :: Distributed Computing",
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
    ],
    keywords=[
        "aws",
        "cdk",
        "auto-scaling",
        "load-balancer",
        "target-groups",
        "infrastructure",
        "cloud",
        "devops",
        "automation",
        "scaling",
        "high-availability",
    ],
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/your-org/auto-scaling-alb-cdk",
        "Tracker": "https://github.com/your-org/auto-scaling-alb-cdk/issues",
    },
    entry_points={
        "console_scripts": [
            "deploy-auto-scaling=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
    },
)