"""Configuration settings for BDA Resume Parser."""

import os

# AWS Configuration
AWS_REGION = os.getenv('AWS_REGION', 'ap-south-1')
AWS_PROFILE = os.getenv('AWS_PROFILE', 'default')

# S3 Configuration
S3_BUCKET = os.getenv('BDA_S3_BUCKET', 'bda-resume-parser-ap-south-1')
S3_INPUT_PREFIX = 'resumes/input/'
S3_OUTPUT_PREFIX = 'resumes/output/'

# BDA Configuration
PROJECT_NAME = 'resume-parser-project'
BLUEPRINT_NAME = 'resume-extraction-blueprint'

# Processing Configuration
SUPPORTED_FORMATS = ['.pdf', '.doc', '.docx', '.png', '.jpg', '.jpeg']
MAX_FILE_SIZE_MB = 10

# Output Configuration
OUTPUT_FORMAT = 'json'
INCLUDE_CONFIDENCE_SCORES = True
