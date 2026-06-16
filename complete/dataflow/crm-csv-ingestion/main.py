"""Schema-driven CRM CSV ingestion Dataflow pipeline."""

from __future__ import annotations

import csv
import datetime as dt
import io
import json
from typing import Any

import apache_beam as beam
from apache_beam.io import fileio
from apache_beam.io.filesystems import FileSystems
from apache_beam.options.pipeline_options import PipelineOptions


class CrmIngestionOptions(PipelineOptions):
    """Runtime parameters exposed by the Flex Template metadata."""

    @classmethod
    def _add_argparse_args(cls, parser: Any) -> None:
        parser.add_argument("--run_date", required=True)
        parser.add_argument("--source_type", required=True)
        parser.add_argument("--input_prefix", required=True)
        parser.add_argument("--schema_config_path", required=True)
        parser.add_argument("--output_table", required=True)
        parser.add_argument("--rejected_output_prefix", required=True)
        parser.add_argument("--audit_table", required=True)


def _load_schema_config(path: str) -> dict[str, Any]:
    with FileSystems.open(path) as handle:
        return json.loads(handle.read().decode("utf-8"))


def _bq_schema(columns: list[dict[str, Any]]) -> str:
    fields = [f"{column['name']}:{column['type']}" for column in columns]
    fields.extend(
        [
            "run_date:DATE",
            "source_type:STRING",
            "source_file:STRING",
            "ingestion_ts:TIMESTAMP",
        ]
    )
    return ",".join(fields)


def _audit_schema() -> str:
    return ",".join(
        [
            "run_date:DATE",
            "source_type:STRING",
            "input_prefix:STRING",
            "schema_config_path:STRING",
            "output_table:STRING",
            "rejected_output_prefix:STRING",
            "input_count:INTEGER",
            "valid_count:INTEGER",
            "rejected_count:INTEGER",
            "audit_ts:TIMESTAMP",
        ]
    )


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def _coerce_value(value: str | None, column_type: str) -> Any:
    if value is None or value == "":
        return None

    if column_type == "STRING":
        return value
    if column_type == "INTEGER":
        return int(value)
    if column_type == "FLOAT":
        return float(value)
    if column_type == "BOOL":
        lowered = value.strip().lower()
        if lowered in {"true", "t", "1", "yes", "y"}:
            return True
        if lowered in {"false", "f", "0", "no", "n"}:
            return False
        raise ValueError(f"Invalid BOOL value: {value}")
    if column_type == "DATE":
        return dt.date.fromisoformat(value).isoformat()
    if column_type == "TIMESTAMP":
        normalized = value.replace(" ", "T")
        timestamp = dt.datetime.fromisoformat(normalized)
        if timestamp.tzinfo is None:
            timestamp = timestamp.replace(tzinfo=dt.timezone.utc)
        return timestamp.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")

    raise ValueError(f"Unsupported column type: {column_type}")


class ReadCsvFiles(beam.DoFn):
    def __init__(self, schema_config: dict[str, Any]) -> None:
        self._schema_config = schema_config

    def process(self, readable_file: fileio.ReadableFile) -> Any:
        csv_config = self._schema_config.get("csv", {})
        delimiter = csv_config.get("delimiter", ",")
        quotechar = csv_config.get("quote", '"')

        with readable_file.open() as handle:
            text = io.TextIOWrapper(handle, encoding="utf-8-sig")
            reader = csv.DictReader(text, delimiter=delimiter, quotechar=quotechar)
            for row_number, row in enumerate(reader, start=2):
                yield {
                    "source_file": readable_file.metadata.path,
                    "row_number": row_number,
                    "raw_row": row,
                }


class ValidateAndFormatRow(beam.DoFn):
    def __init__(
        self,
        schema_config: dict[str, Any],
        run_date: str,
        source_type: str,
    ) -> None:
        self._columns = schema_config["columns"]
        self._run_date = run_date
        self._source_type = source_type

    def process(self, record: dict[str, Any]) -> Any:
        raw_row = record["raw_row"]
        output: dict[str, Any] = {}
        errors: list[str] = []

        for column in self._columns:
            name = column["name"]
            column_type = column["type"]
            value = raw_row.get(name)

            if column.get("required") and (value is None or value == ""):
                errors.append(f"{name} is required")
                continue

            try:
                output[name] = _coerce_value(value, column_type)
            except Exception as exc:  # pragma: no cover - Dataflow error detail
                errors.append(f"{name}: {exc}")

        if errors:
            yield beam.pvalue.TaggedOutput(
                "rejected",
                {
                    "run_date": self._run_date,
                    "source_type": self._source_type,
                    "source_file": record["source_file"],
                    "row_number": record["row_number"],
                    "raw_row": raw_row,
                    "error_reasons": errors,
                    "rejected_ts": _utc_now(),
                },
            )
            return

        output.update(
            {
                "run_date": self._run_date,
                "source_type": self._source_type,
                "source_file": record["source_file"],
                "ingestion_ts": _utc_now(),
            }
        )
        yield output


def _json_dumps(row: dict[str, Any]) -> str:
    return json.dumps(row, sort_keys=True, ensure_ascii=False)


def _audit_row(
    grouped_counts: tuple[str, dict[str, list[int]]],
    options: CrmIngestionOptions,
) -> dict[str, Any]:
    _, counts = grouped_counts
    return {
        "run_date": options.run_date,
        "source_type": options.source_type,
        "input_prefix": options.input_prefix,
        "schema_config_path": options.schema_config_path,
        "output_table": options.output_table,
        "rejected_output_prefix": options.rejected_output_prefix,
        "input_count": (counts.get("input_count") or [0])[0],
        "valid_count": (counts.get("valid_count") or [0])[0],
        "rejected_count": (counts.get("rejected_count") or [0])[0],
        "audit_ts": _utc_now(),
    }


def run() -> None:
    pipeline_options = PipelineOptions()
    options = pipeline_options.view_as(CrmIngestionOptions)
    schema_config = _load_schema_config(options.schema_config_path)

    if schema_config["source_type"] != options.source_type:
        raise ValueError(
            "source_type parameter does not match schema config: "
            f"{options.source_type} != {schema_config['source_type']}"
        )

    file_pattern = options.input_prefix.rstrip("/") + "/" + schema_config["file_pattern"]
    rejected_prefix = options.rejected_output_prefix.rstrip("/") + "/part"

    with beam.Pipeline(options=pipeline_options) as pipeline:
        parsed_rows = (
            pipeline
            | "Match input files" >> fileio.MatchFiles(file_pattern)
            | "Read matched files" >> fileio.ReadMatches()
            | "Read CSV rows" >> beam.ParDo(ReadCsvFiles(schema_config))
        )

        validated = (
            parsed_rows
            | "Validate rows"
            >> beam.ParDo(
                ValidateAndFormatRow(
                    schema_config=schema_config,
                    run_date=options.run_date,
                    source_type=options.source_type,
                )
            ).with_outputs("rejected", main="valid")
        )

        valid_rows = validated.valid
        rejected_rows = validated.rejected

        valid_rows | "Write valid rows" >> beam.io.WriteToBigQuery(
            options.output_table,
            schema=_bq_schema(schema_config["columns"]),
            create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
            write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
        )

        (
            rejected_rows
            | "Format rejected rows" >> beam.Map(_json_dumps)
            | "Write rejected rows"
            >> beam.io.WriteToText(
                rejected_prefix,
                file_name_suffix=".jsonl",
            )
        )

        input_count = parsed_rows | "Count input rows" >> beam.combiners.Count.Globally()
        valid_count = valid_rows | "Count valid rows" >> beam.combiners.Count.Globally()
        rejected_count = rejected_rows | "Count rejected rows" >> beam.combiners.Count.Globally()

        audit = (
            {
                "input_count": input_count | "Key input count" >> beam.Map(lambda count: ("audit", count)),
                "valid_count": valid_count | "Key valid count" >> beam.Map(lambda count: ("audit", count)),
                "rejected_count": rejected_count
                | "Key rejected count"
                >> beam.Map(lambda count: ("audit", count)),
            }
            | "Join counts" >> beam.CoGroupByKey()
            | "Build audit row" >> beam.Map(_audit_row, options)
        )

        audit | "Write audit row" >> beam.io.WriteToBigQuery(
            options.audit_table,
            schema=_audit_schema(),
            create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,
            write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
        )


if __name__ == "__main__":
    run()
