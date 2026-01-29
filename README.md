# TaskFlow Version Comparison

**Purpose**: Compare TaskFlow versions between bird-m1 and bird-intel to determine canonical version

**Date**: 2026-01-29

## Reports

### bird-m1 Report
- **Machine**: bird-m1 (arm64 Apple Silicon)
- **Generated**: 
- **Period**: Past 7 days
- **File**: [taskflow-history-bird-m1-20260129.md](./taskflow-history-bird-m1-20260129.md)

### bird-intel Report
- **Machine**: bird-intel (x86_64 Intel Mac)
- **Generated**: PENDING
- **Period**: Past 7 days
- **File**: WILL BE ADDED

## Comparison Process

1. **Generate reports on each machine**:
   - Run: `/tmp/taskflow-history-report.sh` on bird-m1
   - Run: `/tmp/taskflow-history-report.sh` on bird-intel
   - Both scripts identical, create comparable reports

2. **Push to this repository**:
   - bird-m1: Push to `branch: bird-m1-report`
   - bird-intel: Push to `branch: bird-intel-report`

3. **Compare versions**:
   - Review git commits in both reports
   - Compare TaskFlow API versions
   - Check pattern library updates
   - Identify divergent changes

4. **Determine canonical version**:
   - Choose machine with most recent commits
   - Choose machine with most features
   - Choose machine with most stable implementation
   - Document decision in `CANONICAL_VERSION_DECISION.md`

5. **Sync canonical version**:
   - Push canonical version to `branch: main`
   - Both machines pull from main
   - Both machines sync pattern files
   - Both machines update TaskFlow CLI

## Repository Structure

```
taskflow-version-comparison/
├── README.md (this file)
├── taskflow-history-bird-m1-YYYYMMDD.md
├── taskflow-history-bird-intel-YYYYMMDD.md
├── CANONICAL_VERSION_DECISION.md (to be created)
└── comparison-notes.md (optional)
```

## Instructions for Each Machine

### On bird-m1:
```bash
# 1. Clone this repository (if not already done)
cd ~/tmp/taskflow-version-comparison

# 2. Copy your report
cp /tmp/taskflow-history-bird-m1-*.md .

# 3. Create branch for your report
git checkout -b bird-m1-report

# 4. Add and commit report
git add .
git commit -m "Add bird-m1 TaskFlow history report"

# 5. Push to GitHub
git push -u origin bird-m1-report
```

### On bird-intel:
```bash
# 1. Clone this repository
git clone git@github.com:YOUR_USERNAME/taskflow-version-comparison.git
cd taskflow-version-comparison

# 2. Generate your report (use the same script from bird-m1)
# Copy /tmp/taskflow-history-report.sh from bird-m1
chmod +x taskflow-history-report.sh
./taskflow-history-report.sh

# 3. Copy your report
cp /tmp/taskflow-history-bird-intel-*.md .

# 4. Create branch for your report
git checkout -b bird-intel-report

# 5. Add and commit report
git add .
git commit -m "Add bird-intel TaskFlow history report"

# 6. Push to GitHub
git push -u origin bird-intel-report
```

## Next Steps

After both reports are pushed:
1. Create pull request to compare
2. Review differences
3. Make decision on canonical version
4. Document decision
5. Sync to both machines

---

**Status**: Initialization phase
**Next**: Create GitHub repository and push bird-m1 report

