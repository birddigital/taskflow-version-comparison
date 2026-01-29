#!/bin/bash

REPORT_FILE="/tmp/taskflow-history-bird-m1-$(date +%Y%m%d).md"
CUTOFF_DATE=$(date -v-7d +%Y-%m-%d)

echo "# TaskFlow History Report - bird-m1" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**Generated**: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "**Machine**: bird-m1 (arm64 Apple Silicon)" >> "$REPORT_FILE"
echo "**Period**: Past 7 days (since $CUTOFF_DATE)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "## Table of Contents" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "1. [Session Summaries](#session-summaries)" >> "$REPORT_FILE"
echo "2. [Git Commits](#git-commits)" >> "$REPORT_FILE"
echo "3. [TaskFlow State](#taskflow-state)" >> "$REPORT_FILE"
echo "4. [Pattern Library Updates](#pattern-library-updates)" >> "$REPORT_FILE"
echo "5. [Configuration Changes](#configuration-changes)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Section 1: Session Summaries
echo "## Session Summaries" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

SESSIONS=$(find ~/.claude -name "SESSION-*.md" -mtime -7 2>/dev/null)
if [ -n "$SESSIONS" ]; then
    for session in $SESSIONS; do
        echo "### $(basename $session)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "**Location**: $session" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "\`\`\`" >> "$REPORT_FILE"
        head -50 "$session" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "... (truncated)" >> "$REPORT_FILE"
        echo "\`\`\`" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
else
    echo "No session summaries found from past 7 days." >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# Section 2: Git Commits
echo "## Git Commits" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Check TaskFlow project
if [ -d ~/sources/standalone-projects/taskflow ]; then
    echo "### TaskFlow Project" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "\`\`\`" >> "$REPORT_FILE"
    cd ~/sources/standalone-projects/taskflow
    git log --since="$CUTOFF_DATE" --oneline --decorate >> "$REPORT_FILE" 2>&1
    echo "\`\`\`" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# Check SessionForge project
if [ -d ~/sources/standalone-projects/sessionforge ]; then
    echo "### SessionForge Project (TaskFlow Integration)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "\`\`\`" >> "$REPORT_FILE"
    cd ~/sources/standalone-projects/sessionforge
    git log --since="$CUTOFF_DATE" --oneline --decorate >> "$REPORT_FILE" 2>&1
    echo "\`\`\`" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# Section 3: TaskFlow State
echo "## TaskFlow State" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "### Local Cache Statistics" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
if [ -d ~/.taskflow/tasks ]; then
    TOTAL_TASKS=$(ls ~/.taskflow/tasks/ 2>/dev/null | wc -l | tr -d ' ')
    echo "- **Total tasks**: $TOTAL_TASKS" >> "$REPORT_FILE"
    echo "- **Cache location**: ~/.taskflow/tasks/" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

echo "### TaskFlow API Status" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
API_HEALTH=$(curl -s http://localhost:8081/health 2>/dev/null)
if [ -n "$API_HEALTH" ]; then
    echo "- **Status**: Running" >> "$REPORT_FILE"
    echo "- **Health**: $API_HEALTH" >> "$REPORT_FILE"
    echo "- **URL**: http://localhost:8081" >> "$REPORT_FILE"
else
    echo "- **Status**: Not running" >> "$REPORT_FILE"
fi
echo "" >> "$REPORT_FILE"

# Section 4: Pattern Library Updates
echo "## Pattern Library Updates" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

PATTERNS=$(find ~/.claude-orchestrator/Library -name "*taskflow*" -o -name "*TaskFlow*" -o -name "memory-management*" -mtime -7 2>/dev/null)
if [ -n "$PATTERNS" ]; then
    for pattern in $PATTERNS; do
        echo "### $(basename $pattern)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "**Modified**: $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$pattern")" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "\`\`\`" >> "$REPORT_FILE"
        head -30 "$pattern" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "... (truncated)" >> "$REPORT_FILE"
        echo "\`\`\`" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
else
    echo "No pattern updates found from past 7 days." >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# Section 5: Recent Session Hooks
echo "## Configuration Changes" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "### Session Hooks" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "#### session-start.sh" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
if [ -f ~/.claude/hooks/session-start.sh ]; then
    MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" ~/.claude/hooks/session-start.sh)
    SIZE=$(wc -l < ~/.claude/hooks/session-start.sh | tr -d ' ')
    echo "- **Last modified**: $MODIFIED" >> "$REPORT_FILE"
    echo "- **Size**: $SIZE lines" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

echo "#### session-end.sh" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
if [ -f ~/.claude/hooks/session-end.sh ]; then
    MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" ~/.claude/hooks/session-end.sh)
    SIZE=$(wc -l < ~/.claude/hooks/session-end.sh | tr -d ' ')
    echo "- **Last modified**: $MODIFIED" >> "$REPORT_FILE"
    echo "- **Size**: $SIZE lines" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "## Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**Report generated on**: $(date)" >> "$REPORT_FILE"
echo "**Next steps**:" >> "$REPORT_FILE"
echo "1. Review this report" >> "$REPORT_FILE"
echo "2. Compare with bird-intel report" >> "$REPORT_FILE"
echo "3. Determine which version to use" >> "$REPORT_FILE"
echo "4. Sync agreed version between machines" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "Report saved to: $REPORT_FILE"
cat "$REPORT_FILE"
