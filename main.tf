terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

module "s3_bucket" {
  source      = "./modules/s3"
  bucket_name = "readme-generator-output-bucket-${random_string.suffix.result}"
}

module "lambda_execution_role" {
  source             = "./modules/iam"
  role_name          = "ReadmeGeneratorLambdaExecutionRole"
  service_principals = ["lambda.amazonaws.com"]
  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
}

module "bedrock_agent_role" {
  source             = "./modules/iam"
  role_name          = "ReadmeGeneratorBedrockAgentRole"
  service_principals = ["bedrock.amazonaws.com"]
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  ]
}

output "readme_bucket_name" {
  description = "The name of the S3 bucket where README files are stored."
  value       = module.s3_bucket.bucket_id
}
data "archive_file" "repo_scanner_zip" {
  type        = "zip"
  source_dir  = "${path.root}/src/repo_scanner"
  output_path = "${path.root}/dist/repo_scanner.zip"
}

resource "aws_lambda_function" "repo_scanner_lambda" {
  function_name    = "RepoScannerTool"
  role             = module.lambda_execution_role.role_arn
  filename         = data.archive_file.repo_scanner_zip.output_path
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = 30
  source_code_hash = data.archive_file.repo_scanner_zip.output_base64sha256

  layers = ["arn:aws:lambda:us-east-1:553035198032:layer:git-lambda2:8"]
}
module "repo_scanner_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Repo_Scanner_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction             = "Your job is to use the scan_repo tool to get a file list from a public GitHub URL. You are a helpful AI assistant. When a user provides a GitHub URL, you must use the available tool to scan it."
}

resource "aws_bedrockagent_agent_action_group" "repo_scanner_action_group" {
  agent_id            = module.repo_scanner_agent.agent_id
  agent_version       = "DRAFT"
  action_group_name   = "ScanRepoAction"
  action_group_state  = "ENABLED"

  action_group_executor {
    lambda = aws_lambda_function.repo_scanner_lambda.arn
  }

  api_schema {
    payload = file("${path.root}/repo_scanner_schema.json")
  }
}

resource "aws_lambda_permission" "allow_bedrock_to_invoke_lambda" {
  statement_id  = "AllowBedrockToInvokeRepoScannerLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.repo_scanner_lambda.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = module.repo_scanner_agent.agent_arn
}