# Logs de Lambda
# trivy:ignore:AVD-AWS-0017 - On garde uniquement le chiffrement natif AWS
resource "aws_cloudwatch_log_group" "ar_cw_suricata" {
  name              = "/secops/suricata/eve"
  
  # inutile de garder plus dans notre cas de figure
  retention_in_days = 14 

  tags = {
    Name = "ar-suricata-logs"
  }
}

# Code de la fonction
data "archive_file" "ar_lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# Roles
resource "aws_iam_role" "ar_lambda_exec_role" {
  name = "ar-lambda-secops-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ar_lambda_logs" {
  role       = aws_iam_role.ar_lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Autorise la Lambda à lire et modifier les règles des NACLs
resource "aws_iam_role_policy" "ar_lambda_nacl_policy" {
  name = "ar-lambda-nacl-policy"
  role = aws_iam_role.ar_lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkAclEntry",
          "ec2:DescribeNetworkAcls"
        ]
        Resource = "*"
      }
    ]
  })
}

# Fonction Lambda
resource "aws_lambda_function" "ar_secops_lambda" {
  filename      = data.archive_file.ar_lambda_zip.output_path
  function_name = "ar-secops-alert-processor"
  role          = aws_iam_role.ar_lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 10 # secondes

  source_code_hash = data.archive_file.ar_lambda_zip.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  # Injection de ID de NACL
  environment {
    variables = {
      NACL_ID = aws_network_acl.ar_nacl_public.id 
      NIDS_IP = aws_instance.ar_ec2_nids.private_ip
      VICT_IP_PUBL = aws_instance.ar_ec2_victim.private_ip
      VICT_IP_PRIV = aws_instance.ar_ec2_victim.public_ip
    }
  }
}

# Bridge de CW -> Lambda
resource "aws_lambda_permission" "ar_allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ar_secops_lambda.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.ar_cw_suricata.arn}:*"
}

# Filtre
resource "aws_cloudwatch_log_subscription_filter" "ar_cw_to_lambda" {
  name            = "ar-suricata-alert-filter"
  log_group_name  = aws_cloudwatch_log_group.ar_cw_suricata.name
  destination_arn = aws_lambda_function.ar_secops_lambda.arn
  
  # Déclenchement uniquement pour les alertes
  filter_pattern  = "{ $.event_type = \"alert\" }"

  depends_on = [aws_lambda_permission.ar_allow_cloudwatch]
}