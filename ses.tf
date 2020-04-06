# The DMARC domain
resource "aws_ses_domain_identity" "dmarc" {
  domain = "dmarc.cyber.dhs.gov"
}

# The Route53 zone where the Amazon SES verification record will live
data "aws_route53_zone" "cyber_dhs_gov" {
  name         = "cyber.dhs.gov."
  private_zone = false
}

# Verification TXT record
resource "aws_route53_record" "dmarc_amazonses_verification_record" {
  zone_id = data.aws_route53_zone.cyber_dhs_gov.zone_id
  name    = "_amazonses.${aws_ses_domain_identity.dmarc.domain}"
  type    = "TXT"
  ttl     = "60"
  records = [
    aws_ses_domain_identity.dmarc.verification_token,
  ]
}

# Performs the verification
resource "aws_ses_domain_identity_verification" "cyber_dhs_gov_verification" {
  domain = aws_ses_domain_identity.dmarc.id

  depends_on = [aws_route53_record.dmarc_amazonses_verification_record]
}

# DKIM for the domain
resource "aws_ses_domain_dkim" "dmarc" {
  domain = aws_ses_domain_identity.dmarc.domain
}

# The Route53 DKIM records
resource "aws_route53_record" "dmarc_amazonses_dkim_record" {
  count   = 3
  zone_id = data.aws_route53_zone.cyber_dhs_gov.zone_id
  name    = "${element(aws_ses_domain_dkim.dmarc.dkim_tokens, count.index)}._domainkey.${aws_ses_domain_identity.dmarc.domain}"
  type    = "CNAME"
  ttl     = "1800"
  records = [
    "${element(aws_ses_domain_dkim.dmarc.dkim_tokens, count.index)}.dkim.amazonses.com",
  ]
}

# Stash the name of our rule set, so it is defined in only one place
locals {
  rule_set_name = "dmarc-import-rules"
}

# Make a new rule set for handling the DMARC aggregate report emails
# that arrive
resource "aws_ses_receipt_rule_set" "rules" {
  rule_set_name = local.rule_set_name
}

# Make a rule for handling the DMARC aggregate report emails that
# arrive
resource "aws_ses_receipt_rule" "rule" {
  name          = "receive-dmarc-emails"
  rule_set_name = local.rule_set_name
  recipients    = var.emails

  enabled      = true
  scan_enabled = true

  # Save to the permanent S3 bucket
  s3_action {
    bucket_name = aws_s3_bucket.permanent.id
    position    = 1
  }

  # Save to the temporary S3 bucket
  s3_action {
    bucket_name = aws_s3_bucket.temporary.id
    position    = 2
  }
}

# Make this rule set the active one
resource "aws_ses_active_receipt_rule_set" "active" {
  rule_set_name = local.rule_set_name
}
