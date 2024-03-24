terraform {
  required_version = "~>1.7.0"
  required_providers {
    aws = {
      version = "> 1.0.0"
    }
    tls   = "> 1.0.0"
    local = "> 1.0.0"
  }
}