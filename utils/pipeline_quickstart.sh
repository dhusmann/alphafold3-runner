#!/bin/bash

# AlphaFold3 Pipeline Quick Start and Validation Script

# Get script location and repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "====================================="
echo "AlphaFold3 Pipeline Quick Start"
echo "====================================="
echo

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check current directory
if [[ "$PWD" != *"/alphafold3"* ]]; then
    echo -e "${YELLOW}Warning: Not in alphafold3 directory${NC}"
    echo "Current directory: $PWD"
    echo
fi

# Function to check if file exists
check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} $1"
        return 0
    else
        echo -e "${RED}✗${NC} $1 - NOT FOUND"
        return 1
    fi
}

# Function to check if directory exists
check_dir() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✓${NC} $1/"
        return 0
    else
        echo -e "${RED}✗${NC} $1/ - NOT FOUND"
        return 1
    fi
}

# Check required scripts
echo "Checking pipeline scripts:"
SCRIPTS=(
    "core/batch_reuse_msa.py"
    "core/submit_msa_arrays.sh"
    "core/submit_msa_array.sh"
    "monitoring/monitor_msa_arrays.sh"
    "utils/cleanup_msa_tmp.sh"
    "core/submit_dist.sh"
    "core/submit_gpu.sh"
    "core/launch_af3.sh"
    "core/af3_48hr_cycle.sh"
    "monitoring/get_job_status.sh"
    "monitoring/get_job_status_detailed.sh"
    "monitoring/pipeline_status.sh"
    "monitoring/pipeline_summary.sh"
    "sync/sync_organize_outputs.sh"
    "sync/rclone_to_gdrive.sh"
    "monitoring/check_sync_status.sh"
    "monitoring/check_rclone_status.sh"
    "sync/sync_all.sh"
    "utils/clean_output_dir.sh"
    "tools/test_seed_detection.sh"
)

MISSING_SCRIPTS=0
for script in "${SCRIPTS[@]}"; do
    if ! check_file "$REPO_ROOT/$script"; then
        ((MISSING_SCRIPTS++))
    fi
done

echo

# Check required directories
echo "Checking directories:"
check_dir "jobs"
check_dir "logs"
check_dir "alphafold3_resources"

echo

# Check input file
echo "Checking input files:"
if check_file "folding_jobs.csv"; then
    JOB_COUNT=$(tail -n +2 folding_jobs.csv | grep -v "^$" | wc -l)
    echo "  → Contains $JOB_COUNT jobs"
fi

echo

# Check Python
echo "Checking Python environment:"
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    echo -e "${GREEN}✓${NC} Python available: $PYTHON_VERSION"
else
    echo -e "${RED}✗${NC} Python not found"
    echo "  → Try: ml python/3.9.0"
fi

echo

# Make scripts executable
if [ $MISSING_SCRIPTS -eq 0 ]; then
    echo "Making scripts executable..."
    chmod +x "$REPO_ROOT"/core/*.sh "$REPO_ROOT"/core/*.py 2>/dev/null
    chmod +x "$REPO_ROOT"/sync/*.sh 2>/dev/null
    chmod +x "$REPO_ROOT"/monitoring/*.sh 2>/dev/null
    chmod +x "$REPO_ROOT"/utils/*.sh 2>/dev/null
    chmod +x "$REPO_ROOT"/tools/*.sh 2>/dev/null
    echo -e "${GREEN}✓${NC} Scripts are now executable"
else
    echo -e "${RED}Missing $MISSING_SCRIPTS scripts - cannot proceed${NC}"
    exit 1
fi

echo
echo "====================================="
echo "Quick Start Options:"
echo "====================================="
echo
echo "1. Test MSA reuse (dry run):"
echo "   python $REPO_ROOT/core/batch_reuse_msa.py --dry-run"
echo
echo "2. Start automated 48-hour pipeline:"
echo "   $REPO_ROOT/core/launch_af3.sh"
echo
echo "3. Run individual steps:"
echo "   python $REPO_ROOT/core/batch_reuse_msa.py"
echo "   $REPO_ROOT/core/submit_msa_arrays.sh"
echo "   $REPO_ROOT/core/submit_dist.sh"
echo
echo "4. Monitor progress:"
echo "   $REPO_ROOT/monitoring/monitor_msa_arrays.sh"
echo "   squeue -u \$USER"
echo
echo "====================================="

# Quick validation of job directories
echo
read -p "Would you like to validate job directories? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo
    echo "Validating job directories..."
    
    if [ -f "folding_jobs.csv" ]; then
        VALID=0
        INVALID=0
        
        while IFS= read -r line; do
            # Skip header and empty lines
            if [[ "$line" =~ input_folder_name ]] || [[ -z "$line" ]]; then
                continue
            fi
            
            job_name=$(echo "$line" | tr -d '"' | xargs)
            
            if [ -d "jobs/$job_name" ] || [ -d "jobs/human_test_set/$job_name" ]; then
                ((VALID++))
            else
                ((INVALID++))
                if [ $INVALID -le 5 ]; then
                    echo -e "${RED}✗${NC} Missing: $job_name"
                fi
            fi
        done < "folding_jobs.csv"
        
        echo
        echo "Job directory summary:"
        echo "  Valid: $VALID"
        echo "  Missing: $INVALID"
        
        if [ $INVALID -gt 5 ]; then
            echo "  (showing first 5 missing jobs)"
        fi
    fi
fi

echo
echo "====================================="
echo -e "${GREEN}Setup complete!${NC}"
echo "====================================="
