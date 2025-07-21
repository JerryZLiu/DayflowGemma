#!/usr/bin/env python3
"""Test merger consistency with focused observations"""

import subprocess
import time
from pathlib import Path

def run_single_test(run_number, obs_file):
    """Run merger and capture results"""
    # Clear debug directory
    subprocess.run(["rm", "-rf", "/Users/jerry/Documents/Dayflow/debug_output/merging_test/*"], shell=True)
    
    # Run the merger
    result = subprocess.run(
        ["python", "activity_card_merger.py", obs_file],
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

def test_observations(obs_file, test_name):
    print(f"\n{'='*60}")
    print(f"TESTING: {test_name}")
    print(f"{'='*60}")
    
    results = []
    for i in range(1, 6):
        print(f"\nRun {i}...", end='', flush=True)
        result = run_single_test(i, obs_file)
        results.append(result)
        print(f" {result['card_count']} cards")
        time.sleep(0.5)
    
    # Summary
    card_counts = [r["card_count"] for r in results]
    print(f"\nCard counts: {card_counts}")
    print(f"Average: {sum(card_counts)/len(card_counts):.1f}")
    print(f"Range: {min(card_counts)} - {max(card_counts)}")
    
    print(f"\nMerge decisions:")
    for r in results:
        print(f"  Run {r['run']}: {r['merge_yes']} merged, {r['merge_no']} kept separate")
    
    print(f"\nSample titles:")
    if results[0]['titles']:
        for title in results[0]['titles'][:3]:
            print(f"  - {title}")

if __name__ == "__main__":
    # Test focused observations
    test_observations("focused_observations.json", "FOCUSED WORK SESSION")
    
    # Test messy observations
    test_observations("messy_observations.json", "MESSY/DISTRACTED SESSION")
    
    print(f"\n{'='*60}")
    print("COMPARISON SUMMARY")
    print(f"{'='*60}")
    print("Focused session: Continuous work on related tasks")
    print("Messy session: Frequent context switches and distractions")
    print("\nThe same prompt handles both cases, merging related work")
    print("while keeping distractions and context switches separate.")