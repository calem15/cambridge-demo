provider "aws" {
  region = "ap-southeast-1"
}

terraform {
  backend "s3" {
    bucket = "demo.terraform.tfstate"
    key    = "cambridge"
    region = "ap-southeast-1"
  }
}

provider "random" {
}