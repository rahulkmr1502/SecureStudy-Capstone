#!/usr/bin/env python3
"""
Red-team test of the scanner: copy terraform/, inject 16 known defects, run Checkov,
and report which defects it catches. Nothing here is ever applied; the mutated copy is
written to a temp directory.

usage (from repo root): python3 red-team/mutate_and_scan.py
"""
import json, os, shutil, subprocess, sys, tempfile

SRC = "terraform"
# (id, description, file, old, new, checkov ids that should fire)
M = [
 (1, "RDS publicly accessible", "database.tf", "publicly_accessible                   = false", "publicly_accessible                   = true", ["CKV_AWS_17"]),
 (2, "RDS storage unencrypted", "database.tf", "storage_encrypted                     = true", "storage_encrypted                     = false", ["CKV_AWS_16"]),
 (3, "RDS single-AZ", "database.tf", "multi_az                              = true", "multi_az                              = false", ["CKV_AWS_157"]),
 (4, "RDS deletion protection off", "database.tf", "deletion_protection                   = true", "deletion_protection                   = false", ["CKV_AWS_293"]),
 (5, "RDS backups off", "database.tf", "backup_retention_period               = 7", "backup_retention_period               = 0", ["CKV_AWS_133"]),
 (6, "IMDSv1 allowed", "compute.tf", 'http_tokens                 = "required"', 'http_tokens                 = "optional"', ["CKV_AWS_79"]),
 (7, "ALB keeps invalid headers", "compute.tf", "drop_invalid_header_fields = true", "drop_invalid_header_fields = false", ["CKV_AWS_131"]),
 (8, "ALB deletion protection off", "compute.tf", "enable_deletion_protection = true", "enable_deletion_protection = false", ["CKV_AWS_150"]),
 (9, "App root volume unencrypted", "compute.tf", "encrypted             = true", "encrypted             = false", ["CUSTOM_AWS_002"]),
 (10, "S3 public access block off", "storage.tf",
      'bucket                  = aws_s3_bucket.data_bucket.id\n  block_public_acls       = true\n  block_public_policy     = true\n  ignore_public_acls      = true\n  restrict_public_buckets = true',
      'bucket                  = aws_s3_bucket.data_bucket.id\n  block_public_acls       = false\n  block_public_policy     = false\n  ignore_public_acls      = false\n  restrict_public_buckets = false', ["CKV_AWS_53", "CKV_AWS_54", "CKV_AWS_55", "CKV_AWS_56"]),
 (11, "CloudTrail single region", "monitoring.tf", "is_multi_region_trail         = true", "is_multi_region_trail         = false", ["CKV_AWS_67"]),
 (12, "CloudTrail log validation off", "monitoring.tf", "enable_log_file_validation    = true", "enable_log_file_validation    = false", ["CKV_AWS_36"]),
 (13, "KMS rotation off", "kms.tf", "enable_key_rotation     = true", "enable_key_rotation     = false", ["CKV_AWS_7"]),
 (14, "App role allowed *:* on *", "iam.tf", 'actions   = ["s3:GetObject", "s3:PutObject"]\n    resources = ["${aws_s3_bucket.data_bucket.arn}/*"]', 'actions   = ["*"]\n    resources = ["*"]', ["CKV_AWS_1", "CKV_AWS_49"]),
]
EXTRA = [  # appended as new resources
 (15, "SSH open to the world", ["CKV_AWS_24"], 'resource "aws_vpc_security_group_ingress_rule" "oops_ssh" {\n  security_group_id = aws_security_group.app.id\n  description       = "oops"\n  ip_protocol       = "tcp"\n  from_port         = 22\n  to_port           = 22\n  cidr_ipv4         = "0.0.0.0/0"\n}\n'),
 (16, "Database port open to the world", ["CUSTOM_AWS_001"], 'resource "aws_vpc_security_group_ingress_rule" "oops_db" {\n  security_group_id = aws_security_group.db.id\n  description       = "oops"\n  ip_protocol       = "tcp"\n  from_port         = 5432\n  to_port           = 5432\n  cidr_ipv4         = "0.0.0.0/0"\n}\n'),
]

tmp = tempfile.mkdtemp()
dst = os.path.join(tmp, "mutated")
shutil.copytree(SRC, dst)
for _id, _d, f, old, new, _ in M:
    p = os.path.join(dst, f); s = open(p).read()
    assert old in s, f"mutation {_id}: pattern not found in {f}"
    open(p, "w").write(s.replace(old, new, 1))
with open(os.path.join(dst, "security_groups.tf"), "a") as fh:
    for _id, _d, _c, hcl in EXTRA:
        fh.write("\n" + hcl)

out = os.path.join(tmp, "out")
subprocess.run(["checkov", "-d", dst, "--framework", "terraform", "--external-checks-dir", "policies", "--compact", "-o", "json", "--output-file-path", out],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
res = json.load(open(os.path.join(out, "results_json.json")))
fired = {c["check_id"] for c in res["results"]["failed_checks"]}
print(f"mutated copy: {res['summary']['failed']} failed checks ({res['summary']['passed']} passed)\n")
caught = 0
rows = [(m[0], m[1], m[5]) for m in M] + [(e[0], e[1], e[2]) for e in EXTRA]
for i, desc, ids in sorted(rows):
    hit = bool(ids) and any(x in fired for x in ids)
    caught += hit
    print(f"  {i:2}  {'CAUGHT' if hit else 'MISSED':6}  {desc}" + (f"   ({', '.join(x for x in ids if x in fired)})" if hit else ""))
print(f"\nCheckov caught {caught} of {len(rows)} injected defects")
json.dump({"failed": res["summary"]["failed"], "caught": caught, "injected": len(rows), "fired": sorted(fired)},
          open("scans/red-team-result.json", "w"), indent=1)
shutil.rmtree(tmp)
