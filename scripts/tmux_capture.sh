#!/bin/bash
set -e
cd "$(dirname "$0")/.."

capture_demo() {
    name=$1
    bin=$2
    duration=${3:-3}
    
    echo "Capturing $name..."
    tmux kill-session -t capture 2>/dev/null || true
    tmux new-session -d -s capture -x 100 -y 35 "$bin; sleep 1"
    sleep $duration
    tmux capture-pane -t capture -p -e > "assets/raw/${name}.ansi"
    tmux send-keys -t capture q
    sleep 0.5
    tmux kill-session -t capture 2>/dev/null || true
    echo "  -> assets/raw/${name}.ansi"
}

mkdir -p assets/raw

capture_demo "system_monitor" "zig-out/bin/system_monitor" 3
capture_demo "file_manager" "zig-out/bin/file_manager" 2
capture_demo "showcase" "zig-out/bin/showcase" 2

echo "Done! Raw captures in assets/raw/"
