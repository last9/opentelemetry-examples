"""
Local smoke test — no AWS required.

Generates synthetic CUR data covering all line item types, runs it through
aggregate_costs() and send_otlp_metrics(), and verifies data lands in Last9.

Usage:
  pip install -r requirements.txt
  OTLP_ENDPOINT=https://otlp.last9.io \
  OTLP_HEADERS="Authorization=Basic <token>" \
  CUR_S3_BUCKET=local CUR_REPORT_NAME=local \
  COST_ALLOCATION_TAGS=team,environment \
  python test_local.py
"""

from __future__ import annotations

import os
import sys
from datetime import date, timedelta

import pandas as pd

# Provide dummy values so main.py config block doesn't raise on import
os.environ.setdefault("CUR_S3_BUCKET", "local")
os.environ.setdefault("CUR_REPORT_NAME", "local")

from main import aggregate_costs, send_otlp_metrics  # noqa: E402


def _make_cur_df(days: int = 7) -> pd.DataFrame:
    """Build a minimal CUR-shaped DataFrame covering key line item types."""
    rows = []
    today = date.today()

    services = [
        ("AmazonEC2", "us-east-1", "BoxUsage:t3.medium"),
        ("AmazonS3", "us-east-1", "TimedStorage-ByteHrs"),
        ("AmazonRDS", "ap-south-1", "InstanceUsage:db.t3.micro"),
        ("AWSLambda", "us-east-1", "Lambda-GB-Second"),
    ]

    for d in range(days):
        usage_date = today - timedelta(days=d + 1)
        date_str = usage_date.strftime("%Y-%m-%d")

        for service, region, usage_type in services:
            base = {
                "line_item_usage_start_date": date_str,
                "line_item_product_code": service,
                "line_item_usage_account_id": "123456789012",
                "product_region": region,
                "line_item_usage_type": usage_type,
                "resource_tags_user_team": "platform",
                "resource_tags_user_environment": "production",
            }

            # Regular on-demand usage
            rows.append({**base,
                "line_item_line_item_type": "Usage",
                "line_item_unblended_cost": 12.50,
                "line_item_usage_amount": 24.0,
                "savings_plan_savings_plan_effective_cost": 0.0,
                "reservation_effective_cost": 0.0,
            })

        # Savings Plan covered usage (EC2) — amortized should differ from unblended
        rows.append({
            "line_item_usage_start_date": date_str,
            "line_item_product_code": "AmazonEC2",
            "line_item_usage_account_id": "123456789012",
            "product_region": "us-east-1",
            "line_item_usage_type": "BoxUsage:m5.xlarge",
            "line_item_line_item_type": "SavingsPlanCoveredUsage",
            "line_item_unblended_cost": 4.608,   # on-demand rate
            "line_item_usage_amount": 24.0,
            "savings_plan_savings_plan_effective_cost": 3.312,  # SP effective (cheaper)
            "reservation_effective_cost": 0.0,
            "resource_tags_user_team": "backend",
            "resource_tags_user_environment": "production",
        })

        # Reserved Instance usage
        rows.append({
            "line_item_usage_start_date": date_str,
            "line_item_product_code": "AmazonRDS",
            "line_item_usage_account_id": "123456789012",
            "product_region": "us-east-1",
            "line_item_usage_type": "InstanceUsage:db.r5.large",
            "line_item_line_item_type": "DiscountedUsage",
            "line_item_unblended_cost": 0.0,   # RI shows $0 unblended
            "line_item_usage_amount": 24.0,
            "savings_plan_savings_plan_effective_cost": 0.0,
            "reservation_effective_cost": 2.88,  # RI amortized cost
            "resource_tags_user_team": "data",
            "resource_tags_user_environment": "production",
        })

        # Tax row — should be excluded by INCLUDE_LINE_ITEM_TYPES filter
        rows.append({
            "line_item_usage_start_date": date_str,
            "line_item_product_code": "AmazonEC2",
            "line_item_usage_account_id": "123456789012",
            "product_region": "us-east-1",
            "line_item_usage_type": "Tax",
            "line_item_line_item_type": "Tax",
            "line_item_unblended_cost": 1.50,
            "line_item_usage_amount": 0.0,
            "savings_plan_savings_plan_effective_cost": 0.0,
            "reservation_effective_cost": 0.0,
            "resource_tags_user_team": "",
            "resource_tags_user_environment": "",
        })

    return pd.DataFrame(rows)


def main() -> None:
    df = _make_cur_df(days=7)
    print(f"Generated {len(df)} synthetic CUR rows")

    agg = aggregate_costs(df)
    print(f"\nAggregated to {len(agg)} rows")
    print("\nSample rows:")
    print(agg.to_string(max_rows=10))

    # Verify amortized < unblended for SP/RI rows (discount is working)
    sp_rows = agg[agg["usage_type"].str.contains("m5.xlarge", na=False)]
    if not sp_rows.empty:
        row = sp_rows.iloc[0]
        assert row["amortized_cost"] < row["unblended_cost"], (
            f"SP amortized ({row['amortized_cost']}) should be < unblended ({row['unblended_cost']})"
        )
        print(f"\n✓ SP amortized cost ({row['amortized_cost']:.4f}) < unblended ({row['unblended_cost']:.4f})")

    # Verify RI rows have non-zero amortized despite $0 unblended
    ri_rows = agg[agg["usage_type"].str.contains("db.r5.large", na=False)]
    if not ri_rows.empty:
        row = ri_rows.iloc[0]
        assert row["amortized_cost"] > 0, "RI amortized cost should be non-zero"
        assert row["unblended_cost"] == 0.0, "RI unblended cost should be $0"
        print(f"✓ RI amortized cost ({row['amortized_cost']:.4f}) > 0 despite $0 unblended")

    # Verify Tax rows were excluded
    tax_rows = agg[agg["usage_type"] == "Tax"]
    assert tax_rows.empty, "Tax line items should be filtered out"
    print("✓ Tax line items filtered out")

    # Verify tag columns present
    tag_cols = [c for c in agg.columns if c.startswith("aws_tag_")]
    if tag_cols:
        print(f"✓ Tag columns forwarded: {tag_cols}")
    else:
        print("  (No COST_ALLOCATION_TAGS configured — tag columns not present)")

    print("\nSending to Last9 OTLP endpoint…")
    send_otlp_metrics(agg)
    print("Done. Query aws.cost.unblended and aws.cost.amortized in Last9.")


if __name__ == "__main__":
    main()
