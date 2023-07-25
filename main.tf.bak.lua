provider "aws" {
  region = "us-east-1"
}

#*********************************************************  IAM **************************************
resource "aws_iam_instance_profile" "ec2standard_profile" {
  name = "ec2standard_profile"
  role = aws_iam_role.ec2standard_role.name
}

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

resource "aws_iam_role" "ec2standard_role" {
  name               = "ec2standard_role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "ec2ssm_policy" {
  role       = aws_iam_role.ec2standard_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
#*********************************************************  VPC **************************************

resource "aws_vpc" "Main" {            # Creating VPC here
  cidr_block       = var.main_vpc_cidr # Defining the CIDR block use 10.0.0.0/24 for demo
  instance_tenancy = "default"
  tags = {
    Name        = "Test-Main-VPC"
    Environment = "DEV"
    OS          = "NA"
    Managed     = "IAC"
  }
}

resource "aws_internet_gateway" "IGW" { # Creating Internet Gateway
  vpc_id = aws_vpc.Main.id              # vpc_id will be generated after we create VPC
}

resource "aws_subnet" "publicsubnet1" { # Creating Public Subnets
  vpc_id            = aws_vpc.Main.id
  cidr_block        = var.public_subnet1 # CIDR block of public subnets
  availability_zone = "us-east-1a"
  tags = {
    Name        = "public-subnet-1"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}

resource "aws_subnet" "publicsubnet2" { # Creating Public Subnets
  vpc_id            = aws_vpc.Main.id
  cidr_block        = var.public_subnet2 # CIDR block of public subnets
  availability_zone = "us-east-1b"
  tags = {
    Name        = "public-subnet-2"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}

resource "aws_subnet" "privatesubnet1" { # Creating Private Subnets
  vpc_id            = aws_vpc.Main.id
  cidr_block        = var.private_subnet1 # CIDR block of private subnets
  availability_zone = "us-east-1a"
  tags = {
    Name        = "private-subnet-1"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}

resource "aws_subnet" "privatesubnet2" { # Creating Private Subnets
  vpc_id            = aws_vpc.Main.id
  cidr_block        = var.private_subnet2 # CIDR block of private subnets
  availability_zone = "us-east-1b"
  tags = {
    Name        = "private-subnet-2"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}

resource "aws_route_table" "PublicRT" { # Creating RT for Public Subnet
  vpc_id = aws_vpc.Main.id
  route {
    cidr_block = "0.0.0.0/0" # Traffic from Public Subnet reaches Internet via Internet Gateway
    gateway_id = aws_internet_gateway.IGW.id
  }
}

resource "aws_route_table" "PrivateRT" { # Creating RT for Private Subnet
  vpc_id = aws_vpc.Main.id
  route {
    cidr_block     = "0.0.0.0/0" # Traffic from Private Subnet reaches Internet via NAT Gateway
    nat_gateway_id = aws_nat_gateway.NATgw.id
  }
}

resource "aws_route_table_association" "PublicRTassociation1" {
  subnet_id      = aws_subnet.publicsubnet1.id
  route_table_id = aws_route_table.PublicRT.id
}

resource "aws_route_table_association" "PublicRTassociation2" {
  subnet_id      = aws_subnet.publicsubnet2.id
  route_table_id = aws_route_table.PublicRT.id
}

resource "aws_route_table_association" "PrivateRTassociation1" {
  subnet_id      = aws_subnet.privatesubnet1.id
  route_table_id = aws_route_table.PrivateRT.id
}

resource "aws_route_table_association" "PrivateRTassociation2" {
  subnet_id      = aws_subnet.privatesubnet2.id
  route_table_id = aws_route_table.PrivateRT.id
}
resource "aws_eip" "nateIP" {
  vpc = true
}

resource "aws_nat_gateway" "NATgw" {
  allocation_id = aws_eip.nateIP.id
  subnet_id     = aws_subnet.publicsubnet1.id
}
#*********************************************************  EC2 **************************************
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kp" {
  key_name   = "myKey" # Create a "myKey" to AWS!!
  public_key = tls_private_key.pk.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename = "${aws_key_pair.kp.key_name}.pem"
  content  = tls_private_key.pk.private_key_pem
}

resource "aws_instance" "bastion" {
  ami                         = "ami-053b0d53c279acc90"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.publicsubnet1.id
  key_name                    = aws_key_pair.kp.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.webinstance.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2standard_profile.name

  user_data = <<-EOF
    #!/bin/bash
    echo  
    EOF

  user_data_replace_on_change = true

  provisioner "remote-exec" {
    inline = ["echo 'Wait until SSH is ready'"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(local_file.ssh_key.filename)
      host        = aws_instance.webserver2.public_ip
    }
  }
  provisioner "local-exec" {
    command  = "echo ${aws_instance.webserver2.public_ip} > ./bastion;ansible-playbook -i ${aws_instance.bastion.public_ip}, --private-key ${local_file.ssh_key.filename} bastion.yaml"
  }

  tags = {  
    Name        = "Bastion"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}

resource "aws_instance" "webserver1" {
  ami                         = "ami-053b0d53c279acc90"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.privatesubnet1.id
  key_name                    = aws_key_pair.kp.key_name
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.webinstance.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2standard_profile.name

  user_data = <<-EOF
    #!/bin/bash
    echo
    EOF

  user_data_replace_on_change = true

  provisioner "remote-exec" {
    inline = ["echo 'Wait until SSH is ready'"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(local_file.ssh_key.filename)
      host        = aws_instance.webserver1.public_ip
    }
  }
  provisioner "local-exec" {
    command  = "echo ${aws_instance.webserver1.public_ip} > ./host1;ansible-playbook -i ${aws_instance.webserver1.public_ip}, --private-key ${local_file.ssh_key.filename} nginx.yaml"
  }

  tags = {
    Name        = "Webserver 1"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}

resource "aws_instance" "webserver2" {
  ami                         = "ami-053b0d53c279acc90"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.privatesubnet2.id
  key_name                    = aws_key_pair.kp.key_name
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.webinstance.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2standard_profile.name

  user_data = <<-EOF
    #!/bin/bash
    echo  
    EOF

  user_data_replace_on_change = true

  provisioner "remote-exec" {
    inline = ["echo 'Wait until SSH is ready'"]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(local_file.ssh_key.filename)
      host        = aws_instance.webserver2.public_ip
    }
  }
  provisioner "local-exec" {
    command  = "echo ${aws_instance.webserver2.public_ip} > ./host2;ansible-playbook -i ${aws_instance.webserver2.public_ip}, --private-key ${local_file.ssh_key.filename} nginx.yaml"
  }

  tags = {
    Name        = "Webserver 2"
    Environment = "DEV"
    OS          = "UBUNTU"
    Managed     = "IAC"
  }
}



resource "aws_alb" "robotshop-alb" {
  name               = "robotshop-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.robotshop_lb_sg.id]
  subnets            = [aws_subnet.publicsubnet1.id,aws_subnet.publicsubnet2.id]
}

resource "aws_alb_listener" "web" {
  load_balancer_arn = aws_alb.robotshop-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.robotshop-tg.arn
  }
}
resource "aws_alb_target_group" "robotshop-tg" {
  name     = "robotshop-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.Main.id
}

resource "aws_alb_target_group_attachment" "webserver1" {
  target_group_arn = aws_alb_target_group.robotshop-tg.arn
  target_id        = aws_instance.webserver1.id
  port             = 80
}

resource "aws_alb_target_group_attachment" "webserver2" {
  target_group_arn = aws_alb_target_group.robotshop-tg.arn
  target_id        = aws_instance.webserver2.id
  port             = 80
}
#********************************************************* SG **************************************
resource "aws_security_group" "webinstance" {
  name   = "web"
  vpc_id = aws_vpc.Main.id
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
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
}

resource "aws_security_group" "robotshop_lb_sg" {
  name   = "robotshop_lb_sg"
  vpc_id = aws_vpc.Main.id
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
