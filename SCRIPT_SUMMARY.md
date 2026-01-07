# AlphaFold3 Pipeline Scripts Summary

## Complete Script List (Total: 31 scripts)

### Query Creation Scripts (4)
1. **createAF3query.sh** - Creates AF3 job directories with alphafold_input.json
2. **createAF3query_withSMILES.sh** - Creates jobs with SMILES ligand definitions
3. **createHTS-AF3query.sh** - Creates human test set queries
4. **createBatchAF3queries.sh** - Batch wrapper for createAF3query.sh

### Core Pipeline Scripts (7)
5. **batch_reuse_msa.py** - Identifies and reuses existing MSAs
6. **submit_msa_arrays.sh** - Distributes MSA jobs across partitions
7. **submit_msa_array.sh** - Runs individual MSA generation
8. **submit_dist.sh** - Manages GPU job distribution
9. **submit_gpu.sh** - Runs individual GPU inference
10. **launch_af3.sh** - Starts 48-hour automation
11. **af3_48hr_cycle.sh** - Handles periodic execution

### Monitoring Scripts (5)
12. **monitor_msa_arrays.sh** - Monitors MSA array jobs
13. **get_job_status.sh** - Reports job stages and seeds
14. **get_job_status_detailed.sh** - Advanced status with filters
15. **pipeline_status.sh** - Quick dashboard view
16. **pipeline_summary.sh** - Complete pipeline overview with sync status

### Output Sync Scripts (6)
17. **sync_organize_outputs.sh** - Syncs and organizes outputs locally
18. **rclone_to_gdrive.sh** - Submits SLURM job for Google Drive upload
19. **check_sync_status.sh** - Shows sync readiness
20. **sync_all.sh** - Complete sync workflow
21. **check_rclone_status.sh** - Monitor rclone SLURM jobs
22. **clean_output_dir.sh** - Cleans output directory

### Utility Scripts (3)
23. **cleanup_msa_tmp.sh** - Removes temporary MSA files
24. **pipeline_quickstart.sh** - Validates setup
25. **compress_seeds.sh** - Manual seed compression utility

### Helper Tools (6)
26. **tools/find_single_enzyme_ligand_jobs.py** - Identify single-protein–ligand jobs
27. **tools/clear_output_msa_jsons.py** - Remove `output_msa/*.json` for singles
28. **tools/restore_jobs_to_csv.py** - Merge verified singles into `folding_jobs.csv`
29. **tools/unixify_newlines.py** - Normalize CSVs to LF newlines
30. **tools/remove_outputs_from_list.py** - Delete `jobs/<name>/output` for a list
31. **tools/restore_jobs_from_list.py** - Add a list of jobs back to CSV

## Quick Setup

```bash
# Make all scripts executable
chmod +x *.sh *.py

# Verify setup
./pipeline_quickstart.sh
```

## Typical Workflow

1. **Create jobs**: `./createAF3query.sh enzyme.fa substrate.fa --ptm 2 43 me1 --lig SAH`
2. **Populate queue**: Add job names to `folding_jobs.csv`
3. **Start pipeline**: `./launch_af3.sh`
4. **Monitor progress**: `./pipeline_status.sh`
5. **Check job details**: `./get_job_status.sh`
6. **Sync outputs**: `./sync_all.sh`

## Script Categories by Function

### Creating Jobs
- `createAF3query.sh` - Single job creation
- `createAF3query_withSMILES.sh` - Jobs with SMILES ligands
- `createHTS-AF3query.sh` - Human test set jobs
- `createBatchAF3queries.sh` - Batch job creation

### Starting Pipeline
- `launch_af3.sh` → `af3_48hr_cycle.sh` → `submit_dist.sh`
- `submit_msa_arrays.sh` → `submit_msa_array.sh`
- `submit_gpu.sh`

## Updates (2025-09-17)
- `submit_dist.sh` (updated):
  - Submits single-protein–ligand jobs without requiring `output_msa/`.
  - Strips CR from CSV lines to avoid silent directory mismatches.
  - Applies higher CPU/time for singles.
- `submit_gpu.sh` (updated):
  - Runs AF3 data pipeline for singles from `alphafold_input.json` (no `--norun_data_pipeline`).
  - Keeps GPU-only for multi-chain and prefers `output_msa/alphafold_input_with_msa.json`.
- `batch_reuse_msa.py` (updated):
  - Excludes single-protein–ligand jobs from MSA reuse/copy; writes CSVs with LF newlines.

### Monitoring Progress
- `pipeline_status.sh` - Overall view
- `monitor_msa_arrays.sh` - MSA jobs
- `get_job_status.sh` - Individual jobs
- `get_job_status_detailed.sh` - Advanced queries

### Managing Outputs
- `check_sync_status.sh` - Pre-sync check
- `sync_organize_outputs.sh` - Local organization
- `rclone_to_gdrive.sh` - Cloud upload
- `sync_all.sh` - Complete workflow

### Maintenance
- `cleanup_msa_tmp.sh` - Clean MSA temps
- `clean_output_dir.sh` - Reset output directory
- `pipeline_quickstart.sh` - Verify installation
