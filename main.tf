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

## subnet for DB
resource "aws_db_subnet_group" "db_subnet_group" {
    subnet_ids  = [aws_subnet.subnet_1.id]
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

# 11.   ECS (container service)
############# TODO ###############

module "ecs" {
  source = "terraform-aws-modules/ecs/aws"

  name = "rh-ecs"

  container_insights = true

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy = [
    {
      capacity_provider = "FARGATE_SPOT"
    }
  ]

  tags = {
    Environment = "Development"
  }
}

# resource "aws_db_instance" "testdb" {
#   source  = "terraform-aws-modules/rds/aws"
#   version = "PostgreSQL 12.5-R1"

#   identifier = "testdb"

#   engine            = "postgres"
#   engine_version    = "12.5"
#   instance_class    = "db.t2.micro" # this is the smallest db instance (1GB RAM). Might need to upgrade to db.t2.small --medium --large
#   allocated_storage = 5 # 5GB of storage

#   name     = "testdb"
#   username = "rh"
#   password = "russianhackers"
#   port     = "5432"
  
# #   publicly_accessible = true

#   db_subnet_group_name = aws_db_subnet_group.db_subnet_group.id
#   # security group for db
#   vpc_security_group_ids = [aws_security_group.staging_sg.id] #add the ECS_sg once created

#   tags = {
#     Owner       = "user"
#     Environment = "staging"
#   }

#   # Snapshot name upon DB deletion
#   final_snapshot_identifier = "testdb"

#   # Database Deletion Protection
#   deletion_protection = true


#   12.2 Prod DB
############# TODO ###############
# 