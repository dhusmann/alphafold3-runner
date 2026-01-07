# AlphaFold3 Pipeline Scripts Summary

## Directory Structure

```
alphafold3-runner/
├── core/           # Core pipeline scripts
├── sync/           # Output sync scripts
├── monitoring/     # Status & monitoring
├── utils/          # Cleanup & utilities
├── tools/          # Helper tools
├── docs/           # Documentation
├── createAF3query*.sh  # Query creation (top-level)
└── README.md
```

## Complete Script List (Total: 31 scripts)

### Query Creation Scripts (4) - Top Level
1. **createAF3query.sh** - Creates AF3 job directories with alphafold_input.json
2. **createAF3query_withSMILES.sh** - Creates jobs with SMILES ligand definitions
3. **createHTS-AF3query.sh** - Creates human test set queries
4. **createBatchAF3queries.sh** - Batch wrapper for createAF3query.sh

### Core Pipeline Scripts (7) - `core/`
5. **core/batch_reuse_msa.py** - Identifies and reuses existing MSAs
6. **core/submit_msa_arrays.sh** - Distributes MSA jobs across partitions
7. **core/submit_msa_array.sh** - Runs individual MSA generation
8. **core/submit_dist.sh** - Manages GPU job distribution
9. **core/submit_gpu.sh** - Runs individual GPU inference
10. **core/launch_af3.sh** - Starts 48-hour automation
11. **core/af3_48hr_cycle.sh** - Handles periodic execution

### Monitoring Scripts (7) - `monitoring/`
12. **monitoring/monitor_msa_arrays.sh** - Monitors MSA array jobs
13. **monitoring/get_job_status.sh** - Reports job stages and seeds
14. **monitoring/get_job_status_detailed.sh** - Advanced status with filters
15. **monitoring/pipeline_status.sh** - Quick dashboard view
16. **monitoring/pipeline_summary.sh** - Complete pipeline overview with sync status
17. **monitoring/check_sync_status.sh** - Shows sync readiness
18. **monitoring/check_rclone_status.sh** - Monitor rclone SLURM jobs

### Output Sync Scripts (10) - `sync/`
19. **sync/sync_all.sh** - Complete sync workflow
20. **sync/sync_organize_outputs.sh** - Syncs and organizes outputs locally
21. **sync/sync_organize_rsync.sh** - Parallel rsync worker
22. **sync/sync_organize_rsync.sbatch** - SLURM rsync job
23. **sync/sync_job_discovery.sh** - Job discovery utility
24. **sync/archive_msa_data.sh** - MSA archiving
25. **sync/archive_msa_data.sbatch** - SLURM archive job
26. **sync/compress_seeds_array.sbatch** - SLURM seed compression
27. **sync/rclone_to_gdrive.sh** - Submits SLURM job for Google Drive upload
28. **sync/rclone_retry.sh** - Retry failed syncs
29. **sync/sync_parallel.conf.template** - Configuration template

### Utility Scripts (5) - `utils/`
30. **utils/cleanup_msa_tmp.sh** - Removes temporary MSA files
31. **utils/clean_output_dir.sh** - Cleans output directory
32. **utils/compress_seeds.sh** - Manual seed compression utility
33. **utils/pipeline_quickstart.sh** - Validates setup
34. **utils/pack_seeds_human_test_set.sbatch** - Pack seeds for human test set

### Helper Tools (10) - `tools/`
35. **tools/find_single_enzyme_ligand_jobs.py** - Identify single-protein–ligand jobs
36. **tools/clear_output_msa_jsons.py** - Remove `output_msa/*.json` for singles
37. **tools/restore_jobs_to_csv.py** - Merge verified singles into `folding_jobs.csv`
38. **tools/restore_jobs_from_list.py** - Add a list of jobs back to CSV
39. **tools/remove_outputs_from_list.py** - Delete `jobs/<name>/output` for a list
40. **tools/unixify_newlines.py** - Normalize CSVs to LF newlines
41. **tools/msa_extract_chain1.py** - Extract chain 1 from MSA
42. **tools/msa_batch_extract_chain1.py** - Batch MSA chain extraction
43. **tools/remove_empty_outputs.sh** - Remove empty output directories
44. **tools/move_msa_data.sh** - Move MSA data

## Quick Setup

```bash
# Make all scripts executable
chmod +x core/*.sh sync/*.sh monitoring/*.sh utils/*.sh tools/*.sh
chmod +x core/*.py tools/*.py
chmod +x create*.sh

# Verify setup
./utils/pipeline_quickstart.sh
```

## Typical Workflow

1. **Create jobs**: `./createAF3query.sh enzyme.fa substrate.fa --ptm 2 43 me1 --lig SAH`
2. **Populate queue**: Add job names to `folding_jobs.csv`
3. **Start pipeline**: `./core/launch_af3.sh`
4. **Monitor progress**: `./monitoring/pipeline_status.sh`
5. **Check job details**: `./monitoring/get_job_status.sh`
6. **Sync outputs**: `./sync/sync_all.sh`

## Script Categories by Function

### Creating Jobs
- `./createAF3query.sh` - Single job creation
- `./createAF3query_withSMILES.sh` - Jobs with SMILES ligands
- `./createHTS-AF3query.sh` - Human test set jobs
- `./createBatchAF3queries.sh` - Batch job creation

### Starting Pipeline
- `core/launch_af3.sh` → `core/af3_48hr_cycle.sh` → `core/submit_dist.sh`
- `core/submit_msa_arrays.sh` → `core/submit_msa_array.sh`
- `core/submit_gpu.sh`

### Monitoring Progress
- `monitoring/pipeline_status.sh` - Overall view
- `monitoring/monitor_msa_arrays.sh` - MSA jobs
- `monitoring/get_job_status.sh` - Individual jobs
- `monitoring/get_job_status_detailed.sh` - Advanced queries

### Managing Outputs
- `monitoring/check_sync_status.sh` - Pre-sync check
- `sync/sync_organize_outputs.sh` - Local organization
- `sync/rclone_to_gdrive.sh` - Cloud upload
- `sync/sync_all.sh` - Complete workflow

### Maintenance
- `utils/cleanup_msa_tmp.sh` - Clean MSA temps
- `utils/clean_output_dir.sh` - Reset output directory
- `utils/pipeline_quickstart.sh` - Verify installation

## Updates (2025-09-17)
- `core/submit_dist.sh` (updated):
  - Submits single-protein–ligand jobs without requiring `output_msa/`.
  - Strips CR from CSV lines to avoid silent directory mismatches.
  - Applies higher CPU/time for singles.
- `core/submit_gpu.sh` (updated):
  - Runs AF3 data pipeline for singles from `alphafold_input.json` (no `--norun_data_pipeline`).
  - Keeps GPU-only for multi-chain and prefers `output_msa/alphafold_input_with_msa.json`.
- `core/batch_reuse_msa.py` (updated):
  - Excludes single-protein–ligand jobs from MSA reuse/copy; writes CSVs with LF newlines.

## Reorganization (2026-01-06)
- Scripts reorganized into subdirectories by function
- All scripts use `SCRIPT_DIR` and `REPO_ROOT` patterns for portability
- Query creation scripts remain at top level for easy access
