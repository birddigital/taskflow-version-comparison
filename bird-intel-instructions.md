# Instructions for bird-intel

## Overview

bird-m1 has generated a TaskFlow history report and pushed it to GitHub. This document provides step-by-step instructions for bird-intel to generate a comparable report and determine the canonical TaskFlow version.

## Repository

**URL**: https://github.com/birddigital/taskflow-version-comparison

## Step 1: Clone the Repository

```bash
# On bird-intel
cd ~/tmp
git clone git@github.com:birddigital/taskflow-version-comparison.git
cd taskflow-version-comparison
```

## Step 2: Copy the Report Generation Script

The script is already in this repository at: `scripts/taskflow-history-report.sh`

Make it executable:

```bash
chmod +x scripts/taskflow-history-report.sh
```

## Step 3: Generate Your Report

```bash
# Run the script
./scripts/taskflow-history-report.sh

# This will create:
# - /tmp/taskflow-history-bird-intel-YYYYMMDD.md
```

## Step 4: Add Your Report to Repository

```bash
# Copy your report
cp /tmp/taskflow-history-bird-intel-*.md .

# Create a branch for your report
git checkout -b bird-intel-report

# Add and commit
git add .
git commit -m "Add bird-intel TaskFlow history report"

# Push to GitHub
git push -u origin bird-intel-report
```

## Step 5: Compare Versions

Once both reports are pushed, compare them by reviewing:

### Key Comparison Points:

1. **Git Commits**:
   - Which machine has more recent commits?
   - Which machine has more commits overall?
   - Are there divergent branches?

2. **TaskFlow API Version**:
   - Check health endpoint output
   - Compare version numbers
   - Compare uptime statistics

3. **Local Cache**:
   - Which machine has more tasks?
   - Are tasks consistent between machines?

4. **Pattern Library**:
   - Which machine has more recent pattern updates?
   - Are there machine-specific patterns?

5. **Configuration**:
   - Compare session hooks (session-start.sh, session-end.sh)
   - Compare TaskFlow CLI version
   - Compare API endpoints

## Step 6: Determine Canonical Version

After comparison, create a file: `CANONICAL_VERSION_DECISION.md`

Include:
- Which machine has the canonical version
- Rationale for decision
- Any changes needed on other machine
- Migration plan if needed

Example:

```markdown
# Canonical Version Decision

**Date**: YYYY-MM-DD
**Decision**: bird-m1 (or bird-intel) has canonical version

## Rationale

- More recent commits: X vs Y
- More complete implementation: X
- More features: X
- Better stability: X

## Required Changes on bird-[other]

1. Pull latest TaskFlow from canonical machine
2. Update session hooks
3. Update pattern library
4. Sync local cache

## Migration Steps

1. SSH to bird-[other]
2. Clone TaskFlow repo from canonical machine
3. Run setup scripts
4. Verify functionality

## Status

- [ ] Reports compared
- [ ] Decision made
- [ ] Migration plan created
- [ ] Migration executed
- [ ] Verification complete
```

## Step 7: Sync Canonical Version

Once decision is made:

```bash
# On machine with NON-canonical version
cd ~/sources/standalone-projects/taskflow

# Add canonical machine as remote
git remote add canonical git@github.com:birddigital/taskflow.git

# Fetch from canonical
git fetch canonical

# Reset to canonical's main
git reset --hard canonical/main

# Push to origin (YOUR fork)
git push origin main --force

# Update local cache
rm -rf ~/.taskflow/tasks/*
mkdir -p ~/.taskflow/tasks
# Pull from canonical API (if applicable)
```

## Quick Reference Commands

### On bird-m1:
```bash
cd ~/tmp/taskflow-version-comparison
git log --oneline --all
cat taskflow-history-bird-m1-*.md | head -100
```

### On bird-intel:
```bash
cd ~/tmp/taskflow-version-comparison
git log --oneline --all
cat taskflow-history-bird-intel-*.md | head -100
```

## Contact

If you have questions or need clarification:

- **bird-m1**: This machine (arm64 Apple Silicon)
- **bird-intel**: Other machine (x86_64 Intel Mac)

## Timeline

1. ✅ bird-m1 report generated: 2026-01-29
2. ⏳ bird-intel report: PENDING
3. ⏳ Comparison: PENDING
4. ⏳ Decision: PENDING
5. ⏳ Migration: PENDING

---

**Last Updated**: 2026-01-29  
**Status**: Waiting for bird-intel report
