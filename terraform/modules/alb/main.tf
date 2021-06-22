variable "lb_subnet_ids" {
  description = "A list of subnet IDs to attach to the LB."
  type        = list
}

variable "logging_bucket_id" {
  description = "The ID of the bucket to which we should deliver LB access logs."
}

variable "logging_key_prefix" {
  description = "The prefix for keys in the S3 bucket for LB access logs."
}

variable "vpc_id" {
  description = "The ID of the VPC in which the load balancer will be deployed."
}

variable "application_subnet_cidr_blocks" {
  description = "A list of subnet CIDR blocks to which the LB will allow HTTP traffic.  (Used to control the security group for outbound traffic from the LB.)"
  type        = list
}

variable "environment" {
  description = "The environment for the ALB: prod, uat, etc."
}

variable "client_name" {
  description = "Client name"
  default = "cambridge"
}


variable "lb_type" {
  description = "App type of loadbalancer"
  default = "public"
}


variable "lb_security_group_ids" {
  description = "List of SGs to apply to LB"
  type        = list
}

resource "aws_lb" "alb" {
  name                             = "${var.client_name}-${var.lb_type}-${var.environment}"
  internal                         = false
  load_balancer_type               = "application"
  enable_cross_zone_load_balancing = true

  subnets = var.lb_subnet_ids

  security_groups = var.lb_security_group_ids

  access_logs {
    bucket = var.logging_bucket_id
    prefix = var.logging_key_prefix
  }

  tags = {
    client      = var.client_name
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http_public.arn
  }
}
  
resource "aws_lb_target_group" "http_public" {
  name                 = "${var.client_name}-http-${var.environment}-public"
  port                 = "80"
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    interval            = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 4
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Environment = var.environment
    client      = var.client_name
  }
}

# resource "aws_lb_target_group_attachment" "http_public" {
#   target_group_arn = aws_lb_target_group.http_public.arn
#   target_id        = aws_instance.http_public.*.id[count.index]
#   count            = "2"
# }

resource "aws_security_group" "lb" {
  vpc_id = var.vpc_id

  ingress {
    description = "Allow inbound HTTP from everywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow HTTP to application subnets"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"

    cidr_blocks = var.application_subnet_cidr_blocks
  }

  tags = {
    Name = "${var.client_name}-${var.environment}-lb"
    client      = var.client_name
  }
}

output "lb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.alb.dns_name
}

output "lb_security_group_id" {
  description = "The ID of the security group for the load balancer (so application servers can receive traffic)"
  value       = aws_security_group.lb.id
}

output "lb_listener_http_arn" {
  value = aws_lb_listener.http.arn
}

output "lb_arn" {
  value = aws_lb.alb.arn
}
