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

# -----------------------------------------------
# LAB 2: Repo Scanner
# -----------------------------------------------

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
  layers           = ["arn:aws:lambda:us-east-1:553035198032:layer:git-lambda2:8"]
}

module "repo_scanner_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Repo_Scanner_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction             = "Your job is to use the scan_repo tool to get a file list from a public GitHub URL. You are a helpful AI assistant. When a user provides a GitHub URL, you must use the available tool to scan it."
}

resource "aws_bedrockagent_agent_action_group" "repo_scanner_action_group" {
  agent_id           = module.repo_scanner_agent.agent_id
  agent_version      = "DRAFT"
  action_group_name  = "ScanRepoAction"
  action_group_state = "ENABLED"

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

# -----------------------------------------------
# ASSIGNMENT: Data Intelligence Platform
# Labs 1 and 2 Correlation
# -----------------------------------------------

data "archive_file" "repo_intelligence_scanner_zip" {
  type        = "zip"
  source_dir  = "${path.root}/src/repo_intelligence_scanner"
  output_path = "${path.root}/dist/repo_intelligence_scanner.zip"
}

resource "aws_lambda_function" "repo_intelligence_scanner_lambda" {
  function_name    = "RepoIntelligenceScannerTool"
  role             = module.lambda_execution_role.role_arn
  filename         = data.archive_file.repo_intelligence_scanner_zip.output_path
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = 60
  source_code_hash = data.archive_file.repo_intelligence_scanner_zip.output_base64sha256
  layers           = ["arn:aws:lambda:us-east-1:553035198032:layer:git-lambda2:8"]
}

module "repo_intelligence_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Repo_Intelligence_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction             = "You are a repository intelligence analyst specializing in data engineering assessment. Your job is to use the scan_repo tool to perform a deep analysis of a public GitHub repository. When a user provides a GitHub URL, scan it and provide a structured summary covering: the technology stack, data engineering relevance, project maturity assessment based on the maturity score, CI/CD and testing signals, and any detected data engineering frameworks or tools."
}

resource "aws_bedrockagent_agent_action_group" "repo_intelligence_action_group" {
  agent_id           = module.repo_intelligence_agent.agent_id
  agent_version      = "DRAFT"
  action_group_name  = "ScanRepoAction"
  action_group_state = "ENABLED"

  action_group_executor {
    lambda = aws_lambda_function.repo_intelligence_scanner_lambda.arn
  }

  api_schema {
    payload = file("${path.root}/repo_intelligence_schema.json")
  }
}

resource "aws_lambda_permission" "allow_bedrock_to_invoke_intelligence_lambda" {
  statement_id  = "AllowBedrockToInvokeIntelligenceLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.repo_intelligence_scanner_lambda.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = module.repo_intelligence_agent.agent_arn
}

output "intelligence_agent_id" {
  description = "The ID of the Repo Intelligence Agent."
  value       = module.repo_intelligence_agent.agent_id
}

# -----------------------------------------------
# LAB 3: Analytical Agents
# -----------------------------------------------

module "project_summarizer_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Project_Summarizer_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    You are an expert software developer writing a project summary for a README.md.
    Analyze the provided file list and write a confident, factual summary of the project's purpose and key components.
    **Do not use uncertain or hedging language** like 'it appears to be,' 'likely,' or 'seems to be.' State your analysis as fact.
    Your response must be only the summary paragraph.
  EOT
}

module "installation_guide_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Installation_Guide_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    You are a technical writer creating a README.md. Your ONLY job is to scan the provided list of filenames.
    If you see a common dependency file, write a '## Installation' section in Markdown.
    Your response must be concise and contain ONLY the command.
    For example, if you see 'requirements.txt', your entire response MUST be:
    ## Installation
```bash
    pip install -r requirements.txt
```
    If you do not see any recognizable dependency files, respond with an empty string.
  EOT
}

module "usage_examples_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Usage_Examples_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    You are a software developer writing a README.md. Your ONLY task is to identify the most likely entry point from a list of filenames.
    Write a '## Usage' section in Markdown showing the command to run the project.
    Your response MUST be concise and wrap the command in a bash code block.
    For example, if you see 'main.py', your entire response MUST be:
    ## Usage
```bash
    python main.py
```
  EOT
}
# -----------------------------------------------
# -----------------------------------------------
# ASSIGNMENT: Data Intelligence Analytical Agents
# Day 2 Correlation
# -----------------------------------------------

module "technology_assessment_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Technology_Assessment_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    PERSONA: You are a senior data engineer with 10 years of production pipeline experience conducting a formal technology assessment.

    GOAL: Analyze the provided JSON repository intelligence data and write a ## Technology Assessment section in Markdown.

    STRICT AUDITOR RULE: You must ONLY use the data explicitly present in the provided JSON to generate your assessment. Do NOT use your internal knowledge about common libraries or frameworks to fill in gaps. If a detail is not explicitly found in the provided JSON data, do NOT include it. If information for a subsection is missing from the data, state 'Information not found in source data' for that subsection.

    CONSTRAINTS:
    - Analyze ONLY these fields: extension_breakdown, category_breakdown, detected_de_technologies, top_level_directories.
    - Do NOT include any preamble, introduction, or conclusion outside the four required subsections.
    - Do NOT use uncertain language like 'appears to be' or 'might be'. State facts directly from the data.
    - Do NOT add any text after the final subsection.

    OUTPUT FORMAT: Your response MUST contain exactly these four subsections using ### headers. For example:

    ## Technology Assessment

    ### Primary Language and Frameworks
    Python is the dominant language with 7 .py files. No DE frameworks detected.

    ### File Composition
    - Code files: 7
    - Config files: 1
    - Data files: 1

    ### Data Engineering Relevance
    Medium relevance. The project contains data ingestion and database loading modules indicating pipeline functionality.

    ### Architecture Signals
    Top-level directories (tests, .github, source_data) indicate a pipeline-oriented project with CI/CD automation and dedicated data storage.
  EOT
}

module "maturity_assessment_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Maturity_Assessment_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    PERSONA: You are a software engineering lead evaluating project maturity for a data engineering team making an integration decision.

    GOAL: Analyze the provided JSON repository intelligence data and write a ## Maturity Assessment section in Markdown.

    STRICT AUDITOR RULE: You must ONLY use the data explicitly present in the provided JSON to generate your assessment. Do NOT use your internal knowledge about software engineering practices to fill in gaps. If a boolean field is not present in the JSON, do NOT assume its value. If information for a subsection cannot be determined from the data, state 'Information not found in source data' for that subsection.

    CONSTRAINTS:
    - Analyze ONLY these fields: project_maturity_score, maturity_out_of, has_tests, has_ci_cd_pipeline, has_documentation, category_breakdown.
    - Apply EXACTLY these thresholds: 0-1 is Prototype, 2-3 is Development, 4-5 is Production-Ready.
    - Under Strengths list ONLY items where the boolean value is explicitly true in the JSON. Do NOT infer strengths from file names or your training knowledge.
    - Under Gaps list ONLY items where the boolean value is explicitly false or absent in the JSON. Do NOT infer gaps from your training knowledge.
    - Do NOT include any preamble, introduction, or conclusion outside the three required subsections.

    OUTPUT FORMAT: Your response MUST contain exactly these three subsections using ### headers. For example:

    ## Maturity Assessment

    ### Maturity Score
    2 out of 5 - Development stage. The project has foundational infrastructure but requires significant work before production readiness.

    ### Strengths
    - Automated testing infrastructure present
    - CI/CD pipeline configured via GitHub Actions

    ### Gaps
    - No comprehensive documentation
    - Missing infrastructure-as-code configuration
    - No data quality validation framework
  EOT
}

module "integration_recommendations_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Integration_Recommendations_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    PERSONA: You are a data engineering architect responsible for evaluating third-party projects for integration into a production data platform.

    GOAL: Analyze the provided JSON repository intelligence data and write a ## Integration Recommendations section in Markdown.

    STRICT AUDITOR RULE: You must ONLY use the data explicitly present in the provided JSON to generate your recommendations. Do NOT use your internal knowledge about the project's technology stack or common practices to fill in gaps. Every recommendation in Prerequisites and Next Steps must reference a specific field or value found in the provided JSON. If a recommendation cannot be grounded in explicit evidence from the data, do NOT include it. If information for a subsection is missing, state 'Information not found in source data'.

    CONSTRAINTS:
    - Base ALL recommendations on explicit evidence from the JSON data fields. Do NOT make generic recommendations.
    - Every prerequisite must cite a specific gap found in the JSON boolean fields or category counts.
    - Next Steps must be numbered and ordered by priority with the highest priority first.
    - Do NOT include any preamble, introduction, or conclusion outside the three required subsections.
    - Do NOT add conversational text like 'I hope this helps' or 'Feel free to ask'.

    OUTPUT FORMAT: Your response MUST contain exactly these three subsections using ### headers. For example:

    ## Integration Recommendations

    ### Pipeline Integration Potential
    This project functions as an upstream data ingestion layer. It would serve as a data source component feeding structured document data to downstream analytics or serving layers.

    ### Prerequisites Before Integration
    - Add comprehensive documentation: has_documentation is false in the source data
    - Expand test coverage: only 1 test file detected in the source data scan
    - Implement configuration management to externalize database connections and file paths

    ### Recommended Next Steps
    1. Document database schema and data flow from PDF ingestion through to retrieval
    2. Add unit tests for ingest.py and load_to_db.py with minimum 80% coverage
    3. Implement structured logging and observability for production monitoring
  EOT
}

output "technology_assessment_agent_id" {
  description = "The ID of the Technology Assessment Agent."
  value       = module.technology_assessment_agent.agent_id
}

output "maturity_assessment_agent_id" {
  description = "The ID of the Maturity Assessment Agent."
  value       = module.maturity_assessment_agent.agent_id
}

output "integration_recommendations_agent_id" {
  description = "The ID of the Integration Recommendations Agent."
  value       = module.integration_recommendations_agent.agent_id
}

# -----------------------------------------------
# LAB 4: Final Compiler Agent
# -----------------------------------------------

module "final_compiler_agent" {
  source                  = "./modules/bedrock_agent"
  agent_name              = "Final_Compiler_Agent"
  agent_resource_role_arn = module.bedrock_agent_role.role_arn
  foundation_model        = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  instruction = <<-EOT
    You are a technical document compiler. Your task is to take a JSON object containing different sections of a README file and assemble them into a single Markdown document.
    Use the repository name for the main H1 header (e.g., # repository_name).
    Combine the other sections provided.
    Your output MUST be only the pure, complete Markdown document.
    Do NOT include any preamble, apologies, explanations of your process, or any conversational text.
  EOT
}

# -----------------------------------------------
# LAB 4: Orchestrator IAM and Lambda
# -----------------------------------------------

module "orchestrator_execution_role" {
  source             = "./modules/iam"
  role_name          = "ReadmeGeneratorOrchestratorExecutionRole"
  service_principals = ["lambda.amazonaws.com"]
  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
}

resource "aws_iam_policy" "orchestrator_permissions" {
  name        = "ReadmeGeneratorOrchestratorPolicy"
  description = "Allows Lambda to invoke Bedrock Agents and use the S3 bucket."

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid    = "BedrockAgentInvoke"
        Action = [
          "bedrock:InvokeAgent",
          "bedrock-agent-runtime:InvokeAgent"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Sid    = "S3BucketOperations"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:HeadObject"
        ]
        Effect   = "Allow"
        Resource = "${module.s3_bucket.bucket_arn}/*"
      }
    ]
  })

  lifecycle {
    ignore_changes = [policy]
  }
}

resource "aws_iam_role_policy_attachment" "orchestrator_permissions_attach" {
  role       = module.orchestrator_execution_role.role_name
  policy_arn = aws_iam_policy.orchestrator_permissions.arn
}

data "archive_file" "orchestrator_zip" {
  type        = "zip"
  source_dir  = "${path.root}/src/orchestrator"
  output_path = "${path.root}/dist/orchestrator.zip"
}

resource "aws_lambda_function" "orchestrator_lambda" {
  function_name    = "ReadmeGeneratorOrchestrator"
  role             = module.orchestrator_execution_role.role_arn
  filename         = data.archive_file.orchestrator_zip.output_path
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = 180
  source_code_hash = data.archive_file.orchestrator_zip.output_base64sha256

  environment {
    variables = {
      REPO_SCANNER_AGENT_ID             = module.repo_scanner_agent.agent_id
      REPO_SCANNER_AGENT_ALIAS_ID       = "TSTALIASID"
      PROJECT_SUMMARIZER_AGENT_ID       = module.project_summarizer_agent.agent_id
      PROJECT_SUMMARIZER_AGENT_ALIAS_ID = "TSTALIASID"
      INSTALLATION_GUIDE_AGENT_ID       = module.installation_guide_agent.agent_id
      INSTALLATION_GUIDE_AGENT_ALIAS_ID = "TSTALIASID"
      USAGE_EXAMPLES_AGENT_ID           = module.usage_examples_agent.agent_id
      USAGE_EXAMPLES_AGENT_ALIAS_ID     = "TSTALIASID"
      FINAL_COMPILER_AGENT_ID           = module.final_compiler_agent.agent_id
      FINAL_COMPILER_AGENT_ALIAS_ID     = "TSTALIASID"
      OUTPUT_BUCKET                     = module.s3_bucket.bucket_id
    }
  }
}

# -----------------------------------------------
# LAB 4: S3 Event Trigger
# -----------------------------------------------

resource "aws_lambda_permission" "allow_s3_to_invoke_orchestrator" {
  statement_id  = "AllowS3ToInvokeOrchestratorLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_bucket.bucket_arn
}

# -----------------------------------------------
# ASSIGNMENT: Data Intelligence Report Orchestrator
# Day 3 Correlation
# -----------------------------------------------

data "archive_file" "intelligence_orchestrator_zip" {
  type        = "zip"
  source_dir  = "${path.root}/src/intelligence_orchestrator"
  output_path = "${path.root}/dist/intelligence_orchestrator.zip"
}

resource "aws_lambda_function" "intelligence_orchestrator_lambda" {
  function_name    = "DataIntelligenceOrchestrator"
  role             = module.orchestrator_execution_role.role_arn
  filename         = data.archive_file.intelligence_orchestrator_zip.output_path
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = 300
  source_code_hash = data.archive_file.intelligence_orchestrator_zip.output_base64sha256

  environment {
    variables = {
      REPO_INTELLIGENCE_AGENT_ID                 = module.repo_intelligence_agent.agent_id
      REPO_INTELLIGENCE_AGENT_ALIAS_ID           = "TSTALIASID"
      TECHNOLOGY_ASSESSMENT_AGENT_ID             = module.technology_assessment_agent.agent_id
      TECHNOLOGY_ASSESSMENT_AGENT_ALIAS_ID       = "TSTALIASID"
      MATURITY_ASSESSMENT_AGENT_ID               = module.maturity_assessment_agent.agent_id
      MATURITY_ASSESSMENT_AGENT_ALIAS_ID         = "TSTALIASID"
      INTEGRATION_RECOMMENDATIONS_AGENT_ID       = module.integration_recommendations_agent.agent_id
      INTEGRATION_RECOMMENDATIONS_AGENT_ALIAS_ID = "TSTALIASID"
      OUTPUT_BUCKET                              = module.s3_bucket.bucket_id
    }
  }
}

resource "aws_lambda_permission" "allow_s3_to_invoke_intelligence_orchestrator" {
  statement_id  = "AllowS3ToInvokeIntelligenceOrchestrator"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.intelligence_orchestrator_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_bucket.bucket_arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = module.s3_bucket.bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.orchestrator_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "inputs/"
  }

lambda_function {
    lambda_function_arn = aws_lambda_function.intelligence_orchestrator_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "intelligence-inputs/"
  }

  depends_on = [
    aws_lambda_permission.allow_s3_to_invoke_orchestrator,
    aws_lambda_permission.allow_s3_to_invoke_intelligence_orchestrator
  ]
}

# -----------------------------------------------
# LAB 6: Remote State Backend Resources
# -----------------------------------------------

resource "random_string" "state_bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "tf-readme-generator-state-${random_string.state_bucket_suffix.result}"
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "readme-generator-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "terraform_state_bucket_name" {
  description = "The name of the S3 bucket for the Terraform state."
  value       = aws_s3_bucket.terraform_state.bucket
}
