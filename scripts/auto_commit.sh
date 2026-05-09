#!/bin/bash

# Auto-commit script for Termisol
# Commits changes older than 10 seconds to main branch

REPO_DIR="${TERMISOL_REPO_DIR:-$(pwd)}"
LOG_FILE="$REPO_DIR/.git/auto_commit.log"
MIN_AGE_SECONDS=10

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to generate commit message
generate_commit_message() {
    local changed_files=$(git diff --cached --name-only 2>/dev/null || git diff --name-only)
    local file_count=$(echo "$changed_files" | wc -l)
    
    if [ "$file_count" -eq 1 ]; then
        local filename=$(basename "$changed_files")
        echo "Auto-commit: Update $filename"
    else
        echo "Auto-commit: Update $file_count files"
    fi
}

# Function to check if changes are old enough
changes_are_old_enough() {
    local oldest_change=$(git status --porcelain | awk '{print $2}' | xargs -I {} stat -c %Y {} 2>/dev/null | sort -n | head -1)
    
    if [ -z "$oldest_change" ]; then
        return 1
    fi
    
    local current_time=$(date +%s)
    local age=$((current_time - oldest_change))
    
    [ "$age" -ge "$MIN_AGE_SECONDS" ]
}

# Function to commit and push changes
commit_changes() {
    cd "$REPO_DIR" || exit 1
    
    # Check if there are changes to commit
    if ! git diff --quiet || ! git diff --cached --quiet; then
        # Add all changes
        git add .
        
        # Generate and use commit message
        local commit_msg=$(generate_commit_message)
        
        # Commit changes
        if git commit -m "$commit_msg"; then
            log_message "Committed: $commit_msg"
            
            # Push to current branch
            local current_branch=$(git branch --show-current)
            if git push origin "$current_branch"; then
                log_message "Pushed to remote ($current_branch)"
            else
                log_message "Failed to push to remote ($current_branch)"
            fi
        else
            log_message "Failed to commit changes"
        fi
    fi
}

# Main execution
log_message "Auto-commit check started"

# Check if we're in a git repo
if [ ! -d "$REPO_DIR/.git" ]; then
    log_message "Not a git repository, exiting"
    exit 1
fi

# Check if changes are old enough
if changes_are_old_enough; then
    log_message "Changes are older than $MIN_AGE_SECONDS seconds, committing"
    commit_changes
else
    log_message "Changes are too recent, skipping commit"
fi

log_message "Auto-commit check completed"
