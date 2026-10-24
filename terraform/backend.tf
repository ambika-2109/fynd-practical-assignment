terraform {
  backend "s3" {
    key          = "fynd-practical-assignment/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
