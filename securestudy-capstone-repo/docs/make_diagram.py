"""Draws docs/architecture.png (SecureStudy reference architecture)."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle

NAVY, BLUE, GREY = "#1F3864", "#2E74B5", "#595959"
fig, ax = plt.subplots(figsize=(16, 10.4), dpi=130)
ax.set_xlim(0, 160); ax.set_ylim(0, 104); ax.axis("off")

def box(x, y, w, h, label, fc="#FFFFFF", ec=NAVY, lw=1.4, fs=9, bold=False, ls="-", color="#111111", va="center", ha="center", dy=0):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.25,rounding_size=0.8", fc=fc, ec=ec, lw=lw, ls=ls))
    ty = y + h/2 + dy if va == "center" else y + h - 1.2
    tx = x + w/2 if ha == "center" else x + 1.2
    ax.text(tx, ty, label, ha=ha, va=va if va != "center" else "center", fontsize=fs, color=color,
            fontweight="bold" if bold else "normal", linespacing=1.25)

def arrow(x1, y1, x2, y2, label="", c=NAVY, ls="-", lx=0, ly=1.2):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1), arrowprops=dict(arrowstyle="-|>", color=c, lw=1.5, ls=ls, shrinkA=0, shrinkB=0))
    if label:
        ax.text((x1+x2)/2+lx, (y1+y2)/2+ly, label, ha="center", fontsize=8, color=c)

def badge(x, y, n):
    ax.add_patch(plt.Circle((x, y), 1.35, fc="#C55A11", ec="white", lw=1.2, zorder=5))
    ax.text(x, y, str(n), ha="center", va="center", fontsize=8.5, color="white", fontweight="bold", zorder=6)

ax.text(2, 101.5, "SecureStudy: secure three-tier reference architecture (AWS, ap-south-1)", fontsize=15, fontweight="bold", color=NAVY, va="center")
ax.text(2, 98.6, "Numbered badges match the controls table in the report. Everything shown is defined in terraform/ and scanned with Checkov.", fontsize=9, color=GREY, va="center")

# users + edge
box(2, 78, 14, 9, "Students /\nstaff\n(internet)", fc="#F2F2F2", ec=GREY, fs=9)
box(21, 78, 15, 9, "AWS WAF\nmanaged rules\n+ rate limit", fc="#FDE9D9", ec="#C55A11", fs=9)
badge(35.5, 87.2, 1)
arrow(16.4, 82.5, 20.6, 82.5)

# VPC
ax.add_patch(Rectangle((40, 22), 79, 70, fc="#F7FAFD", ec=BLUE, lw=2, ls="--"))
ax.text(41.5, 90, "VPC 10.20.0.0/16  (two Availability Zones)", fontsize=10, color=BLUE, fontweight="bold", va="center")
arrow(36.4, 82.5, 44.6, 82.5)

def tier(y, h, title, tint):
    ax.add_patch(Rectangle((42, y), 75, h, fc=tint, ec="#BFBFBF", lw=1))
    ax.text(106.5, y+h-1.6, title, fontsize=9, color=GREY, fontweight="bold", va="center", ha="right")

tier(70, 17, "Public subnets (2 x /24)", "#EEF3FA")
tier(45, 22, "Private subnets: app tier (2 x /24, no public IPs)", "#F3F8F0")
tier(25, 17, "Data subnets: database tier (2 x /24, no internet route)", "#FBF4E6")

box(45, 73, 24, 9, "Application Load Balancer\nHTTPS 443 only, TLS 1.3 policy\naccess logs on", fs=8.5)
badge(68.5, 82.2, 2)
box(75, 73, 18, 9, "NAT gateway\n(outbound 443 only)", fs=8.5)
box(97, 73, 17, 9, "Internet gateway", fs=8.5, fc="#F2F2F2", ec=GREY)

box(48, 49, 28, 14, "Auto Scaling group (2 to 4)\nAmazon Linux 2023, IMDSv2 only\nencrypted EBS, SSM (no SSH)", fs=8.5)
box(82, 49, 28, 14, "App instances in AZ a and b\nSG: 8443 from ALB only\nrole: one bucket + one key", fs=8.5)
badge(47.5, 63.2, 3); badge(109.5, 63.2, 4)

box(48, 28, 30, 10, "RDS PostgreSQL, Multi-AZ\nSG: 5432 from app SG only", fs=8.5)
box(84, 28, 28, 10, "NACL on data subnets\n5432 from app subnets only", fs=8.5, fc="#FFFFFF")
badge(77.5, 38.2, 5); badge(111.5, 38.2, 6)

arrow(57, 73, 57, 63.4, "443 -> 8443", lx=5, ly=-0.5)
arrow(62, 49, 62, 38.4, "5432", lx=2.5, ly=0)

# right side: data + keys
box(124, 74, 32, 10, "S3 data bucket\nSSE-KMS, versioned, public access\nblocked, TLS-only policy", fs=8.5)
badge(155.5, 84.2, 7)
box(124, 58, 32, 10, "KMS customer key\nrotation on; used by S3, RDS, EBS,\nlogs, SNS, secrets", fs=8.5, fc="#EEF3FA")
badge(155.5, 68.2, 8)
box(124, 42, 32, 10, "Secrets Manager\nDB password generated + rotated\nby RDS, never in code", fs=8.5)
badge(155.5, 52.2, 9)
arrow(110, 56, 124, 77, c=BLUE)
ax.text(119.5, 70.8, "S3 gateway endpoint", fontsize=8, color=BLUE, ha="left")
arrow(140, 74, 140, 68.4, c=GREY, ls=":")

# bottom band: detection
ax.add_patch(Rectangle((2, 2), 156, 17, fc="#FFF8EC", ec="#BF8F00", lw=1.2))
ax.text(3.5, 17.4, "Detection and response layer", fontsize=10, color="#7F5F00", fontweight="bold", va="center")
box(4, 4, 24, 10, "CloudTrail\nall regions, KMS, log\nvalidation, S3 data events", fs=8)
box(31, 4, 22, 10, "CloudWatch Logs\n4 metric filters\n+ alarms", fs=8)
box(56, 4, 22, 10, "VPC Flow Logs\nWAF logs\nRDS logs", fs=8)
box(81, 4, 22, 10, "GuardDuty\nSecurity Hub (CIS)\nAccess Analyzer", fs=8)
box(106, 4, 22, 10, "SNS (encrypted)\nemail alerts\n+ budget alarm", fs=8)
box(131, 4, 25, 10, "Analyst role\nread-only, MFA required\n(no IAM users)", fs=8)
badge(27.5, 14.2, 10); badge(52.5, 14.2, 11); badge(102.5, 14.2, 12); badge(155.5, 14.2, 13)
for x1, x2 in [(28, 31), (53, 56), (78, 81), (103, 106)]:
    arrow(x1+0.3, 9, x2-0.3, 9)
arrow(80, 19.2, 80, 24.6, c="#BF8F00", ls=":")

fig.savefig("docs/architecture.png", bbox_inches="tight", facecolor="white")
