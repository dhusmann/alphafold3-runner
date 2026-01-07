#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Base directory where FASTA files are located.
BASE_INPUT_DIR="/scratch/groups/ogozani/alphafold3/jobs/inputs"
# Directory where the final job folders will be created.
OUTPUT_DIR="/scratch/groups/ogozani/alphafold3/jobs"
# --- End Configuration ---

# --- PTM CCD Code Mapping ---
# Use an associative array to map short names to AlphaFold 3 CCD codes.
declare -A CCD_MAP
CCD_MAP[me1]=MLZ
CCD_MAP[me2]=MLY
CCD_MAP[me3]=M3L
CCD_MAP[ac]=ALY
# ---

# --- Argument Parsing ---
# Initialize arrays and variables to store parsed arguments.
FASTA_FILES=()
PTM_ARGS=()
LIGANDS_STR=""

# Loop through all provided arguments to parse them.
while (( "$#" )); do
  case "$1" in
    --ptm)
      # PTM requires 3 arguments: <fasta_index> <position> <type>
      if [ "$#" -lt 4 ]; then
        echo "Error: --ptm requires 3 arguments: <fasta_index> <position> <type>" >&2
        exit 1
      fi
      PTM_ARGS+=("$2 $3 $4")
      shift 4 # Consume --ptm and its 3 arguments
      ;;
    --lig)
      # Ligand requires 1 argument: <ccd1:count,ccd2,...>
      if [ "$#" -lt 2 ]; then
        echo "Error: --lig requires a comma-separated list of CCD codes." >&2
        exit 1
      fi
      LIGANDS_STR="$2"
      shift 2 # Consume --lig and its argument
      ;;
    -*) # Catch any other unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # Otherwise, assume it's a positional FASTA file argument.
      FASTA_FILES+=("$1")
      shift 1 # Consume the fasta file argument
      ;;
  esac
done

# --- Input Validation ---
if [ ${#FASTA_FILES[@]} -eq 0 ]; then
  echo "Usage: $0 <p1.fa> [p2.fa...] [--ptm <idx> <pos> <type>...] [--lig <LIG1:COUNT,LIG2...>]"
  echo ""
  echo "Description:"
  echo "  This script generates an AlphaFold 3 JSON input and creates a uniquely named job directory."
  echo "  It automatically detects Protein, DNA, or RNA sequences from the input FASTA files."
  echo "  It also handles stoichiometry (e.g., '2x...') in the job name."
  echo ""
  echo "  - To specify multiple copies of a molecule (Protein, DNA, RNA), list its FASTA file multiple times."
  echo "  - To specify multiple copies of a LIGAND, use the 'LIGAND:COUNT' syntax in the --lig argument."
  echo ""
  echo "Example for a heterotrimer with two identical subunits:"
  echo "  $0 proteinA.fa proteinA.fa proteinB.fa --lig SAH:2,GTP"
  echo "  # This will create a job folder named '2xproteinA-proteinB-2xSAH-GTP'"
  exit 1
fi

# --- Process Sequences and Detect Molecule Type ---
SEQUENCES=()
MOLECULE_TYPES=()
CLEAN_NAMES=()
for file in "${FASTA_FILES[@]}"; do
  filepath="$BASE_INPUT_DIR/$file"
  if [ ! -f "$filepath" ]; then
    echo "Error: FASTA file not found: $filepath" >&2
    exit 1
  fi
  # Read sequence, removing header and newlines, and convert to uppercase for matching
  seq=$(grep -v '^>' "$filepath" | tr -d '\n\r' | tr '[:lower:]' '[:upper:]')
  SEQUENCES+=("$seq")

  # Clean the name for the directory: remove "h" prefix and ".fa" suffix
  name=$(basename "${file%.fa}")
  name=${name#h}
  CLEAN_NAMES+=("$name")

  # Detect molecule type based on sequence content
  if [[ "$seq" =~ ^[GATC]+$ ]]; then
    MOLECULE_TYPES+=("dna")
  elif [[ "$seq" =~ ^[GAUC]+$ ]]; then
    MOLECULE_TYPES+=("rna")
  else
    MOLECULE_TYPES+=("protein")
  fi
done

# --- Build Stoichiometric Name Part for Proteins/Nucleic Acids ---
declare -A MOLECULE_COUNTS
for name in "${CLEAN_NAMES[@]}"; do
  MOLECULE_COUNTS[$name]=$(( ${MOLECULE_COUNTS[$name]:-0} + 1 ))
done

MOLECULE_NAME_PARTS=()
# Get a unique list of names, preserving the order of first appearance
UNIQUE_CLEAN_NAMES=($(printf "%s\n" "${CLEAN_NAMES[@]}" | awk '!a[$0]++'))
for name in "${UNIQUE_CLEAN_NAMES[@]}"; do
  count=${MOLECULE_COUNTS[$name]}
  if (( count > 1 )); then
    MOLECULE_NAME_PARTS+=("${count}x${name}")
  else
    MOLECULE_NAME_PARTS+=("$name")
  fi
done
MOLECULE_NAME_PART=$(IFS=-; echo "${MOLECULE_NAME_PARTS[*]}")
FINAL_JOB_NAME="$MOLECULE_NAME_PART"


# --- Process PTMs and Augment Job Name ---
declare -A PTM_MAP # Stores PTMs per protein index for JSON generation
PTM_NAME_PART=""
for ptm_arg in "${PTM_ARGS[@]}"; do
  read -r ptm_file_idx ptm_pos ptm_type <<< "$ptm_arg"
  if (( ptm_file_idx < 1 || ptm_file_idx > ${#SEQUENCES[@]} )); then
      echo "Error: Invalid FASTA file index '$ptm_file_idx' for --ptm. Must be between 1 and ${#SEQUENCES[@]}." >&2; exit 1
  fi
  sequence_idx=$((ptm_file_idx - 1)); position_idx=$((ptm_pos - 1))
  # Ensure PTMs are only applied to proteins
  if [[ "${MOLECULE_TYPES[$sequence_idx]}" != "protein" ]]; then
      echo "Error: PTMs can only be applied to proteins. Molecule at index $ptm_file_idx is a ${MOLECULE_TYPES[$sequence_idx]}." >&2; exit 1
  fi
  residue=${SEQUENCES[$sequence_idx]:$position_idx:1}
  PTM_NAME_PART+="_${residue}${ptm_pos}${ptm_type}"
  ccd_code=${CCD_MAP[$ptm_type]}
  if [ -z "$ccd_code" ]; then echo "Error: Unknown PTM type '$ptm_type'." >&2; exit 1; fi
  ptm_json="{\"ptmType\": \"$ccd_code\", \"ptmPosition\": $ptm_pos}"
  PTM_MAP[$ptm_file_idx]+="$ptm_json,"
done
FINAL_JOB_NAME+="$PTM_NAME_PART"

# --- Process Ligands and Augment Job Name ---
LIGAND_CODES_EXPANDED=()
if [ -n "$LIGANDS_STR" ]; then
    ORIGINAL_IFS=$IFS
    IFS=',' read -ra LIGAND_ARRAY <<< "$LIGANDS_STR"
    IFS=$ORIGINAL_IFS

    for item in "${LIGAND_ARRAY[@]}"; do
        count=1
        code="$item"
        if [[ "$item" == *":"* ]]; then
            code="${item%:*}"
            count="${item#*:}"
            if ! [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
                echo "Error: Invalid ligand count in '$item'. Must be a positive integer." >&2
                exit 1
            fi
        fi
        for ((j=0; j<count; j++)); do
            LIGAND_CODES_EXPANDED+=("$code")
        done
    done
fi

# Build Stoichiometric Ligand Name Part
if [ ${#LIGAND_CODES_EXPANDED[@]} -gt 0 ]; then
  declare -A LIGAND_COUNTS
  for code in "${LIGAND_CODES_EXPANDED[@]}"; do
    LIGAND_COUNTS[$code]=$(( ${LIGAND_COUNTS[$code]:-0} + 1 ))
  done

  LIGAND_NAME_PARTS=()
  UNIQUE_LIGAND_CODES=($(printf "%s\n" "${LIGAND_CODES_EXPANDED[@]}" | awk '!a[$0]++'))
  for code in "${UNIQUE_LIGAND_CODES[@]}"; do
      count=${LIGAND_COUNTS[$code]}
      if (( count > 1 )); then LIGAND_NAME_PARTS+=("${count}x${code}"); else LIGAND_NAME_PARTS+=("$code"); fi
  done
  LIGAND_NAME_PART_STR=$(IFS=-; echo "${LIGAND_NAME_PARTS[*]}")
  FINAL_JOB_NAME+="-$LIGAND_NAME_PART_STR"
fi


# --- Create Directory ---
FINAL_DIR="$OUTPUT_DIR/$FINAL_JOB_NAME"
mkdir -p "$FINAL_DIR"

# --- Generate JSON Content ---
JSON_SEQUENCES_ENTRIES=""
CHAIN_ID_ASCII=65 # 'A'

# Add Protein/DNA/RNA sequences to JSON
for i in "${!SEQUENCES[@]}"; do
  chain_id=$(printf "\\$(printf '%03o' "$CHAIN_ID_ASCII")")
  sequence="${SEQUENCES[$i]}"
  molecule_type="${MOLECULE_TYPES[$i]}"
  molecule_idx=$((i + 1))

  [ -n "$JSON_SEQUENCES_ENTRIES" ] && JSON_SEQUENCES_ENTRIES+=","
  
  modifications_json=""
  if [[ "$molecule_type" == "protein" ]] && [ -n "${PTM_MAP[$molecule_idx]}" ]; then
    mods=$(echo "${PTM_MAP[$molecule_idx]}" | sed 's/,$//')
    modifications_json=",\"modifications\": [ $mods ]"
  fi
  
  # Generate the correct JSON entry based on the detected molecule type
  molecule_entry=$(printf '\n    {\n      "%s": {\n        "id": "%s",\n        "sequence": "%s"%s\n      }\n    }' "$molecule_type" "$chain_id" "$sequence" "$modifications_json")
  JSON_SEQUENCES_ENTRIES+="$molecule_entry"
  ((CHAIN_ID_ASCII++))
done

# Add ligand sequences to JSON from the expanded list
for ligand_ccd in "${LIGAND_CODES_EXPANDED[@]}"; do
  chain_id=$(printf "\\$(printf '%03o' "$CHAIN_ID_ASCII")")
  [ -n "$JSON_SEQUENCES_ENTRIES" ] && JSON_SEQUENCES_ENTRIES+=","
  ligand_entry=$(printf '\n    {\n      "ligand": {\n        "id": "%s",\n        "ccdCodes": ["%s"]\n      }\n    }' "$chain_id" "$ligand_ccd")
  JSON_SEQUENCES_ENTRIES+="$ligand_entry"
  ((CHAIN_ID_ASCII++))
done

# Assemble the final JSON file using a heredoc.
cat <<EOF > "$FINAL_DIR/alphafold_input.json"
{
  "name": "$FINAL_JOB_NAME",
  "modelSeeds": [1, 2, 8, 42, 88],
  "sequences": [${JSON_SEQUENCES_ENTRIES}
  ],
  "dialect": "alphafold3",
  "version": 1
}
EOF

echo $FINAL_JOB_NAME >> /scratch/groups/ogozani/alphafold3/folding_jobs.csv
echo "✅ Success! AlphaFold 3 input created at:"
echo "$FINAL_DIR"

