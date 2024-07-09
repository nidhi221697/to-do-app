terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "jenkins-project-backend-raife1"
    key = "backend/tf-backend-jenkins.tfstate"
    region = "ap-south-1"
  }
}

provider "aws" {
  region = "ap-south-1"
}

variable "tags" {
  default = ["postgresql", "nodejs", "react"]
}

variable "user" {
  default = "raife"
}

resource "aws_instance" "managed_nodes" {
  ami = "ami-04f8d7ed2f1a54b14"
  count = 3
  instance_type = "t2.micro"
  key_name = "terraform"  # change with your pem file
  vpc_security_group_ids = [aws_security_group.tf-sec-gr.id]
  iam_instance_profile = "jenkins-project-profile-${var.user}" # we created this with jenkins server
  tags = {
    Name = "ansible_${element(var.tags, count.index )}"
    stack = "ansible_project"
    environment = "development"
  }
  user_data = <<-EOF
            #! /bin/bash
            dnf update -y
            EOF
}

resource "aws_security_group" "tf-sec-gr" {
  name = "project208-sec-gr-${var.user}"
  tags = {
    Name = "project208-sec-gr"
  }

  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 5000
    protocol    = "tcp"
    to_port     = 5000
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    protocol    = "tcp"
    to_port     = 3000
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 5432
    protocol    = "tcp"
    to_port     = 5432
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    protocol    = -1
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "react_ip" {
  value = "http://${aws_instance.managed_nodes[2].public_ip}:3000"
}

output "node_public_ip" {
  value = aws_instance.managed_nodes[1].public_ip
}

output "postgre_private_ip" {
  value = aws_instance.managed_nodes[0].private_ip
}
resource "aws_lb" "alb" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_tls.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_deletion_protection = false

  tags = {
    Environment = "test"
  }
}

//Target Group
resource "aws_lb_target_group" "albtg" {
  name     = "tf-example-lb-tg"
  port     = 80
  protocol = "HTTP"
  target_type = "instance"
  vpc_id   = aws_vpc.main.id

  health_check {    
    healthy_threshold   = 3    
    unhealthy_threshold = 10    
    timeout             = 5    
    interval            = 10    
    path                = "/"    
    port                = 80  
  }
}

resource "aws_lb_target_group_attachment" "front_end" {
  target_group_arn = aws_lb_target_group.albtg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
  count = 2
}

//Listener
resource "aws_lb_listener" "albl" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.albtg.arn
  }
}
