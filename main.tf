terraform {
  required_providers{
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

#configure the AWS provider
provider "aws" {
  region = "us-east-1"
}

#configure aws s3 as backend
terraform {
  bakend s3 {
    bucket = "devops-interview-state-file"
    key = "network/terraform.tfstate"
    region = "us=east-1"
  }
}

#use default vpc and subnet
resource "aws_default_vpc" "ecs_vpc" {
}

resource "aws_default_subnet" "ecs_subnet_a" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "ecs_subnet_b" {
  availability_zone = "us-east-1b"
}

#creating an ECS task
resource "aws_ecs_task_definition" "ecs_task" {
  family = "my-ecs-task"
  container_definitions = jsonencode(
    [
      {
        name = "my-container"
        image = "684882368970.dkr.ecr.us-east-1.amazonaws.com/my-ecr-repo:${var.mage_tag}"
        cpu = 256
        memory = 512
        portMappings = [
          {
            containerPort = 8080
            hostPort = 8080
          }
        ]
      }
    ])
    network_mode = "awsvpc"
    requires_compatibility = ["FARGATE"]
    execution_role_arn = aws_iam_role.ecs_task_execution.arn
    memory = "512"
    cpu = "256"
}

# Define the IAM role for the ECS task
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# iam policy document
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type - "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role = "${aws_iam_role.ecs_task_execution.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Define an ECS Service
resource "aws_ecs_service" "app_service" {
  name = "my-ecs-service"
  cluster = "${aws_ecs_cluster.ecs_cluster.id}"
  task_definition = "${aws_ecs_task_definition.ecs_task.arn}"
  launch_type = "FARGATE"
  desired_count = 2
  
  load_balancer {
    target_group_arn = "${aws_lb_target_group.target_group.arn}"
    container_name = "my-container"
    container_port = 8080
  }
  
  network_configuration {
    subnets = ["${aws_default_subnet.ecs_subnet_a.id}","${aws_default_subnet.ecs_subnet_b.id}"]
    assign_public_ip = true
    security_groups = ["${aws_security_group.service_security_group.id}"]
  }
}

# Define ECS Cluster

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "my-ecs-cluster"
}

#setup load balancer
resource "aws_alb" "application_load_balancer" {
  name = "load-balancer-dev"
  load_balancer_type = "application"
  subnets = [
    "${aws_default_subnet.ecs_subnet_a.id}",
    "${aws_default_subnet.ecs_subnet_b.id}"
  ]
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

#create a service group for service
resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#create a service group for load balancer
resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #to allow all traffic
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#reate a load balacer target group
resource "aws_lb_target_group" "target_group" {
  name = "target-group"
  port = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id = "${aws_default_vpc.ecs_vpc.id}"
}

#load balancer listener
resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}"
  port = "80"
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = "${aws_lb_target_group.target_group.arn}"
  }
}

# get the application URL
output "app_url" {
  value = aws_alb.application_load_balancer.dns_name
}
