#!/bin/bash

# Watch and auto-commit script for Termisol
# Uses inotify to monitor file changes and commits after 10 seconds

REPO_DIR="${TERMISOL_REPO_DIR:-$(pwd)}"
LOG_FILE="$REPO_DIR/.git/auto_commit.log"
MIN_AGE_SECONDS=10
PENDING_FILE="$REPO_DIR/.git/pending_commit"

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
            
            # Push to main branch (try both main and master)
            if git push origin main 2>/dev/null || git push origin master 2>/dev/null; then
                log_message "Pushed to remote"
            else
                log_message "Failed to push to remote"
            fi
        else
            log_message "Failed to commit changes"
        fi
        
        # Remove pending file
        rm -f "$PENDING_FILE"
    fi
}

# Function to handle file change event
handle_file_change() {
    local changed_file="$1"
    local current_time=$(date +%s)
    local file_time=$(stat -c %Y "$changed_file" 2>/dev/null)
    
    if [ -n "$file_time" ]; then
        local age=$((current_time - file_time))
        
        if [ "$age" -ge "$MIN_AGE_SECONDS" ]; then
            log_message "File $changed_file is $age seconds old, triggering commit"
            commit_changes
        else
            log_message "File $changed_file is $age seconds old, scheduling commit"
            echo "$current_time" > "$PENDING_FILE"
            
            # Schedule commit for when file is old enough
            (
                sleep $((MIN_AGE_SECONDS - age))
                if [ -f "$PENDING_FILE" ]; then
                    log_message "Scheduled commit triggered"
                    commit_changes
                fi
            ) &
        fi
    fi
}

# Main monitoring loop
log_message "Starting file monitoring for auto-commit"

cd "$REPO_DIR" || exit 1

# Monitor for file changes
inotifywait -m -r -e modify,create,delete,move --exclude '\.git/' . | while read path action file; do
    if [ -n "$file" ]; then
        full_path="$path$file"
        log_message "Detected $action on $full_path"
        handle_file_change "$full_path"
    fi
done
