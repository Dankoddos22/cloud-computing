provider "aws" {
    region = "us-east-2"
    access_key = var.aws_access_key
    secret_key = var.aws_secret_key
  
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners = [ "amazon" ]

  filter {
   name   = "owner-alias"
   values = ["amazon"]
 }


 filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
 }

 filter {
       name   = "architecture"
       values = ["x86_64"]
     }
}

resource "aws_instance" "for_ami" {
  ami = data.aws_ami.amazon_linux_2.id
  associate_public_ip_address = true
  iam_instance_profile = "EC2-S3Read-Role"
  instance_type = var.aws_instance_type
  key_name = var.keypair
  security_groups = [ "Port-22" ]
  user_data = file("UserData.txt")

  tags = {
    Name = "For-AMI"
  }
}
# WAIT FOR UserData to execute

resource "null_resource" "user_data_status_check" {
  provisioner "local-exec" {
    on_failure  = fail
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
          echo -e "\x1B[33m waiting for instance to warm up \x1B[0m"
          # wait 30 sec 
          sleep 30
          ssh -i MyNewKeypair.pem instance_ip ConnectTimeout=30  -o 'ConnectionAttempts 5' test -f "/home/ec2-user/var/www/html/index.html" && echo found || echo not found
          if [ $? -eq 0 ]; then
          echo -e "\x1B[32m User data executed sucessfully \x1B[0m"
          else
            echo -e "\x1B[31m Failed to execute user data  \x1B[0m"
          fi
     EOT        
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [aws_instance.for_ami]
}

resource "aws_ami_from_instance" "instance_ami"{
  name = "EC2_AMI"
  source_instance_id = aws_instance.for_ami.id

  tags = {
    "Name" = "EC2-AMI"
  }
}

resource "aws_security_group" "Lab6_SG" {

    name = "Lab6-SG"
    vpc_id = var.aws_default_vpc

    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Lab6-SG"
  }
  
}

resource "aws_lb" "lb" {
  name = "Lab6-ALB"
  internal = false
  load_balancer_type = "application"
  security_groups = [ aws_security_group.Lab6_SG.id ]
  subnets = [ "subnet-42499e29", "subnet-78502434" , "subnet-1c545866" ]

  tags = {
    Name = "Lab6-ALB"
  }
}

resource "aws_instance" "ec2" {
  count = 2
  ami = aws_ami_from_instance.instance_ami.id
  instance_type = var.aws_instance_type
  key_name = var.keypair
  security_groups = [ aws_security_group.Lab6_SG.name ]

  tags = {
    Name = format("Instance-%d", count.index)
  }
}

resource "aws_lb_target_group" "target_group" {
  name     = "Lab6-Target-Group"
  target_type = "instance"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.aws_default_vpc
}

resource "aws_lb_target_group_attachment" "target_group_attachment" {
  count = length(aws_instance.ec2)
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id = aws_instance.ec2[count.index].id
  port = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

# AUTOSCALING

/* resource "aws_autoscaling_group" "asg"{
  name = "Lab6-ASG"
  launch_template {
    id = "lt-070e65558a16d6543"
    version = "$Latest"
  }
  min_size = 2
  max_size = 2
  desired_capacity = 2
  vpc_zone_identifier = ["subnet-78502434"]
  target_group_arns = [aws_lb_target_group.target_group.arn]
}

resource "aws_autoscaling_attachment" "asg_attachment_bar" {
  autoscaling_group_name = aws_autoscaling_group.asg.id
  alb_target_group_arn    = aws_lb_target_group.target_group.arn
} */