provider "aws" {
    region = "us-east-1"
    access_key = "AKIAU7KIJ25UTKOM65K6"
    secret_key = "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"
    # access_key = ${env.TF_VAR_ak}
    # secret_key = ${env.TF_VAR_sk}
}
# 1.    VPC
resource "aws_vpc" "prod_vpc" {
  cidr_block       = "10.0.0.0/16"
  tags = {
    Name = "prod"
  }
}

# 2.    Internet Gateway
resource "aws_internet_gateway" "gw" {
    vpc_id = aws_vpc.prod_vpc.id
    tags = {
        Name = "prod"
    }
}

# 3.    Custom Route Table (might be optional)
resource "aws_route_table" "prod_route_table" {
    vpc_id = aws_vpc.prod_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.gw.id
    }
    route {
        ipv6_cidr_block = "::0/0"
        gateway_id = aws_internet_gateway.gw.id
    }
    tags = {
        Name = "prod"
    }
}

### Associate Subnet with Route Table
resource "aws_route_table_association" "a" {
    subnet_id = aws_subnet.subnet_1.id
    route_table_id = aws_route_table.prod_route_table.id
}

# 4.    Private Subnet for Prod ENV
resource "aws_subnet" "subnet_1" {
    vpc_id     = aws_vpc.prod_vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-east-1a"
    tags = {
        Name = "prod_subnet"
    }
}
# 4.    Private Subnet for Prod ENV 2
resource "aws_subnet" "subnet_2" {
    vpc_id     = aws_vpc.prod_vpc.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "us-east-1b"
    tags = {
        Name = "prod_subnet2"
    }
}

## subnet for DB
resource "aws_db_subnet_group" "db_subnet_group" {
    subnet_ids  = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
}


# 6.    Security Group for Staging
############# TODO ###############
resource "aws_security_group" "staging_sg" {
    name        = "staging_sg"
    description = "Allow web traffic"
    vpc_id      = aws_vpc.prod_vpc.id

    ingress {
        description = "HTTPS from VPC"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "HTTP from VPC"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "SSH from VPC"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "staging_sg"
    }
}

# 7.    Security Group for Prod
resource "aws_security_group" "allow_web" {
    name        = "allow_web"
    description = "Allow web traffic"
    vpc_id      = aws_vpc.prod_vpc.id

    ingress {
        description = "HTTPS from VPC"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "HTTP from VPC"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "SSH from VPC"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "allow_web"
    }
}

# 8.    Network Interface
resource "aws_network_interface" "web_server_nic" {
    subnet_id       = aws_subnet.subnet_1.id
    private_ips     = ["10.0.1.50"]
    security_groups = [aws_security_group.allow_web.id]
}

# 9.    Elastic IP Address
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web_server_nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}


# 10.   Ubuntu Server with Apache for the Front-end
resource "aws_instance" "ec2" {
    ami           = "ami-02fe94dee086c0c37"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "russianhackers" #1:33:42
    network_interface {
        device_index          = 0
        network_interface_id  = aws_network_interface.web_server_nic.id
    }

    user_data = <<-EOF
                #! /bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c echo 'echo your very first web server > /var/www/html/index.html'
                EOF
    tags = {
        Name = "web_server"
    }
}

### Create ECS Cluster
resource "aws_ecs_cluster" "rh_cluster" {
  name = "rh-cluster"
}

resource "aws_ecs_task_definition" "rh_task_definition" {
  family                   = "rh-task-definition" # 
  container_definitions    = <<DEFINITION
  [
    {
      "name": "rh-task-definition",
      "image": "342138410857.dkr.ecr.us-east-1.amazonaws.com/journalapp:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "hostPort": 8080
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"    
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}

resource "aws_iam_role" "ecsTaskExecutionRole" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role       = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_service" "rh_ecs_service" {
  name            = "rh-ecs-service"                             # Naming our first service
  cluster         = "${aws_ecs_cluster.rh_cluster.id}"             # Referencing our created Cluster
  task_definition = "${aws_ecs_task_definition.rh_task_definition.arn}" # Referencing the task our service will spin up
  launch_type     = "FARGATE"
  desired_count   = 3 # Setting the number of containers we want deployed to 3

  load_balancer {
    target_group_arn = "${aws_lb_target_group.rh_target_group.arn}" # Referencing our target group
    container_name   = "${aws_ecs_task_definition.rh_task_definition.family}"
    container_port   = 8080 # Specifying the container port
  }

  network_configuration {
    subnets          = ["${aws_subnet.subnet_1.id}", "${aws_subnet.subnet_2.id}"]
    assign_public_ip = true # Providing our containers with public IPs
    security_groups = ["${aws_security_group.service_security_group.id}"]
  }
}

### Create security group for the network configuration of the AWS service
resource "aws_security_group" "service_security_group" {
  vpc_id      = aws_vpc.prod_vpc.id
  
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}

resource "aws_alb" "application_load_balancer" {
  name               = "rh-lb-tf" # Naming our load balancer
  load_balancer_type = "application"
  subnets = [ # Referencing the default subnets
    "${aws_subnet.subnet_1.id}",
    "${aws_subnet.subnet_2.id}"
    ]
  # Referencing the security group made for the load balancer (below)
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

# Creating a security group specifically for the load balancer
resource "aws_security_group" "load_balancer_security_group" {
  vpc_id        = aws_vpc.prod_vpc.id
  
  ingress {
    from_port   = 80 # Allowing traffic in from port 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}

### Specify where to direct the traffic on the website
resource "aws_lb_target_group" "rh_target_group" {
  name        = "rh-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_vpc.prod_vpc.id}" # Referencing the prod VPC
  health_check {
    matcher = "200,301,302"
    path = "/"
  }

  depends_on = ["aws_alb.application_load_balancer"]
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}" # References the load balancer
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.rh_target_group.arn}" # References the provided target group
  }
}