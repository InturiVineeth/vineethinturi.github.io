"""
===============================================================================
Project: Python Data Pipeline SLA & Data Quality Monitoring Framework
Author: Vineeth Inturi

Purpose:
    Recreated portfolio example showing how Python can be used to monitor
    data pipelines, detect SLA breaches, validate row counts, identify schema
    drift, classify data quality issues, and generate reporting-ready exception
    summaries.

Business Context:
    In enterprise analytics environments, BI dashboards and reporting layers depend
    on reliable upstream data pipelines. If a pipeline fails, loads late, produces
    unexpected row counts, or changes schema unexpectedly, downstream dashboards
    can become inaccurate or unavailable.

    This framework simulates how a data team can use Python to monitor pipeline
    execution logs and data quality checks before reporting datasets are published.

Technical Focus:
    - pandas-based pipeline log analysis
    - SLA breach detection
    - failed and delayed refresh identification
    - row count reconciliation
    - schema drift detection
    - data quality severity scoring
    - issue prioritization
    - reporting-ready output generation

Notes:
    - This is a recreated portfolio project using generic fields and sample logic.
    - No confidential company data, internal table names, or production logic are used.
===============================================================================
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List

import numpy as np
import pandas as pd


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

@dataclass(frozen=True)
class MonitoringConfig:
    """
    Configuration for pipeline SLA and quality monitoring.
    """

    pipeline_log_file: str = "sample_pipeline_run_logs.csv"
    row_count_file: str = "sample_row_count_validation.csv"
    schema_check_file: str = "sample_schema_validation.csv"

    output_folder: str = "pipeline_monitoring_outputs"

    sla_threshold_minutes: int = 60
    row_count_tolerance_pct: float = 5.0

    business_critical_domains: tuple = (
        "sales",
        "inventory",
        "purchase_orders",
        "pricing",
        "finance",
    )


# -----------------------------------------------------------------------------
# Logging Setup
# -----------------------------------------------------------------------------

def configure_logging() -> None:
    """
    Configures logging for the monitoring workflow.
    """

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
    )


# -----------------------------------------------------------------------------
# Data Loading
# -----------------------------------------------------------------------------

def load_csv(file_path: str) -> pd.DataFrame:
    """
    Loads a CSV file and returns a pandas DataFrame.

    Parameters
    ----------
    file_path:
        Path to the CSV file.

    Returns
    -------
    pd.DataFrame
        Loaded DataFrame.

    Raises
    ------
    FileNotFoundError
        If the file does not exist.
    """

    path = Path(file_path)

    if not path.exists():
        raise FileNotFoundError(f"Input file not found: {file_path}")

    logging.info("Loading file: %s", file_path)
    return pd.read_csv(path)


# -----------------------------------------------------------------------------
# Pipeline Run Cleaning
# -----------------------------------------------------------------------------

def clean_pipeline_logs(pipeline_df: pd.DataFrame) -> pd.DataFrame:
    """
    Cleans pipeline execution logs and standardizes date/time fields.

    Expected columns:
        pipeline_id
        pipeline_name
        source_system
        target_table
        data_domain
        scheduled_start_time
        actual_start_time
        actual_end_time
        run_status
        records_loaded
        error_message
    """

    df = pipeline_df.copy()

    datetime_columns = [
        "scheduled_start_time",
        "actual_start_time",
        "actual_end_time",
    ]

    for column in datetime_columns:
        df[column] = pd.to_datetime(df[column], errors="coerce")

    df["run_status"] = (
        df["run_status"]
        .fillna("UNKNOWN")
        .str.strip()
        .str.upper()
    )

    df["data_domain"] = (
        df["data_domain"]
        .fillna("unknown")
        .str.strip()
        .str.lower()
    )

    df["source_system"] = (
        df["source_system"]
        .fillna("unknown")
        .str.strip()
    )

    df["target_table"] = (
        df["target_table"]
        .fillna("unknown")
        .str.strip()
    )

    df["records_loaded"] = pd.to_numeric(
        df["records_loaded"],
        errors="coerce",
    ).fillna(0)

    df["run_duration_minutes"] = (
        (df["actual_end_time"] - df["actual_start_time"])
        .dt.total_seconds()
        .div(60)
    )

    df["start_delay_minutes"] = (
        (df["actual_start_time"] - df["scheduled_start_time"])
        .dt.total_seconds()
        .div(60)
    )

    df["run_duration_minutes"] = df["run_duration_minutes"].fillna(0)
    df["start_delay_minutes"] = df["start_delay_minutes"].fillna(0)

    return df


# -----------------------------------------------------------------------------
# SLA Monitoring
# -----------------------------------------------------------------------------

def evaluate_pipeline_sla(
    pipeline_df: pd.DataFrame,
    config: MonitoringConfig,
) -> pd.DataFrame:
    """
    Evaluates pipeline failures, delays, and SLA breaches.
    """

    df = pipeline_df.copy()

    df["is_failed"] = df["run_status"].isin(["FAILED", "ERROR", "CANCELLED"])

    df["is_late_start"] = df["start_delay_minutes"] > config.sla_threshold_minutes

    df["is_long_running"] = (
        df["run_duration_minutes"] > config.sla_threshold_minutes
    )

    df["is_zero_record_load"] = (
        (df["records_loaded"] == 0)
        & (~df["run_status"].isin(["SKIPPED", "NO_DATA"]))
    )

    df["is_business_critical"] = df["data_domain"].isin(
        config.business_critical_domains
    )

    df["sla_status"] = np.select(
        [
            df["is_failed"],
            df["is_late_start"],
            df["is_long_running"],
            df["is_zero_record_load"],
        ],
        [
            "Failed",
            "Late Start",
            "Long Running",
            "Zero Record Load",
        ],
        default="Passed",
    )

    return df


# -----------------------------------------------------------------------------
# Row Count Validation
# -----------------------------------------------------------------------------

def clean_row_count_validation(row_count_df: pd.DataFrame) -> pd.DataFrame:
    """
    Cleans source-to-target row count validation results.

    Expected columns:
        validation_date
        source_system
        target_table
        source_row_count
        target_row_count
    """

    df = row_count_df.copy()

    df["validation_date"] = pd.to_datetime(
        df["validation_date"],
        errors="coerce",
    )

    numeric_columns = ["source_row_count", "target_row_count"]

    for column in numeric_columns:
        df[column] = pd.to_numeric(df[column], errors="coerce").fillna(0)

    df["row_count_difference"] = (
        df["target_row_count"] - df["source_row_count"]
    )

    df["row_count_difference_pct"] = np.where(
        df["source_row_count"] == 0,
        0,
        (df["row_count_difference"] / df["source_row_count"]) * 100,
    )

    return df


def evaluate_row_count_quality(
    row_count_df: pd.DataFrame,
    config: MonitoringConfig,
) -> pd.DataFrame:
    """
    Flags row count mismatches based on configured tolerance.
    """

    df = row_count_df.copy()

    df["row_count_status"] = np.where(
        df["row_count_difference_pct"].abs() > config.row_count_tolerance_pct,
        "Row Count Mismatch",
        "Passed",
    )

    return df


# -----------------------------------------------------------------------------
# Schema Validation
# -----------------------------------------------------------------------------

def clean_schema_validation(schema_df: pd.DataFrame) -> pd.DataFrame:
    """
    Cleans schema validation results.

    Expected columns:
        validation_date
        target_table
        column_name
        expected_data_type
        actual_data_type
        expected_nullable
        actual_nullable
        column_exists_flag
    """

    df = schema_df.copy()

    df["validation_date"] = pd.to_datetime(
        df["validation_date"],
        errors="coerce",
    )

    df["column_exists_flag"] = (
        df["column_exists_flag"]
        .fillna("N")
        .astype(str)
        .str.upper()
    )

    for column in [
        "target_table",
        "column_name",
        "expected_data_type",
        "actual_data_type",
        "expected_nullable",
        "actual_nullable",
    ]:
        df[column] = df[column].fillna("UNKNOWN").astype(str).str.strip()

    return df


def evaluate_schema_drift(schema_df: pd.DataFrame) -> pd.DataFrame:
    """
    Identifies missing columns, data type mismatches, and nullability changes.
    """

    df = schema_df.copy()

    df["is_missing_column"] = df["column_exists_flag"] != "Y"

    df["is_data_type_mismatch"] = (
        df["expected_data_type"].str.lower()
        != df["actual_data_type"].str.lower()
    )

    df["is_nullability_mismatch"] = (
        df["expected_nullable"].str.upper()
        != df["actual_nullable"].str.upper()
    )

    df["schema_status"] = np.select(
        [
            df["is_missing_column"],
            df["is_data_type_mismatch"],
            df["is_nullability_mismatch"],
        ],
        [
            "Missing Column",
            "Data Type Mismatch",
            "Nullability Change",
        ],
        default="Passed",
    )

    return df


# -----------------------------------------------------------------------------
# Issue Classification
# -----------------------------------------------------------------------------

def classify_pipeline_issues(pipeline_df: pd.DataFrame) -> pd.DataFrame:
    """
    Creates issue records for pipeline SLA and execution failures.
    """

    issue_df = pipeline_df[pipeline_df["sla_status"] != "Passed"].copy()

    if issue_df.empty:
        return pd.DataFrame(columns=[
            "issue_source",
            "issue_type",
            "data_domain",
            "source_system",
            "target_table",
            "severity",
            "priority_score",
            "issue_description",
            "recommended_action",
        ])

    issue_df["issue_source"] = "Pipeline SLA"
    issue_df["issue_type"] = issue_df["sla_status"]

    issue_df["severity"] = np.select(
        [
            issue_df["is_failed"] & issue_df["is_business_critical"],
            issue_df["is_failed"],
            issue_df["is_late_start"] & issue_df["is_business_critical"],
            issue_df["is_zero_record_load"],
        ],
        [
            "Critical",
            "High",
            "High",
            "Medium",
        ],
        default="Low",
    )

    issue_df["priority_score"] = np.select(
        [
            issue_df["severity"] == "Critical",
            issue_df["severity"] == "High",
            issue_df["severity"] == "Medium",
        ],
        [100, 75, 50],
        default=25,
    )

    issue_df["issue_description"] = (
        "Pipeline "
        + issue_df["pipeline_name"].astype(str)
        + " reported "
        + issue_df["sla_status"].astype(str)
        + " for target table "
        + issue_df["target_table"].astype(str)
        + "."
    )

    issue_df["recommended_action"] = np.select(
        [
            issue_df["is_failed"],
            issue_df["is_late_start"],
            issue_df["is_long_running"],
            issue_df["is_zero_record_load"],
        ],
        [
            "Review pipeline failure logs and rerun after upstream issue is resolved.",
            "Review upstream dependency timing and SLA schedule.",
            "Review query performance, source latency, and transformation logic.",
            "Validate source extract and confirm whether zero records are expected.",
        ],
        default="Review pipeline execution details.",
    )

    return issue_df[
        [
            "issue_source",
            "issue_type",
            "data_domain",
            "source_system",
            "target_table",
            "severity",
            "priority_score",
            "issue_description",
            "recommended_action",
        ]
    ]


def classify_row_count_issues(row_count_df: pd.DataFrame) -> pd.DataFrame:
    """
    Creates issue records for row count mismatches.
    """

    issue_df = row_count_df[row_count_df["row_count_status"] != "Passed"].copy()

    if issue_df.empty:
        return pd.DataFrame(columns=[
            "issue_source",
            "issue_type",
            "data_domain",
            "source_system",
            "target_table",
            "severity",
            "priority_score",
            "issue_description",
            "recommended_action",
        ])

    issue_df["issue_source"] = "Row Count Validation"
    issue_df["issue_type"] = "Row Count Mismatch"
    issue_df["data_domain"] = "unknown"

    issue_df["severity"] = np.select(
        [
            issue_df["row_count_difference_pct"].abs() >= 25,
            issue_df["row_count_difference_pct"].abs() >= 10,
        ],
        [
            "Critical",
            "High",
        ],
        default="Medium",
    )

    issue_df["priority_score"] = np.select(
        [
            issue_df["severity"] == "Critical",
            issue_df["severity"] == "High",
        ],
        [95, 70],
        default=45,
    )

    issue_df["issue_description"] = (
        "Source-to-target row count mismatch for "
        + issue_df["target_table"].astype(str)
        + ". Difference: "
        + issue_df["row_count_difference"].astype(str)
        + " records ("
        + issue_df["row_count_difference_pct"].round(2).astype(str)
        + "%)."
    )

    issue_df["recommended_action"] = (
        "Compare source extract filters, incremental load window, and target load status."
    )

    return issue_df[
        [
            "issue_source",
            "issue_type",
            "data_domain",
            "source_system",
            "target_table",
            "severity",
            "priority_score",
            "issue_description",
            "recommended_action",
        ]
    ]


def classify_schema_issues(schema_df: pd.DataFrame) -> pd.DataFrame:
    """
    Creates issue records for schema drift and structural changes.
    """

    issue_df = schema_df[schema_df["schema_status"] != "Passed"].copy()

    if issue_df.empty:
        return pd.DataFrame(columns=[
            "issue_source",
            "issue_type",
            "data_domain",
            "source_system",
            "target_table",
            "severity",
            "priority_score",
            "issue_description",
            "recommended_action",
        ])

    issue_df["issue_source"] = "Schema Validation"
    issue_df["issue_type"] = issue_df["schema_status"]
    issue_df["data_domain"] = "unknown"
    issue_df["source_system"] = "unknown"

    issue_df["severity"] = np.select(
        [
            issue_df["is_missing_column"],
            issue_df["is_data_type_mismatch"],
            issue_df["is_nullability_mismatch"],
        ],
        [
            "Critical",
            "High",
            "Medium",
        ],
        default="Low",
    )

    issue_df["priority_score"] = np.select(
        [
            issue_df["severity"] == "Critical",
            issue_df["severity"] == "High",
            issue_df["severity"] == "Medium",
        ],
        [100, 80, 55],
        default=25,
    )

    issue_df["issue_description"] = (
        "Schema issue detected on "
        + issue_df["target_table"].astype(str)
        + ". Column: "
        + issue_df["column_name"].astype(str)
        + ". Issue: "
        + issue_df["schema_status"].astype(str)
        + "."
    )

    issue_df["recommended_action"] = np.select(
        [
            issue_df["is_missing_column"],
            issue_df["is_data_type_mismatch"],
            issue_df["is_nullability_mismatch"],
        ],
        [
            "Confirm upstream schema change and update downstream model dependencies.",
            "Review source data type change and update transformation casting logic.",
            "Review business impact of nullable field change.",
        ],
        default="Review schema validation output.",
    )

    return issue_df[
        [
            "issue_source",
            "issue_type",
            "data_domain",
            "source_system",
            "target_table",
            "severity",
            "priority_score",
            "issue_description",
            "recommended_action",
        ]
    ]


# -----------------------------------------------------------------------------
# Summary Reporting
# -----------------------------------------------------------------------------

def create_monitoring_summary(
    pipeline_df: pd.DataFrame,
    row_count_df: pd.DataFrame,
    schema_df: pd.DataFrame,
    issue_df: pd.DataFrame,
) -> pd.DataFrame:
    """
    Creates an executive summary of pipeline health and data quality status.
    """

    summary_data = {
        "total_pipeline_runs": len(pipeline_df),
        "failed_pipeline_runs": int((pipeline_df["sla_status"] == "Failed").sum()),
        "late_pipeline_runs": int((pipeline_df["sla_status"] == "Late Start").sum()),
        "long_running_pipeline_runs": int(
            (pipeline_df["sla_status"] == "Long Running").sum()
        ),
        "zero_record_loads": int(
            (pipeline_df["sla_status"] == "Zero Record Load").sum()
        ),
        "row_count_mismatches": int(
            (row_count_df["row_count_status"] == "Row Count Mismatch").sum()
        ),
        "schema_issues": int((schema_df["schema_status"] != "Passed").sum()),
        "critical_issues": int((issue_df["severity"] == "Critical").sum()),
        "high_issues": int((issue_df["severity"] == "High").sum()),
        "medium_issues": int((issue_df["severity"] == "Medium").sum()),
        "low_issues": int((issue_df["severity"] == "Low").sum()),
    }

    return pd.DataFrame([summary_data])


def create_domain_summary(issue_df: pd.DataFrame) -> pd.DataFrame:
    """
    Summarizes issues by data domain and severity.
    """

    if issue_df.empty:
        return pd.DataFrame(columns=[
            "data_domain",
            "severity",
            "issue_count",
            "avg_priority_score",
        ])

    return (
        issue_df
        .groupby(["data_domain", "severity"], as_index=False)
        .agg(
            issue_count=("issue_type", "count"),
            avg_priority_score=("priority_score", "mean"),
        )
        .sort_values(
            by=["avg_priority_score", "issue_count"],
            ascending=[False, False],
        )
    )


# -----------------------------------------------------------------------------
# Output Handling
# -----------------------------------------------------------------------------

def write_outputs(
    output_folder: str,
    pipeline_df: pd.DataFrame,
    row_count_df: pd.DataFrame,
    schema_df: pd.DataFrame,
    issue_df: pd.DataFrame,
    monitoring_summary: pd.DataFrame,
    domain_summary: pd.DataFrame,
) -> None:
    """
    Writes monitoring outputs to CSV files.
    """

    output_path = Path(output_folder)
    output_path.mkdir(parents=True, exist_ok=True)

    pipeline_df.to_csv(output_path / "pipeline_sla_results.csv", index=False)
    row_count_df.to_csv(output_path / "row_count_validation_results.csv", index=False)
    schema_df.to_csv(output_path / "schema_validation_results.csv", index=False)
    issue_df.to_csv(output_path / "data_quality_issue_summary.csv", index=False)
    monitoring_summary.to_csv(output_path / "executive_monitoring_summary.csv", index=False)
    domain_summary.to_csv(output_path / "domain_issue_summary.csv", index=False)

    logging.info("Monitoring outputs written to folder: %s", output_folder)


# -----------------------------------------------------------------------------
# Main Workflow
# -----------------------------------------------------------------------------

def run_monitoring_workflow(config: MonitoringConfig) -> None:
    """
    Runs the full pipeline SLA and data quality monitoring workflow.
    """

    pipeline_logs = load_csv(config.pipeline_log_file)
    row_count_validation = load_csv(config.row_count_file)
    schema_validation = load_csv(config.schema_check_file)

    cleaned_pipeline_logs = clean_pipeline_logs(pipeline_logs)
    pipeline_sla_results = evaluate_pipeline_sla(
        cleaned_pipeline_logs,
        config,
    )

    cleaned_row_count = clean_row_count_validation(row_count_validation)
    row_count_results = evaluate_row_count_quality(
        cleaned_row_count,
        config,
    )

    cleaned_schema = clean_schema_validation(schema_validation)
    schema_results = evaluate_schema_drift(cleaned_schema)

    pipeline_issues = classify_pipeline_issues(pipeline_sla_results)
    row_count_issues = classify_row_count_issues(row_count_results)
    schema_issues = classify_schema_issues(schema_results)

    all_issues = pd.concat(
        [pipeline_issues, row_count_issues, schema_issues],
        ignore_index=True,
    ).sort_values(
        by=["priority_score"],
        ascending=False,
    )

    monitoring_summary = create_monitoring_summary(
        pipeline_sla_results,
        row_count_results,
        schema_results,
        all_issues,
    )

    domain_summary = create_domain_summary(all_issues)

    write_outputs(
        output_folder=config.output_folder,
        pipeline_df=pipeline_sla_results,
        row_count_df=row_count_results,
        schema_df=schema_results,
        issue_df=all_issues,
        monitoring_summary=monitoring_summary,
        domain_summary=domain_summary,
    )

    logging.info("Pipeline SLA and data quality monitoring completed.")
    logging.info("Total issues identified: %s", len(all_issues))


if __name__ == "__main__":
    configure_logging()

    monitoring_config = MonitoringConfig()

    try:
        run_monitoring_workflow(monitoring_config)
    except Exception as exc:
        logging.exception("Monitoring workflow failed: %s", exc)
        raise
