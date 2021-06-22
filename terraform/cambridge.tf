module "demo_cambridge_vpc_zone" {
  source             = "terraform-aws-modules/vpc/aws"
  name               = "demo-${var.demo_cambridge_life-cycle}"
  cidr               = local.demo_cambridge_vpc_cidr
  azs                = ["ap-southeast-1a", "ap-southeast-1b"]
  private_subnets    = local.demo_cambridge_private_subnet_cidr_blocks
  public_subnets     = local.demo_cambridge_public_subnet_cidr_blocks
  enable_nat_gateway = true
  tags = {
    Environment = var.demo_cambridge_life-cycle
    client      = var.demo_cambridge_client_name
  }
}

locals {
  demo_cambridge_developer_ips = ["119.93.206.32/32","122.55.14.126/32"]
  demo_cambridge_amazon_linux_ami = "ami-02f26adf094f51167"
  demo_cambridge_public_subnet_cidr_blocks  = ["10.14.101.0/24","10.14.102.0/24"]
  demo_cambridge_private_subnet_cidr_blocks = ["10.14.1.0/24","10.14.2.0/24"]
  demo_cambridge_vpc_cidr_block             = ["10.14.0.0/16"]
  demo_cambridge_vpc_cidr                   = "10.14.0.0/16"
  demo_cambridge_public_instance_subnets = [
    module.demo_cambridge_vpc_zone.public_subnets[0],
    module.demo_cambridge_vpc_zone.public_subnets[1],
  ]
  demo_cambridge_account_ids = {
    elb_ap_southeast_1 = "074666906807"
  }
}

resource "aws_s3_bucket" "demo_cambridge_logs" {
  bucket = "${var.demo_cambridge_client_name}-${var.demo_cambridge_life-cycle}-logs"
  acl    = "private"

  lifecycle_rule {
    enabled = true

    expiration {
      days = 2
    }
  }

  tags = {
    Name = "${var.demo_cambridge_client_name} Cambridge Logs"
    Environment = var.demo_cambridge_life-cycle
    client = var.demo_cambridge_client_name
  }
}

resource "aws_s3_bucket_policy" "demo_cambridge_write_logs" {
  bucket = aws_s3_bucket.demo_cambridge_logs.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:PutObject"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::${aws_s3_bucket.demo_cambridge_logs.id}/*",
      "Principal": {
        "AWS": [
          "${local.demo_cambridge_account_ids["elb_ap_southeast_1"]}"
        ]
      }
    }
  ]
}
EOF
}

module "demo_cambridge_public_alb" {
  source                         = "./modules/alb"
  lb_subnet_ids                  = module.demo_cambridge_vpc_zone.public_subnets
  logging_bucket_id              = aws_s3_bucket.demo_cambridge_logs.id
  environment                    = var.demo_cambridge_life-cycle
  client_name                    = var.demo_cambridge_client_name
  lb_type                        = "public"
  lb_security_group_ids          = [ "${aws_security_group.demo_cambridge_public_load_balancer.id}" ]
  logging_key_prefix             = "cambridge-${var.demo_cambridge_life-cycle}"
  vpc_id                         = module.demo_cambridge_vpc_zone.vpc_id
  application_subnet_cidr_blocks = local.demo_cambridge_public_subnet_cidr_blocks
}

resource "aws_security_group" "demo_cambridge_public_load_balancer" {
  description = "Demo load balancer"
  vpc_id      = module.demo_cambridge_vpc_zone.vpc_id

  ingress {
    description = "Allow inbound HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.demo_cambridge_developer_ips
  }

  egress {
    description = "Allow outbound HTTP to any private IP in the VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.demo_cambridge_vpc_cidr_block
  }

  tags = {
    Name        = "lb-${var.demo_cambridge_life-cycle}-${var.demo_cambridge_client_name}"
    Environment = var.demo_cambridge_life-cycle
    client = var.demo_cambridge_client_name
  }
}

module "demo_cambridge_http" {
  source                     = "./modules/cambridge_http"
  vpc_id                     = module.demo_cambridge_vpc_zone.vpc_id
  public_instance_subnet_ids = local.demo_cambridge_public_instance_subnets
  private_subnet_ids         = module.demo_cambridge_vpc_zone.private_subnets
  vpc_cidr_block             = local.demo_cambridge_vpc_cidr
  private_subnet_cidr_blocks = local.demo_cambridge_private_subnet_cidr_blocks
  environment                = var.demo_cambridge_life-cycle
  environment_short          = var.demo_cambridge_life-cycle_short
  client_name                = var.demo_cambridge_client_name
  demo_cambridge_developer_ips  = local.demo_cambridge_developer_ips
  amazon_linux_ami           = local.demo_cambridge_amazon_linux_ami
  lb_public_listener_arn      = module.demo_cambridge_public_alb.lb_listener_http_arn
  lb_public_security_group_id = aws_security_group.demo_cambridge_public_load_balancer.id
}


