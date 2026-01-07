#!/bin/bash

# Launcher script for AlphaFold3 48-hour cycling job
# Modified to run first cycle directly on login node for immediate feedback
TOTAL_CYCLES=72
CYCLE_LENGTH=1

echo "========================================="
echo "Starting AlphaFold3 48-hour automated pipeline..."
echo "========================================="
echo ""
echo "What will happen:"
echo "  1. Initial MSA analysis and array job submission (Cycle 1) - RUNNING NOW"
echo "  2. GPU job submissions every $CYCLE_LENGTH hours (Cycles 1-$TOTAL_CYCLES)"
echo "  3. Automatic processing of jobs as MSAs complete"
echo "  4. Email notification after last cycle"
echo ""
echo "Total runtime: $TOTAL_CYCLES cycles × $CYCLE_LENGTH hour(s))"
echo ""
echo "Note: First cycle will run directly here for immediate feedback"
echo "      Subsequent cycles will run as SLURM jobs"
echo ""

# Set base directory
BASE_DIR="/scratch/groups/ogozani/alphafold3"
cd "$BASE_DIR"

# Set up script paths relative to repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

SUBMIT_SCRIPT="${REPO_ROOT}/core/submit_dist.sh"
CYCLE_SCRIPT="${REPO_ROOT}/core/af3_48hr_cycle.sh"
MSA_ARRAYS_SCRIPT="${REPO_ROOT}/core/submit_msa_arrays.sh"
BATCH_REUSE_SCRIPT="${REPO_ROOT}/core/batch_reuse_msa.py"
CYCLE_NUM=1

# Check if the submit script exists
if [ ! -f "$SUBMIT_SCRIPT" ]; then
    echo "ERROR: Submit script not found at $SUBMIT_SCRIPT"
    echo "Please check the path and try again."
    exit 1
fi

# Make sure required scripts are executable
chmod +x "$SUBMIT_SCRIPT" "$MSA_ARRAYS_SCRIPT" "$BATCH_REUSE_SCRIPT" 2>/dev/null

# Load python module for batch_reuse_msa.py
ml python/3.12.1 2>/dev/null || module load python/3.12.1 2>/dev/null || true

echo "========================================="
echo "AlphaFold3 Cycle $CYCLE_NUM of $TOTAL_CYCLES"
echo "Started at $(date)"
echo "Working directory: $(pwd)"
echo "========================================="

# Run first cycle directly on login node
echo ""
echo "=== First cycle: Running initial MSA analysis and submission ==="

# Run batch_reuse_msa.py to identify MSA needs
echo "Running batch_reuse_msa.py to analyze MSA requirements..."
"$BATCH_REUSE_SCRIPT"

if [ $? -eq 0 ]; then
    # Check if there are MSA jobs to submit
    if [ -f "msa_array_jobs.csv" ]; then
        MSA_COUNT=$(tail -n +2 msa_array_jobs.csv | grep -v "^$" | wc -l)
        
        if [ $MSA_COUNT -gt 0 ]; then
            echo ""
            echo "Found $MSA_COUNT jobs requiring MSA generation"
            echo "Submitting MSA array jobs..."

            "$MSA_ARRAYS_SCRIPT" msa_array_jobs.csv
            
            if [ $? -eq 0 ]; then
                echo "MSA array jobs submitted successfully"
                
                # Check how many were actually submitted
                MSA_RUNNING=$(squeue -u $USER -n af3_msa_array -h | wc -l)
                echo "MSA array jobs in queue: $MSA_RUNNING"
                
                # If many MSA jobs were submitted, skip GPU submission this cycle
                if [ $MSA_RUNNING -gt 100 ]; then
                    echo ""
                    echo "Large number of MSA jobs submitted ($MSA_RUNNING)"
                    echo "Skipping GPU submission this cycle to allow MSAs to start"
                    echo "GPU submissions will begin in cycle 2"
                else
                    # Run submit_dist.sh as normal
                    echo ""
                    echo "Proceeding with GPU job submission..."
                    "$SUBMIT_SCRIPT"
                fi
            else
                echo "ERROR: Failed to submit MSA array jobs"
                echo "Continuing with GPU submission anyway..."
                "$SUBMIT_SCRIPT"
            fi
        else
            echo "No MSA jobs to submit (all MSAs already exist)"
            echo "Proceeding with GPU job submission..."
            "$SUBMIT_SCRIPT"
        fi
    else
        echo "No msa_array_jobs.csv file created"
        echo "Proceeding with GPU job submission..."
        "$SUBMIT_SCRIPT"
    fi
else
    echo "WARNING: batch_reuse_msa.py failed"
    echo "Proceeding with GPU job submission anyway..."
    "$SUBMIT_SCRIPT"
fi

# Check the exit status
exit_status=$?
if [ $exit_status -eq 0 ]; then
    echo ""
    echo "Cycle $CYCLE_NUM completed successfully at $(date)"
else
    echo ""
    echo "WARNING: Cycle $CYCLE_NUM exited with status $exit_status at $(date)"
fi

# Submit the next cycle to run in $CYCLE_LENGTH hours
NEXT_CYCLE=2
START_TIME=$(date -d "+$CYCLE_LENGTH hours" "+%Y-%m-%dT%H:%M:%S")

echo ""
echo "========================================="
echo "Submitting cycle $NEXT_CYCLE to start at $START_TIME"

# Submit next job with delayed start as a SLURM job
NEXT_JOBID=$(sbatch --begin="$START_TIME" --export=ALL "$CYCLE_SCRIPT" $NEXT_CYCLE | awk '{print $4}')

if [ $? -eq 0 ]; then
    echo "Next cycle submitted successfully with job ID: $NEXT_JOBID"
    echo ""
    echo "The pipeline will now run automatically for $TOTAL_CYCLES cyles ($CYCLE_LENGTH hours per cycle)."
    echo "Each cycle will submit the next one to run $CYCLE_LENGTH hours later"
    echo ""
    echo "Monitor progress with:"
    echo "  squeue -u $USER"
    echo "  tail -f af3_cycle_${NEXT_JOBID}_*.out"
    echo "  ${REPO_ROOT}/monitoring/pipeline_status.sh"
    echo "  ${REPO_ROOT}/monitoring/monitor_msa_arrays.sh"
    echo ""
    echo "You will receive an email at dhusmann@stanford.edu when all cycles complete"
else
    echo "ERROR: Failed to submit next cycle"
    exit 1
fi

echo "========================================="
echo "First cycle completed. Pipeline is now running automatically."
echo "========================================="
