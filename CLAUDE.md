# AlphaFold3 Sync System - AI Assistant Instructions

## Project Context
This is a high-throughput AlphaFold3 prediction project with 13,700+ methyltransferase-substrate predictions. The system has been optimized for parallel processing and efficient data organization.

## Key System Architecture

### Parallel Processing System
- **All heavy I/O operations run on compute nodes via SLURM** - never on login nodes
- **Dynamic scaling**: System handles any number of jobs without hardcoding
- **320+ concurrent operations** using GNU parallel and SLURM arrays
- **Configuration**: Edit `sync_parallel.conf` for performance tuning

### MSA Management Strategy
- **Smart deduplication**: Only unique MSA files (*_data.json) are archived
- **10-50x storage reduction** through eliminating shared MSAs
- **Master index**: `output/msa/master_index.csv` tracks all archived files
- **Search paths**: Include both main jobs and `human_test_set/` subdirectory
- **Efficient file discovery**: Uses bash glob patterns instead of nested find commands
- **Dynamic processing**: Handles 486+ job groups without hardcoded limits

### Critical Files to Never Remove
- `msa_array_jobs_part*.tmp` - These are created by running SLURM processes, not our scripts
- Any files in `/tmp/tmp.*` patterns used by `mktemp` in scripts
- Always ask user before removing any .tmp files

## Main Workflow Scripts

### sync_all.sh - Primary Entry Point
- **Fully automated** - no confirmation prompts
- Orchestrates entire workflow: local processing + Google Drive sync
- Options: `--dry-run`, `--quiet`, `--local-only`

### sync_organize_outputs.sh - Local Processing Orchestrator
- Submits SLURM array jobs for parallel operations
- Dependencies: rsync → MSA archiving → seed compression → Google Drive
- Never runs heavy operations on login node

### Key Worker Scripts
- `sync_organize_rsync.sh` - Parallel rsync using GNU parallel
- `archive_msa_data.sh` - MSA deduplication and archiving (fixed hanging issues)
- `compress_seeds_array.sbatch` - Parallel seed compression
- `rclone_to_gdrive.sh` - Complete backup with deterministic filter rules

## Organization Pattern Maintained
```
output/
├── msa/                    # Deduplicated MSA archives
├── arabidopsis_EEF1A/      # Jobs with *ateef1a*
├── ecoli/ecEFTU/           # Jobs with *eftu*
├── human_EF_KMTs/EEF1A/    # Jobs starting with eef1akmt* or mettl13*
├── yeast/EFM/              # Jobs starting with scefm*
├── NSD2i/                  # Jobs with aa*[0-9]to[0-9]*
└── human_test_set/         # All human test set jobs
```

## Common Issues & Solutions

### MSA Archiving Problems
- **Issue**: Script not finding jobs in `human_test_set/`
- **Solution**: Ensure find command includes both paths:
  ```bash
  find "$JOBS_DIR" "$JOBS_DIR/human_test_set" -maxdepth 2 -type d
  ```

- **Issue**: Script hanging during MSA archiving
- **Solution**: Use bash glob patterns instead of nested for loops with command substitution:
  ```bash
  # BAD: This hangs with many files
  for job_path in $(find "$JOBS_DIR" -name "${job_group}-*"); do
  
  # GOOD: Use direct glob patterns
  for job_path in "$JOBS_DIR"/${job_group}-*; do
  ```

- **Issue**: Arithmetic expansion failing with set -euo pipefail
- **Solution**: Use explicit assignment instead of shorthand:
  ```bash
  # BAD: Can cause script to exit
  ((current_group++))
  
  # GOOD: Safe with set -euo pipefail
  current_group=$((current_group + 1))
  ```

- **Issue**: rclone filter warnings about mixing --include and --exclude
- **Solution**: Use deterministic --filter rules instead:
  ```bash
  # BAD: Indeterminate parsing order
  --exclude "**/seed-*/**" --include "**/seeds.tar.gz"
  
  # GOOD: Deterministic filter rules
  --filter "+ msa/**" --filter "+ **/seeds.tar.gz" --filter "- **/seed-*/**" --filter "+ **"
  ```

### Function Return Values
- **Issue**: Echo statements breaking temp file handling
- **Solution**: Redirect informational output to stderr:
  ```bash
  echo "Status message" >&2  # Not stdout
  ```

### Performance Tuning
- **Large job counts**: Increase `JOBS_PER_TASK` in `sync_parallel.conf`
- **Resource limits**: Reduce `MAX_ARRAY_TASKS` and `PARALLEL_WORKERS`
- **Testing**: Set `MAX_JOBS_LIMIT` environment variable

## Monitoring Commands
```bash
# Check all jobs
squeue -u $USER

# View specific logs
tail -f logs/sync_rsync_*.out      # Rsync progress
tail -f logs/archive_msa_*.out     # MSA archiving
tail -f logs/Rclone_*.out          # Google Drive sync
```

## Never Do These Things
1. Run sync operations on login nodes - always submit to SLURM
2. Remove msa_array_jobs_part*.tmp files - they're from running processes
3. Hardcode job counts - system must scale dynamically
4. Remove stdout redirections in functions that return temp file paths
5. Skip the human_test_set directory in search operations

## Performance Improvements Made
- **Rsync**: 2-4 hours → 5-15 minutes (10-50x faster)
- **MSA Storage**: Individual files → compressed archives (10-50x reduction)
- **MSA Archiving**: Now processes all 486+ job groups without hanging
- **Seed Compression**: Sequential → parallel (5-20x faster)
- **Overall**: Manual blocking → automated non-blocking workflow

## MSA Archiving Implementation Details
- **File discovery**: Uses direct bash glob patterns for efficiency
- **Processing order**: Iterates through job directories first, then finds MSA files
- **Dual structure support**: 
  - Main jobs: `output_msa/*_data.json`
  - Human test set: `output_msa/{job_name}/{job_name}_data.json`
- **Archive naming**: `{GROUP}_YYYY_MM_DD.tar.gz` format
- **Tested archives**: Successfully creates archives like `FBL_2025_09_08.tar.gz` and `Q9M027_2025_09_08.tar.gz`

## Google Drive Structure
After sync: `gozani_labshare_alphafold:alphafold3/` contains:
- `scripts/` - All pipeline scripts and tools
- `analysis/` - Analysis files and results
- `output/` - Organized AlphaFold3 results with MSA archives

This system processes thousands of jobs efficiently while keeping login nodes free for interactive work.