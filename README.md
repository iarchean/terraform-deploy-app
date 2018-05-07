# 使用 Terrafrom 半自动化白嫖 GCP、AWS 搭建翻墙服务

最近公司云主机管理业务统一切换到了 [Terraform](https://www.terraform.io) 这个非常棒的 [IaC](https://en.wikipedia.org/wiki/Infrastructure_as_code) 工具上，它可以大大简化整个集群管理的难度，经过改造，也实现了统一的配置中心，结合公司现有 Git 服务和流水线工具，让 OP 协同更加高效。

相比 Ansible（两者实际上并不能完全放在一起对比），Terraform 不需要在目标服务器上部署 agent，侵入性较小；配置的是一个最终状态而不是过程；使用也更加简单。我司一般在物理机上使用 Ansible。

所以我觉得有必要向大家推荐一下这个工具，计划写成系列文章，由简入深的介绍几个使用场景。公司中的架构和使用案例不便分享，分享几个大家日常生活中都会遇到的。

---

## 首先当然是绕过可恶的 GFW。

> 本文所有的配置文件均可在我的[这个 repo](https://github.com/iarchean/terraform-deploy-app) 中找到

GCP、AWS 海外节点的网络质量和路由都比较优质，多年来我一直用他们作为主力梯子使用，另外还在上面部署了很多其他服务，如监控探针、博客后台、测速节点、定时任务、爬虫、推送服务、一些自用 api 等。况且，两者都提供 1 年的免费试用额度。

但是每年都要重新部署一次应用，略显繁琐（Update：大概 2020 年 9 月前后， GCP 的免费试用期限由 1 年缩短为 3 个月了），于是我写了一段 [Shell 脚本](https://gist.github.com/iarchean/d0af8c6e0d2ceca7969f6628de644071)来批量初始化服务器和应用。今天我们把它改造成 Terraform 工程。

### 主要流程

1. 在 AWS 或 GCP 上申请一个免费试用账户，获取 AccessKey 和 SecretKey；
2. 然后使用 Terraform 的 AWS/GCP Provider 创建主机实例；
3. 可选：通过 Terraform 的 Output 模块返回的主机 IP 信息，更新 Cloudflare DNS 记录；
4. 安装 Docker；
5. 使用 remote-exec provider 在 Docker 里部署应用，返回关键信息。

![Image](https://res.craft.do/user/full/f05fc002-1ef2-257c-e47b-1fef72d2bf58/doc/40C18753-A0D2-41BE-A3A0-1A64B9213F6D/1A2292AA-4D41-4D67-A191-01052B0EEFFA_2/OiHtEti2kwXUflIHJwJAMBf0QBwZ5NSxeRkRWEMlLP4z/Image)

以上流程中，除了第 1 步不可避免的要手工操作以外，2-4 仅仅需要2条命令即可实现：

```other
terraform init
terraform apply
```

## 环境准备

- [terraform cli](https://learn.hashicorp.com/tutorials/terraform/install-cli)
- [aws cli](https://aws.amazon.com/cli/) / [gcloud cli](https://cloud.google.com/sdk/gcloud)
- 公、私钥对（不能用加密的）

### 安装 Terraform CLI：

macOS 安装 terraform cli 非常容易:

```other
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

检查是否已经安装好：

```other
terraform -help
```

### 检查公私钥对

假设你电脑上已经存在公私钥对（`~/.ssh/id_rsa, ~/.ssh/id_rsa.pub`），否则的话，参照此文档[生成一对](https://docs.oracle.com/cd/E19683-01/806-4078/6jd6cjru7/index.html)。

### 了解 Terraform 配置语言

terraform 配置中有几种常见的语言：

1. Provider

Provider 是 Terraform 与云服务商、SaaS 提供商或 API 交互的桥梁，我们今天主要会使用到 2 个

   - aws（或 gcp）
   - cloudflare
2. Variable 和 Output

Variables 和 Output 一个负责输入，一个负责输出，很容易理解。我们的参数会放在 variable 里，例如 accsess token 和 region 等信息。程序执行后需要的信息会放在 output 中，供下一步使用，如 public_ip、elb_ip 等。

3. Resource

resource 是 Terraform 语言中最重要的元素。每个 resource block 描述一个或多个基础设施对象，如虚拟网络、计算实例或更高级别的组件，如 DNS 记录。

4. State

Terraform必须存储有关托管基础设施和配置的状态。Terraform使用此状态将现实世界资源映射到配置中。

### 编辑配置文件

遵照最佳实践，terraform 有几个主要的配置文件需要首先定义好：

1. versions.tf 定义 Prividers 版本

```other
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "3.18.0"
    }    
  }
  required_version = ">= 0.13"
}
```

2. outputs.tf 定义输出信息

```other
output "ipmaster" {
  value = "aws_instance.app.public_ip"
}
```

3. Key-pairs.tf 定义公私钥对资源配置

```code
resource "aws_key_pair" "deployer" {
  key_name = "deploy-${var.workspace}"
  public_key = "${file("~/.ssh/id_rsa.pub")}"
}
```

4. variables.tf 定义各类输入数据的默认值

```other
variable "access_key" {
	default = "****"
}
variable "secret_key" {
	default = "*****"
}
variable "cloudflare_apikey" {
    default = "*****"
}
variable "cloudflare_zone_id" {
  default = "*****"
}
variable "region" {
    default = "ap-northeast-1"
}
variable "workspace" {
    default = "user"
}
variable "bucket" {
    default = "bucket"
}
variable "aws_type" {
    default = "t2.micro"
}
variable "aws_ami" {
    default = "ami-0e00e89380cb2a63b"
}
```

准备工作就绪，下面定义 resource，也就是整个流程中真正执行业务的配置，我们总共有 3 个 resource：分别是创建 ec2 实例的 app-instances.tf，创建防火墙配置的 security_group.tf，和创建 DNS A 记录的 cloudflare.tf。

app-instances.tf

```other
provider "aws" {
  access_key  = "${var.access_key}"
  secret_key  = "${var.secret_key}"
  region      = "${var.region}"
}
resource "aws_instance" "app" {
  ami           = "${var.aws_ami}"
  instance_type = "${var.aws_type}"
  security_groups = ["${aws_security_group.app.name}"]
  key_name = "${aws_key_pair.deployer.key_name}"
  connection {
    host = self.public_ip
    user = "ubuntu"
    private_key = "${file("~/.ssh/id_ed25519")}"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
    
    ]
  }
  tags = { 
    Name = "${var.workspace}-primary"
  }
}
```

security_group.tf 定义 aws 防火墙资源配置

```other
/* Default security group */
resource "aws_security_group" "app" {
  name = "app-group-${var.workspace}"
  description = "Default security group that allows inbound and outbound traffic from all instances in the VPC"

  ingress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    self        = true
  }
  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 21000
    to_port   = 21000
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    self        = true
  }
  egress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 21000
    to_port   = 21000
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

cloudflare.tf

```other
provider "cloudflare" {
  email = "zephyr422@gmail.com"
  api_token = "${var.cloudflare_apitoken}"
}

resource "cloudflare_record" "aws-test" {
  zone_id = "${var.cloudflare_zone_id}"
  name    = "aws-test"
  value   = "${aws_instance.app.public_ip}"
  type    = "A"
  proxied = false

  depends_on = [
    aws_instance.app
  ]
}
```

OK，现在所有的配置均已经完成，让我们 review 一下目录结构：

```other
app/
├── app-instances.tf			# aws ec2 resource
├── cloudflare.tf				# dns A record resource
├── key-pairs.tf
├── outputs.tf
├── security-group.tf		# firewall recource
├── variables.tf
└── versions.tf
```

### 执行初始化

```other
terraform init
```

如果一切正常，我们会看到如下返回（删除了多余的描述信息）

```other
Initializing the backend...

Initializing provider plugins...
- Finding latest version of hashicorp/aws...
- Finding cloudflare/cloudflare versions matching "~> 3.0"...
- Installing hashicorp/aws v4.22.0...
- Installed hashicorp/aws v4.22.0 (signed by HashiCorp)
- Installing cloudflare/cloudflare v3.18.0...
- Installed cloudflare/cloudflare v3.18.0 (signed by a HashiCorp partner, key ID DE413CEC881C3283)

Terraform has been successfully initialized!
```

### 执行部署

```other
terraform apply
```

terraform 会列出此次部署的所有变化，非常精细，里面有几个值得我们关注的点：

下面的文字是说我们将要执行的，是一个创建任务。

```other
Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create
```

总共有 4 个新增，0 个变化，0 个销毁。

```other
Plan: 4 to add, 0 to change, 0 to destroy.
```

那具体是哪 4 个新增呢？

```other
# aws_instance.app will be created
# aws_key_pair.deployer will be created
# aws_security_group.app will be created
# cloudflare_record.aws-test will be created
```

这行表示了执行后的输出都有什么

```other
Changes to Outputs:
  + ipmaster = (known after apply)
```

现在我们充分理解了本次部署的所有操作，输入 yes 确认开始执行。观察一下输出，IP 地址我就不隐藏了反正待会儿就删掉了。

```other
aws_key_pair.deployer: Creating...
aws_security_group.app: Creating...
aws_key_pair.deployer: Creation complete after 0s [id=deploy-user]
aws_security_group.app: Creation complete after 2s [id=sg-0847b070b1c0f3057]
aws_instance.app: Creating...
aws_instance.app: Still creating... [10s elapsed]
aws_instance.app: Provisioning with 'remote-exec'...
aws_instance.app (remote-exec): Connecting to remote host via SSH...
aws_instance.app (remote-exec):   Host: 54.250.229.47
aws_instance.app (remote-exec):   User: ubuntu
aws_instance.app (remote-exec):   Password: false
aws_instance.app (remote-exec):   Private key: true
aws_instance.app (remote-exec):   Certificate: false
aws_instance.app (remote-exec):   SSH Agent: false
aws_instance.app (remote-exec):   Checking Host Key: false
aws_instance.app (remote-exec):   Target Platform: unix
aws_instance.app (remote-exec): Connected!
...
aws_instance.app (remote-exec): psk = f9820fc282341036f21e0f3f46a094fa
aws_instance.app (remote-exec): obfs = http
...
aws_instance.app: Creation complete after 1m1s [id=i-038a9d00fab6abe90]
cloudflare_record.aws-test: Creating...
cloudflare_record.aws-test: Creation complete after 0s [id=7078b55ccea7670a65eefe16f160b074]


Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

ipmaster = "54.250.229.47"
```

![Image.png](https://res.craft.do/user/full/f05fc002-1ef2-257c-e47b-1fef72d2bf58/doc/40C18753-A0D2-41BE-A3A0-1A64B9213F6D/119C71B5-66FC-4461-86D8-44BB5ACED9CE_2/1cd13ocLnfE33tUtRyHwQGzxOBcMwBsoxbZQ0CSxpAsz/Image.png)

部署执行成功，分别去 AWS Console 和 Cloudflare Dashboard 中查看，资源都按照计划创建完成了

![Image.png](https://res.craft.do/user/full/f05fc002-1ef2-257c-e47b-1fef72d2bf58/doc/40C18753-A0D2-41BE-A3A0-1A64B9213F6D/2D14DB77-9DFE-46E8-9570-68A031FF01DF_2/S2e1oUyCHux4uHGNmyZz4YLM9bJnDvnZnCARSVJhBKQz/Image.png)

![Image.png](https://res.craft.do/user/full/f05fc002-1ef2-257c-e47b-1fef72d2bf58/doc/40C18753-A0D2-41BE-A3A0-1A64B9213F6D/8BC133AB-24C4-4498-879D-6D8E6F727F7E_2/X1jnDTVYTSxNGIPxWECZlExkVrhAZTWYZcFVHp6ykZcz/Image.png)

部署的输出中也已经把 psk 打印出来了，剩下的就是放到翻墙代理中使用即可。

另外，terraform apply 命令也支持使用环境变量传递参数，不想将 APIkey 等用明文放入配置文件的话，也可以使用这种方式进行。

```other
export TF_VAR_access_key=xxxx
export TF_VAR_secret_key=xxxxxxxx

terraform apply
```

