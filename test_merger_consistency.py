#!/usr/bin/env python3
"""Test merger consistency with messy observations"""

import json
import subprocess
import time
from pathlib import Path

def run_single_test(run_number):
    """Run merger and capture results"""
    print(f"\n{'='*60}")
    print(f"RUN {run_number}")
    print(f"{'='*60}")
    
    # Clear debug directory
    subprocess.run(["rm", "-rf", "/Users/jerry/Documents/Dayflow/debug_output/merging_test/*"], shell=True)
    
    # Run the merger
    result = subprocess.run(
        ["python", "activity_card_merger.py"],
        capture_output=True,
        text=True
    )
    
    # Extract key info from output
    output_lines = result.stdout.split('\n')
    
    # Count final cards
    final_cards_line = [line for line in output_lines if "FINAL CARDS" in line]
    if final_cards_line:
        card_count = int(final_cards_line[0].split('(')[1].split(' ')[0])
    else:
        card_count = 0
    
    # Extract card titles
    titles = []
    for i, line in enumerate(output_lines):
        if "Title:" in line and not line.strip().startswith("Generated"):
            title = line.split("Title:")[1].strip()
            titles.append(title)
    
    # Count merge decisions
    merge_yes = len([line for line in output_lines if "Merge decision: True" in line])
    merge_no = len([line for line in output_lines if "Merge decision: False" in line])
    
    return {
        "run": run_number,
        "card_count": card_count,
        "merge_yes": merge_yes,
        "merge_no": merge_no,
        "titles": titles
    }

def main():
    # Update merger to use messy observations
    merger_code = Path("activity_card_merger.py").read_text()
    merger_code = merger_code.replace('process_with_merging("dummy_observations.json")', 
                                      'process_with_merging("messy_observations.json")')
    Path("activity_card_merger.py").write_text(merger_code)
    
    results = []
    for i in range(1, 6):
        result = run_single_test(i)
        results.append(result)
        time.sleep(1)  # Brief pause between runs
    
    # Restore original file
    merger_code = merger_code.replace('process_with_merging("messy_observations.json")', 
                                      'process_with_merging("dummy_observations.json")')
    Path("activity_card_merger.py").write_text(merger_code)
    
    # Summary
    print(f"\n{'='*60}")
    print("CONSISTENCY SUMMARY")
    print(f"{'='*60}")
    
    card_counts = [r["card_count"] for r in results]
    print(f"Card counts: {card_counts}")
    print(f"Average: {sum(card_counts)/len(card_counts):.1f}")
    print(f"Range: {min(card_counts)} - {max(card_counts)}")
    
    print(f"\nMerge decisions:")
    for r in results:
        print(f"  Run {r['run']}: {r['merge_yes']} merged, {r['merge_no']} kept separate")
    
    print(f"\nSample titles from each run:")
    for r in results:
        print(f"\nRun {r['run']} ({r['card_count']} cards):")
        for title in r['titles'][:3]:  # First 3 titles
            print(f"  - {title}")
        if len(r['titles']) > 3:
            print(f"  ... and {len(r['titles']) - 3} more")

if __name__ == "__main__":
    main()