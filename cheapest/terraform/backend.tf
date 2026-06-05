terraform {
  backend "gcs" {
    bucket = "cheapest-497709-tfstate"
    prefix = "cheapest/terraform"
  }
}
