terraform {
  backend "s3" {
    bucket       = "ts-academy-voting-multiple-server-file"
    key          = "voting-app2.tfstate"
    region       = "eu-north-1"
  }
}