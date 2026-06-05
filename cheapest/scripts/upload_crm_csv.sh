#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  upload_crm_csv.sh [options]

Options:
  --run-date YYYY-MM-DD     Run date used in GCS prefix and lab file names. Defaults to today.
  --source-dir PATH         Directory containing CRM CSV files.
  --bucket gs://BUCKET      Destination bucket. Defaults to gs://cheapest-497709-crm-lake.
  --project PROJECT_ID      GCP project id. Defaults to cheapest-497709.
  --log-dir PATH            Directory for upload logs. Defaults to /tmp/cheapest-crm-upload-logs.
  --dry-run                 Print what would be uploaded without copying files.
  -h, --help                Show this help.

Example:
  ./upload_crm_csv.sh --run-date 2026-05-26

Production example:
  ./upload_crm_csv.sh \
    --run-date "$(date +%F)" \
    --source-dir /opt/companyx/crm_exports \
    --log-dir /var/log/companyx/crm-upload
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

RUN_DATE="$(date +%F)"
PROJECT_ID="cheapest-497709"
BUCKET="gs://cheapest-497709-crm-lake"
SOURCE_DIR="${WORKSPACE_ROOT}/local-data-lab-repo/data/crm"
LOG_DIR="${TMPDIR:-/tmp}/cheapest-crm-upload-logs"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-date)
      RUN_DATE="${2:?--run-date requires a value}"
      shift 2
      ;;
    --source-dir)
      SOURCE_DIR="${2:?--source-dir requires a value}"
      shift 2
      ;;
    --bucket)
      BUCKET="${2:?--bucket requires a value}"
      shift 2
      ;;
    --project)
      PROJECT_ID="${2:?--project requires a value}"
      shift 2
      ;;
    --log-dir)
      LOG_DIR="${2:?--log-dir requires a value}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "${RUN_DATE}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "RUN_DATE must use YYYY-MM-DD format: ${RUN_DATE}" >&2
  exit 2
fi

if [[ ! "${BUCKET}" =~ ^gs://[^/]+$ ]]; then
  echo "BUCKET must look like gs://bucket-name without a trailing path: ${BUCKET}" >&2
  exit 2
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
  echo "Source directory does not exist: ${SOURCE_DIR}" >&2
  exit 1
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud command not found. Install Google Cloud CLI before running this script." >&2
  exit 1
fi

RUN_DATE_FOR_FILE="${RUN_DATE//-/_}"
DESTINATION="${BUCKET}/raw/crm/${RUN_DATE}/"
mkdir -p "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/crm-upload-${RUN_DATE}-$(date +%Y%m%dT%H%M%S).log"
MANIFEST_FILE="${LOG_DIR}/crm-upload-${RUN_DATE}-manifest.csv"

EXPECTED_FILES=(
  "crm_sales_${RUN_DATE_FOR_FILE}.csv"
  "crm_support_${RUN_DATE_FOR_FILE}.csv"
  "crm_campaign_events_${RUN_DATE_FOR_FILE}.csv"
  "crm_new_partner_leads_${RUN_DATE_FOR_FILE}.csv"
)

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${LOG_FILE}"
}

log "Starting CRM upload"
log "project=${PROJECT_ID}"
log "run_date=${RUN_DATE}"
log "source_dir=${SOURCE_DIR}"
log "destination=${DESTINATION}"
log "dry_run=${DRY_RUN}"

missing_files=0
for file_name in "${EXPECTED_FILES[@]}"; do
  file_path="${SOURCE_DIR}/${file_name}"
  if [[ ! -f "${file_path}" ]]; then
    log "MISSING file=${file_path}"
    missing_files=1
  fi
done

if [[ "${missing_files}" -ne 0 ]]; then
  log "Upload aborted because one or more expected CRM CSV files are missing."
  exit 1
fi

printf 'run_date,file_name,source_path,size_bytes,destination,exit_code\n' > "${MANIFEST_FILE}"

upload_failed=0
for file_name in "${EXPECTED_FILES[@]}"; do
  file_path="${SOURCE_DIR}/${file_name}"
  size_bytes="$(wc -c < "${file_path}" | tr -d ' ')"
  object_uri="${DESTINATION}${file_name}"

  log "Uploading file=${file_name} size_bytes=${size_bytes} destination=${object_uri}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    exit_code=0
    log "DRY_RUN would upload ${file_path} to ${object_uri}"
  elif gcloud --project="${PROJECT_ID}" storage cp "${file_path}" "${object_uri}" >>"${LOG_FILE}" 2>&1; then
    exit_code=0
    log "SUCCESS file=${file_name}"
  else
    exit_code=$?
    upload_failed=1
    log "FAILED file=${file_name} exit_code=${exit_code}"
  fi

  printf '%s,%s,%s,%s,%s,%s\n' \
    "${RUN_DATE}" \
    "${file_name}" \
    "${file_path}" \
    "${size_bytes}" \
    "${object_uri}" \
    "${exit_code}" >> "${MANIFEST_FILE}"
done

if [[ "${upload_failed}" -ne 0 ]]; then
  log "Upload finished with failures. Manifest: ${MANIFEST_FILE}"
  exit 1
fi

if [[ "${DRY_RUN}" == "false" ]]; then
  object_count="$(gcloud --project="${PROJECT_ID}" storage ls "${DESTINATION}" | wc -l | tr -d ' ')"
  log "Uploaded object_count=${object_count}"

  if [[ "${object_count}" -ne "${#EXPECTED_FILES[@]}" ]]; then
    log "Unexpected object count at ${DESTINATION}. Expected ${#EXPECTED_FILES[@]}, got ${object_count}."
    exit 1
  fi
fi

log "CRM upload completed successfully. Manifest: ${MANIFEST_FILE}"
