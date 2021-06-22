variable "vpc_id" {
  description = "The ID of the VPC into which to place the instances."
  type        = string
}

variable "lb_rules" {
  description = "rules for public loadbalancer"
  type        = list
  default     = []
}

variable "vpc_cidr_block" {
  description = "The CIDR block of all private IPs in the VPC."
  type        = string
}

variable "public_instance_subnet_ids" {
  description = "A list of subnet ids into which to place the HTTP Public instances."
  type        = list
}

variable "private_subnet_ids" {
  description = "A list of private subnet IDs into which to place the databases."
  type        = list
}

variable "private_subnet_cidr_blocks" {
  description = "A list of private subnet CIDR blocks to allow traffic from the EC2 instances"
  type        = list
}

variable "environment" {
  description = "The name of the HTTP environment, e.g. 'prod'."
  type        = string
}

variable "environment_short" {
  description = "The name of the HTTP environment, e.g. 'prod'."
  type        = string
}

variable "lb_public_listener_arn" {
  description = "The ARN of the HTTP Public listener on the load balancer (typically for HTTPS)"
  type        = string
}

variable "lb_public_security_group_id" {
  description = "The ID of the Security Group for the HTTP Public load balancer (to allow traffic for health checks)"
  type        = string
}

variable "client_name" {
  description = "Client name"
  default = "cambridge"
}

variable "amazon_linux_ami" {
  description = "Amazon AMI to use"
  default = "ami-02f26adf094f51167"
}

variable "demo_cambridge_developer_ips" {
  description = "List of IP's for direct access to servers"
  type        = list
  default     = [
   "119.93.206.32/32"
  ]
}

locals {
  amazon_linux_ami = "ami-02f26adf094f51167"
  demo_cambridge_vpc_cidr = [ "10.14.0.0/16" ]
  demo_cambridge_developer_ips = [
    "119.93.206.32/32",
    "122.55.14.126/32"
  ]
}

resource "aws_default_vpc" "default" {}

resource "aws_instance" "bastion" {
  ami                         = local.amazon_linux_ami
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  security_groups             = ["${aws_security_group.bastion-sg.name}"]
  key_name                    = aws_key_pair.demo_key.key_name
  tags = {
      name                    = "bastion"
      Environment = var.environment
      deploy      = "public-${var.environment}-${var.client_name}.com"
      client      = var.client_name
  }
}

resource "aws_security_group" "bastion-sg" {
  name   = "bastion-security-group"
  vpc_id = aws_default_vpc.default.id

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = local.demo_cambridge_developer_ips
  }

  egress {
    protocol    = -1
    from_port   = 0 
    to_port     = 0 
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "http_public" {
  count                  = 2
  ami                    = var.amazon_linux_ami
  instance_type          = "t2.micro"
  subnet_id              = element(var.public_instance_subnet_ids, count.index)
  vpc_security_group_ids = [ "${aws_security_group.http_public.id}" ]
  key_name               = "demo_bastion_key"
  user_data              = data.template_file.userdata_public.rendered

  tags = {
    Name        = "${var.client_name}-http-${var.environment}-public-${count.index + 1}"
    Environment = var.environment
    deploy      = "public-${var.environment}-${var.client_name}.com"
    client      = var.client_name
  }

}

data "aws_subnet" "public_instances" {
  count = 2
  id    = element(var.public_instance_subnet_ids, count.index)
}

data "template_file" "userdata_public" {
  template = file("${path.module}/files/userdata_public.sh.tpl")

  vars = {
    authorized_keys = file("${path.module}/files/authorized_keys.sh")
  }
}

resource "aws_security_group" "http_public" {
  description = "http Public instances"
  vpc_id      = var.vpc_id
  ingress {
    description     = "Allow HTTP ingress from the load balancer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.lb_public_security_group_id]
  }

  ingress {
    description     = "Allow ingress publishing traffic from client and crescendo"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks     = var.demo_cambridge_developer_ips
  }

  ingress {
    description     = "Allow ingress publishing traffic from client and crescendo"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["${aws_instance.bastion.public_ip}/32"]
  }

  egress {
    description = "Allow HTTP egress for package updates/installation"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "${var.client_name}-http-${var.environment}-public"
    Environment = var.environment
    client      = var.client_name
  }
}

resource "aws_lb_listener_rule" "http_public" {
  count = length(var.lb_rules)
  listener_arn = var.lb_public_listener_arn
  priority  = 99

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http_public.arn
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
  condition {
    host_header {
      values = [var.lb_rules[count.index]]
    }
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

resource "aws_lb_target_group_attachment" "http_public" {
  target_group_arn = aws_lb_target_group.http_public.arn
  target_id        = aws_instance.http_public.*.id[count.index]
  count            = "2"
}

resource "aws_key_pair" "demo_key" {
  key_name   = "demo_bastion_key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDiKpSNbbhRrvMiF3svqNXwqdy6yJgPCaXgTlsQtgUC74u5ai0VvHqYenOXnkQzv30ByYf4Z3KXQjifMAUxTczK6N+11r/AW3HHdoGRvTc1LBvGcB4EON02sGnYPij71SXK0w07RbPNSRrufepFgAPgAglp3gs7FAPUp87JLbo+0im5vFlo4V0AMava4SKLk10n0TALEIqOOyvuPdKPXFo4479DikS1qLYmLSkCuTdJ479fPT0BsgzenXYCdWLmUrP4Kyfb92noo+ztIRlVF3pp0O8KrcDcQV1wm2NSUnN58/6rybNq0WQYdNlNljOCNFmuGu+auoLgZBPNrMPODPk1OihoNN7XbimncM9mxHUbjZVTtJ1505Ux9F/oFzVrdGAMAf9AQRpQtIR6jpTwPlW+WNPsO9R33aXYhTpret/Ik4SFAIo8h3NKUVAC1g0l/0aHIzmANn3ufbyc7XmTPqiB4XD1RIg60yDL3IuP9Etb0UIENtQhuHysDnYiZjiLIU= jrobes@MacBook-Pro.local"
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}