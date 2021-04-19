### Athenticate
provider "aws" {
    region = "us-east-1"
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
    # access_key = ${env.TF_VAR_ak}
    # secret_key = ${env.TF_VAR_sk}
}

### Variables currently stored in .tfvars file
variable "aws_access_key" {
  description = "AWS Access Key"
  type = "string"
}

variable "aws_secret_key" {
  description = "AWS Secret Key"
  type = "string"
}

### VPC
resource "aws_vpc" "prod_vpc" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "prod VPC"
  }
}

### Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.prod_vpc.id
}

### Custom Route Table
resource "aws_route_table" "prod_route_table" {
  vpc_id = aws_vpc.prod_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

### Associate Subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.prod_route_table.id
}
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.prod_route_table.id
}

### Subnets for prod
resource "aws_subnet" "subnet_1" {
  vpc_id     = aws_vpc.prod_vpc.id
  availability_zone = "us-east-1a"
  cidr_block = "10.0.0.0/26"
}
resource "aws_subnet" "subnet_2" {
  vpc_id     = aws_vpc.prod_vpc.id
  availability_zone = "us-east-1b"
  cidr_block = "10.0.0.64/26"
}

### Security Groups
resource "aws_security_group" "allow_web_sg" {
  vpc_id = aws_vpc.prod_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress{
    protocol = "tcp"
    from_port = 80
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress{
    protocol = "tcp"
    from_port = 8080
    to_port = 8080
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### Create IAM role for ECS 
data "aws_iam_policy_document" "ecs_agent" {//
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "ecs_agent" {//
  name               = "ecs-agent"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent.json
}
resource "aws_iam_role_policy_attachment" "ecs_agent" {//
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_instance_profile" "ecs_agent" {//
  name = "ecs-agent"
  role = aws_iam_role.ecs_agent.name
}

### Create EC2  
resource "aws_launch_configuration" "ecs_launch_config" {//
  image_id             = "ami-0ec7896dee795dfa9"
  iam_instance_profile = aws_iam_instance_profile.ecs_agent.name
  security_groups      = [aws_security_group.allow_web_sg.id]
  user_data            = "#!/bin/bash\necho ECS_CLUSTER=rh-cluster >> /etc/ecs/ecs.config"
  instance_type        = "t2.micro"
  associate_public_ip_address = true
  name_prefix = "journal-ecs"
  lifecycle {
    create_before_destroy = true
  }
  key_name = "russianhackers"
}

resource "aws_autoscaling_group" "rh-asg" {//
  name                 = "rh-asg"
  vpc_zone_identifier  = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
  launch_configuration = aws_launch_configuration.ecs_launch_config.name
  desired_capacity          = 1
  min_size                  = 1
  max_size                  = 10
  health_check_grace_period = 300
  health_check_type         = "EC2"
  lifecycle {
    create_before_destroy = true
  }
}

### Create ECS
resource "aws_ecs_cluster" "ecs_cluster" {//
  name = "rh-cluster"
}
resource "aws_ecs_task_definition" "rh_task_definition" {//
  family                = "worker"
  container_definitions = <<DEFINITION
  [
  {
    "essential": true,
    "memory": 512,
    "name": "worker",
    "cpu": 2,
    "image": "342138410857.dkr.ecr.us-east-1.amazonaws.com/journalapp:latest",
    "environment": [],
    "portMappings": [
      {
        "containerPort": 8080,
        "hostPort": 8080
      }
    ]
  }
]
  DEFINITION
}
resource "aws_ecs_service" "worker" {//
  name            = "worker"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.rh_task_definition.arn
  desired_count   = 1
  load_balancer {
    target_group_arn = aws_lb_target_group.rh-target-group.arn
    container_name   = "worker"
    container_port   = 8080
  }
}

### Create target group
resource "aws_lb_target_group" "rh-target-group" {
  name     = "rh-target-group"
  port     = 8080 //expose on port 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.prod_vpc.id
  depends_on = [aws_lb.rh-lb]
  health_check {
    path = "/api/v1/journal/hc" //health check through backend testing
    matcher = 200
  }
}
### Create load balancer for endpoint
resource "aws_lb" "rh-lb" {//
  name               = "rh-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_web_sg.id]
  subnets            = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
}
resource "aws_lb_listener" "rh-listener" {
  load_balancer_arn = aws_lb.rh-lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rh-target-group.arn
  }
}