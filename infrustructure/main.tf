terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.tag_prefix}_MainVPC"
  }
}

## Public subnets
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.tag_prefix}_InternetGateway"
  }
}

resource "aws_subnet" "public" {
  count = 3

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 3}.0/24"
  availability_zone       = element(["eu-north-1a", "eu-north-1b", "eu-north-1c"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.tag_prefix}_Web_${element(["a", "b", "c"], count.index)}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.tag_prefix}_Web_Route_Table"
  }
}

resource "aws_route_table_association" "web" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

## Private subnets
resource "aws_subnet" "private" {
  count = 3

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = element(["eu-north-1a", "eu-north-1b", "eu-north-1c"], count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.tag_prefix}_Data_${element(["a", "b", "c"], count.index)}"
  }
}

# Security Groups
resource "aws_security_group" "web_lb_sg" {
  name        = "${local.tag_prefix}_Web_LB_SG"
  description = "Allow Internet inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${local.tag_prefix}_Web_LB_SG"
  }
}

resource "aws_security_group" "web_sg" {
  name        = "${local.tag_prefix}_Web_SG"
  description = "Allow Load Balancer inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web_lb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${local.tag_prefix}_Web_SG"
  }
}

resource "aws_security_group" "data_sg" {
  name        = "${local.tag_prefix}_Data_SG"
  description = "Allow Web Instances inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  tags = {
    Name = "${local.tag_prefix}_Data_SG"
  }
}

# S3
resource "aws_s3_bucket" "main" {
  bucket = "todo-list-terraform"

  tags = {
    Name = "TodoListBucket"
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id
}

resource "aws_s3_bucket_policy" "allow_lb_logs" {
  bucket = aws_s3_bucket.main.id
  policy = data.aws_iam_policy_document.allow_read_write.json
}

data "aws_iam_policy_document" "allow_read_write" {
  statement {

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      aws_s3_bucket.main.arn,
      "${aws_s3_bucket.main.arn}/*",
    ]
  }
}

# Application Load Balancer (ALB)
resource "aws_lb" "main" {
  name               = "MainALB"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_lb_sg.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  access_logs {
    enabled = false
    bucket  = aws_s3_bucket.main.id
    prefix  = "main-lb-access-logs"
  }

  depends_on = [
    aws_s3_bucket_policy.allow_lb_logs
  ]
}

## Target Group
resource "aws_lb_target_group" "main" {
  name     = "MainTargetGroup"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    path                = "/health"
    protocol            = "HTTP"
    port                = 80
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
  }
}

## Listeners and rules (Application Load Balancer (ALB) -> Target Group)
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# Launch template
resource "aws_launch_template" "main" {
  name            = "${local.tag_prefix}_Web_Server_Template"
  default_version = 1
  image_id        = "ami-0989fb15ce71ba39e" # Replace with your desired AMI ID
  instance_type   = "t3.micro"

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  key_name = "EC2 Tutorial"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_s3_rds_instance_profile.name
  }
  user_data = filebase64("${path.module}/instance-user-data.sh")

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.tag_prefix}_Web_Server_Template"
    }
  }
}
## EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2_s3_rds_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_s3_rds_role.name
}

## IAM role for EC2 instance (RDS and S3 access)
resource "aws_iam_role" "ec2_s3_rds_role" {
  name = "ec2_role"

  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "rds_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
  role       = aws_iam_role.ec2_s3_rds_role.name
}

resource "aws_iam_role_policy_attachment" "s3_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.ec2_s3_rds_role.name
}

### Trust relationship policy
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "main" {
  name                      = "${local.tag_prefix}_Auto_Scaling_Group"
  desired_capacity          = 2
  min_size                  = 1
  max_size                  = 4
  health_check_type         = "EC2"
  health_check_grace_period = 300
  force_delete              = true
  vpc_zone_identifier       = aws_subnet.public[*].id

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.main.arn]
  depends_on        = [aws_lb.main]
}

# RDS
resource "aws_db_instance" "my_rds_instance" {
  identifier = "myrdsinstance"

  allocated_storage = 20
  storage_type      = "gp2"

  db_name = "postgres"

  engine         = "postgres"
  engine_version = "15.3"
  instance_class = "db.t3.micro"

  username = "dbuser"
  password = "dbpassword"

  db_subnet_group_name = aws_db_subnet_group.main.id

  publicly_accessible = false
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_security_group.data_sg.id]

  tags = {
    Name = "MyRDSInstance"
  }
}

## DB Subnet group
resource "aws_db_subnet_group" "main" {
  name       = "main"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "My DB subnet group"
  }
}

# Lambda (name=FrontEnd)
resource "aws_lambda_function" "front_end" {
  function_name = "FrontEnd"

  s3_bucket = aws_s3_bucket.main.id
  s3_key    = aws_s3_object.front_end.key

  runtime = "nodejs14.x"
  handler = "hello.handler"

  source_code_hash = data.archive_file.front_end.output_base64sha256

  role = aws_iam_role.lambda_execution_role.arn
}

## Upload Lambda code
data "archive_file" "front_end" {
  type = "zip"

  source_dir  = "${path.module}/../todo-list-front"
  output_path = "${path.module}/todo-list-front.zip"
}

resource "aws_s3_object" "front_end" {
  bucket = aws_s3_bucket.main.id

  key    = "front-end.zip"
  source = data.archive_file.front_end.output_path

  etag = filemd5(data.archive_file.front_end.output_path)
}

## Resource-based policy
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.front_end.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

## IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_execution_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

### Trust relationship policy
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "main" {
  name          = "Main_HTTP_APIGW"
  protocol_type = "HTTP"
}

## Stages
resource "aws_apigatewayv2_stage" "dev" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "dev"
  auto_deploy = true
}

resource "aws_apigatewayv2_stage" "test" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "test"
  auto_deploy = true
}

## Front end integration (Lambda)
resource "aws_apigatewayv2_integration" "front_end" {
  api_id = aws_apigatewayv2_api.main.id

  integration_uri    = aws_lambda_function.front_end.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "front_end" {
  api_id = aws_apigatewayv2_api.main.id

  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.front_end.id}"
}

## Back end integration (Load balancer)
resource "aws_apigatewayv2_vpc_link" "example" {
  name               = "example"
  security_group_ids = [aws_security_group.web_lb_sg.id]
  subnet_ids         = aws_subnet.public[*].id

  tags = {
    Usage = "example"
  }
}

resource "aws_apigatewayv2_integration" "back_end" {
  api_id = aws_apigatewayv2_api.main.id

  integration_uri    = aws_lb_listener.web.arn
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"

  connection_type = "VPC_LINK"
  connection_id   = aws_apigatewayv2_vpc_link.example.id

  request_parameters = {
    "overwrite:path" = "$request.path"
  }
}

resource "aws_apigatewayv2_route" "back_end" {
  api_id = aws_apigatewayv2_api.main.id

  route_key = "ANY /api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.back_end.id}"
}

# TODO: Route53, Cloudfront?