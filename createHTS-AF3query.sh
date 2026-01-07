#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Base directory where FASTA files are located.
BASE_INPUT_DIR="/scratch/groups/ogozani/alphafold3/jobs/inputs"
# Directory where the final job folders will be created.
OUTPUT_DIR="/scratch/groups/ogozani/alphafold3/jobs/human_test_set"
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
EACH_PTM_ARGS=()
LIGANDS_STR=""

# Loop through all provided arguments to parse them.
while (( "$#" )); do
  case "$1" in
    --ptm)
      # PTM can be: 
      # --ptm <fasta_index> <position> <type> 
      # --ptm ALL <type>
      # --ptm <fasta_index> ALL <type>
      if [ "$#" -lt 3 ]; then
        echo "Error: --ptm requires at least 2 arguments" >&2
        exit 1
      fi
      
      if [ "$2" = "ALL" ]; then
        # Handle --ptm ALL <type> syntax (applies to last protein)
        if [ "$#" -lt 3 ]; then
          echo "Error: --ptm ALL requires a PTM type" >&2
          exit 1
        fi
        PTM_ARGS+=("ALL $3")
        shift 3 # Consume --ptm, ALL, and type
      elif [ "$#" -ge 4 ] && [ "$3" = "ALL" ]; then
        # Handle --ptm <fasta_index> ALL <type> syntax
        if [ "$#" -lt 4 ]; then
          echo "Error: --ptm <index> ALL requires a PTM type" >&2
          exit 1
        fi
        PTM_ARGS+=("$2 ALL $4")
        shift 4 # Consume --ptm, index, ALL, and type
      elif [ "$#" -ge 4 ] && [ "$3" = "EACH" ]; then
        # Handle --ptm <fasta_index> EACH <type> syntax
        if [ "$#" -lt 4 ]; then
          echo "Error: --ptm <index> EACH requires a PTM type" >&2
          exit 1
        fi
        EACH_PTM_ARGS+=("$2 $4")
        shift 4 # Consume --ptm, index, EACH, and type
      else
        # Handle regular --ptm <fasta_index> <position> <type> syntax
        if [ "$#" -lt 4 ]; then
          echo "Error: --ptm requires 3 arguments: <fasta_index> <position> <type>" >&2
          exit 1
        fi
        PTM_ARGS+=("$2 $3 $4")
        shift 4 # Consume --ptm and its 3 arguments
      fi
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
  echo "Usage: $0 <p1.fa> [p2.fa...] [--ptm <idx> <pos> <type>...] [--ptm ALL <type>] [--ptm <idx> ALL <type>] [--ptm <idx> EACH <type>] [--lig <LIG1:COUNT,LIG2...>]"
  echo ""
  echo "Description:"
  echo "  This script generates an AlphaFold 3 JSON input and creates a uniquely named job directory."
  echo "  It automatically detects Protein, DNA, or RNA sequences from the input FASTA files."
  echo "  It also handles stoichiometry (e.g., '2x...') in the job name."
  echo ""
  echo "  - To specify multiple copies of a molecule (Protein, DNA, RNA), list its FASTA file multiple times."
  echo "  - To specify multiple copies of a LIGAND, use the 'LIGAND:COUNT' syntax in the --lig argument."
  echo "  - Use '--ptm ALL <type>' to apply a PTM to all lysine residues in the last protein."
  echo "  - Use '--ptm <idx> ALL <type>' to apply a PTM to all lysine residues in a specific protein."
  echo "  - Use '--ptm <idx> EACH <type>' to create separate jobs, each with one lysine modified in the specified protein."
  echo ""
  echo "Example for a heterotrimer with two identical subunits:"
  echo "  $0 proteinA.fa proteinA.fa proteinB.fa --lig SAH:2,GTP"
  echo "  # This will create a job folder named '2xproteinA-proteinB-2xSAH-GTP'"
  echo ""
  echo "Example with ALL PTM on specific protein:"
  echo "  $0 protein1.fa protein2.fa --ptm 2 ALL me1 --lig SAH"
  echo "  # This will create a job folder named 'protein1-protein2_KALLme1-SAH'"
  echo ""
  echo "Example with EACH PTM on specific protein:"
  echo "  $0 protein1.fa protein2.fa --ptm 2 EACH me1 --lig SAH"
  echo "  # This will create separate job folders for each lysine: 'protein1-protein2_K15me1-SAH', 'protein1-protein2_K23me1-SAH', etc."
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
HAS_ALL_PTM=false
ALL_PTM_TYPE=""

for ptm_arg in "${PTM_ARGS[@]}"; do
  if [[ "$ptm_arg" =~ ^ALL[[:space:]](.+)$ ]]; then
    # Handle --ptm ALL <type> case (applies to last protein)
    HAS_ALL_PTM=true
    ALL_PTM_TYPE="${BASH_REMATCH[1]}"
    
    # Find the last protein in the sequence list
    last_protein_idx=-1
    for i in "${!MOLECULE_TYPES[@]}"; do
      if [[ "${MOLECULE_TYPES[$i]}" == "protein" ]]; then
        last_protein_idx=$((i + 1))  # Convert to 1-indexed
      fi
    done
    
    if [ $last_protein_idx -eq -1 ]; then
      echo "Error: No protein found for ALL PTM application." >&2
      exit 1
    fi
    
    # Find all lysine positions in the last protein
    sequence_idx=$((last_protein_idx - 1))
    sequence="${SEQUENCES[$sequence_idx]}"
    
    # Find all K positions and apply PTMs
    ccd_code=${CCD_MAP[$ALL_PTM_TYPE]}
    if [ -z "$ccd_code" ]; then 
      echo "Error: Unknown PTM type '$ALL_PTM_TYPE'." >&2
      exit 1
    fi
    
    for ((pos=0; pos<${#sequence}; pos++)); do
      if [ "${sequence:$pos:1}" = "K" ]; then
        ptm_pos=$((pos + 1))  # Convert to 1-indexed
        ptm_json="{\"ptmType\": \"$ccd_code\", \"ptmPosition\": $ptm_pos}"
        PTM_MAP[$last_protein_idx]+="$ptm_json,"
      fi
    done
    
    # Use compact naming for ALL PTMs
    PTM_NAME_PART+="_KALL${ALL_PTM_TYPE}"
    
  elif [[ "$ptm_arg" =~ ^([0-9]+)[[:space:]]ALL[[:space:]](.+)$ ]]; then
    # Handle --ptm <index> ALL <type> case
    ptm_file_idx="${BASH_REMATCH[1]}"
    ptm_type="${BASH_REMATCH[2]}"
    
    if (( ptm_file_idx < 1 || ptm_file_idx > ${#SEQUENCES[@]} )); then
        echo "Error: Invalid FASTA file index '$ptm_file_idx' for --ptm. Must be between 1 and ${#SEQUENCES[@]}." >&2
        exit 1
    fi
    
    sequence_idx=$((ptm_file_idx - 1))
    
    # Ensure PTMs are only applied to proteins
    if [[ "${MOLECULE_TYPES[$sequence_idx]}" != "protein" ]]; then
        echo "Error: PTMs can only be applied to proteins. Molecule at index $ptm_file_idx is a ${MOLECULE_TYPES[$sequence_idx]}." >&2
        exit 1
    fi
    
    sequence="${SEQUENCES[$sequence_idx]}"
    
    # Find all K positions and apply PTMs
    ccd_code=${CCD_MAP[$ptm_type]}
    if [ -z "$ccd_code" ]; then 
      echo "Error: Unknown PTM type '$ptm_type'." >&2
      exit 1
    fi
    
    lysine_count=0
    for ((pos=0; pos<${#sequence}; pos++)); do
      if [ "${sequence:$pos:1}" = "K" ]; then
        ptm_pos=$((pos + 1))  # Convert to 1-indexed
        ptm_json="{\"ptmType\": \"$ccd_code\", \"ptmPosition\": $ptm_pos}"
        PTM_MAP[$ptm_file_idx]+="$ptm_json,"
        lysine_count=$((lysine_count + 1))
      fi
    done
    
    if [ $lysine_count -eq 0 ]; then
      echo "Warning: No lysine residues found in protein at index $ptm_file_idx" >&2
    else
      echo "Info: Found $lysine_count lysine residues in protein at index $ptm_file_idx" >&2
    fi
    
    # Use compact naming for ALL PTMs on specific protein
    PTM_NAME_PART+="_KALL${ptm_type}"
    
  else
    # Handle regular PTM case
    read -r ptm_file_idx ptm_pos ptm_type <<< "$ptm_arg"
    if (( ptm_file_idx < 1 || ptm_file_idx > ${#SEQUENCES[@]} )); then
        echo "Error: Invalid FASTA file index '$ptm_file_idx' for --ptm. Must be between 1 and ${#SEQUENCES[@]}." >&2
        exit 1
    fi
    sequence_idx=$((ptm_file_idx - 1)); position_idx=$((ptm_pos - 1))
    # Ensure PTMs are only applied to proteins
    if [[ "${MOLECULE_TYPES[$sequence_idx]}" != "protein" ]]; then
        echo "Error: PTMs can only be applied to proteins. Molecule at index $ptm_file_idx is a ${MOLECULE_TYPES[$sequence_idx]}." >&2
        exit 1
    fi
    residue=${SEQUENCES[$sequence_idx]:$position_idx:1}
    PTM_NAME_PART+="_${residue}${ptm_pos}${ptm_type}"
    ccd_code=${CCD_MAP[$ptm_type]}
    if [ -z "$ccd_code" ]; then echo "Error: Unknown PTM type '$ptm_type'." >&2; exit 1; fi
    ptm_json="{\"ptmType\": \"$ccd_code\", \"ptmPosition\": $ptm_pos}"
    PTM_MAP[$ptm_file_idx]+="$ptm_json,"
  fi
done
FINAL_JOB_NAME+="$PTM_NAME_PART"

# --- Process EACH PTMs and Determine Job Structure ---
EACH_JOBS=()  # Array to store job definitions for EACH PTMs
HAS_EACH_PTM=false

for each_ptm_arg in "${EACH_PTM_ARGS[@]}"; do
  HAS_EACH_PTM=true
  read -r ptm_file_idx ptm_type <<< "$each_ptm_arg"
  
  if (( ptm_file_idx < 1 || ptm_file_idx > ${#SEQUENCES[@]} )); then
    echo "Error: Invalid FASTA file index '$ptm_file_idx' for --ptm EACH. Must be between 1 and ${#SEQUENCES[@]}." >&2
    exit 1
  fi
  
  sequence_idx=$((ptm_file_idx - 1))
  
  # Ensure PTMs are only applied to proteins
  if [[ "${MOLECULE_TYPES[$sequence_idx]}" != "protein" ]]; then
    echo "Error: PTMs can only be applied to proteins. Molecule at index $ptm_file_idx is a ${MOLECULE_TYPES[$sequence_idx]}." >&2
    exit 1
  fi
  
  sequence="${SEQUENCES[$sequence_idx]}"
  
  # Find all lysine positions and create separate job definitions
  ccd_code=${CCD_MAP[$ptm_type]}
  if [ -z "$ccd_code" ]; then 
    echo "Error: Unknown PTM type '$ptm_type'." >&2
    exit 1
  fi
  
  lysine_count=0
  for ((pos=0; pos<${#sequence}; pos++)); do
    if [ "${sequence:$pos:1}" = "K" ]; then
      ptm_pos=$((pos + 1))  # Convert to 1-indexed
      # Create job definition: "file_idx:position:type:ccd_code"
      EACH_JOBS+=("$ptm_file_idx:$ptm_pos:$ptm_type:$ccd_code")
      lysine_count=$((lysine_count + 1))
    fi
  done
  
  if [ $lysine_count -eq 0 ]; then
    echo "Warning: No lysine residues found in protein at index $ptm_file_idx for EACH PTM" >&2
  else
    echo "Info: Found $lysine_count lysine residues in protein at index $ptm_file_idx. Will create $lysine_count separate jobs." >&2
  fi
done

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

# --- Function to Create a Single Job ---
create_job() {
  local job_name="$1"
  local each_ptm_file_idx="$2"
  local each_ptm_pos="$3"
  local each_ptm_type="$4"
  local each_ccd_code="$5"
  
  # Create directory
  local job_dir="$OUTPUT_DIR/$job_name"
  mkdir -p "$job_dir"
  
  # Generate JSON Content
  local json_sequences_entries=""
  local chain_id_ascii=65 # 'A'
  
  # Add Protein/DNA/RNA sequences to JSON
  for i in "${!SEQUENCES[@]}"; do
    local chain_id=$(printf "\\$(printf '%03o' "$chain_id_ascii")")
    local sequence="${SEQUENCES[$i]}"
    local molecule_type="${MOLECULE_TYPES[$i]}"
    local molecule_idx=$((i + 1))
    
    [ -n "$json_sequences_entries" ] && json_sequences_entries+=","
    
    local modifications_json=""
    if [[ "$molecule_type" == "protein" ]]; then
      local mods=""
      
      # Add regular PTMs (from PTM_MAP)
      if [ -n "${PTM_MAP[$molecule_idx]}" ]; then
        mods="${PTM_MAP[$molecule_idx]}"
      fi
      
      # Add EACH PTM if this is the target protein
      if [ -n "$each_ptm_file_idx" ] && [ "$molecule_idx" -eq "$each_ptm_file_idx" ]; then
        local each_ptm_json="{\"ptmType\": \"$each_ccd_code\", \"ptmPosition\": $each_ptm_pos}"
        if [ -n "$mods" ]; then
          mods+="$each_ptm_json,"
        else
          mods="$each_ptm_json,"
        fi
      fi
      
      if [ -n "$mods" ]; then
        mods=$(echo "$mods" | sed 's/,$//')
        modifications_json=",\"modifications\": [ $mods ]"
      fi
    fi
    
    # Generate the correct JSON entry based on the detected molecule type
    local molecule_entry=$(printf '\n    {\n      "%s": {\n        "id": "%s",\n        "sequence": "%s"%s\n      }\n    }' "$molecule_type" "$chain_id" "$sequence" "$modifications_json")
    json_sequences_entries+="$molecule_entry"
    ((chain_id_ascii++))
  done
  
  # Add ligand sequences to JSON from the expanded list
  for ligand_ccd in "${LIGAND_CODES_EXPANDED[@]}"; do
    local chain_id=$(printf "\\$(printf '%03o' "$chain_id_ascii")")
    [ -n "$json_sequences_entries" ] && json_sequences_entries+=","
    local ligand_entry=$(printf '\n    {\n      "ligand": {\n        "id": "%s",\n        "ccdCodes": ["%s"]\n      }\n    }' "$chain_id" "$ligand_ccd")
    json_sequences_entries+="$ligand_entry"
    ((chain_id_ascii++))
  done
  
  # Assemble the final JSON file using a heredoc.
  cat <<EOF > "$job_dir/alphafold_input.json"
{
  "name": "$job_name",
  "modelSeeds": [1, 2, 8, 42, 88],
  "sequences": [${json_sequences_entries}
  ],
  "dialect": "alphafold3",
  "version": 1
}
EOF

  echo "$job_name" >> /scratch/groups/ogozani/alphafold3/folding_jobs.csv
}

# --- Create Jobs ---
if [ "$HAS_EACH_PTM" = true ]; then
  # Create multiple jobs - one for each lysine in EACH PTMs
  for each_job in "${EACH_JOBS[@]}"; do
    IFS=':' read -r ptm_file_idx ptm_pos ptm_type ccd_code <<< "$each_job"
    
    # Build job name with specific lysine position
    ligand_suffix=""
    if [ -n "$LIGAND_NAME_PART_STR" ]; then
      ligand_suffix="-$LIGAND_NAME_PART_STR"
    fi
    
    each_job_name="${MOLECULE_NAME_PART}_K${ptm_pos}${ptm_type}${ligand_suffix}"
    
    create_job "$each_job_name" "$ptm_file_idx" "$ptm_pos" "$ptm_type" "$ccd_code"
  done
else
  # Create single job (original behavior)
  create_job "$FINAL_JOB_NAME"
fi
